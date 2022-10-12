# Package implementing the HTTP protocol. The http package shipping with Tcl
# is too cumbersome and has too many issues to be used effectively.

# Test sites:
# http://jigsaw.w3.org/HTTP/
# http://httpbin.org/

package require Thread
package require sqlite3

if {$tcl_platform(platform) ne "windows"} {
    # Need the fix for bug f583715154
    package require Tcl 8.6.11-
}

proc ::oo::Helpers::callback {method args} {
    list [uplevel 1 {::namespace which my}] $method {*}$args
}

namespace eval www {
    variable schemes {
	http {port 80 command {} secure 0}
	https {port 443 command www::https secure 1}
    }
    variable encodings {
	gzip		{decode gzip}
	deflate		{decode deflate}
    }
    variable config {
	-proxy		defaultproxy
	-pipeline	0
	-urlencoding	utf-8
	-socketcmd	socket
    }
    variable headers {
	User-Agent	{Tcl-www/2.0 (linux-gnu)}
	Accept		{*/*}
	Accept-Encoding	{identity}
    }
    variable formmap [apply [list {} {
	set map {}
	for {set i 0} {$i <= 256} {incr i} {
	    set c [format %c $i]
	    if {![string match {[-._~a-zA-Z0-9]} $c]} {
		dict set map $c %[format %.2X $i]
	    }
	}
	return $map
    }]]
    variable tlscfg {}
    variable defaultproxy {}
    variable logpfx list

    # Track the persistent connections using an in-memory sqlite db
    sqlite3 [namespace current]::db :memory:
    db eval {
	create table reuse (
	  connection text primary key,
	  scheme text,
	  host text,
	  port text,
	  persistent boolean default 1
	);
    }

    namespace ensemble create -subcommands {
	get post head put delete log configure register certify cookiedb
	certcheck header urlencode
    } -map {
	log logpfx
	cookiedb cookies::dbfile
    }

    namespace ensemble create -command cert -map {
	error errcmd info nop verify vfycmd
    }
}

proc www::log {str} {
    variable logpfx
    if {[catch {{*}$logpfx $str}]} {logpfx ""}
}

proc www::logpfx {prefix} {
    variable logpfx $prefix
    if {$prefix eq ""} {set logpfx list}
}

# Load the TLS package on the first use of a https url.
proc www::https {args} {
    package require tls
    set cmd [list apply [list {sock host} {
	variable tlscfg
	# fileevent $sock writable {}
	# puts [list tls::import $sock -servername $host {*}$tlscfg]
	tls::import $sock -servername $host {*}$tlscfg
    } [namespace current]]]
    www register https 443 $cmd 1
    tailcall {*}$cmd {*}$args
}

# Execute a script when a variable is accessed
proc www::varevent {name ops {script ""}} {
    set cmd {{cmd var arg op} {catch {uplevel #0 $cmd}}}
    foreach n [uplevel 1 [list trace info variable $name]] {
	lassign $n op prefix
	if {$op eq $ops && \
	  [lindex $prefix 0] eq "apply" && [lindex $prefix 1] eq $cmd} {
	    if {[llength [info level 0]] < 4} {
		return [lindex $prefix 2]
	    }
	    uplevel 1 [list trace remove variable $name $ops $prefix]
	}
    }
    if {$script ne ""} {
	uplevel 1 \
	  [list trace add variable $name $ops [list apply $cmd $script]]
    }
    return
}

oo::class create www::connection {
    constructor {host port {transform ""}} {
	namespace path [linsert [namespace path] 0 ::www]
	variable fd "" timeout 30000 id ""
	variable translation {crlf crlf}
	variable waiting {} pending {}
	# Copy the arguments to namespace variables with the same name
	namespace eval [namespace current] \
	  [list variable host $host port $port transform $transform]
    }

    destructor {
	my Disconnect
    }

    method Disconnect {} {
	my variable fd id
	after cancel $id
	if {$fd ne ""} {
	    rename ::www::$fd ""
	    set fd [close $fd]
	}
    }

    method Failed {code info {index 0}} {
	my variable pending
	my Disconnect
	set callback [dict get [lindex $pending $index] Request callback]
	set opts [dict create -code 1 -level 1 -errorcode $code]
	$callback -options $opts $info
	set pending [lreplace $pending $index $index]
    }

    method Failure {args} {
	if {[llength $args] == 1} {
	    set opts [lindex $args]
	} else {
	    set opts [dict create -code 1 -level 1]
	    lassign $args errorcode result
	    dict set opts -errorcode $errorcode
	}
	my variable waiting pending
	foreach n [concat $pending $waiting] {
	    # Inform the caller of the failure
	    if {[catch {uplevel #0 [linsert [dict get $n callback] end $opts]} err opts]} {
		log "Failure: $err"
	    }
	}
	my destroy
    }

    method Pending {} {
	my variable pending
	set num 0
	foreach transaction $pending {
	    if {[dict get $transaction Attempt] > 5} {
		my Failed {WWW MAXATTEMPTS} {too many attempts} $num
	    } else {
		incr num
	    }
	}
	return [expr {$num > 0}]
    }

    method Process {} {
	my variable fd waiting pending
	if {[llength $waiting] == 0} return
	set count [llength $pending]
	if {$count && [dict get [lindex $waiting 0] pipeline] == 0} return
	if {$count && $fd eq ""} return
	# Start processing the next request
	set request [my PushRequest]
	if {$fd eq ""} {
	    my Connect
	} else {
	    my Request $count
	}
    }

    # Connect the socket in another thread to be totally non-blocking
    method Connect {} {
	my Disconnect
	if {![my Pending]} return
	coroutine connect my Initiate
    }

    method Initiate {} {
	if {[my Contact]} {
	    if {[catch {my Request} err opts]} {
		log "Request: $err"
		log [dict get $opts -errorinfo]
	    }
	}
    }

    method Timeout {} {
	my variable pending timeout
	if {[dict exists [lindex $pending 0] Request timeout]} {
	    return [dict get [lindex $pending 0] Request timeout]
	} else {
	    return $timeout
	}
    }

    method Contact {} {
	my variable fd host port connect transform

	# Build a command to open a socket in a separate thread
	set cmd [list {cmd} {
	    global fd result
	    if {![catch $cmd fd opts]} {
		fileevent $fd writable {set result socket}
		vwait result
		fileevent $fd writable {}
		if {[fconfigure $fd -connecting]} {
		    close $fd
		    set msg {connection timed out}
		    set fd "couldn't open socket: $msg"
		    dict set opts -code 1
		    dict set opts -errorcode [list POSIX ETIMEDOUT $msg]
		} else {
		    set error [fconfigure $fd -error]
		    if {$error eq ""} {
			thread::detach $fd
		    } else {
			close $fd
			set fd "couldn't open socket: $error"
			dict set opts -code 1
			switch $error {
			    {connection refused} {
				dict set opts \
				  -errorcode [list POSIX ECONNREFUSED $error]
			    }
			    {host is unreachable} {
				dict set opts \
				  -errorcode [list POSIX EHOSTUNREACH $error]
			    }
			}
		    }
		}
	    }
	    return [list $fd $opts]
	}]

	set socketcmd [linsert [cget -socketcmd] end -async $host $port]
	set script [list apply $cmd $socketcmd]
	# Open a plain socket in a helper thread
	set tid [thread::create]
	set ms [my Timeout]
	set id [after $ms [list thread::send -async $tid {set result timeout}]]
	set var [namespace which -variable connect]
	thread::send -async $tid $script $var
	trace add variable $var write [list [info coroutine]]
	yieldto list
	trace remove variable $var write [list [info coroutine]]
	after cancel $id
	lassign $connect result opts
	thread::release $tid
	# Check the socket was opened successfully
	if {[dict get $opts -code] == 0} {
	    set fd $result
	    coroutine ::www::$fd my Monitor
	    thread::attach $fd
	    fconfigure $fd -blocking 0
	    # Apply any transformations, such as importing TLS
	    if {$transform ne ""} {
		try {
		    {*}$transform $fd $host
		} trap WWW {result opts} {
		    # Immediately return WWW errors, without retrying
		    my Failed [dict get $opts -errorcode] $result
		} on error {err opts} {
		    log "Transform: $err"
		}
	    }
	    return 1
	} else {
	    my Failed [list WWW CONNECT $result] $result
	}
	return 0
    }

    method Monitor {} {
	set result [yield]
	my Failed [list WWW CONNECT $result] $result
    }

    method Request {{num 0}} {
	my variable fd pending id
	if {[eof $fd]} {
	    my Connect
	}

	set transaction [lindex $pending $num]
	dict incr transaction Attempt
	lset pending $num $transaction
	# Do not report the failure at this point because the callback may
	# create a new request that would mess up the order of the messages
	if {[dict get $transaction Attempt] > 5} {tailcall my Pending}
	try {
	    my Transmit [dict get $transaction Request]
	} trap {POSIX EPIPE} {} {
	    # Force eof condition
	    read $fd
	    tailcall my Connect
	}
	# Now report any problems to the callers
	my Pending

	if {$num == 0} {my Response}
	tailcall my Process
    }

    method Transmit {request} {
	my variable fd
	fconfigure $fd -translation [set translation {crlf crlf}]
	set method [dict get $request method]
	set resource [dict get $request resource]
	set head [list "$method $resource HTTP/1.1"]
	lappend head "Host: [dict get $request host]"
	if {[dict exists $request upgrade]} {
	    dict update request headers hdrs upgrade upgrade {
		header add hdrs Connection Upgrade
		header add hdrs Upgrade {*}[dict keys $upgrade]
	    }
	}
	foreach {key val} [dict get $request headers] {
	    lappend head "$key: $val"
	}
	lappend head ""
	set str [join $head \n]
	log $str
	puts $fd $str
	if {[dict exists $request body]} {
	    fconfigure $fd -translation [lset translation 1 binary]
	    puts -nonewline $fd [dict get $request body]
	}
	flush $fd
    }

    method Result {args} {
	my variable pending
	set response [lindex $pending 0]
	if {[llength $args] > 1} {
	    lset pending 0 [dict set response {*}$args]
	} elseif {[llength $args] == 0} {
	    return $response
	} elseif {[dict exists $response {*}$args]} {
	    return [dict get $response {*}$args]
	}
	return
    }

    method Response {} {
	my variable fd translation id
	set ms [my Timeout]
	set id [after $ms [callback Timedout]]
	fconfigure $fd -translation [lset translation 0 crlf]
	fileevent $fd readable [callback Statusline]
    }

    method Statusline {} {
	my variable fd
	try {
	    if {[eof $fd]} {
		my Connect
	    } elseif {[gets $fd line] >= 0} {
		log $line
		if {[scan $line {HTTP/%s %d %n} version code pos] != 3} {
		    my Failed [list WWW DATA STATUS] "invalid status line"
		}
		set reason [string range $line $pos end]
		my Result status [dict create line $line \
		  version HTTP/$version code $code reason $reason]
		fileevent $fd readable [callback Responsehead]
	    } elseif {[chan pending input $fd] > 1024} {
		# A status line shouldn't be this long.
		my Failed [list WWW DATA STATUS] "status line too long"
	    }
	} trap {POSIX ECONNABORTED} {msg opts} {
	    # This happens if there is a problem with the certificate
	    my Failed [dict get $opts -errorcode] $msg
	}
    }

    method Responsehead {} {
	my variable fd
	if {[eof $fd]} {
	    tailcall my Connect
	}
	set head [my Result Head]
	while {[gets $fd line] >= 0} {
	    if {$line eq ""} {
		set headers [my Headers $head]
		my Result Head {}
		my Result headers $headers
		tailcall my Responsebody $headers
	    }
	    lappend head $line
	}
	my Result Head $head
    }

    method Headers {head} {
	# Unfold headers
	foreach x [lreverse [lsearch -all -regexp $head {^\s}]] {
	    set str [string trimright [lindex $head [expr {$x - 1}]]]
	    append str " " [string trimleft [lindex $head $x]]
	    set head [lreplace $head [expr {$x - 1}] $x $str]
	}
	log [join $head \n]\n
	# Parse headers into a list
	set rc {}
	foreach str $head {
	    lassign [slice $str] name value
	    lappend rc [string tolower $name] $value
	}
	return $rc
    }

    method Responsebody {headers} {
	my variable fd translation
	set code [dict get [my Result status] code]
	variable size 0 length 0
	if {[dict get [my Result Request] method] eq "HEAD"} {
	    # All responses to the HEAD request method MUST NOT include
	    # a message-body, even though the presence of entity-header
	    # fields might lead one to believe they do
	    tailcall my Finished
	} elseif {$code eq "101" && [header exists $headers upgrade]} {
	    tailcall my Upgrade $headers
	} elseif {[string match 1?? $code] || $code in {204 304}} {
	    # All 1xx (informational), 204 (no content), and 304 (not
	    # modified) responses MUST NOT include a message-body
	    tailcall my Finished
	}
	set enc [header get $headers content-encoding all -lowercase]
	set transfer [header get $headers transfer-encoding all -lowercase]
	foreach n $transfer {if {$n ni {chunked identity}} {lappend enc $n}}
	if {[llength $transfer] == 0} {set transfer [list identity]}
	my Result Encoding [lmap name [lreverse $enc] {
	    set coro encodingcoro_$name
	    coroutine $coro {*}[encodingcmd $name]
	    set coro
	}]
	if {"identity" ni $transfer} {
	    fileevent $fd readable [callback Responsechunks]
	} elseif {[header exists $headers content-length]} {
	    set length [header get $headers content-length last]
	    if {$length} {
		fconfigure $fd -translation [lset translation 0 binary]
		fileevent $fd readable [callback Responsecontent]
	    } else {
		my Finished
	    }
	} elseif {[header get $headers content-type last] \
	  eq "multipart/byteranges"} {
	    # Not currently implemented
	    my Failure
	} else {
	    # Read data until the connection is closed
	    fconfigure $fd -translation [lset translation 0 binary]
	    fileevent $fd readable [callback Responserest]
	}
    }

    method Responsecontent {} {
	my variable fd size length
	if {[eof $fd]} {
	    tailcall my Connect
	}
	set data [read $fd [expr {$length - $size}]]
	if {$data ne ""} {
	    incr size [string length $data]
	    my Progress $data
	    log "Received $size/$length"
	    if {$size >= $length} {
		my Finished
	    }
	}
    }

    method Responsechunks {} {
	my variable fd translation size length
	if {[eof $fd]} {
	    tailcall my Finished
	}
	if {$length == 0} {
	    if {[gets $fd line] <= 0} return
	    lassign [slice $line {;}] hex ext
	    scan $hex %x length
	    if {$length == 0} {
		fileevent $fd readable [callback Responsetrailer]
		return
	    }
	    set size 0
	    fconfigure $fd -translation [lset translation 0 binary]
	}
	set data [read $fd [expr {$length - $size}]]
	if {$data ne ""} {
	    incr size [string length $data]
	    # log "$size/$length"
	    my Progress $data
	    if {$size >= $length} {
		fconfigure $fd -translation [lset translation 0 crlf]
		set length 0
	    }
	}
    }

    method Responsetrailer {} {
	my variable fd
	set tail [my Result Tail]
	if {[eof $fd]} {
	    set done 1
	} else {
	    set done 0
	    while {[gets $fd line] >= 0} {
		if {$line eq ""} {
		    set done 1
		    break
		}
		lappend tail $line
	    }
	}
	if {$done} {
	    if {$tail ne ""} {
		my Result Tail {}
		set headers [my Result headers]
		my Result headers [dict merge $headers [my Headers $tail]]
	    }
	    tailcall my Finished
	} else {
	    my Result Tail $tail
	}
    }

    method Responserest {} {
	my variable fd
	if {[eof $fd]} {
	    tailcall my Finished
	}
	my Progress [read $fd]
    }

    method Responseidle {} {
	my variable fd
	read $fd
	if {[eof $fd]} {
	    my destroy
	}
    }

    method Progress {{data ""}} {
	set finish [expr {$data eq ""}]
	foreach n [my Result Encoding] {
	    if {$data ne ""} {set data [$n $data]}
	    if {$finish} {append data [$n]}
	}
	if {$data eq ""} return

	set request [my Result Request]
	set handler \
	   [if {[dict exists $request handler]} {dict get $request handler}]

	if {$handler eq ""} {
	    set body [my Result Body]
	    my Result Body [append body $data]
	} else {
	    uplevel #0 [linsert $handler end $data]
	}
    }

    method PushRequest {} {
	# Move the next request from the waiting queue to the pending queue
	my variable waiting pending
	set waiting [lassign $waiting request]
	set transaction [dict create Request $request Attempt 0]
	# Provide some information back to the caller
	dict set transaction url [dict get $request url]
	dict set transaction uri [dict get $request path]
	lappend pending $transaction
	return $request
    }

    method PopRequest {} {
	my variable pending
	set pending [lassign $pending result]
	return $result
    }

    method Finished {} {
	my variable fd id pending waiting
	# Process any leftover data and end the coroutines
	my Progress
	set result [my PopRequest]
	if {[scan [dict get $result status version] HTTP/%s version] != 1} {
	    tailcall my Failure \
	      "invalid HTTP version: [dict get $result status version]"
	}
	set connection \
	  [header get [dict get $result headers] connection all -lowercase]
	after cancel $id
	if {[llength $pending]} {
	    my Response
	} else {
	    fileevent $fd readable [callback Responseidle]
	}
	if {![package vsatisfies $version 1.1] || "close" in $connection} {
	    my Disconnect
	    my Return $result
	    if {[llength $pending] == 0 && [llength $waiting] == 0} {
		# Nothing left to do. Destroy the object, if it still exists.
		if {[self] ne ""} {my destroy}
		return
	    }
	} else {
	    my Return $result
	}
	# The callback may have destroyed the object
	if {[self] ne ""} {my Process}
    }

    method Return {result} {
	set callback [dict get $result Request callback]
	set data [if {[dict exists $result Body]} {dict get $result Body}]
	# Just like in TclOO, public names start with a lowercase letter
	$callback -options [dict filter $result key {[a-z]*}] $data
    }

    method Upgrade {headers} {
	my variable fd id
	set upgrade [header get $headers upgrade]
	# Unfortunately (some) upgrade protocol names are not case sensitive
	try {
	    dict for {name mixin} [dict get [my Result Request] upgrade] {
		if {![string equal -nocase $name $upgrade]} continue
		after cancel $id
		oo::objdefine [self] mixin $mixin
		my Startup $headers
		return
	    }
	    my Failed {WWW UPGRADE} "protocol not supported: $upgrade"
	} on error {msg info} {
	    log [dict get $info -errorinfo]
	}
    }

    method Timedout {} {
	my Failed {WWW DATA TIMEOUT} "timeout waiting for a response"
    }

    method request {data} {
	my variable waiting
	dict set data callback [info coroutine]
	lappend waiting $data
	return {*}[yieldto my Process]
    }

    method fd {} {
	my variable fd
	return $fd
    }
}

# Use a derived class to simplify setting up an HTTP tunnel to a proxy server
oo::class create www::proxyconnect {
    superclass www::connection

    constructor {fh} {
	namespace path [linsert [namespace path] 0 ::www]
	variable fd $fh timeout 30000 id ""
	variable translation {crlf crlf}
	variable waiting {} pending {}
    }

    destructor {
	# Obscure the connection destructor, which would disconnect the socket
    }

    method connect {resource} {
	set request {headers {}}
	dict set request method CONNECT
	dict set request resource $resource
	dict set request host $resource
	dict set request url $resource
	dict set request path $resource
	try {
	    my request $request
	} on ok {data opts} {
	    set code [dict get $opts status code]
	    if {![string match 2?? $code]} {
		set codegrp [string replace $code 1 2 XX]
		set reason [dict get $opts status reason]
		dict set opts -code 1
		dict set opts -errorcode [list WWW CODE $codegrp $code $reason]
	    }
	    return -options [dict incr opts -level] $data
	}
    }

    method Responsebody {headers} {
	set code [dict get [my Result status] code]
	if {[string match 2?? $code]} {
	    # A "200 Connection established" response doesn't have a body
	    tailcall my Finished
	} else {
	    # All other responses are treated normally, but will finally fail
	    next $headers
	}
    }
}

namespace eval www::cookies {
    variable cookiejar ""
    namespace path [namespace parent]
    namespace ensemble create -subcommands {get save}
}

proc www::cookies::dbfile {filename} {
    variable cookiejar $filename
}

proc www::cookies::db {args} {
    variable cookiejar
    sqlite3 [namespace current]::db $cookiejar
    set create {
	create table if not exists %s.cookies (
	  domain text,
	  path text,
	  name text,
	  value text,
	  created int,
	  accessed int,
	  expires int not null default 4294967295,
	  attributes text,
	  primary key (domain, path, name)
	);
    }
    db transaction {
	db eval [format $create main]
	# Add a temporary database to hold the session cookies
	db eval {attach database "" as sess}
	db eval [format $create sess]
	# Create a view combining the two tables to simplify access
	# This must be a temporary view to allow combining two databases
	db eval {
	    create temp view cookieview as \
	      select domain, path, name, value, \
	      created, accessed, expires, attributes \
	      from main.cookies \
	      union all \
	      select domain, path, name, value, \
	      created, accessed, expires, attributes \
	      from sess.cookies
	}
	# Clean up expired cookies
	set now [clock seconds]
	db eval {delete from cookies where expires < $now}
    }
    tailcall db {*}$args
}

proc www::cookies::date {str} {
    # Implement most of the weird date and time parsing rules of RFC 6265
    # https://tools.ietf.org/html/rfc6265#section-5.1.1
    set time {}
    foreach token [regexp -all -inline -nocase {[0-9A-Z:]+} $str] {
	switch -nocase -regexp -matchvar match $token {
	    {^\d\d?:\d\d?:\d\d?} {
		if {![dict exists $time %T]} {
		    dict set time %T $match
		}
	    }
	    {^\d{5}} {}
	    {^\d{4}} {
		if {![dict exists $time %Y]} {
		    dict set time %Y $match
		}
	    }
	    {^\d{3}} {}
	    {^\d{2}} {
		if {![dict exists $time %d]} {
		    dict set time %d $match
		} elseif {![dict exists $time %Y]} {
		    incr match [expr {$match < 70 ? 2000 : 1900}]
		    dict set time %Y $match
		}
	    }
	    ^jan - ^feb - ^mar - ^apr -
	    ^may - ^jun - ^jul - ^aug -
	    ^sep - ^oct - ^nov - ^dec {
		if {![dict exists $time %b]} {
		    dict set time %b $match
		}
	    }
	}
    }
    if {[dict size $time] == 4} {
	return [clock scan [join [dict values $time]] \
	  -format [join [dict keys $time]] -timezone :UTC]
    }
    # invalid expiry date
}

proc www::cookies::save {rec data} {
    set now [clock seconds]
    db transaction {
	foreach n $data {
	    set args {}
	    foreach av [lassign [split $n {;}] pair] {
		lassign [slice $av =] key value
		dict set args [string tolower $key] $value
	    }
	    lassign [slice $pair =] name value
	    array unset arg
	    set host [dict get $rec host]
	    if {[dict exists $args domain]} {
		set str [dict get $args domain]
		if {[string index $str 0] eq "."} {
		    set str [string range $str 1 end]
		}
		set pat [format {*.%s} [string tolower $str]]
		if {$host eq $str || [string match $pat $host]} {
		    set arg(domain) $pat
		} else {
		    # Reject the cookie because of an invalid domain
		    continue
		}
	    } else {
		set arg(domain) $host
	    }
	    set path [dict get $rec path]
	    set arg(path) [file join [if {[dict exists $args path]} {
		dict get $args path
	    } else {
		file dirname $path
	    }] *]
	    if {![string match $arg(path) $path]} {
		# Reject the cookie because of an invalid path
		continue
	    }
	    if {[dict exists $args max-age]} {
		set maxage [dict get $args max-age]
		if {[string is integer -strict $maxage]} {
		    set arg(expires) [expr {[clock seconds] + $maxage}]
		}
	    } elseif {[dict exists $args expires]} {
		set sec [date [dict get $args expires]]
		if {$sec ne ""} {set arg(expires) $sec}
	    }
	    if {[dict exists $args secure]} {
		lappend arg(attr) secure
	    }
	    if {[dict exists $args httponly]} {
		lappend arg(attr) httponly
	    }
	    set arg(created) $now
	    set arg(accessed) $now
	    db eval {
		select created, attributes from cookies \
		  where name = $name \
		  and domain = $arg(domain) and path = $arg(path)
	    } {
		set arg(created) $created
	    }
	    if {[info exists arg(expires)]} {set db main} else {set db sess}
	    db eval [format {
		replace into %s.cookies \
		  (domain, path, name, value, created, accessed, expires, attributes) \
		  values ($arg(domain), $arg(path), $name, $value, $arg(created), $arg(accessed), $arg(expires), $arg(attr))
	    } $db]
	}
    }
}

proc www::cookies::get {rec} {
    set host [dict get $rec host]
    set path [dict get $rec path]
    set scheme [dict get $rec scheme]
    set attr {}
    if {[secure $scheme]} {lappend attr secure}
    if {$scheme in {http https}} {lappend attr httponly}
    set now [clock seconds]
    set rc {}
    db eval {
	select name, value, attributes, expires from cookieview \
	  where (domain = '*.' || $host or $host glob domain) \
	  and $path glob path \
	  order by length(path), created
    } {
	set allowed [expr {$expires >= $now}]
	foreach a $attributes {
	    if {$a ni $attr} {set allowed 0}
	}
	if {$allowed} {
	    lappend rc $name=$value
	}
    }
    return $rc
}

proc www::slice {str {sep :}} {
    set x [string first $sep $str]
    if {$x < 0} {return [list [string trim $str]]}
    return [list [string trim [string range $str 0 [expr {$x - 1}]]] \
      [string trim [string range $str [expr {$x + [string length $sep]}] end]]]
}

proc www::secure {scheme} {
    variable schemes
    if {[dict exists $schemes $scheme secure]} {
	return [dict get $schemes $scheme secure]
    } else {
	return 0
    }
}

proc www::urljoin {url args} {
    foreach n $args {
	switch -glob $n {
	    *://* {
		# Absolute URL
		set url $n
	    }
	    //* {
		# URL relative on current scheme
		set x [string first :// $url]
		set url [string replace $url [expr {$x + 1} end $n]
	    }
	    /* {
		# URL relative to the root of the website
		set x [string first :// $url]
		set x [string first / $url [expr {$x + 3}]]
		if {$x < 0} {
		    append url $n
		} else {
		    set url [string replace $url $x end $n]
		}
	    }
	    * {
		# Relative URL
		set x [string first ? $url]
		if {$x < 0} {
		    set x [string first # $url]
		    if {$x < 0} {
			set x [string length $url]
		    }
		}
		set x [string last / $url $x]
		if {$x < [string first :// $url] + 3} {
		    append url / $n
		} else {
		    set url [string replace $url $x end $n]
		}
	    }
	}
    }
    return $url
}

proc www::parseurl {url} {
    variable schemes
    set list [slice $url ://]
    if {[llength $list] < 2} {set list [list http $url]}
    lassign $list scheme str
    if {![dict exists $schemes $scheme port]} {
	throw {WWW URL SCHEME} "unknown scheme: $scheme"
    }
    lassign [slice $str /] authority str
    lassign [slice /$str #] resource fragment
    lassign [slice $resource ?] path query
    set rc [dict create url $url scheme $scheme host localhost \
      port [dict get $schemes $scheme port] \
      command [dict get $schemes $scheme command] \
      resource $resource path $path fragment $fragment]
    set slice [slice $authority @]
    dict set rc host [lindex $slice end]
    if {[llength $slice] > 1} {
	lassign [slice [lindex $slice 0]] username password
	dict set rc username $username
	dict set rc password $password
    }
    return $rc
}

proc www::getopt {var list body} {
    upvar 1 $var value
    dict for {pat code} $body {
	switch -glob -- $pat {
	    -- {# end-of-options option}
	    -?*:* {# option requiring an argument
		set opt [lindex [split $pat :] 0]
		set arg($opt) [dict create pattern $pat argument 1]
		# set arg(-$opt) $arg($opt)
	    }
	    -?* {# option without an argument
		set arg($pat) [dict create pattern $pat argument 0]
		# set arg(-$pat) $arg($pat)
	    }
	}
    }
    while {[llength $list]} {
	set rest [lassign $list opt]
	# Does it look like an option?
	if {$opt eq "-" || [string index $opt 0] ne "-"} break
	# Is it the end-of-options option?
	if {$opt eq "--"} {set list $rest; break}
	set value 1
	if {![info exists arg($opt)]} {
	    throw {WWW GETOPT OPTION} "unknown option: $opt"
	} elseif {[dict get $arg($opt) argument]} {
	    if {![llength $rest]} {
		throw {WWW GETOPT ARGUMENT} \
		  "option requires an argument: $opt"
	    }
	    set rest [lassign $rest value]
	}
	uplevel 1 [list switch -- [dict get $arg($opt) pattern] $body]
	set list $rest
    }
    return $list
}

proc www::stdopts {{body {}}} {
    return [dict merge {
	-timeout:milliseconds {
	    dict set request timeout $arg
	}
	-auth:data {
	    dict set request headers \
	      Authorization "Basic [binary encode base64 $arg]"
	}
	-digest:cred {
	    dict set request digest [slice $arg]
	}
	-persistent:bool {
	    if {[string is false -strict $arg]} {
		dict set request headers Connection close
	    }
	}
	-headers:dict {
	    dict update request headers hdrs {
		foreach {name value} $arg {
		    header append hdrs $name $value
		}
	    }
	}
	-upgrade:dict {
	    dict set request upgrade $arg
	}
	-handler:cmdprefix {
	    dict set request handler $arg
	}
	-maxredir:cnt {
	    dict set request maxredir $arg
	}
    } $body]
}

proc www::postopts {} {
    return {
	-multipart:type {
	    dict set request multipart $arg
	}
	-name:string {
	    dict set request partdata name $arg
	}
	-type:mediatype {
	    dict set request partdata type $arg
	}
	-file:file {
	    dict set request partdata file $arg
	    dict lappend request parts [dict get $request partdata]
	    dict unset request partdata file
	}
	-value:string {
	    dict set request partdata value $arg
	    dict lappend request parts [dict get $request partdata]
	    dict unset request partdata value
	}
    }
}

proc www::configure {args} {
    variable config
    variable headers
    set args [getopt arg $args {
	-accept:mimetypes {
	    header add headers Accept {*}$arg
	}
	-useragent:string {
	    header replace headers User-Agent $arg
	}
	-proxy:cmdprefix {
	    dict set config -proxy $arg
	}
	-pipeline:boolean {
	    dict set config -pipeline $arg
	}
	-socketcmd:prefix {
	    dict set config -socketcmd $arg
	}
    }]
}

proc www::cget {opt} {
    variable config
    if {[dict exists $config $opt]} {
	return [dict get $config $opt]
    }
    set valid [lsort [dict keys $config]]
    if {[llength $valid] > 1} {lset valid end "or [lindex $valid end]"}
    retrun -code error -errorcode {WWW CONFIGURE UNKNOWN} \
      [format {unknown option: "%s"; must be %s} $opt [join $valid ,]]
}

proc www::certify {cainfo {prefix ""}} {
    variable tlscfg {} cacheck $prefix
    if {$cainfo ne ""} {
	if {[file isdir $cainfo]} {
	    dict set tlscfg -cadir $cainfo -cafile {}
	} else {
	    dict set tlscfg -cafile $cainfo -cadir {}
	}
    }
    if {$prefix ne ""} {
	dict set tlscfg -command [namespace which cert]
    }
}

proc www::nop args {}

proc www::vfycmd {chan depth cert status error} {
    variable cacheck
    try {
	set rc [uplevel #0 [linsert $cacheck end $depth $cert]]
	if {[string is boolean -strict $rc]} {set status [string is true $rc]}
    } on error msg {
	log "Error: $msg"
    }
    return $status
}

proc www::errcmd {sock msg} {
    $sock $msg
}

proc www::certcheck {args} {
    
}

proc www::encodingcmd {name} {
    variable encodings
    return [dict get $encodings $name]
}

namespace eval www {
    # The three compression formats deflate, compress, and gzip are all the
    # same, except for headers and checksums. The Tcl zlib package uses the
    # following mapping:
    # deflate: raw compressed data only
    # compress: 2-byte header (78 ..) + data + ADLER32 checksum
    # gzip: 10-byte header (1F 8B 08 ...) + data + CRC-32 checksum
    # The http 1.1 spec rfc2616 uses the same names with the following mapping:
    # deflate: 2-byte header (78 ..) + data + ADLER32 checksum
    # compress: different compression method used by unix compress command
    # gzip: 10-byte header (1F 8B 08 ...) + data + CRC-32 checksum
    # One additional complication is that Microsoft got it wrong again and
    # made IE to expect a bare deflate stream for content-encoding deflate,
    # so some sites may provide that instead of the correct format. Other
    # browsers adapted by accepting both types.
    namespace ensemble create -command decode \
      -subcommands {gzip compress deflate}
}

proc www::gzip {} {
    set cmd [zlib stream gunzip]
    set data [yield]
    while {$data ne ""} {
	set data [yield [$cmd add $data]]
    }
    set rc [if {![$cmd eof]} {$cmd add -finalize {}}]
    $cmd close
    return $rc
}

proc www::deflate {} {
    set cmd [zlib stream decompress]
    set data [yield]
    if {$data ne ""} {
	try {
	    $cmd add $data
	} trap {TCL ZLIB DATA} {} {
	    # log "Decompress failed, trying inflate"
	    $cmd close
	    set cmd [zlib stream inflate]
	    set data [$cmd add $data]
	} on ok {data} {
	}
	set data [yield $data]
	while {$data ne ""} {
	    set data [yield [$cmd add $data]]
	}
    }
    set rc [if {![$cmd eof]} {$cmd add -finalize {}}]
    $cmd close
    return $rc
}

proc www::proxies {rec} {
    variable config
    set cmd [dict get $config -proxy]
    if {$cmd eq ""} {return [list DIRECT]}
    set host [dict get $rec host]
    set scheme [dict get $rec scheme]
    if {$scheme eq "https"} {
	set url [format %s://%s/ $scheme $host]
    } else {
	set url [dict get $rec url]
    }
    try {
	return [uplevel 0 [linsert $cmd end $url $host]]
    } on error {err opts} {
	return [list DIRECT]
    }
}

proc www::noproxy {url host} {
    return [list DIRECT]
}

proc www::defaultproxy {url host} {
    variable defaultproxy
    if {[dict size $defaultproxy] == 0} {
	global env
	dict set defaultproxy no {}
	foreach n [array names env -regexp {(?i)_proxy$}] {
	    set scheme [string tolower [string range $n 0 end-6]]
	    set proxy $env($n)
	    if {$scheme eq "no"} {
		dict set defaultproxy no [split $proxy {;,}]
		continue
	    } elseif {[string match *://* $proxy]} {
	       	set proxy [dict get [parseurl $env(http_proxy)] host]
	    }
	    dict set defaultproxy $scheme [list [list PROXY $proxy]]
	}
    }
    set scheme [lindex [slice $url ://] 0]
    if {[dict exists $defaultproxy $scheme]} {
	foreach domain [dict get $defaultproxy no] {
	    if {[string match $domain $host]} {
		return [list DIRECT]
	    }
	}
	return [dict get $defaultproxy $scheme]
    }
    return [list DIRECT]
}

proc www::httpproxy {server url host} {
    return [list "HTTP $server"]
}

proc www::httpsproxy {server url host} {
    return [list "HTTPS $server"]
}

proc www::socksproxy {server url host} {
    return [list "SOCKS $server"]
}

proc www::socks4proxy {server url host} {
    return [list "SOCKS4 $server"]
}

proc www::socks5proxy {server url host} {
    return [list "SOCKS5 $server"]
}

proc www::register {scheme port {command ""} {secure 0}} {
    variable schemes
    dict set schemes $scheme \
      [dict create port $port command $command secure $secure]
    return
}

proc www::urlencode {str} {
    variable config
    variable formmap
    set string [encoding convertto [dict get $config -urlencoding] $str]
    return [string map $formmap $str]
}

proc www::challenge {str} {
    scan $str {%s %n} type pos
    set rc {}
    foreach n [split [string range $str $pos end] ,] {
	lassign [slice $n =] key val
	if {[string match {"*"} $val]} {set val [string range $val 1 end-1]}
	dict set rc $key $val
    }
    return [list $type $rc]
}

proc www::hostport {dest {defaultport 80}} {
    # Extract host and port from the destination specification
    if {[regexp {^\[([[:xdigit:]:]+)\]} $dest ipv6 host]} {
	set l [string length $ipv6]
	if {$l == [string length $spec]} {
	    return [list $host $defaultport]
	} elseif {[string index $spec $l] eq ":"} {
	    return [list $host [string range $spec [expr {$l + 1}] end]]
	} else {
	    throw {WWW URL HOSTSPEC} "invalid host specification"
	} 
    } else {
	set rc [slice $dest]
	if {[llength $rc] < 2} {lappend rc $defaultport}
	return $rc
    }
}

proc www::reuse {scheme host port cmd} {
    # Check if a connection to the requested destination already exists
    db eval {select connection from reuse \
      where scheme = $scheme and host = $host and port = $port} {
	return $connection
    }
    set conn [{*}$cmd]
    db eval {insert into reuse (connection, scheme, host, port) \
      values($conn, $scheme, $host, $port)}

    # Arrange to update the administration when the object disappears
    trace add command $conn delete [list apply [list {obj args} {
	release $obj
    } [namespace current]]]

    return $conn
}

proc www::release {obj} {
    log "Deleting connection $obj"
    db eval {delete from reuse where connection = $obj}
    log "deleted [db changes] rows"
}

proc www::headers {extra} {
    variable headers
    variable encodings
    set hdrs $headers
    header add hdrs Accept-Encoding {*}[dict keys $encodings]
    foreach {name value} $extra {
	header replace hdrs $name $value
    }
    return $hdrs
}

namespace eval www::header {
    namespace ensemble create -subcommands {exists get replace append add}

    proc indexlist {hdrs name} {
	return [lmap n [lsearch -all -nocase -exact $hdrs $name] {
	    if {$n % 2} continue else {expr {$n + 1}}
	}]
    }

    proc exists {hdrs name} {
	# Usage: header exists headerlist name
	# Check if a header with the specified name exists
	return [expr {[llength [indexlist $hdrs $name]] != 0}]
    }

    proc get {hdrs name args} {
	# Usage: header get headerlist name ?index? ?-lowercase?
	# Return the value of the requested header, if any. By default all
	# entries are joined together, separated with a comma and a space.
	# The resulting string is returned.
	# If an index is specified, that is taken as an indication that the
	# header value is defined as a comma-separated list. In that case,
	# a Tcl list is constructed from the individual elements of all
	# entries. The requested index from the resulting list is returned.
	# The special index "all" causes the complete list to be returned.
	# When the -lowercase option is specified, all values are converted
	# to lower case.
	if {[lindex $args 0] eq "-lowercase"} {
	    set cmd [list string tolower]
	    set index [lindex $args 1]
	} else {
	    set cmd [list string cat]
	    set index [lindex $args 0]
	}
	if {$index eq ""} {
	    return [join [lmap n [indexlist $hdrs $name] {
		{*}$cmd [lindex $hdrs $n]
	    }] {, }]
	}
	set list [indexlist $hdrs $name]
	set rc {}
	if {[string equal -nocase $name Set-Cookie]} {
	    # The Set-Cookie header is special
	    foreach h $list {lappend rc [lindex $hdrs $h]}
	} else {
	    foreach h $list {
		foreach v [split [lindex $hdrs $h] ,] {
		    lappend rc [{*}$cmd [string trim $v]]
		}
	    }
	}
	if {$index eq "all"} {
	    return $rc
	} elseif {$index eq "last"} {
	    return [lindex $rc end]
	} else {
	    return [lindex $rc $index]
	}
    }

    proc add {var name args} {
	# Usage: header add headerlistvar name ?-nocase? value ?...?
	# Add one or more values to a header, if they are not alread present
	# The -nocase option makes the compare operation case insensitive.
	upvar 1 $var hdrs
	set list [get [lappend hdrs] $name all]
	set opts -exact
	if {[lindex $args 0] eq "-nocase"} {
	    lappend opts -nocase
	    set args [lrange $args 1 end]
	}
	foreach arg $args {
	    if {[lsearch {*}$opts $list $arg] < 0} {
		lappend list $arg
	    }
	}
	return [replace hdrs $name [join $list {, }]]
    }

    proc append {var name args} {
	# Usage: header append headerlistvar name ?value? ?...?
	# Set a new value for a header in addition to any existing values
	upvar 1 $var hdrs
	set list [indexlist [lappend hdrs] $name]
	set values [linsert $args 0 {*}[lmap n $list {lindex $hdrs $n}]]
	set index end
	foreach index [lreverse $list] {
	    set hdrs [lreplace $hdrs [expr {$index - 1}] $index]
	    incr index -1
	}
	set hdrs [linsert $hdrs $index $name [join $values {, }]]
    }

    proc replace {var name args} {
	# Usage: header replace headerlistvar name ?value? ?...?
	# Set a new value for a header replacing all existing entries.
	# Multiple values are joined together into a comma-separated list.
	# If no values are specified, all entries for the header are removed.
	upvar 1 $var hdrs
	set index end
	foreach index [lreverse [indexlist [lappend hdrs] $name]] {
	    set hdrs [lreplace $hdrs [expr {$index - 1}] $index]
	    incr index -1
	}
	if {[llength $args]} {
	    set hdrs [linsert $hdrs $index $name [join $args {, }]]
	}
	return $hdrs
    }
}

proc www::boundary {} {
    # Generate a unique boundary string
    for {set i 0} {$i < 6} {incr i} {
	lappend data [expr {int(rand() * 0x100000000)}]
    }
    # ModSecurity 2.9.2 complains about some characters in the boundary
    # string that are perfectly legal according to RFC 2046. "/" is one
    # of them. (It looks like this is fixed in ModSecurity 2.9.3.)
    # Wireshark also has issues when the boundary contains a "/".
    return [string map {/ -} [binary encode base64 [binary format I* $data]]]
}

proc www::formdata {list} {
    return [lmap {name value} $list {
	dict create name $name value $value
    }]
}

proc www::multipart {sep parts {disp ""}} {
    set rc {}
    foreach part $parts {
	lassign [bodypart $part $disp] body hdrs
	lappend rc "--$sep"
	foreach {hdr val} $hdrs {
	    lappend rc "$hdr: $val"
	}
	lappend rc "" $body
    }
    lappend rc --$sep--
    return [join $rc \r\n]
}

proc www::mimetype {file} {
    return application/octet-string
}

proc www::bodypart {data {disp ""}} {
    if {$disp ne ""} {
	if {[dict exists $data name]} {
	    set name [dict get $data name]
	} else {
	    set name value
	}
	set dispstr [format {%s; name="%s"} $disp $name]
	if {[dict exists $data file]} {
	    set filename [file tail [dict get $data file]]
	    append dispstr [format {; filename="%s"} $filename]
	}
	header replace hdrs Content-Disposition $dispstr
    }
    if {$disp eq "" || ![dict exists $data value]} {
	if {[dict exists $data type]} {
	    set type [dict get $data type]
	} elseif {[dict exists $data file]} {
	    set type [mimetype [dict get $data file]]
	} else {
	    set type application/octet-string
	}
	header replace hdrs Content-Type $type
    }
    if {[dict exists $data value]} {
	set body [dict get $data value]
    } elseif {[dict exists $data file]} {
	set f [open [dict get $data file] rb]
	set body [read $f]
	close $f
    } else {
	set body {}
    }
    return [list $body $hdrs]
}

proc www::bodybuilder {method url request args} {
    dict lappend request headers
    dict lappend request parts
    if {[llength $args] % 2} {
	dict set request partdata value [lindex $args end]
	set args [lrange $args 0 end-1]
	dict lappend request parts [dict get $request partdata]
    }
    if {$method in {POST}} {
	if {[llength [dict get $request parts]] == 0} {
	    set type application/x-www-form-urlencoded
	} elseif {[llength [dict get $request parts]] > 1 || [llength $args]} {
	    set type multipart/form-data
	} else {
	    set type application/octet-string
	}
    } elseif {[llength [dict get $request parts]] > 1} {
	set type multipart/mixed
    } elseif {[llength [dict get $request parts]]} {
	set type application/octet-string
    } else {
	set type ""
    }

    if {[dict exists $request multipart]} {
	switch [dict get $request multipart] {
	    "" {
		set type ""
	    }
	    formdata {
		set type multipart/form-data
	    }
	    default {
		set type multipart/[dict get $request multipart]
	    }
	}
    }

    set query {}
    set parts [if {[dict exists $request parts]} {dict get $request parts}]
    if {$type eq "multipart/form-data"} {
	set sep [boundary]
	set body [multipart $sep [concat $parts [formdata $args]] form-data]
	append type "; boundary=$sep"
    } elseif {$type eq "application/x-www-form-urlencoded"} {
	set body [join [lmap {key val} $args {
	    string cat [urlencode $key] = [urlencode $val]
	}] &]
    } else {
	set query $args
	if {[string match multipart/* $type]} {
	    set sep [boundary]
	    set body [multipart $sep $parts]
	    append type "; boundary=$sep"
	} elseif {[llength $parts]} {
	    lassign [bodypart [lindex $parts 0]] body hdrs
	    set type [header get $hdrs Content-Type]
	}
    }
    if {[llength $query]} {
	append url ? [join [lmap {key val} $args {
	    string cat [urlencode $key] = [urlencode $val]
	}] &]
    }
    dict set request url $url
    if {$type ne ""} {
	dict set request body $body
	dict set request headers Content-Type $type
    }
    return $request
}

proc www::request {method url request args} {
    variable requestid
    set request [bodybuilder $method $url $request {*}$args]
    # Get a local copy of the requestid, because the requestcoro may need to
    # perform a new request to obtain proxies, which would change requestid
    set id [incr requestid]
    set cmdline [list coroutine request$id requestcoro $method $request]
    set coro [info coroutine]
    if {$coro ne ""} {
	{*}$cmdline [list $coro]
	lassign [yield] data opts
    } else {
	variable result
	{*}$cmdline [list set [namespace which -variable result]($id)]
	vwait [namespace which -variable result]($id)
	lassign $result($id) data opts
	unset result($id)
    }
    if {[dict get $opts -code]} {
	return -options [dict incr opts -level] $data
    }
    set code [dict get $opts status code]
    if {$code in {101 200 201 202 204 207 304}} {
	# 101 Switching protocols
	# 200 OK
	# 201 Created
	# 202 Accepted
	# 204 No Content
	# 207 Multi-Status (WEBDAV)
	# 304 Not Modified
	return -options [dict incr opts -level] $data
    } elseif {$code in {301 302 303 307 308}} {
	# 301 Moved Permanently
	# 302 Found
	# 303 See Other
	# 307 Temporary Redirect
	# 308 Permanent Redirect
	if {[dict exists $request maxredir]} {
	    set redir [dict get $request maxredir]
	    if {$redir > 0} {dict incr request maxredir -1} 
	} else {
	    set redir 1
	}
	if {$redir > 0} {
	    if {$code eq "303"} {
		set method GET
		dict unset request body
		# Remove any Content-Length headers
		dict with request headers hdrs {
		    header replace hdrs Content-Length
		}
	    }
	    set url [dict get $request url]
	    set location [header get [dict get $opts headers] location]
	    log "Redirected to: $location"
	    tailcall request $method [urljoin $url $location] $request
	}
    } elseif {$code eq "401" \
      && [header exists [dict get $opts headers] www-authenticate]} {
	# 401 Unauthorized
	set challenge [header get [dict get $opts headers] www-authenticate]
	lassign [challenge $challenge] type args
	# RFC 2068 10.4.2: If the request already included Authorization
	# credentials, then the 401 response indicates that authorization
	# has been refused for those credentials.
	# RFC 2069 2.1.1: stale - A flag, indicating that the previous
	# request from the client was rejected because the nonce value was
	# stale. If stale is TRUE (in upper or lower case), the client may
	# wish to simply retry the request with a new encrypted response,
	# without reprompting the user for a new username and password.
	set stale [expr {[dict exists $args stale] \
	  && [string equal -nocase [dict get $args stale] true]}]
	set auth [header get [dict get $request headers] Authorization]
	if {$auth ne "" && !$stale} {
	    # Credentials must be incorrect
	} elseif {$type eq "Digest" && [dict exists $request digest]} {
	    package require www::digest
	    lassign [dict get $request digest] user password
	    set body \
	      [if {[dict exists $request body]} {dict get $request body}]
	    set uri [dict get $opts uri]
	    dict update request headers hdrs {
		set cred \
		  [digest::digest $args $user $password $method $uri $body]
		header replace hdrs Authorization $cred
	    }
	    tailcall request $method [dict get $opts url] $request
	}
    }
    set codegrp [string replace $code 1 2 XX]
    set reason [dict get $opts status reason]
    dict set opts -code 1
    dict set opts -errorcode [list WWW CODE $codegrp $code $reason]
    return -options [dict incr opts -level] $data
}

proc www::requestcoro {method request callback} {
    variable config
    variable headers
    variable schemes
    set url [dict get $request url]
    set rec [parseurl $url]
    set hdrs [dict get $request headers]
    set cookies [cookies get $rec]
    if {[llength $cookies]} {
	header replace hdrs Cookie [join $cookies {; }]
    } else {
	header replace hdrs Cookie
    }
    set proxies [proxies $rec]
    foreach n $proxies {
	lassign $n keyword arg
	set scheme [dict get $rec scheme]
	switch $keyword {
	    PROXY - HTTP - HTTPS {
		if {$keyword eq "HTTPS"} {
		    set version https
		} else {
		    set version http
		}
		set transform [dict get $schemes $scheme command]
		if {[llength $transform]} {
		    # If a transformation must be applied, an HTTP tunnel is
		    # needed via the CONNECT method
		    # Once the tunnel is established, the connection is to the
		    # remote server. Scheme, host and port must point there.
		    set host [dict get $rec host]
		    set port [dict get $rec port]
		    set transform \
		      [list proxyinit $version $host $port $transform]
		    lassign [hostport $arg 8080] phost pport
		    set command [list connection new $phost $pport $transform]
		    # The resource is just the local path
		    set resource [dict get $rec resource]
		} else {
		    # The connection is to the proxy, so the scheme, host and
		    # port must point to that for reuse
		    lassign [hostport $arg 8080] host port
		    set scheme $version
		    set transform [dict get $schemes $scheme command]
		    set command [list connection new $host $port $transform]
		    # The resource is the full remote path
		    set resource $url
		}
	    }
	    SOCKS - SOCKS4 - SOCKS5 {
		package require www::socks
		if {$keyword eq "SOCKS5"} {
		    set version socks5
		} else {
		    set version socks4
		}
		lassign [hostport [dict get $rec host] [dict get $rec port]] \
		  host port
		lassign [hostport $arg 1080] phost pport
		set transform [dict get $schemes $scheme command]
		set transform [list socksinit $version $host $port $transform]
		set command [list connection new $phost $pport $transform]
		set scheme $version+$scheme
		set resource [dict get $rec resource]
	    }
	    default {
		# DIRECT
		lassign [hostport [dict get $rec host] [dict get $rec port]] \
		  host port
		set transform [dict get $schemes $scheme command]
		set command [list connection new $host $port $transform]
		set resource [dict get $rec resource]
	    }
	}

	set conn [reuse $scheme $host $port $command]

	dict set rec method $method
	dict set rec pipeline [dict get $config -pipeline]
	if {[dict exists $request body]} {
	    header replace hdrs \
	      Content-Length [string length [dict get $request body]]
	    dict set rec body [dict get $request body]
	}
	foreach key {timeout upgrade} {
	    if {[dict exists $request $key]} {
		dict set rec $key [dict get $request $key]
	    }
	}
	dict set rec headers [headers $hdrs]
	dict set rec callback [list [info coroutine]]
	try {
	    $conn request [dict replace $rec resource $resource]
	} on ok {data opts} {
	} trap {WWW CONNECT} {data opts} {
	    log "proxy $n failed: $data"
	    continue
	} on error {data opts} {
	    log "requestcoro error: $data"
	}
	# log "requestcoro: $opts"
	if {[dict exists $opts headers]} {
	    set cookies [header get [dict get $opts headers] set-cookie all]
	    if {[llength $cookies]} {
		cookies save $rec $cookies
	    }
	}
	{*}$callback [list $data $opts]
	return
    }
    log "All proxies exhausted: $proxies"
    # Retry with http -> https ?
    {*}$callback [list $data $opts]
}

proc www::parseopts {optspec arglist} {
    set request {headers {}}
    # Call getopts twice to allow options to be specified before and after the url
    set args [getopt arg [lassign [getopt arg $arglist $optspec] url] $optspec]
    return [linsert $args 0 $url $request]
}

proc www::get {args} {
    set args [lassign [parseopts [stdopts] $args] url request]
    if {[llength $args] % 2} {
	throw {WWW ARGS} "expected key/value pairs"
    }
    request GET $url $request {*}$args
}

proc www::head {args} {
    set args [lassign [parseopts [stdopts] $args] url request]
    if {[llength $args] % 2} {
	throw {WWW ARGS} "expected key/value pairs"
    }
    request HEAD $url $request {*}$args
}

proc www::post {args} {
    request POST {*}[parseopts [stdopts [postopts]] $args]
}

proc www::put {args} {
    request PUT {*}[parseopts [stdopts [postopts]] $args]
}

proc www::delete {args} {
    request DELETE {*}[parseopts [stdopts [postopts]] $args]
}

proc www::proxyinit {scheme host port cmd fd args} {
    variable schemes
    # Apply a transformation for the connection to the proxy, if necessary
    set transform [dict get $schemes $scheme command]
    if {[llength $transform]} {{*}$transform $fd {*}$args}
    if {[llength $cmd]} {
	# Create a proxyconnect object for the CONNECT transaction to the proxy
	set obj [proxyconnect new $fd]
	# Actually start the connection
	try {
	    $obj connect $host:$port
	} finally {
	    $obj destroy
	}
	# Apply the transformation on the tunneled connection to the server
	{*}$cmd $fd $host
    }
}

proc www::socksinit {version host port cmd fd args} {
    socks $version $fd $host $port
    if {[llength $cmd]} {
	{*}$cmd $fd {*}$args
    }
}
