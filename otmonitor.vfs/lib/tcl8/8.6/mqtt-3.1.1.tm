# MQTT Utilities - 2019, 2021 Schelte Bron
# library of routines for mqtt comms.
# All normative statement references refer to the mqtt-v5.0-os document:
# https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.pdf

package require Tcl 8.6

namespace eval mqtt {
    variable logpfx list

    variable reasoncode {
	1   {VERSION		"unacceptable protocol version"}
	2   {CLIENTID		"client identifier not valid"}
	3   {SERVER		"server unavailable"}
	4   {LOGIN		"bad user name or password"}
	5   {AUTH		"not authorized"}
	16  {NOMATCH		"no matching subscribers"}
	17  {NOSUBSCRIPTION	"no subscription existed"}
	24  {CONTINUE		"continue authentication"}
	25  {REAUTH		"re-authenticate"}
	128 {UNSPECIFIED	"unspecified error"}
	129 {MALFORMED		"malformed packet"}
	130 {PROTOCOL		"protocol error"}
	131 {IMPLEMENTATION	"implementation specific error"}
	132 {VERSION		"unsupported protocol version"}
	133 {CLIENTID		"client identifier not valid"}
	134 {LOGIN		"bad user name or password"}
	135 {AUTH		"not authorized"}
	136 {SERVER		"server unavailable"}
	137 {BUSY		"server busy"}
	138 {BANNED		"banned"}
	139 {SHUTDOWN		"server shutting down"}
	140 {AUTHMETHOD		"bad authentication method"}
	141 {KEEPALIVE		"keep alive timeout"}
	142 {TAKEOVER		"session taken over"}
	143 {FILTER		"topic filter invalid"}
	144 {TOPIC		"topic name invalid"}
	145 {INUSE		"packet identifier in use"}
	146 {NOTFOUND		"packet identifier not found"}
	147 {RECEIVE		"receive maximum exceeded"}
	148 {ALIAS		"topic alias invalid"}
	149 {PACKETSIZE		"packet too large"}
	150 {MESSAGERATE	"message rate too high"}
	151 {QUOTA		"quota exceeded"}
	152 {ADMIN		"administrative action"}
	153 {PAYLOAD		"payload format invalid"}
	154 {RETAIN		"retain not supported"}
	155 {QOS		"qos not supported"}
	156 {OTHER		"use another server"}
	157 {MOVED		"server moved"}
	159 {CONNECTIONRATE	"connection rate exceeded"}
	160 {CONNECTTIME	"maximum connect time"}
	161 {SUBSCRIPTIONID	"subscription identifiers not supported"}
	161 {WILDCARD		"wildcard subscriptions not supported"}
    }

    namespace ensemble create -command prop -parameters id -subcommands {
	byte short long integer utf8 pair bindata
    }

    proc logpfx {prefix} {
	variable logpfx $prefix
	if {$prefix eq ""} {set logpfx list}
    }

    proc log {str} {
	variable logpfx
	if {[catch {{*}$logpfx $str}]} {logpfx ""}
    }

    # Check for a topic match
    proc match {pattern topic} {
	set psplit [split $pattern /]
	if {[lindex $psplit 0] eq {$share}} {set psplit [lrange $psplit 2 end]}
	set tsplit [split $topic /]
	# The Server MUST NOT match Topic Filters starting with a wildcard
	# character (# or +) with Topic Names beginning with a $ character
	# [MQTT-4.7.2-1]
	if {[string index $topic 0] eq {$}} {
	    if {[lindex $psplit 0] ne [lindex $tsplit 0]} {return 0}
	}
	foreach p $psplit n $tsplit {
	    if {$p eq "#"} {
		return 1
	    } elseif {$p ne $n && $p ne "+"} {
		return 0
	    }
	}
	return 1
    }

    proc vbi {num} {
	set list {}
	while {$num > 127} {
	    lappend list [expr {$num & 0x7f | 0x80}]
	    set num [expr {$num >> 7}]
	}
	return [binary format c* [lappend list $num]]
    }

    proc byte {id val} {
	return [vbi $id][binary format c $val]
    }

    proc short {id val} {
	return [vbi $id][binary format S $val]
    }

    proc long {id val} {
	return [vbi $id][binary format I $val]
    }

    proc integer {id val} {
	return [vbi $id][vbi $val]
    }

    proc utf8 {id val} {
	set bytes [encoding convertto utf-8 $val]
        return [vbi $id][binary format S [string length $bytes]]$bytes
    }

    proc pair {id val} {
	lassign $val key value
	set rc [vbi $id]
	set bytes [encoding convertto utf-8 $key]
	append rc [binary format S [string length $bytes]] $bytes
	set bytes [encoding convertto utf-8 $value]
	append rc [binary format S [string length $bytes]] $bytes
    }

    proc bindata {id val} {
	return [vbi $id][binary format S [string length $val]]$val
    }

    proc reasontext {num} {
	variable reasoncode
	if {[dict exists $reasoncode $num]} {
	    return [lindex [dict get $reasoncode $num] 1]
	}
    }

    proc connecterror {num {ref ""}} {
	variable reasoncode
	if {![dict exists $reasoncode $num]} {set num 128}
	lassign [dict get $reasoncode $num] code str
	set opts [dict create -retcode $num]
	if {$ref ne ""} {dict set opts -location $ref}
	return -code error -level 2 -options $opts \
	  -errorcode [list MQTT CONNECTION REFUSED $code] $str
    }
}

# The base mqtt class implements all features for the latest supported version
# of the MQTT specification. Older MQTT versions are supported by mixing in a
# class that implements the differences. For this reason, new functionality
# should be implemented via a dedicated method so it can easily be skipped for
# older versions by defining a dummy method in the mixin class.

oo::class create mqtt {
    constructor {args} {
	namespace path [linsert [namespace path] end ::mqtt]
	variable config {
	    -keepalive		60
	    -retransmit		5000
	    -username		""
	    -password		""
	    -clean		1
	    -protocol		5
	    -socketcmd		socket
	}
	variable fd "" data "" queue {} connect {} coro "" events {}
	variable subscriptions {} seqnum 0 statustopic {$SYS/local}
	variable authentication {} authmethod {} topicalias {} aliasmax 0

	# Message types
	variable msgtype {
	    {}		CONNECT		CONNACK		PUBLISH
	    PUBACK	PUBREC		PUBREL		PUBCOMP
	    SUBSCRIBE	SUBACK	    	UNSUBSCRIBE	UNSUBACK
	    PINGREQ	PINGRESP	DISCONNECT	AUTH
	}

	# Assume some defaults until informed otherwise in CONNACK
	variable limits {
	    ReceiveMaximum 65536
	    MaximumQoS 2
	    RetainAvailable 1
	    MaximumPacketSize 0
	    TopicAliasMaximum 0
	    WildcardSubscriptionAvailable 1
	    SubscriptionIdentifierAvailable 1
	    SharedSubscriptionAvailable 1
	}

	my configure {*}[dict merge $config $args]
    }

    destructor {
	my disconnect
    }

    method protocol {} {
	return [my bin MQTT]
    }

    method validate {str {type topic}} {
	my variable limits
	# All Topic Names and Topic Filters MUST be at least one character
	# long [MQTT-4.7.3-1]
	if {$str eq ""} {return 0}
	set rec [split $str /]
	# The single-level wildcard can be used at any level in the Topic
	# Filter, including first and last levels. Where it is used it MUST
	# occupy an entire level of the filter [MQTT-4.7.1-2].
	foreach term [lsearch -all -inline $rec *+*] {
	    if {$type ne "filter"} {return 0}
	    if {$term ne "+"} {return 0}
	    if {![dict get $limits WildcardSubscriptionAvailable]} {return 0}
	}
	# The multi-level wildcard character MUST be specified either on its
	# own or following a topic level separator. In either case it MUST
	# be the last character specified in the Topic Filter [MQTT-4.7.1-1].
	foreach pos [lsearch -all $rec *#*] {
	    if {$type ne "filter"} {return 0}
	    if {$pos != [llength $rec] - 1} {return 0}
	    if {[lindex $rec $pos] ne "#"} {return 0}
	    if {![dict get $limits WildcardSubscriptionAvailable]} {return 0}
	}
	# Topic Names and Topic Filters MUST NOT include the null character
	# (Unicode U+0000) [MQTT-4.7.3-2]
	if {[string first \0 $str] >= 0} {return 0}
	# Topic Names and Topic Filters are UTF-8 encoded strings, they MUST
	# NOT encode to more than 65535 bytes [MQTT-4.7.3-3].
	if {[string length [encoding convertto utf-8]] > 65535} {return 0}
	# All checks passed
	return 1
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
			if {$val ni {3 4 5}} {
			    error "only protocol levels 3 (3.1), 4 (3.1.1),\
			      and 5 (5.0) are currently supported"
			}
			if {$val != [dict get $config $opt]} {
			    my variable fd
			    if {$fd ne ""} {
				error "cannot change the protocol version\
				  while connected"
			    }
			}
			# Mix in the specifics for the selected version
			oo::objdefine [self] mixin mqtt-v$val
		    }
		}
		dict set config $opt $val
	    }
	    return
	} else {
	    error "wrong # args:\
	      should be \"[self] configure ?-option value ...?\""
	}
    }

    method report {dir type dict} {
	lassign $dir dir client
	set str "[string totitle $dir] $type"
	if {$client ne ""} {
	    if {$dir eq "sending"} {
		append str " to $client"
	    } else {
		append str " from $client"
	    }
	}
	set arglist {}
	switch -- $type {
	    CONNECT {
		if {$dir eq "received"} {
		    set sock [namespace tail [info coroutine]]
		    set ip [lindex [fconfigure $sock -peer] 0]
		    set str "New client connected from $ip as $client"
		}
		lappend arglist p[dict get $dict version]
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
		  ([string length [dict get $dict message]] bytes)"
	    }
	    PUBREC - PUBREL - PUBCOMP - PUBACK {
		lappend arglist "Mid: [dict get $dict msgid]"
	    }
	    SUBSCRIBE {
		dict for {topic opts} [dict get $dict topics] {
		    set qos [expr {$opts & 3}]
		    append str \n "    $topic (QoS $qos)"
		    if {$dir eq "received"} {
			append str \n "$client $qos $topic"
		    }
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
			lappend arglist "Error $n"
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

    method structure {arglist args} {
	set rc {prop {}}
	set error 0
	while {1} {
	    switch [lindex $arglist 0] {
		-properties {
		    if {[llength $arglist] < 2} {incr error}
		    dict set rc prop [lindex $arglist 1]
		    set arglist [lrange $arglist 2 end]
		}
		-- {
		    set arglist [lrange $arglist 1 end]
		    break
		}
		default {
		    break
		}
	    }
	}
	set num 0
	foreach val $arglist arg $args {
	    lassign $arg name default
	    if {$num >= [llength $args]} {
		# Too many arguments
		incr error
	    } elseif {$num < [llength $arglist]} {
		dict set rc $name $val
	    } elseif {[llength $arg] == 2} {
		dict set rc $name $default
	    } else {
		# Not enough arguments
		incr error
	    }
	    incr num
	}
	if {!$error} {return $rc}
	# Build an error message
	set argspec [list {?-properties properties?}]
	foreach arg $args {
	    if {[llength $arg] < 2} {
		lappend argspec [lindex $arg 0]
	    } elseif {[lindex $arg 0] ne "void"} {
		lappend argspec "?[lindex $arg 0]?"
	    }
	}
	lassign [info level -1] object method
	return -level 2 -code error -errorcode {TCL WRONGARGS} \
	  "wrong # args: should be \"$object $method [join $argspec]\""
    }

    method connect {args} {
	my variable coro
	if {$coro ne ""} {error "illegal request"}
	set msg [my structure $args {client ""} {host localhost} {port 1883}]
	coroutine [self object]_coro my client $msg
    }

    method connack {} {
	payload bcu session retcode
	my properties
    }

    method reasoncode {remain} {
	if {!$remain} {
	    payload c0a0 reason prop
	} else {
	    payload cu reason
	    if {$remain > 1} {my properties}
	}
    }

    method suback {} {
	payload Su msgid
	my properties
	payload cu* results
    }

    method unsuback {} {
	payload cu* results
    }

    method disconnected {msg} {
	set code [dict get $msg reason]
	my status connection [dict create type DISCONNECT reason $code]
    }

    method challenge {fd msg} {
	my variable authentication
	set method [dict get $msg prop AuthenticationMethod]
	set challenge [dict get $msg prop AuthenticationData]
	if {[dict exists $authentication $method]} {
	    set callback [dict get $authentication $method]
	    set response [{*}$callback $challenge]
	} else {
	    # 131: Implementation specific error
	    my disconnect 131
	    return 0
	}
	set msg {reason 24 prop {}}
	dict lappend msg prop AuthenticationMethod $method
	dict lappend msg prop AuthenticationData $response
	my message $fd AUTH msg
	return 1
    }

    method disconnect {args} {
	my variable fd
	set msg [my structure $args {reason 0}]
	my notifier
	my message $fd DISCONNECT msg
	my finish
    }

    method finish {} {
	my variable timer coro
	if {$coro ne "" && $coro ne [info coroutine]} {
	    set coro [$coro destroy]
	}
	my close
	foreach n [array names timer] {
	    after cancel $timer($n)
	}
    }

    method close {{retcode 0}} {
	my variable fd
	if {$fd ne "" || $retcode != 0} {
	    my status connection \
	      [dict create type DISCONNECT reason $retcode]
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
	    if {[catch {uplevel #0 $cmd} result info]} {
		#log $result
		log [dict get $info -errorinfo]
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

    method varint {num} {
	set list {}
	while {$num > 127} {
	    lappend list [expr {$num & 0x7f | 0x80}]
	    set num [expr {$num >> 7}]
	}
	return [binary format c* [lappend list $num]]
    }

    method data {str} {
	return [my varint [string length $str]]$str
    }

    method will {args} {
	my variable connect

	set will [my structure $args topic {message ""} {qos 0} {retain ""}]
	if {[dict get $will topic] eq ""} {
	    dict unset connect will
	} else {
	    if {[dict get $will retain] eq ""} {
		dict set will retain \
		  [dict exists $will prop MessageExpiryInterval]
	    }
	    dict set connect will $will
	}
	return
    }

    method client {msg} {
	my variable connect queue pending aliasmax
	variable coro [info coroutine]

	set connect [dict merge $connect $msg]
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
	if {[dict exists $connect prop TopicAliasMaximum]} {
	    set aliasmax [dict get $connect prop TopicAliasMaximum]
	}

	set host [dict get $msg host]
	set port [dict get $msg port]
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
		set code [dict get $opts -retcode]
		my close $code
		if {$code == 156 || $code == 157} {
		    if {[dict exists $opts -location]} {
			set list [dict get $opts -location]
			# Pick a random server from the list
			set n [expr {int(rand() * [llength $list])}]
			set str [lindex $list $n]
			if {![regexp {^\[(.*)\](?::(\d+))$} $str -> host p]} {
			    lassign [split $str :] host p
			}
			if {$p eq ""} {set port 1883} else {set port $p}
			continue
		    }
		}
		# These are fatal errors, no need to retry
		break
	    } trap {MQTT} {result opts} {
		log "Failed to connect to broker: $result"
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
	if {[catch {{*}[my configure -socketcmd] -async $host $port} sock]} {
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
			    my message $sock CONNECT connect
			} else {
			    log "Connection failed: $error"
			    return 10000
			}
		    }
		    AUTH {
			lassign $args msg
			if {![my challenge $sock $msg]} return
		    }
		    CONNACK {
			lassign $args msg
			set retcode [dict get $msg retcode]
			my status connection $msg
			# A receiver MUST NOT carry forward any Topic Alias
			# mappings from one Network Connection to another
			# [MQTT-3.3.2-7].
			variable topicalias {} limits
			dict for {key val} $limits {
			    if {[dict exists $msg prop $key]} {
				dict set limits $key [dict get $msg prop $key]
			    }
			}
			if {!$retcode} {
			    # Connection Accepted
			    if {[dict exists $msg prop ServerKeepAlive]} {
				set sec [dict get $msg prop ServerKeepAlive]
				my variable config keepalive
				dict set config -keepalive $sec
				set keepalive [expr {1000 * $sec}]
				# Restart the keep-alive timer
				if {$keepalive > 0} {
				    my timer ping $keepalive \
				      [list [namespace which my] keepalive]
				}
			    }
			    if {[dict exists $msg prop AuthenticationMethod]} {
				# Remember the authentication method for
				# future re-authentication
				variable authmethod \
				  [dict get $msg prop AuthenticationMethod]
			    }
			} else {
			    set ref [if {[dict exists $msg prop ServerReference]} {
				dict get $msg prop ServerReference
			    }]
			    connecterror $retcode $ref
			}
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
	} trap {MQTT CONNECTION REFUSED} {} {
	    # The failure has already been reported
	} on error {err info} {
	    my status connection {type CONNECT reason 136}
	    # Rethrow the error
	    return -options [dict incr info -level] $err
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
	my subscriptions 1 [my session $msg]

	set ms [clock milliseconds]
	# Run the main loop as long as the connection is up
	fileevent $fd readable [list $coro receive $fd]
	# Default error code: Server unavailable
	set rc 136
	while {$fd ne "" && ![eof $fd]} {
	    # Send out any queued messages
	    set queue [lmap n $queue {
		lassign $n type msg
		if {[my message $fd $type msg]} continue
		# Keep messages that cannot be sent at this time
		# The messages may have been updated with a packet identifier
		list $type $msg
	    }]
	    set event [my receive $fd]
	    if {[set result [my handle $event]]} {
		set rc $result
		break
	    }
	}
	my close $rc
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

    method handle {event} {
	try {
	    my process {*}$event
	} on ok {} {
	    return 0
	} on continue {} {
	    return 24
	} trap {MQTT PROTOCOL} {reason info} {
	    set rc [lindex [dict get $info -errorcode] end]
	} on error {reason info} {
	    log [dict get $info -errorinfo]
	    set rc 128
	}
	my variable config
	if {[dict get $config -protocol] < 5} {
	    my disconnect
	} else {
	    my disconnect -properties [list ReasonString $reason] $rc
	}
	return $rc
    }

    method process {event {msg {}}} {
	my variable fd store topicalias aliasmax
	# Events: contact dead destroy noanswer queue receive wake
	switch -- $event {
	    PUBLISH {
		if {[dict exists $msg prop PayloadFormatIndicator]} {
		    if {[dict get $msg prop PayloadFormatIndicator]} {
			set data [dict get $msg message]
			dict set msg message [encoding convertfrom utf-8 $data]
		    }
		}
		if {[dict exists $msg prop TopicAlias]} {
		    set alias [dict get $msg prop TopicAlias]
		    if {$alias > $aliasmax} {
			# Topic Alias invalid
			throw {MQTT PROTOCOL 148} "topic alias out of range"
		    }
		    if {[dict get $msg topic] ne ""} {
			dict set topicalias $alias [dict get $msg topic]
		    } elseif {[dict exists $topicalias $alias]} {
			dict set msg topic [dict get $topicalias $alias]
		    } else {
			# Topic Alias invalid
			throw {MQTT PROTOCOL 148} "unknown topic alias"
		    }
		}
		# Notify all subscribers
		my notify $msg
		set ctrl [dict get $msg control]
		if {"assure" in $ctrl} {
		    set msgid [dict get $msg msgid]
		    # Store the data
		    set store($msgid) [list $msg]
		    # Indicate reception of the PUBLISH message
		    my message $fd PUBREC msg
		} else {
		    if {"ack" in $ctrl} {
			# Indicate reception of the PUBLISH message
			my message $fd PUBACK msg
		    }
		}
	    }
	    PUBACK {
		my ack PUBLISH $msg
	    }
	    PUBREC {
		my ack PUBLISH $msg
		if {![dict exists $msg reason] \
		  || [dict get $msg reason] < 0x80} {
		    my message $fd PUBREL msg
		}
	    }
	    PUBREL {
		my ack PUBREC $msg
		set msgid [dict get $msg msgid]
		if {[info exists store($msgid)]} {
		    unset store($msgid)
		}
		if {![dict exists $msg reason] \
		  || [dict get $msg reason] < 0x80} {
		    my message $fd PUBCOMP msg
		}
	    }
	    PUBCOMP {
		my ack PUBREL $msg
	    }
	    SUBACK {
		my ack SUBSCRIBE $msg
	    }
	    UNSUBACK {
		my ack UNSUBSCRIBE $msg
	    }
	    PINGRESP {
		variable pingmiss 0
		my timer pong cancel
	    }
	    DISCONNECT {
		my disconnected $msg
	    }
	    AUTH {
		# During the re-authentication sequence, the flow of other
		# packets between the Client and Server can continue using
		# the previous authentication.
		set reason [dict get $msg reason]
		# The only valid Authenticate Reason Codes are 0, 24, and 25
		if {$reason == 0} {
		    my status connection $msg
		    log "re-authentication succeeded"
		} elseif {$reason >= 128} {
		    # This is a protocol error
		    my disconnect 130
		    log "re-authentication failed: error code $reason"
		    return 0
		} elseif {![my challenge $fd $msg]} {
		    return 0
		}
	    }
	    CONNECT - CONNACK - SUBSCRIBE - UNSUBSCRIBE - PINGREQ {
		# The server should not be sending these messages at this point
		throw {MQTT MESSAGE UNEXPECTED} "unexpected message: $event"
	    }
	    dead {
		my variable pingmiss
		log "No PINGRESP received"
		if {[incr pingmiss] < 5} {
		    my keepalive
		} else {
		    my close 136
		    return 0
		}
	    }
	}
	return 1
    }

    method control {val} {
	set mask 0
	return [lmap n {retain ack assure dup} {
	    try {
		if {$val & 1 << $mask} {set n} else continue
	    } finally {
		incr mask
	    }
	}]
    }

    method receive {{fd ""}} {
	my variable data msgtype
	while 1 {
	    # Send out notifications and then wait for something to happen
	    set rc [yieldto my notifier]
	    if {[lindex $rc 0] ne "receive"} {return $rc}
	    if {[eof $fd]} {return EOF}
	    set size [string length $data]
	    # A message is at least 2 bytes
	    if {$size < 2} {
		append data [read $fd [expr {2 - $size}]]
		set size [string length $data]
	    }
	    if {[binary scan $data cucu hdr len] < 2} continue
	    set ptr 2
	    if {$size < $ptr + $len} {
		append data [read $fd [expr {$ptr + $len - $size}]]
		set size [string length $data]
	    }
	    if {$size < $ptr + $len} continue
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

	    set size \
	      [coroutine payload my payload [string range $data $ptr end]]
	    set type [lindex $msgtype [expr {$hdr >> 4}]]
	    set control [my control $hdr]
	    set msg $data
	    set data ""

	    try {
		set rc [dict create type $type control $control]
		set rc [dict merge $rc [my decode $type $control $msg $size]]
		my report received $type $rc
	    } trap {MQTT PAYLOAD} {result err} {
		my invalid $msg
		if {[llength [namespace which payload]]} {rename payload {}}
	    } on error {- err} {
		log [dict get $err -errorinfo]
		if {[llength [namespace which payload]]} {rename payload {}}
	    }
	    return [list $type $rc]
	}
    }

    method decode {type control msg size} {
	switch -- $type {
	    CONNACK {
		my connack
	    }
	    PUBLISH {
		my string topic
		if {"assure" in $control || "ack" in $control} {
		    payload Su msgid
		}
		my properties
		payload a* message
	    }
	    PUBACK - PUBREC - PUBREL - PUBCOMP {
		payload Su msgid
		my reasoncode [expr {$size - 2}]
	    }
	    SUBACK {
		my suback
	    }
	    UNSUBACK {
		payload Su msgid
		my properties
		my unsuback
	    }
	    PINGRESP {}
	    DISCONNECT - AUTH {
		my reasoncode $size
	    }
	    CONNECT - SUBSCRIBE - UNSUBSCRIBE - PINGREQ {
		throw {MQTT MESSAGE UNEXPECTED} "Unexpected message: $type"
	    }
	    default {
		throw {MQTT PAYLOAD UNKNOWN} "Unknown payload: $type"
	    }
	}
	return [payload]
    }

    method payload {data} {
	set pos 0
	set len [string length $data]
	set msg {}
	set args [lassign [yieldto list $len] spec]
	while {$spec ne "" || [llength $args]} {
	    # {([Xx]\d*)?[aAbBhHcsStiInwWmfrRdqQ]u?(?:\d*|\*)}
	    set parts [regexp -all -inline \
	      {(?:[Xx]\d*)?[aAbBhHcsStiInwWmfrRdqQ]u?(?:\d*|\*)} $spec]
	    set vars {}
	    set cnt [llength $parts]
	    for {set i 1} {$i <= $cnt} {incr i} {lappend vars $i}
	    if {[binary scan $data @$pos$spec {*}$vars] != $cnt} {
		binary scan $data H* hex
		throw {MQTT PAYLOAD DEPLETED} "payload too short"
	    }
	    set result [lmap v $vars {set $v}]
	    foreach a $args v $result p $parts {
		if {$a eq ""} break
		# Remove any leading cursor movement instructions
		set p [string trimleft $p {xX0123456789}]
		if {[string match {[aA]u*} $p]} {
		    set v [encoding convertfrom utf-8 $v]
		} elseif {[string match {[csSiI]0} $p]} {
		    set v 0
		} elseif {[string match {cu0*} $p]} {
		    # Variable Byte Integer
		    foreach b [lassign [lreverse $v] v] {
			set v [expr {($v << 7) | ($b & 0x7f)}]
		    }
		}
		if {[lindex $a end-1] eq "prop"} {
		    # Some properties can occur more than once
		    set prop [lindex $a end]
		    set path [lrange $a 0 end-1]
		    set list [if {[dict exists $msg {*}$path]} {
			dict get $msg {*}$path
		    }]
		    dict set msg {*}$path [linsert $list end $prop $v]
		} else {
		    dict set msg {*}$a $v
		}
	    }
	    # Unfortunately there is no way to get the internal cursor from
	    # [binary scan]. So we need to reformat the parsed binary data.
	    set newpos [string length [binary format x$pos$spec {*}$result]]
	    set cnt [expr {$newpos - $pos}]
	    set pos $newpos
	    set args \
	      [lassign [yieldto return -level 0 -count $cnt $result] spec]
	}
	return $msg
    }

    method string {{name ""}} {
	lassign [payload Su] len
	lassign [payload au$len $name] data
	return -count [incr len 2] [encoding convertfrom utf-8 $data]
    }

    method vbi {{name ""}} {
	set val 0
	for {set cnt 1} {$cnt <= 4} {incr cnt} {
	    set byte [payload cu]
	    incr val [expr {($byte & 0x7f) << 7 * ($cnt - 1)}]
	    if {($byte & 0x80) == 0} {
		if {$name ne ""} {payload [format X%dcu%02d $cnt $cnt] $name}
		return -count $cnt $val
	    }
	}
	throw {MQTT PAYLOAD BADVBI} "malformed variable byte integer"
    }

    method bindata {{name ""}} {
	lassign [payload Su] len
	lassign [payload cu$len $name] data
	return -count [incr len 2] $data
    }

    method stringpair {{name ""}} {
	lassign [payload Su] l1
        lassign [payload au$l1] data
	set key [encoding convertfrom utf-8 $data]
	if {$name ne ""} {lappend name $key}
	lassign [payload Su] l2
	lassign [payload au$l2 $name] data
	set val [encoding convertfrom utf-8 $data]
	return -count [expr {$l1 + $l2 + 4}] [dict create $key $val]
    }

    method ack {type ack} {
	my variable pending
	set msgid [dict get $ack msgid]
	if {![info exists pending($type,$msgid)]} return
	my timer $msgid cancel
	set msg [dict get $pending($type,$msgid) msg]
	if {[dict exists $ack reason]} {
	    set reason [dict get $ack reason]
	} else {
	    set reason 0
	}
	if {$reason < 128} {
	    # Don't clean up a qos=2 PUBLISH message until the PUBCOMP is
	    # received, because if the connection drops, the PUBLISH needs
	    # to be reissued
	    if {$type eq "PUBLISH" && "assure" in [dict get $msg control]} {
		return
	    }
	}
	unset pending($type,$msgid)
	switch -- $type {
	    PUBLISH {
		my status publication [dict merge $msg $ack]
	    }
	    PUBREL {
		if {[info exists pending(PUBLISH,$msgid)]} {
		    set msg [dict get $pending(PUBLISH,$msgid) msg]
		    unset pending(PUBLISH,$msgid)
		    my status publication [dict merge $msg $ack]
		}
	    }
	    SUBSCRIBE - UNSUBSCRIBE {
		my status subscription [dict merge $msg $ack]
	    }
	    default {
		if {$reason >= 128} {
		    my status publication [dict merge $msg $ack]
		}
	    }
	}
    }

    method invalid {msg} {
	binary scan $msg H* hex
	log "Invalid message: [regexp -all -inline .. $hex]"
	return
    }

    method status {notification msg} {
	my variable statustopic subscriptions
	set msg [dict merge {control {} prop {}} $msg]
	switch $notification {
	    connection {
		set data [dict create state disconnected]
		if {[dict get $msg type] eq "CONNACK"} {
		    set code [dict get $msg retcode]
		    if {!$code} {
			set data [dict create state connected]
			if {[dict exists $msg session]} {
			    dict set data session [dict get $msg session]
			}
		    } else {
			dict set data reason $code
			dict set data text [reasontext $code]
		    }
		} elseif {[dict get $msg type] eq "AUTH"} {
		    set data [dict create state connected]
		} elseif {[dict exists $msg reason]} {
		    set code [dict get $msg reason]
		    dict set data reason $code
		    if {!$code} {
			# Normal disconnection
			set str "normal disconnection"
		    } else {
			set str [reasontext $code]
		    }
		    dict set data text $str
		}
	    }
	    publication {
		dict set data topic [dict get $msg topic]
                dict set data data [dict get $msg message]
		if {[dict exists $msg reason]} {
		    dict set data result [dict get $msg reason]
		}
	    }
	    subscription {
		set data {}
		set topics [dict get $msg topics]
		foreach {topic qos} $topics code [dict get $msg results] {
		    if {$qos ne ""} {
			dict set data $topic $code
			dict set subscriptions $topic ack $code
		    } else {
			# Use negative error codes for unsubscribes
			dict set data $topic [if {$code} {expr {-$code}}]
			# Don't delete any new subscription requests that
			# happened while the unsubscribe was in transit
			if {[dict exists $subscriptions $topic callback]} {
			    dict set subscriptions $topic ack ""
			} else {
			    dict unset subscriptions $topic
			}
		    }
		}
	    }
	}
	dict set msg topic $statustopic/$notification
	my notify [dict set msg message $data]
    }

    method notify {msg} {
	# Do not immediately invoke the registered callbacks, in case they
	# perform commands that need to call into the coroutine again
	my variable events
	set event [list [dict get $msg topic] [dict get $msg message]]
	lappend event [expr {"retain" in [dict get $msg control]}]
	# For better compatibility with Tcl mqtt 2, only add the properties
	# argument if there are properties.
	if {[dict exists $msg prop] && [dict size [dict get $msg prop]]} {
	    lappend event [dict get $msg prop]
	}
	lappend events $event
    }

    method notifier {} {
	my variable events subscriptions
	# Can't use a foreach here because the callbacks may call back into
	# the coroutine, which could affect the list of events
	while {[llength $events]} {
	    set events [lassign $events event]
	    set args [lassign $event topic]
	    dict for {pat dict} $subscriptions {
		if {[match $pat $topic]} {
		    if {[dict exists $dict callback]} {
			set pfx [dict get $dict callback]
		    } else {
			continue
		    }
		    try {
			uplevel #0 [linsert $pfx end $topic {*}$args]
		    } on error {msg opts} {
			log "Callback '$pfx' for $pat failed: $msg"
			# Disable the faulty callback
			my unsubscribe $pat $pfx
		    }
		}
	    }
	}
    }

    method message {fd type {msgvar {}}} {
	my variable msgtype pending coro keepalive limits
	# Can only send a message when connected
	if {$fd eq ""} {return 0}

	if {$msgvar ne ""} {upvar 1 $msgvar msg} else {set msg {}}
	# Build the payload depending on the message type
	set payload [my $type msg]
	set maxsize [dict get $limits MaximumPacketSize]

	if {$maxsize} {
	    # Overhead: Header = 1 byte, payload length = 1..4 bytes
	    set overhead [expr {1 + [string length [my varint $maxsize]]}]
	    set space [expr {$maxsize - [string length $payload] - $overhead}]
	    if {$space < 0} {
		# Message is too large
		# Check if discarding ReasonString and UserProperty helps
		set save [lmap {key value} [dict get $msg prop] {
		    switch $key {
			ReasonString {
			    set len [string length [prop 31 utf8 $value]]
			}
			UserProperty {
			    set len [string length [prop 38 pair $value]]
			}
			default {
			    continue
			}
		    }
		    incr space $len
		    set len
		}]
		if {$space < 0} {
		    # It's impossible to free up enough space to meet the limit
		    log "Message too large - discarded"
		    return -1
		}
		# Determine exactly which properties must be discarded
		set props {}
		foreach {key value} [dict get $msg prop] {
		    if {$key in {ReasonString UserProperty}} {
			set save [lassign $save len]
			if {$len > $space} continue
			# This property still fits in the available space
			set space [expr {$space - $len}]
		    }
		    lappend props $key $value
		}
		# Reduce the message properties to the set that will fit
		dict set msg prop $props
		# Rebuild the message with the modified set of properties
		set payload [my $type msg]
		if {$payload eq ""} {return -1}
	    }
	}
	dict set msg payload $payload

	# Determine the Quality of Service value
	set control [dict get $msg control]
	if {"assure" in $control} {
	    set qos 2
	} elseif {"ack" in $control} {
	    set qos 1
	} else {
	    set qos 0
	}
	if {$qos > [dict get $limits MaximumQoS]} {
	    set qos [dict get $limits MaximumQoS]
	}

	if {$qos > 0} {
	    if {$type eq "PUBLISH"} {
		set inflight [llength [array names pending PUBLISH,*]]
		# Disregard the pending incoming messages
		if {$inflight >= [dict get $limits ReceiveMaximum]} {
		    # This message can not be sent at this time
		    return 0
		}
	    }
	    set msgid [dict get $msg msgid]
	    dict set pending($type,$msgid) msg $msg
	    dict incr pending($type,$msgid) count
	    set ms [my configure -retransmit]
	    set cmd [list [namespace which my] retransmit $type $msgid]
	    my timer $msgid $ms $cmd
	    if {[dict get $pending($type,$msgid) count] > 1} {
		if {[my dup $type] && "dup" ni $control} {
		    dict set msg control [lappend control dup]
		}
	    }
	}

	# Build the header byte
	set hdr [expr {[lsearch -exact $msgtype $type] << 4 | $qos << 1}]
	if {"dup" in $control} {set hdr [expr {$hdr | 0b1000}]}
	if {"retain" in $control} {
	    if {[dict get $limits RetainAvailable]} {
		set hdr [expr {$hdr | 0b1}]
	    } else {
		log "Retain flag dropped - server does not support retain"
	    }
	}

	my report sending $type $msg

	# Send the message
	set data [binary format c $hdr][my data $payload]
	if {[catch {puts -nonewline $fd $data}]} {
	    return 0
	} else {
	    # Restart the keep-alive timer
	    if {$keepalive > 0} {
		my timer ping $keepalive [list [namespace which my] keepalive]
	    }
	    return 1
	}
    }

    method session {msg} {
	dict get $msg session
    }

    method dup {type} {
	# There is a difference in the way the DUP flag is described
	# in spec 3.1 and 3.1.1. According to 3.1.1 the DUP flag
	# should not be set in PUBREL, SUBSCRIBE, UNSUBSCRIBE messages
	return [expr {$type eq "PUBLISH"}]
    }

    method retransmit {type msgid} {
	my variable pending fd
	if {[info exists pending($type,$msgid)]} {
	    set msg [dict get $pending($type,$msgid) msg]
	    if {[dict get $pending($type,$msgid) count] <= 5} {
		my message $fd $type msg
	    } else {
		log "Server failed to respond"
		unset pending($type,$msgid)
		# my close 136
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

    # subscriptions:
    #   <pattern>
    #     callback <prefix>
    #     opts <options>
    #     prop <properties>
    #     ack <ack>
    method subscriptions {{init 0} {session 0}} {
	my variable subscriptions queue statustopic fd
	set delta {}
	# On a new clean session, all subscriptions must be reinstated
	if {$init && !$session} {
	    # Reinstate subscriptions
	    dict for {pat dict} $subscriptions {
		set opts [dict get $dict opts]
		if {$opts ne "" && ![string match $statustopic/* $pat]} {
		    if {$opts >= 0} {
			dict set delta $pat $dict
			dict set subscriptions $pat ack {}
		    }
		}
	    }
	}
	# Check for queued SUBSCRIBE and UNSUBSCRIBE requests
	set list [lsearch -all -inline -index 0 $queue *SUBSCRIBE]
	if {[dict size $delta] == 0 && [llength $list] == 0} return

	# Remove the SUBSCRIBE and UNSUBSCRIBE requests from the queue
	set queue [lsearch -all -inline -not -index 0 $queue *SUBSCRIBE]

	set notify {}
	# Process queued SUBSCRIBE and UNSUBSCRIBE request
	# These requests have already been applied to the subscriptions dict
	foreach n $list {
	    lassign $n type msg
	    dict for {pat opts} [dict get $msg topics] {
		if {![dict exists $subscriptions $pat ack]} continue
		if {[string match $statustopic/* $pat]} {
		    # Special treatment for local status topics
		    if {[dict get $subscriptions $pat opts] ne ""} {
			set qos [if {$opts ne ""} {expr {$opts & 3}}]
			dict set subscriptions $pat ack $qos
		    } elseif {[dict exists $subscriptions $pat]} {
			# Unsubscribed
			dict unset subscriptions $pat
			set qos ""
		    } else {
			# No subscription existed
			set qos 17
		    }
		    dict set notify $pat $qos
		} elseif {$fd eq ""} {
		    # Cannot handle this request when not yet connected
		    # Place the request back in the queue
		    lappend queue $n
		} else {
		    # Subscription to be updated
		    dict set delta $pat [dict get $subscriptions $pat]
		}
	    }
	}

	if {$fd eq ""} {tailcall my notifier}

	# Combine multiple subscriptions into one message, if possible
	set sub {}
	set unsub {}
	dict for {pat dict} $delta {
	    set ack [dict get $subscriptions $pat ack]
	    set opts [dict get $subscriptions $pat opts]
	    if {$opts ne ""} {
		# Not subscribed yet
		# Need to send a SUBSCRIBE message
		# Only combine subscriptions without properties
		set prop [dict get $dict properties]
		set key [if {[dict size $prop]} {incr seqnum}]
		dict set sub $key topics $pat $opts
		dict set sub $key prop $prop
	    } elseif {$ack ne "" || $session} {
		# Subscription is in place
		# Need to send an UNSUBSCRIBE message
		# Only combine unsubscriptions without properties
		set prop [dict get $dict properties]
		set key [if {[dict size $prop]} {incr seqnum}]
		dict set unsub $key topics $pat $opts
		dict set unsub $key prop $prop
	    } else {
		# Notify interested parties that the subscription is gone
		dict set notify $pat $ack
		dict unset subscriptions $pat
	    }
	}

	# Actually send the messages
	dict for {key msg} $unsub {
	    my message $fd UNSUBSCRIBE msg
	}
	dict for {key msg} $sub {
	    my message $fd SUBSCRIBE msg
	}
    }

    method subscribe {args} {
	my variable subscriptions subscriptionid
	set msg [my structure $args \
	  pattern prefix {qos 2} {nl 0} {rap 0} {rh 0}]
	dict with msg {
	    if {$qos > 2} {set qos 2}
	}
	if {![my validate $pattern filter]} {
	    return -code error -errorcode {MQTT FILTER INVALID} \
	      "invalid topic filter: $pattern"
	}
	if {![dict exists $subscriptions $pattern ack]} {
	    dict set subscriptions $pattern {
		ack "" callback {} properties {} opts 0
	    }
	    if {$qos < 0} {
		dict set subscriptions $pattern ack $qos
		dict set subscriptions $pattern opts -1
	    }
	}
	dict with subscriptions $pattern {
	    set callback $prefix
	    if {$qos >= 0} {
		set opts [expr {$qos | $nl << 2 | $rap << 3 | $rh << 4}]
		set properties $prop
		dict set msg topics $pattern $opts
		my queue SUBSCRIBE $msg
	    }
	}
	return
    }

    method unsubscribe {args} {
	my variable subscriptions
	# A second argument is allowed for backward compatibility
	# The special name "void" means it is omitted from the error message
	set dict [my structure $args pattern {void ""}]
	dict with dict {}
	dict set subscriptions $pattern opts ""
	dict set subscriptions $pattern properties $prop
	dict set subscriptions $pattern callback {}
	set msg [dict create topics [dict create $pattern {}] properties $prop]
	my queue UNSUBSCRIBE $msg
	return
    }

    method publish {args} {
	set msg [my structure $args topic message {qos 0} {retain ""}]
	dict with msg {}
	if {$topic eq "" && [dict exists $prop TopicAlias]} {
	    # Empty topic is allowed when using a topic alias
	} elseif {![my validate $topic]} {
	    return -code error -errorcode {MQTT TOPICNAME INVALID} \
	      "invalid topic name: $topic"
	}
	set control [lindex {{} ack assure} $qos]
	if {[dict exists $prop MessageExpiryInterval]} {
	    dict set msg expire \
	      [expr {[clock seconds] + [dict get $prop MessageExpiryInterval]}]
	    if {$retain eq ""} {set retain 1}
	} elseif {$retain eq ""} {
	    set retain 0
	}
	if {[dict exists $msg prop PayloadFormatIndicator]} {
	    if {[dict get $msg prop PayloadFormatIndicator]} {
		dict set msg message [encoding convertto utf-8 $message]
	    }
	}
	if {$retain} {lappend control retain}
	dict set msg control $control
	my queue PUBLISH $msg
	return
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

    method reason {type var} {
	upvar 1 $var msg
	if {[dict exists $msg reason]} {
	    set reason [dict get $msg reason]
	    set props [llength [dict get $msg prop]]
	} else {
	    set reason 0
	    set props 0
	}
	if {$reason || $props} {
	    set rc [binary format c $reason]
	    if {$props} {append rc [my props $type msg]}
	    return $rc
	} else {
	    return
	}
    }

    method props {packet var} {
        upvar 1 $var dict
	set data {}
        if {[dict exists $dict prop]} {
	    foreach {key val} [dict get $dict prop] {
		append data [switch -glob $packet,$key {
		    publish,PayloadFormatIndicator -
		    will,PayloadFormatIndicator {prop 1 byte $val}
		    publish,MessageExpiryInterval -
		    will,MessageExpiryInterval {prop 2 long $val}
		    publish,ContentType -
		    will,ContentType {prop 3 utf8 $val}
		    publish,ResponseTopic -
		    will,ResponseTopic {prop 8 utf8 $val}
		    publish,CorrelationData -
		    will,CorrelationData {prop 9 bindata $val}
		    publish,SubscriptionIdentifier -
		    subscribe,SubscriptionIdentifier {prop 11 integer $val}
		    conn*,SessionExpiryInterval -
		    disconnect,SessionExpiryInterval {prop 17 long $val}
		    connack,AssignedClientIdentifier {prop 18 utf8 $val}
		    connack,ServerKeepAlive {prop 19 short $val}
		    conn*,AuthenticationMethod -
		    auth,AuthenticationMethod {prop 21 utf8 $val}
		    conn*,AuthenticationData -
		    auth,AuthenticationData {prop 22 bindata $val}
		    connect,RequestProblemInformation {prop 23 byte $val}
		    will,WillDelayInterval {prop 24 long $val}
		    connect,RequestResponseInformation {prop 25 byte $val}
		    connack,ResponseInformation {prop 26 utf8 $val}
		    connack,ServerReference -
		    disconnect,ServerReference {prop 28 utf8 $val}
		    connack,ReasonString -
		    puback,ReasonString -
		    pubrec,ReasonString -
		    pubrel,ReasonString -
		    pubcomp,ReasonString -
		    suback,ReasonString -
		    unsuback,ReasonString -
		    disconnect,ReasonString -
		    auth,ReasonString {prop 31 utf8 $val}
		    conn*,ReceiveMaximum {prop 33 short $val}
		    conn*,TopicAliasMaximum {prop 34 short $val}
		    publish,TopicAlias {prop 35 short $val}
		    connack,MaximumQoS {prop 36 byte $val}
		    connack,RetainAvailable {prop 37 byte $val}
		    *,UserProperty {prop 38 pair $val}
		    conn*,MaximumPacketSize {prop 39 long $val}
		    connack,WildcardSubscriptionAvailable {prop 40 byte $val}
		    connack,SubscriptionIdentifierAvailable {prop 41 byte $val}
		    connack,SharedSubscriptionAvailable {prop 42 byte $val}
		    default {
			if {$packet eq "will"} {
			    set str "in will properties"
			} else {
			    set str "inside a [string toupper $packet] packet"
			}
			throw {MQTT PROPERTY ILLEGAL} \
			  "property \"$key\" is not allowed $str"
		    }
		}]
	    }
	}
	return [my data $data]
    }

    method properties {args} {
	try {my vbi} on ok {len opts} {
	    set rc [expr {$len + [dict get $opts -count]}]
	}
	lappend args prop name
	while {$len > 0} {
	    try {
		set prop [my vbi]
		switch $prop {
		    1 {payload cu [lset args end PayloadFormatIndicator]}
		    2 {payload Iu [lset args end MessageExpiryInterval]}
		    3 {my string [lset args end ContentType]}
		    8 {my string [lset args end ResponseTopic]}
		    9 {my bindata [lset args end CorrelationData]}
		    11 {my vbi [lset args end SubscriptionIdentifier]}
		    17 {payload Iu [lset args end SessionExpiryInterval]}
		    18 {my string [lset args end AssignedClientIdentifier]}
		    19 {payload Su [lset args end ServerKeepAlive]}
		    21 {my string [lset args end AuthenticationMethod]}
		    22 {my bindata [lset args end AuthenticationData]}
		    23 {payload cu [lset args end RequestProblemInformation]}
		    24 {payload Iu [lset args end WillDelayInterval]}
		    25 {payload cu [lset args end RequestResponseInformation]}
		    26 {my string [lset args end ResponseInformation]}
		    28 {my string [lset args end ServerReference]}
		    31 {my string [lset args end ReasonString]}
		    33 {payload Su [lset args end ReceiveMaximum]}
		    34 {payload Su [lset args end TopicAliasMaximum]}
		    35 {payload Su [lset args end TopicAlias]}
		    36 {payload cu [lset args end MaximumQoS]}
		    37 {payload cu [lset args end RetainAvailable]}
		    38 {my stringpair [lset args end UserProperty]}
		    39 {payload Iu [lset args end MaximumPacketSize]}
		    40 {payload cu [lset args end WildcardSubscriptionAvailable]}
		    41 {payload cu [lset args end SubscriptionIdentifierAvailable]}
		    42 {payload cu [lset args end SharedSubscriptionAvailable]}
		}
	    } on ok {- opts} {
		if {[dict exists $opts -count]} {
		    set len [expr {$len - 1 - [dict get $opts -count]}]
		}
	    }
	}
	return $rc
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
	    dict update msg will will {
		append payload [my props will will]
	    }
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
	dict set msg version $level
	set data [my protocol]
	append data [binary format ccS $level $flags [dict get $msg keepalive]]
	append data [my props connect msg]
	append data $payload
	return $data
    }

    method PUBLISH {msgvar} {
	upvar 1 $msgvar msg
	set msg [dict merge {control {} message ""} $msg]
	set data [my bin [dict get $msg topic]]
	set control [dict get $msg control]
	if {"ack" in $control || "assure" in $control} {
	    append data [my seqnum msg]
	}
	if {[dict exists $msg expire]} {
	    set interval [expr {[dict get $msg expire] - [clock seconds]}]
	    if {$interval < 0} {
		log "Message has expired - discarded"
		return -code return -1
	    }
	    set properties {}
	    foreach {k v} [dict get $msg prop] {
		if {$k eq "MessageExpiryInterval"} {
		    set v $interval
		}
		lappend properties $k $v
	    }
	    dict set msg prop $properties
	}
	append data [my props publish msg]
	append data [dict get $msg message]
	return $data
    }

    method PUBACK {msgvar} {
	upvar 1 $msgvar msg
	dict set msg control {}
	set data [my seqnum msg]
	append data [my reason puback msg]
	return $data
    }

    method PUBREC {msgvar} {
	upvar 1 $msgvar msg
	dict set msg control {}
	set data [my seqnum msg]
	append data [my reason pubrec msg]
	return $data	
    }

    method PUBREL {msgvar} {
	upvar 1 $msgvar msg
	set msg [dict merge $msg {control ack}]
	set data [my seqnum msg]
	append data [my reason pubrel msg]
	return $data

	return [my seqnum msg]
    }

    method PUBCOMP {msgvar} {
	upvar 1 $msgvar msg
	dict set msg control {}
	set data [my seqnum msg]
	append data [my reason pubcomp msg]
	return $data

	return [binary format S [dict get $msg msgid]]
    }

    method SUBSCRIBE {msgvar} {
	upvar 1 $msgvar msg
	set msg [dict merge {topics {}} $msg {control ack}]
	set data [my seqnum msg]
	append data [my props subscribe msg]
	dict for {topic qos} [dict get $msg topics] {
	    append data [my bin $topic]
	    append data [binary format c $qos]
	}
	return $data
    }

    method UNSUBSCRIBE {msgvar} {
	upvar 1 $msgvar msg
	set msg [dict merge {topics {}} $msg {control ack}]
	set data [my seqnum msg]
	append data [my props unsubscribe msg]
	dict for {topic qos} [dict get $msg topics] {
	    append data [my bin $topic]
	}
	return $data
    }

    method PINGREQ {msgvar} {
	upvar 1 $msgvar msg
	set msg {control {}}
	return
    }

    method DISCONNECT {msgvar} {
	upvar 1 $msgvar msg
	dict set msg control {}
	return [my reason disconnect msg]
    }

    method AUTH {msgvar} {
	upvar 1 $msgvar msg
	dict set msg control {}
	return [my reason auth msg]
    }

    # Hide private methods that would otherwise be visible
    unexport ack bin bindata challenge client close connack control
    unexport data decode dialog disconnected dup finish handle invalid
    unexport keepalive match message notifier notify payload process
    unexport properties props protocol queue receive reason reasoncode report
    unexport seqnum session sleep status string stringpair structure suback
    unexport subscriptions timer retransmit unsuback validate varint vbi
}

oo::objdefine mqtt {forward log ::mqtt::logpfx}

# Version specific methods
oo::class create mqtt-v5 {
    method authentication {method prefix} {
	my variable authentication
	if {$prefix ne ""} {
	    dict set authentication $method $prefix
	} else {
	    dict unset authentication $method
	}
	return
    }

    method reauthenticate {args} {
	my variable fd authmethod
	if {$fd eq ""} {
	    throw {MQTT CONNECTION AUTH} \
	      "cannot re-authenticate when not connected"
	} elseif {$authmethod eq ""} {
	    throw {MQTT CONNECTION AUTH} \
	      "connection not established with enhanced authentication"
	} else {
	    set msg [my structure $args]
	    if {![dict exists $msg prop AuthenticationMethod]} {
		dict lappend msg prop AuthenticationMethod $authmethod
	    }
	    dict set msg reason 25
	    my message $fd AUTH msg
	}
    }
}

# Undo the differences between MQTT v3.1.1 (4) and v5 (5)
oo::class create mqtt-v4 {

    # Server assigned ClientIDs can only be used with Clean Session=1
    # (v5: Returns the ClientID in the Assigned Client Identifier property)
    method connect {{name ""} {host localhost} {port 1883}} {
	if {$name eq "" && ![my configure -clean]} {
	    error "a zero-length client identifier is not allowed\
	      when the -clean option is set to false"
	}
	next -- $name $host $port
    }

    # Disconnect Reason Code values are different
    method close {{retcode 0}} {
	if {$retcode < 128} {
	    next $retcode
	} else {
	    set map {132 1 133 2 134 4 135 5 136 3}
	    if {[dict exists $map $retcode]} {
		next [dict get $map $retcode]
	    } else {
		next -1
	    }
	}
    }

    # Report topic, data, retain flag (v5: Add properties)
    method notify {msg} {
	# Do not immediately invoke the registered callbacks, in case they
	# perform commands that need to call into the coroutine again
	my variable events
	lappend events [list [dict get $msg topic] [dict get $msg message] \
	  [expr {"retain" in [dict get $msg control]}]]
    }

    # Disconnect has no parameters (v5: Disconnect Reason Code and Properties)
    method disconnect {} {next}

    # Will parameters have changed (v5: Add Properties)
    method will {topic {message ""} {qos 0} {retain 0}} {
	next -- $topic $message $qos $retain
    }

    # Subscribe parameters have changed (v5: Add Properties, nl, rap, rh)
    method subscribe {pattern prefix {qos 2}} {
	next -- $pattern $prefix $qos
    }

    # Unsubscribe parameters have changed (v5: Add Properties)
    # Accept a prefix for backward compatibility
    method unsubscribe {pattern {prefix ""}} {
	next -- $pattern
    }

    # Publish parameters have changed (v5: Add Properties)
    method publish {topic message {qos 0} {retain 0}} {
	next -- $topic $message $qos $retain
    }

    # UNSUBACK has no payload (v5: List of reason codes) 
    method unsuback {} {
	payload c0 results
    }

    method disconnected {} {
	# The server should not be sending a DISCONNECT messages
	throw {MQTT MESSAGE UNEXPECTED} "unexpected message: DISCONNECT"
    }

    # Missing data elements (v5: Introduce Reason Code and Properties)
    method reason args {}
    method props args {}
    method reasoncode args {}
    method properties args {return 0}
}

# Undo the differences between MQTT v3.1 (3) and v3.1.1 (4)
oo::class create mqtt-v3 {
    superclass mqtt-v4
    # The method chain is: mqtt-v3 -> mqtt-v4 -> mqtt

    # Protocol Name: MQIsdp
    method protocol {} {
	return [my bin MQIsdp]
    }

    # ClientID is limited to 23 characters (v3.1.1: 65536)
    # Empty ClientID is not allowed (v3.1.1: Server assigns a ClientID)
    method connect {name {host localhost} {port 1883}} {
	if {$name eq "" || [string length $name] > 23} {
	    error [format {invalid client identifier: "%s"} $name]
	}
	nextto mqtt -- $name $host $port
    }

    # Resume session when Clean Session=0
    # (v3.1.1: Session Present indication in connect acknowledge flags)
    method session {msg} {
	return [string is false [my configure -clean]]
    }

    # All Connect Acknowledge Flags are reserved (v3.1.1: bit0=Session Present)
    method connack {} {
	payload cucu reserved retcode
    }

    # All retried messages have DUP bit set (v3.1.1: Only PUBLISH uses DUP bit)
    method dup {type} {
	return 1
    }
}
