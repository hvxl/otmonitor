# MQTT Utilities - 2018 Schelte Bron
# Small library of routines for mqtt comms.
# Based on code by Mark Lawson
# BTW, some of this stuff only makes sense if you have the MQTT spec handy.

package require Tcl 8.6

namespace eval mqtt {
    proc log {str} {
	# Override if logging is desired
    }

    # Allow yield resumption with multiple arguments
    proc yieldm {{value {}}} {
	yieldto return -level 0 $value
    }

    # Check for a topic match
    proc match {pattern topic} {
	if {[string index $topic 0] eq "$"} {
	    if {[string index $pattern 0] ne "$"} {return 0}
	}
	foreach p [split $pattern /] n [split $topic /] {
	    if {$p eq "#"} {
		return 1
	    } elseif {$p ne $n && $p ne "+"} {
		return 0
	    }
	}
	return 1
    }
}

oo::class create mqtt {
    constructor {args} {
	namespace path [linsert [namespace path] end ::mqtt]
	variable config {
	    -keepalive		60
	    -retransmit		5000
	    -username		""
	    -password		""
	    -clean		1
	    -protocol		4
	}
	variable fd "" data "" queue {} connect {} coro "" events {}
	variable keepalive [expr {[dict get $config -keepalive] * 1000}]
	variable subscriptions {} seqnum 0 statustopic {$LOCAL}

	# Message types
	variable msgtype {
	    {}		CONNECT		CONNACK		PUBLISH
	    PUBACK	PUBREC		PUBREL		PUBCOMP
	    SUBSCRIBE	SUBACK	    	UNSUBSCRIBE	UNSUBACK
	    PINGREQ	PINGRESP	DISCONNECT	{}
	}

	my configure {*}$args
    }

    destructor {
	my disconnect
    }

    method report {dir type dict} {
	set str "[string totitle $dir] $type"
	set arglist {}
	switch -- $type {
	    CONNECT {
		foreach n {clean keepalive username} {
		    if {[dict exists $dict $n]} {
			lappend arglist [string index $n 0][dict get $dict $n]
		    }
		}
	    }
	    CONNACK {
		foreach n {session retcode} {
		    if {[dict exists $dict $n]} {
			lappend arglist [dict get $dict $n]
		    }
		}
	    }
	    PUBLISH {
		set control [dict get $dict control]
		set tmp [dict create dup 0 qos 0 retain 0]
		if {[dict exists $dict msgid]} {
		    dict set tmp msgid [dict get $dict msgid]
		}
		if {"retain" in $control} {dict incr tmp retain}
		if {"ack" in $control} {dict set tmp qos 1}
		if {"assure" in $control} {dict set tmp qos 2}
		if {"dup" in $control} {dict incr tmp dup}
		foreach n {dup qos retain msgid} {
		    if {[dict exists $tmp $n]} {
			lappend arglist [string index $n 0][dict get $tmp $n]
		    }
		}
		lappend arglist '[dict get $dict topic]'
		lappend arglist "...\
		  ([string length [dict get $dict data]] bytes)"
	    }
	    PUBREC - PUBREL - PUBCOMP - PUBACK {
		lappend arglist "Mid: [dict get $dict msgid]"
	    }
	    SUBSCRIBE {
		dict for {topic qos} [dict get $dict topics] {
		    append str \n "    $topic (QoS $qos)"
		}
	    }
	    UNSUBSCRIBE {
		dict for {topic qos} [dict get $dict topics] {
		    append str \n "    $topic"
		}
	    }
	    SUBACK {
		foreach n [dict get $dict results] {
		    if {$n < 128} {
			lappend arglist "QoS $n"
		    } else {
			lappend arglist "Failure"
		    }
		}
	    }
	    default {
		set args {}
	    }
	}
	if {[llength $arglist]} {
	    append str " ([join $arglist {, }])"
	}
	log $str
    }

    method configure {args} {
	my variable config
	if {[llength $args] == 0} {
	    return [lsort -index 0 -stride 2 $config]
	} elseif {[llength $args] == 1} {
	    set arg [lindex $args 0]
	    if {![dict exist $config $arg]} {
		set args [dict keys $config $arg*]
		if {[llength $args] != 1} {
		    error [format {unknown or ambiguous option: "%s"} $arg]
		}
		set arg [lindex $args 0]
	    }
	    return [dict get $config $arg]
	} elseif {[llength $args] % 2 == 0} {
	    foreach {opt val} $args {
		if {![dict exist $config $opt]} {
		    set opts [dict keys $config $opt*]
		    if {[llength $opts] != 1} {
			error [format {unknown or ambiguous option: "%s"} $opt]
		    }
		    set opt [lindex $opts 0]
		}
		switch -- $opt {
		    -keepalive {
			if {$val < 0 || $val > 65535} {
			    error "keepalive must be between 0 and 65535"
			}
			variable keepalive [expr {$val * 1000}]
		    }
		    -retransmit {
			if {$val < 0 || $val > 3600000} {
			    error "retransmit must be between 0 and 3600000"
			}
		    }
		    -clean {
			set val [expr {![string is false -strict $val]}]
		    }
		    -protocol {
			if {$val ni {3 4}} {
			    error "only protocol levels 3 (3.1)\
			      and 4 (3.1.1) are currently supported"
			}
		    }
		}
		dict set config $opt $val
	    }
	}
    }

    method connect {name {host localhost} {port 1883}} {
	my variable coro
	if {$coro ne ""} {error "illegal request"}
	set level [my configure -protocol]
	if {$level == 4} {
	    if {$name eq "" && ![my configure -clean]} {
		error "a zero-length client identifier is not allowed\
		  when the -clean option is set to false"
	    }
	} elseif {$level == 3} {
	    if {$name eq "" || [string length $name] > 23} {
		error [format {invalid client identifier: "%s"} $name]
	    }
	}
	coroutine [self object]_coro my client $name $host $port
    }

    method disconnect {} {
	my variable timer fd coro
	my message $fd DISCONNECT
	foreach n [array names timer] {
	    after cancel $timer($n)
	}
	if {$coro ne ""} {
	    set coro [$coro destroy]
	    my notifier
	}
	my close
    }

    method close {{retcode 0}} {
	my variable fd
	if {$fd ne "" || $retcode != 0} {
	    my status connection \
	      [dict create state disconnected reason $retcode]
	}
	if {$fd ne ""} {
	    # Stop keepalive messages
	    my timer ping cancel
	    my timer subscribe cancel
	    catch {close $fd}
	    set fd ""
	}
    }

    method timer {name time {cmd ""}} {
	my variable timer
	if {[info exists timer($name)]} {
	    if {$time eq "idle"} return
	    after cancel $timer($name)
	    unset timer($name)
	}
	if {$time eq "expire"} {
	    if {[catch {uplevel #0 $cmd} result]} {
		log $result
	    }
	} elseif {$time ne "cancel"} {
	    # Route timer expiry back through this method to clean up the array
	    set timer($name) \
	      [after $time [list [namespace which my] timer $name expire $cmd]]
	    return $name
	}
    }

    # Convert a string to utf8
    method bin {str} {
	set bytes [encoding convertto utf-8 $str]
	return [binary format Sa* [string length $bytes] $bytes]
    }

    method will {topic {message ""} {qos 1} {retain 0}} {
	my variable connect
	if {$topic eq ""} {
	    dict unset connect will
	} else {
	    dict set connect will [dict create \
	      topic $topic message $message qos $qos retain $retain]
	}
	return
    }

    method client {name host port} {
	my variable connect queue pending
	variable coro [info coroutine]

	dict set connect client $name
	dict set connect keepalive [my configure -keepalive]
	dict set connect clean [my configure -clean]
	dict set connect username [my configure -username]
	if {[dict get $connect username] eq ""} {
	    dict unset connect username
	} else {
	    dict set connect password [my configure -password]
	    if {[dict get $connect password] eq ""} {
		dict unset connect password
	    }
	}

	set retry 0
	while {1} {
	    try {
		set sleep [my dialog $host $port]
	    } trap {MQTT CONNECTION REFUSED SERVER} {result opts} {
		log "Connection refused, $result"
		my close [dict get $opts -retcode]
		set sleep 60000
	    } trap {MQTT CONNECTION REFUSED} {result opts} {
		log "Connection refused, $result"
		my close [dict get $opts -retcode]
		# These are fatal errors, no need to retry
		break
	    } trap {MQTT} {result opts} {
		log [dict get $opts -errorcode]
		set sleep 10000
	    } on error {err info} {
		# Something unexpected went wrong. Try to recover.
		log "($coro): [dict get $info -errorinfo]"
		# Prevent looping too fast
		set sleep 10000
	    } finally {
		my close
		# Cancel all retransmits, and requeue messages
		foreach n [array names pending] {
		    set msg [dict get $pending($n) msg]
		    my timer [dict get $msg msgid] cancel
		    # A next attempt will always be a DUP message
		    dict update msg control ctrl {
			if {"dup" ni $ctrl} {lappend ctrl dup}
		    }
		    set type [lindex [split $n ,] 0]
		    if {$type in {PUBLISH PUBREL}} {
			lappend queue [list PUBLISH $msg]
		    }
		    if {$type in {SUBSCRIBE UNSUBSCRIBE}} {
			lappend queue [list $type $msg]
		    }
		    unset pending($n)
		}
	    }
	    my sleep $sleep
	}
	set coro ""
	tailcall my notifier
    }

    method sleep {time} {
	my variable coro
	my timer sleep $time [list $coro wake]
	while {[my receive] ne "wake"} {}
    }

    method dialog {host port} {
	my variable fd coro connect queue
	if {$fd ne ""} {
	    log "Warning: Init called ($host:$port) while fd = $fd"
	    return 0
	}
	log "Connecting to $host on port $port"
	if {[catch {socket -async $host $port} sock err]} {
	    log "Connection failed: $sock"
	    return 10000
	}
	# Put a time limit on the connection
	my timer init 10000 [list $coro noanswer $sock]
	fileevent $sock writable [list $coro contact $sock]
	# Queue events are allowed to happen during initialization
	try {
	    while 1 {
		set args [lassign [my receive $sock] event]
		switch -- $event {
		    noanswer {
			throw {MQTT CONNECTION TIMEOUT} "connection timed out"
		    }
		    contact {
			fileevent $sock writable {}
			set error [fconfigure $sock -error]
			if {$error eq ""} {
			    fconfigure $sock \
			      -blocking 0 -buffering none -translation binary
			    variable data "" pingmiss 0
			    fileevent $sock readable [list $coro receive $sock]
			    my message $sock CONNECT $connect
			} else {
			    log "Connection failed: $error"
			    return 10000
			}
		    }
		    CONNACK {
			my process $event {*}$args
			fileevent $sock readable {}
			set fd $sock
			break
		    }
		    queue {}
		    default {
			throw [list MQTT UNEXPECTED $event] \
			  "unexpected event: $event"
		    }
		}
	    }
	} finally {
	    # Cancel the timer even if [my receive] fails, while allowing
	    # the error to continue to percolate up the call stack
	    my timer init cancel
	    if {$sock ne $fd} {
		close $sock
	    }
	}
	
	# The connection has been established.
	if {[llength $queue]} {
	    # Allow the connection callbacks to run
	    my sleep 0
	}
	# Send out initial subscription requests.
	my subscriptions 1

	set ms [clock milliseconds]
	# Run the main loop as long as the connection is up
	fileevent $fd readable [list $coro receive $fd]
	while {$fd ne "" && ![eof $fd]} {
	    # Send out any queued messages
	    set queue [foreach n $queue {my message $fd {*}$n}]
	    set event [my receive $fd]
	    my process {*}$event
	}
	my close 3
	# If the connection was established but lost again very
	# quickly, we were possibly stealing the connection from
	# another client with the same name, who took it back
	upvar #1 retry retry
	if {[clock milliseconds] < $ms + 1000} {
	    if {$retry <= 0} {
		return 30000
	    } else {
		incr retry -1
	    }
	} else {
	    set retry 3
	}
	return 0
    }

    method process {event args} {
	my variable fd store pending
	# Events: contact dead destroy noanswer queue receive wake
	switch -- $event {
	    CONNACK {
		lassign $args msg
		set retcode [dict get $msg retcode]
		switch -- $retcode {
		    0 {
			# Connection Accepted
			set status [dict create state connected]
			if {[dict exists $msg session]} {
			    dict set status session [dict get $msg session]
			}
			my status connection $status
		    }
		    1 {
			return -code error -retcode $retcode \
			  -errorcode {MQTT CONNECTION REFUSED PROTOCOL} \
			  "unacceptable protocol version"
		    }
		    2 {
			return -code error -retcode $retcode \
			  -errorcode {MQTT CONNECTION REFUSED IDENTIFIER} \
			  "identifier rejected"
		    }
		    3 {
			return -code error -retcode $retcode \
			  -errorcode {MQTT CONNECTION REFUSED SERVER} \
			  "server unavailable"
		    }
		    4 {
			return -code error -retcode $retcode \
			  -errorcode {MQTT CONNECTION REFUSED LOGIN} \
			  "bad user name or password"
		    }
		    5 {
			return -code error -retcode $retcode \
			  -errorcode {MQTT CONNECTION REFUSED AUTH} \
			  "not authorized"
		    }
		}
	    }
	    PUBLISH {
		lassign $args msg
		set ctrl [dict get $msg control]
		if {"assure" in $ctrl} {
		    set msgid [dict get $msg msgid]
		    # Store the data
		    set store($msgid) [list $msg]
		    # Indicate reception of the PUBLISH message
		    my message $fd PUBREC $msg
		} else {
		    # Notify all subscribers
                    my notify $msg
		    if {"ack" in $ctrl} {
			# Indicate reception of the PUBLISH message
			my message $fd PUBACK $msg
		    }
		}
	    }
	    PUBACK {
		lassign $args msg
		my ack PUBLISH $msg
	    }
	    PUBREC {
		lassign $args msg
		my ack PUBLISH $msg
		my message $fd PUBREL $msg
	    }
	    PUBREL {
		lassign $args msg
		my ack PUBREC $msg
		set msgid [dict get $msg msgid]
		if {[info exists store($msgid)]} {
		    my notify {*}$store($msgid)
		    unset store($msgid)
		}
		my message $fd PUBCOMP $msg
	    }
	    PUBCOMP {
		lassign $args msg
		my ack PUBREL $msg
	    }
	    SUBACK {
		lassign $args msg
		my ack SUBSCRIBE $msg
	    }
	    UNSUBACK {
		lassign $args msg
		my ack UNSUBSCRIBE $msg
	    }
	    PINGRESP {
		variable pingmiss 0
		my timer pong cancel
	    }
	    CLIENT - SUBSCRIBE - UNSUBSCRIBE - PINGREQ - DISCONNECT {
		# The server should not be sending these messages
		throw {MQTT MESSAGE UNEXPECTED} "unexpected message: $event"
	    }
	    dead {
		my variable pingmiss
		log "No PINGRESP received"
		if {[incr pingmiss] < 5} {
		    my keepalive
		} else {
		    my close 3
		}
	    }
	}
    }

    method receive {{fd ""}} {
	my variable data msgtype coro
	while 1 {
	    # Send out notification and then wait for something to happen
	    set rc [yieldto my notifier]
	    if {[lindex $rc 0] ne "receive"} {return $rc}
	    if {[eof $fd]} {return EOF}
	    set size [string length $data]
	    # A message is at least 2 bytes
	    if {$size < 2} {
		append data [read $fd [expr {2 - $size}]]
	    }
	    if {[binary scan $data cucu hdr len] < 2} continue
	    append data [read $fd $len]
	    set size [string length $data]
	    if {$size < 2 + $len} continue
	    set ptr 2
	    if {$len > 127} {
		# The max number of bytes in the Remaining Length field is 4
		binary scan $data x2cu3 length
		set len [expr {$len & 0x7f}]
		set shift 0;
		foreach l $length {
		    set len [expr {$len + (($l & 0x7f) << [incr shift 7])}]
		    incr ptr
		    if {$l < 128} break
		}
		if {$size < $ptr + $len} {
		    append data [read $fd [expr {$ptr + $len - $size}]]
		    if {[string length $data] < $ptr + $len} continue
		}
	    }

	    set type [lindex $msgtype [expr {$hdr >> 4}]]
	    set size \
	      [coroutine payload my payload [string range $data $ptr end]]
	    set msg $data
	    set data ""

	    set mask 1
	    set control {}
	    foreach n {retain ack assure dup} {
		if {$hdr & $mask} {lappend control $n}
		incr mask $mask
	    }
	    set rc [dict create type $type control $control]
	    try {
		switch -- $type {
		    CONNECT {
			my string protocol
			payload cu version
			set flags [payload cu]
			payload Su keepalive
			my string client
			dict set rc clean [expr {($flags & 0b10) != 0}]
			if {$flags & 0b100} {
			    my string {will topic}
			    my string {will message}
			    dict set rc will qos [expr {$flags >> 3 & 0b11}]
			}
			if {$flags & 0b10000000} {my string username}
			if {$flags & 0b01000000} {my string password}
		    }
		    CONNACK {
			if {[my configure -protocol] < 4} {
			    payload cucu reserved retcode
			} else {
			    payload cucu session retcode
			}
		    }
		    PUBLISH {
			my string topic
			if {"assure" in $control || "ack" in $control} {
			    payload Su msgid
			}
			payload a* data
		    }
		    PUBACK - PUBREC - PUBREL - PUBCOMP {
			payload Su msgid
		    }
		    SUBSCRIBE {
			payload Su msgid
			set pos 2
			while {$pos < $size} {
			    lassign [my string] len topic
			    payload cu [list topics $topic]
			    incr pos 3
			    incr pos $len
			}
		    }
		    SUBACK {
			payload Sucu* msgid results
		    }
		    UNSUBSCRIBE {
			payload Su msgid
			set pos 2
			while {$pos < $size} {
			    lassign [my string] len topic
			    dict set rc topics $topic ""
			    incr pos 2
			    incr pos $len
			}
		    }
		    UNSUBACK {
			payload Su msgid
		    }
		    PINGREQ - PINGRESP - DISCONNECT {}
		    default {
			throw {MQTT PAYLOAD UNKNOWN}
		    }
		}
		set rc [dict merge $rc [payload]]
		my report received $type $rc
	    } trap {MQTT PAYLOAD} {- err} {
		my invalid $msg
		rename payload {}
	    } on error {- err} {
		log [dict get $err -errorinfo]
		rename payload {}
	    }
	    return [list $type $rc]
	}
    }

    method payload {data} {
	set pos 0
	set len [string length $data]
	set msg {}
	set args [lassign [yieldm $len] spec]
	while {$spec ne "" || [llength $args]} {
	    set parts [regexp -all -inline \
	      {[aAbBhHcsStiInwWmfrRdqQ]u?(?:\d*|\*)} $spec]
	    set vars {}
	    set cnt [llength $parts]
	    for {set i 1} {$i <= $cnt} {incr i} {lappend vars $i}
	    if {[binary scan $data @$pos$spec {*}$vars] != $cnt} {
		throw {MQTT PAYLOAD DEPLETED}
	    }
	    set result [lmap v $vars {set $v}]
	    foreach a $args v $result p $parts {
		if {$a eq ""} break
		if {[string match {[aA]u*} $p]} {
		    dict set msg {*}$a [encoding convertfrom utf-8 $v]
		} else {
		    dict set msg {*}$a $v
		}
	    }
	    # Unfortunately there is no way to get the internal cursor from
	    # [binary scan]. So we need to reformat the parsed binary data.
	    incr pos [string length [binary format $spec {*}$result]]
	    set args [lassign [yieldm $result] spec]
	}
	return $msg
    }

    method string {{name ""}} {
	set len [payload Su]
	return [list $len [payload au$len $name]]
    }

    method ack {type ack} {
	my variable pending subscriptions
	set msgid [dict get $ack msgid]
	if {![info exists pending($type,$msgid)]} return
	my timer $msgid cancel
	set msg [dict get $pending($type,$msgid) msg]
	# Don't clean up a qos=2 PUBLISH message until the PUBCOMP is received
	# Because if the connection drops, the PUBLISH needs to be reissued
	if {$type eq "PUBLISH" && "assure" in [dict get $msg control]} return
	unset pending($type,$msgid)
	if {$type eq "PUBREL"} {
	    if {[info exists pending(PUBLISH,$msgid)]} {
		set msg [dict get $pending(PUBLISH,$msgid) msg]
		unset pending(PUBLISH,$msgid)
	    } else {
		return
	    }
	}
	set status {}
	switch -- $type {
	    PUBLISH - PUBREL {
		dict set status topic [dict get $msg topic]
		dict set status data [dict get $msg data]
		my status publication $status
	    }
	    SUBSCRIBE {
		set topics [dict keys [dict get $msg topics]]
		foreach topic $topics code [dict get $ack results] {
		    dict set status $topic $code
		    dict set subscriptions $topic ack $code
		    if {![dict exists $subscriptions $topic callbacks]} {
			dict set subscriptions $topic callbacks {}
		    }
		}
		my status subscription $status
	    }
	    UNSUBSCRIBE {
		foreach topic [dict keys [dict get $msg topics]] {
		    dict set status $topic ""
		    # Don't delete any new subscription requests that
		    # happened while the unsubscribe was in transit
		    if {![dict exists $subscriptions $topic callbacks] || \
		      ![llength [dict get $subscriptions $topic callbacks]]} {
			dict unset subscriptions $topic
		    } else {
			dict set subscriptions $topic ack ""
		    }
		}
		my status subscription $status
	    }
	}
    }

    method invalid {msg} {
	binary scan $msg H* hex
	log "Invalid message: [regexp -all -inline .. $hex]"
	return
    }

    method status {topic data} {
	my variable statustopic events
	lappend events $statustopic/$topic $data
    }

    method notify {msg} {
	# Do not immediately invoke the registered callbacks, in case they
	# perform commands that need to call into the coroutine again
	my variable events
	lappend events [dict get $msg topic] [dict get $msg data] \
	  [expr {"retain" in [dict get $msg control]}]
    }

    method notifier {} {
	my variable events subscriptions
	# Can't use a foreach here because the callbacks may call back into
	# the coroutine, which could affect the list of events
	while {[llength $events]} {
	    set events [lassign $events topic data retain]
	    dict for {pat dict} $subscriptions {
		if {[match $pat $topic]} {
		    foreach n [dict get $dict callbacks] {
			uplevel #0 \
			  [linsert [lindex $n 1] end $topic $data $retain]
		    }
		}
	    }
	}
    }

    method message {fd type {msg {}}} {
	my variable msgtype pending coro keepalive
	# Can only send a message when connected
	if {$fd eq ""} {return 0}

	# Build the payload depending on the message type
	dict set msg payload [set payload [my $type msg]]

	set control [dict get $msg control]

	if {"ack" in $control || "assure" in $control} {
	    set msgid [dict get $msg msgid]
	    dict set pending($type,$msgid) msg $msg
	    dict incr pending($type,$msgid) count
	    set ms [my configure -retransmit]
	    set cmd [list [namespace which my] retransmit $type $msgid]
	    my timer $msgid $ms $cmd
	    if {[dict get $pending($type,$msgid) count] > 1} {
		# There is a difference in the way the DUP flag is described
		# in spec 3.1 and 3.1.1. According to 3.1.1 the DUP flag
		# should not be set in PUBREL, SUBSCRIBE, UNSUBSCRIBE messages
		if {$type eq "PUBLISH" || [my configure -protocol] < 4} {
		    if {"dup" ni $control} {
			dict set msg control [lappend control dup]
		    }
		}
	    }
	}

	my report sending $type $msg

	# Build the header byte
	set hdr [expr {[lsearch -exact $msgtype $type] << 4}]
	if {"dup" in $control} {set hdr [expr {$hdr | 0b1000}]}
	if {"assure" in $control} {
	    set hdr [expr {$hdr | 0b100}]
	} elseif {"ack" in $control} {
	    set hdr [expr {$hdr | 0b010}]
	}
	if {"retain" in $control} {set hdr [expr {$hdr | 0b1}]}

	# Calculate the data length
	set ll {}
	set len [string length $payload]
	while {$len > 127} {
	    lappend ll [expr {$len & 0x7f | 0x80}]
	    set len [expr {$len >> 7}]
	}
	lappend ll $len

	# Restart the keep-alive timer
	if {$keepalive > 0} {
	    my timer ping $keepalive [list [namespace which my] keepalive]
	}

	# Send the message
	set data [binary format cc*a* $hdr $ll $payload]
	if {[catch {puts -nonewline $fd $data}]} {
	    return 0
	} else {
	    return 1
	}
    }

    method retransmit {type msgid} {
	my variable pending fd
	if {[info exists pending($type,$msgid)]} {
	    set msg [dict get $pending($type,$msgid) msg]
	    if {[dict get $pending($type,$msgid) count] <= 5} {
		my message $fd $type $msg
	    } else {
		log "Server failed to respond"
		unset pending($type,$msgid)
		# my close 3
	    }
	}
    }

    method keepalive {} {
	my variable fd coro
	my message $fd PINGREQ
	my timer pong [my configure -retransmit] [list $coro dead]
    }

    method queue {type msg} {
	my variable queue fd coro
	lappend queue [list $type $msg]
	if {$type in {SUBSCRIBE UNSUBSCRIBE}} {
	    my timer subscribe idle [list [namespace which my] subscriptions]
	} elseif {$fd ne ""} {
	    $coro queue
	}
    }

    method subscriptions {{init 0}} {
	my variable subscriptions queue statustopic fd
	set list {}
	set clean [my configure -clean]
	if {$init && $clean} {
	    # Reinstate subscriptions
	    dict for {pat dict} $subscriptions {
		set qos [lindex [dict get $dict callbacks] 0 0]
		if {$qos >= 0 && ![string match $statustopic/* $pat]} {
		    set msg [dict create topics [dict create $pat $qos]]
		    lappend list [list SUBSCRIBE $msg]
		    dict set subscriptions $pat ack {}
		}
	    }
	}
	lappend list {*}[lsearch -all -inline -index 0 $queue *SUBSCRIBE]
	if {[llength $list] == 0} return

	set queue [lsearch -all -inline -not -index 0 $queue *SUBSCRIBE]

	set sub {}
	set unsub {}
	set notify {}
	foreach n $list {
	    set msg [lindex $n 1]
	    dict for {pat qos} [dict get $msg topics] {
		if {![dict exists $subscriptions $pat ack]} continue
		set ack [dict get $subscriptions $pat ack]
		set qos [lindex [dict get $subscriptions $pat callbacks] 0 0]
		if {[string match $statustopic/* $pat]} {
		    if {$qos eq ""} {
			dict unset subscriptions $pat
		    } else {
			if {$ack > $qos} {set qos $ack}
			dict set subscriptions $pat ack $qos
		    }
		    dict set notify $pat $qos
		} elseif {$fd eq ""} {
		    lappend queue $n
		} elseif {$qos > $ack} {
		    dict set sub topics $pat $qos
		} elseif {$qos eq "" && ($ack ne "" || !$clean)} {
		    dict set unsub topics $pat $qos
		} else {
		    dict set notify $pat $ack
		}
	    }
	}

	if {[dict size $notify]} {my status subscription $notify}
	if {$fd ne ""} {
	    if {[dict size $unsub] > 0} {my message $fd UNSUBSCRIBE $unsub}
	    if {[dict size $sub] > 0} {my message $fd SUBSCRIBE $sub}
	} else {
	    my notifier
	}
    }

    method subscribe {pattern prefix {qos 2}} {
	my variable subscriptions
	if {$qos > 2} {set qos 2}
	if {![dict exists $subscriptions $pattern]} {
	    dict set subscriptions $pattern {ack "" callbacks {}}
	}
	dict with subscriptions $pattern {
	    set x [lsearch -exact -index 1 $callbacks $prefix]
	    if {$x < 0} {
		lappend callbacks [list $qos $prefix]
	    } else {
		lset callbacks $x [list $qos $prefix]
	    }
	    set callbacks [lsort -integer -decreasing -index 0 $callbacks]
	    set msg [dict create topics [dict create $pattern $qos]]
	    my queue SUBSCRIBE $msg
	}
	return
    }

    method unsubscribe {pattern prefix} {
	my variable subscriptions
	if {![dict exists $subscriptions $pattern]} {
	    dict set subscriptions $pattern {ack "" callbacks {}}
	}
	dict with subscriptions $pattern {
	    set callbacks \
	      [lsearch -all -inline -exact -index 1 -not $callbacks $prefix]
	    set msg [dict create topics [dict create $pattern {}]]
	    my queue UNSUBSCRIBE $msg
	}
    }

    method publish {topic message {qos 1} {retain 0}} {
	if {[regexp {[#+]} $topic]} {
	    # MQTT-3.3.2-2
	    return -code error -errorcode {MQTT TOPICNAME INVALID} \
	      "invalid topic name: $topic"
	}
	set control [lindex {{} ack assure} $qos]
	if {$retain} {lappend control retain}
	set msg [dict create topic $topic data $message control $control]
	my queue PUBLISH $msg
    }

    method seqnum {msgvar} {
	upvar 1 $msgvar msg
	my variable seqnum
	if {[dict exists $msg msgid]} {
	    set msgid [dict get $msg msgid]
	} else {
	    if {([incr seqnum] & 0xffff) == 0} {set seqnum 1}
	    set msgid $seqnum
	    dict set msg msgid $msgid
	}
	return [binary format S $msgid]
    }

    method CONNECT {msgvar} {
	upvar 1 $msgvar msg

	# The DUP, QoS, and RETAIN flags are not used in the CONNECT message.
	dict set msg control {}

	# Create the payload
	set flags 0
	if {[dict exists $msg clean] && [dict get $msg clean]} {
	    set flags 0b10
	}
	# Client Identifier
	set payload [my bin [dict get $msg client]]
	if {[dict exists $msg will topic]} {
	    set flags [expr {$flags | 0b100}]
	    append payload [my bin [dict get $msg will topic]]
	    if {[dict exists $msg will message]} {
		append payload [my bin [dict get $msg will message]]
	    } else {
		append payload [my bin ""]
	    }
	    if {[dict exists $msg will qos]} {
		set flags [expr {$flags | ([dict get $msg will qos] << 3)}]
	    }
	    if {[dict exists $msg will retain] && [dict get $msg will retain]} {
		set flags [expr {$flags | 0b100000}]
	    }
	}
	if {[dict exists $msg username]} {
	    set flags [expr {$flags | 0b10000000}]
	    append payload [my bin [dict get $msg username]]
	    if {[dict exists $msg password]} {
		set flags [expr {$flags | 0b1000000}]
		append payload [my bin [dict get $msg password]]
	    }
	}
	set level [my configure -protocol]
	if {$level < 4} {
	    set data [my bin MQIsdp]
	} else {
	    set data [my bin MQTT]
	}
	append data [binary format ccS $level $flags [dict get $msg keepalive]]
	append data $payload
	return $data
    }

    method CONNACK {msgvar} {
	upvar 1 $msgvar msg
	set msg [dict merge {session 0 retcode 0} $msg {control {}}]
	return [binary format cc \
	  [dict get $msg session] [dict get $msg retcode]]
    }

    method PUBLISH {msgvar} {
	upvar 1 $msgvar msg
	set msg [dict merge {control {} data ""} $msg]
	set data [my bin [dict get $msg topic]]
	set control [dict get $msg control]
	if {"ack" in $control || "assure" in $control} {
	    append data [my seqnum msg]
	}
	append data [dict get $msg data]
	return $data
    }

    method PUBACK {msgvar} {
	upvar 1 $msgvar msg
	dict set msg control {}
	return [my seqnum msg]
    }

    method PUBREC {msgvar} {
	upvar 1 $msgvar msg
	dict set msg control {}
	return [my seqnum msg]
    }

    method PUBREL {msgvar} {
	upvar 1 $msgvar msg
	set msg [dict merge $msg {control ack}]
	return [my seqnum msg]
    }

    method PUBCOMP {msgvar} {
	upvar 1 $msgvar msg
	dict set msg control {}
	return [binary format S [dict get $msg msgid]]
    }

    method SUBSCRIBE {msgvar} {
	upvar 1 $msgvar msg
	set msg [dict merge {topics {}} $msg {control ack}]
	set data [my seqnum msg]
	dict for {topic qos} [dict get $msg topics] {
	    append data [my bin $topic]
	    append data [binary format c $qos]
	}
	return $data
    }

    method SUBACK {msgvar} {
	upvar 1 $msgvar msg
	dict set msg control {}
	set data [my seqnum msg]
	append data [binary format c* [dict get $msg results]]
	return $data
    }

    method UNSUBSCRIBE {msgvar} {
	upvar 1 $msgvar msg
	set msg [dict merge {topics {}} $msg {control ack}]
	set data [my seqnum msg]
	dict for {topic qos} [dict get $msg topics] {
	    append data [my bin $topic]
	}
	return $data
    }

    method UNSUBACK {msgvar} {
	upvar 1 $msgvar msg
	dict set msg control {}
	return [my seqnum msg]
    }

    method PINGREQ {msgvar} {
	upvar 1 $msgvar msg
	set msg {control {}}
	return
    }

    method PINGRESP {msgvar} {
	upvar 1 $msgvar msg
	set msg {control {}}
	return
    }

    method DISCONNECT {msgvar} {
	upvar 1 $msgvar msg
	set msg {control {}}
	return
    }

    unexport ack bin client close dialog invalid keepalive match message
    unexport notifier notify payload process queue receive report
    unexport seqnum sleep status string subscriptions timer
}

oo::objdefine mqtt {forward log proc ::mqtt::log}
