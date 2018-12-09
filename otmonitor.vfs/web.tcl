package require wibble

# Allow resourcing
wibble reset

proc webinit {} {
    global cfg
    set rc [dict create http {port 0} https {port 0}]
    # Try to start the http server
    if {$cfg(web,port) > 0} {
	if {![catch {wibble listen $cfg(web,port)} fd]} {
	    dict set rc http [dict create fd $fd port $cfg(web,port)]
	} else {
	    # puts "Couldn't start wibble on port $cfg(web,port)"
	}
    }
    # Try to start the https server
    if {$cfg(web,sslport) > 0} {
	set ssldir [file join [file dirname $starkit::topdir] auth]
	foreach {v n} {keyfile server.key crtfile server.crt rootcrt CA.crt} {
	    set $v [file join $ssldir $n]
	}
	# Check the necessary files are present
	if {![file exists $keyfile] || ![file exists $crtfile]} {
	    # puts "Missing $keyfile or $crtfile"
	    return $rc
	}
	if {[catch {package require tls} tlsver]} {
	    # puts "Couldn't load tls package"
	    return $rc
	}
	set cmd [list tls::socket -command callback \
	  -certfile $crtfile -keyfile $keyfile -cafile $rootcrt]
	if {[file exists $rootcrt]} {
	    set require [expr {!!$cfg(web,certonly)}]
	    lappend cmd -request 1 -require $require
	} else {
	    lappend cmd -request 0 -require 0
	}
	set protocols {ssl2 ssl3 tls1}
	if {[package vsatisfies $tlsver 1.6.4-]} {
	    lappend protocols tls1.1 tls1.2
	}
	set enableprot [split $cfg(web,sslprotocols) {, }]
	foreach prot $protocols {
	    lappend cmd -$prot [expr {$prot in $enableprot}]
	}
	if {![catch {wibble listen $cfg(web,sslport) $cmd} fd]} {
	    dict set rc https [dict create fd $fd port $cfg(web,sslport)]
	} else {
	    # puts "Couldn't start wibble on port $cfg(web,sslport): $fd"
	}
    }
    return $rc
}

set wibblesock [webinit]

if {[dict size $wibblesock] == 0} return

if {![settings get debug wibble false]} {
    proc ::wibble::log {message} {}
}

namespace eval callback {
    namespace ensemble create -map {error errcmd info infocmd verify vfycmd}
}

proc callback::infocmd {chan major minor message} {
    # puts $major/$minor:$message
}

proc callback::vfycmd {chan depth cert status error} {
    # Depth = 1 concerns the root certificate
    # Depth = 0 concerns the user certificate
    set fmt {%b %d %T %Y %Z}
    set first [clock scan [dict get $cert notBefore] -format $fmt]
    set last [clock scan [dict get $cert notAfter] -format $fmt]
    set now [clock seconds]
    if {$now < $first || $now > $last} {
	# Certificate has expired
	return 0
    }
    # Convert some fields to dicts
    foreach var {subject issuer} {
	if {[dict exist $cert $var]} {
	    set new {}
	    foreach n [split [dict get $cert $var] ,] {
		set val [join [lassign [split $n =] arg] =]
		dict set new $arg $val
	    }
	    dict set cert $var $new
	}
    }
    # Convert dates to timestamps
    dict set cert notBefore $first
    dict set cert notAfter $last
    if {[dict exists $cert subject CN]} {
	dict set cert user [dict get $cert subject CN]
    }
    # Convert serial number from hex to dec
    scan [dict get $cert serial] %lx serial
    dict set cert serial $serial
    dict set cert type certificate
    if {$depth == 0} {
	# User certificate
	set user [security vfycert $serial]
	if {[dict size $user] > 0} {
	    wibble icc put [info coroutine] authorize [dict merge $cert $user]
	} else {
	    return 0
	}
    }
    return $status
}

proc cmddel {args} {
}

proc callback::errcmd {chan msg} {
    # puts $msg
}

proc ::wibble::include {name} {
    upvar 1 fspath fspath
    set fname [file join [file dirname $fspath] $name]
    if {![catch {open $fname} fd]} {
	set str [read $fd]
	close $fd
	return $str
    }
    return
}

proc ::wibble::zone::userinfo {state} {
    set details [format "via websocket from %s:%s" \
      [dict get $state request peerhost] [dict get $state request peerport]]
    if {[dict exists $state authentication user]} {
	append details ", user: [dict get $state authentication user]"
    }
    return $details
}

proc ::wibble::zone::json {state} {
    dict set state response status 200
    dict set state response header content-type "" application/json
    dict set state response header Access-Control-Allow-Origin *
    dict set state response content [::json::dump]
    sendresponse [dict get $state response]
}

proc ::wibble::zone::cmd {state} {
    if {[dict get $state request method] eq "POST"} {
	set cmd [dict get $state request rawpost]
    } elseif {[dict exists $state request rawquery]} {
	set cmd [string range [dict get $state request rawquery] 1 end]
    } else {
	set cmd PR=A
    }
    dict set state response status 200
    dict set state response header content-type "" text/plain
    dict set state response content [sercmd $cmd [userinfo $state]]
    sendresponse [dict get $state response]
}

# Support websockets
include websocket.tcl

# Handler for reporting status changes via websocket
proc ::wibble::zone::status {state event args} {
    log "[info coroutine] Rx $event $args"

    # Perform initialization and cleanup.
    if {$event in {connect disconnect}} {
	if {[dict exists $state request query]} {
	    set vars [lmap {n v} [dict get $state request query] {
		if {$n ne "var"} continue
		lindex $v 1
	    }]
	} else {
	    set vars {gui}
	}
	set cmdprefix [list wibble icc put [info coroutine] varchange]
	if {$event eq "connect"} {
	    icc configure [info coroutine] accept varchange
	    set op add
	} else {
	    set op remove
	    upvar #1 configchange change
	    if {[info exists change]} {
		configsave
	    }
	}
	foreach n $vars {
	    uplevel #0 \
	      [list trace $op variable $n write [linsert $cmdprefix end $n]]
	}
    }

    # Process variable changes.
    if {$event in {varchange}} {
	lassign $args name - arg op
	set what status
	upvar #0 $name var
	if {[array exists var]} {
	    set val $var($arg)
	    set what $name
	    if {$name eq "gui"} {set what status}
	    if {$name eq "cfg"} {set what config}
	} else {
	    set val $var
	    set arg $name
	}
        ws::send text [format {{"%s": {"%s": "%s"}}} $what $arg $val]
    }

    # Process commands received over the websocket
    if {$event eq "text"} {
	set args [lassign [lindex $args 0] cmd]
	switch -- $cmd {
	    config - configure {
		global cfg
		lassign $args section name value
		if {[info exists cfg($section,$name)]} {
		    set cfg($section,$name) $value
		    upvar #1 configchange change
		    set change 1
		}
	    }
	    command {
		lassign $args str
		sercmd $str "via websocket"
	    }
	    connect {
		catch {connect manual}
	    }
	    eval {
		# Security risk?
		catch {uplevel #0 {*}$args}
	    }
	}
    }
}

# Handler for reporting firmware download progress
proc ::wibble::zone::fwflash {state event args} {
    global cocmd cocnt fwstatus
    log "[info coroutine] Rx $event $args"

    # Perform initialization and cleanup.
    if {$event eq "connect"} {
        icc configure [info coroutine] accept status progress check progbutton
	set cmdprefix [list wibble icc put [info coroutine]]
	trace add variable cocmd write [linsert $cmdprefix end progress]
    } elseif {$event eq "disconnect"} {
	set cmdprefix [list wibble icc put [info coroutine]]
	trace remove variable cocmd write [linsert $cmdprefix end progress]
    }

    if {$event in {status check progbutton}} {
	ws::send text [format {{"%s": "%s"}} $event [lindex $args 0]]
    } elseif {$event eq "progress"} {
	global cocmd cocnt
	if {$cocnt > 0} {
	    ws::send text [format {{"%s": "%s", "%s": "%s%%"}} \
	      progress [expr {100. * $cocmd / $cocnt}] \
	      percent [expr {100 * $cocmd / $cocnt}]]
	}
    } elseif {$event eq "text"} {
	lassign [lindex $args 0] cmd arg1
	if {$cmd eq "program"} {
	    webupgrade start [info coroutine]
	} elseif {$cmd eq "check"} {
	    catch {::webupgrade::coro $arg1}
	}
    }
}

# Handler for reporting each message
proc ::wibble::zone::message {state event args} {
    global msglog

    # Perform initialization and cleanup.
    if {$event eq "connect"} {
        icc configure [info coroutine] accept message
	set cmdprefix [list msglog [info coroutine]]
	trace add variable msglog write $cmdprefix
    } elseif {$event eq "disconnect"} {
	set cmdprefix [list msglog [info coroutine]]
	trace remove variable msglog write $cmdprefix
    } elseif {$event eq {message}} {
	ws::send text [lindex $args 0]
    }
}

# Send a 401 Authorize.
proc ::wibble::zone::authorize {state} {
    set auth [list "" Basic realm [dict get $state options realm]]
    dict set state response status "401 Unauthorized"
    dict set state response header www-authenticate $auth
    dict set state response header content-type {"" text/plain charset utf-8}
    dict set state response content "Authorization required\n"
    sendresponse [dict get $state response]
}

proc ::wibble::zone::protect {state} {
    global wibblesock cfg

    set port [dict get $state request port]
    set https [expr {$port eq [dict get $wibblesock https port]}]

    # Is some kind of authentication required
    if {!$https && $cfg(web,nopass)} {
	# HTTP access doesn't require a password
	# puts "Passwordless HTTP request"
	return
    }

    # Check if the connection was authorized via a certificate
    upvar #1 certificate cert
    if {![info exists cert]} {
	set auth [lindex [wibble icc get [info coroutine] authorize 0] 0]
	if {[dict exists $auth authorize]} {
	    set cert [dict get $auth authorize]
	}
    }

    if {[info exists cert]} {
	# The user provided a valid certificate. Allow the request to continue
	dict set state request authentication $cert
	# puts "Client certificate provided"
	nexthandler $state
    } elseif {$https && $cfg(web,certonly)} {
	# No certificate - intruder!
	# puts "HTTPS access without a certificate is not allowed"
	tailcall forbidden $state
    } elseif {[dict exists $state request header authorization]} {
	set auth [dict get $state request header authorization]
	if {[scan $auth {%s %s} scheme base64] == 2 && $scheme eq "Basic"} {
	    set user [{*}[dict get $state options test] $base64]
	    if {[dict size $user] > 0} {
		# Provide the authorized user to further handlers
		# puts "Access with password"
		dict set state request authentication \
		  [dict merge [dict create type password] $user]
		nexthandler $state
	    }
	}
    }
    # puts "Requesting authorization"
    authorize $state
}

proc ::wibble::zone::get {name {default ""}} {
    if {[catch {upvar 1 $name var}] || ![info exists var]} {
	return $default
    } else {
	return $var
    }
}

proc ::wibble::zone::checked {name {value true} {default 0}} {
    upvar 1 $name var
    set rc [format {value="%s"} $value]
    if {[info exists var] ? $var eq $value : $default} {
	append rc " " checked
    }
    return $rc
}

proc ::wibble::zone::selected {name value {default 0}} {
    upvar 1 $name var
    set rc [format {value="%s"} $value]
    if {[info exists var] ? $var eq $value : $default} {
	append rc " " selected
    }
    return $rc
}

proc msglog {coro var arg op} {
    global msglog
    wibble icc put $coro message [lindex $msglog end]
}

wibble handle / protect realm "Opentherm Monitor" test {security vfyuser}

foreach n $docpath {
    # Redirect when a directory is requested without a trailing slash
    wibble handle / dirslash root $n

    # Rewrite directory requests to search for an indexfile
    wibble handle / indexfile root $n indexfile index.html
    wibble handle / indexfile root $n indexfile status.html

    # Send static files
    wibble handle / staticfile root $n

    # Process template files
    wibble handle / templatefile root $n
}

# Built-in images
wibble handle /images staticfile root $imgdir

# Echo request dictionary
wibble handle /vars vars

# Dump opentherm information in json format
wibble handle /json json

# Allow commands to be executed
wibble handle /command cmd

# Websockets
wibble handle /status.ws websocket handler status
wibble handle /basic.ws websocket handler basic
wibble handle /upgrade.ws websocket handler fwflash
wibble handle /message.ws websocket handler message

# Send a 404 Not Found
wibble handle / notfound

# Define file types
wibble handle / contenttype typetable {
    application/javascript	^js$
    application/json		^json$
    image/gif			^gif$
    image/jpeg			^(?:jp[eg]|jpeg)$
    image/png			^png$
    image/svg+xml		^svg$
    text/css			^css$
    text/html			^html?$
    text/plain			^txt$
    text/xml			^xml$
}

# Create a json representation of various bits of information
#
namespace eval json {
    variable description {
		boilertemp		"Boiler water temperature"
		boilertemp2		"Boiler water temperature 2"
		ch2mode			"Central heating mode 2"
		chmode			"Central heating mode"
		chwsetpoint		"Max CH water setpoint"
		controlsp		"Control setpoint"
		controlsp2		"Control setpoint 2"
		dhwenable		"Domestic hot water enable"
		dhwmode			"Domestic hot water mode"
		dhwsetpoint		"DHW setpoint"
		dhwtemp			"DHW temperature"
		dhwtemp2		"DHW temperature 2"
		diag			"Diagnostic indication"
		fault			"Fault indication"
		flame			"Flame status"
		maxmod			"Max relative modulation level"
		modulation		"Relative modulation level"
		outside			"Outside temperature"
		pressure		"CH water pressure"
		returntemp		"Return water temperature"
		roomtemp		"Room temperature"
		roomtemp2		"Room temperature 2"
		setpoint		"Room setpoint"
		setpoint2		"Room setpoint 2"
    }

    proc dump {} {
	global dump gui version gwversion
	variable description
	set tab "    "
	set str \n
	set time [clock format [clock seconds] -format {%Y-%m-%d %T %z}]
	append str $tab [format {"time": "%s",} $time] \n

	set ver \n
	append ver $tab [format {  "name": "%s",} "Opentherm Gateway"] \n
	append ver $tab [format {  "version": "%s"} $gwversion] \n
	append str $tab [format {"firmware": {%s},} $ver$tab] \n

	set ver \n
	append ver $tab [format {  "name": "%s",} "Opentherm Monitor"] \n
	append ver $tab [format {  "version": "%s"} $version] \n
	append str $tab [format {"software": {%s}} $ver$tab] \n

	lappend rc [format {  "%s": {%s  }} otgw $str]
	dict for {key desc} $description {
	    if {[info exists gui($key)]} {
		set str \n
		append str $tab [format {"value": "%s",} $gui($key)] \n
		append str $tab [format {"description": "%s"} $desc] \n
		lappend rc [format {  "%s": {%s  }} $key $str]
	    }
	}
	return "{\n[join $rc ,\n]\n}"
    }
}

namespace eval webupgrade {
    namespace ensemble create -subcommands {
	start status check init manual progress go done
    }

    proc start {cmd} {
	variable coro $cmd
	coroutine coro upgrade loadhex [namespace current]
    }

    proc status {msg} {
	variable coro
	wibble icc put $coro status $msg
    }

    proc check {what} {
	global checkreturn
	variable coro
	if {$what eq "magic"} {
            set msg "Warning: The selected firmware does not start with\
              the recommended instruction sequence. This may render the\
              device incapable of performing any firmware updates in the\
              future.\\n\\nAre you sure you want to continue?"
        } elseif {$what eq "call"} {
            set msg "Warning: The startup instruction sequence calls a\
              different address than the starting address reported by the\
              current self-programming code. This may render the device\
              inoperable.\\n\\nAre you sure you want to continue?"
        }
	set id [after 60000 [list [info coroutine] timeout]]
	set ans [yieldto wibble icc put $coro check $msg]
	after cancel $id
	return cancel
    }

    proc init {} {
	variable coro
	wibble icc put $coro progbutton disabled
    }

    proc manual {} {
    }

    proc progress {max} {
	global cocnt
	set cocnt $max
    }

    proc go {} {
    }

    proc done {} {
	variable coro
	wibble icc put $coro progbutton enabled
    }
}
