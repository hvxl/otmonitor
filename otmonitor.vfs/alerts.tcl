namespace eval alert {
    namespace ensemble create -subcommands {
	providers test boilerfault ventilationfault solarfault
	watchdogtimer commproblem roomcold pressure log
    }

    # 0 LB0 -> 5,115	General
    # 70 LB0 -> 72,73	Ventilation/heat-recovery
    # 101 LB0 -> 102	Solar storage

    variable roomcold $cfg(alert,roomcold)
    variable pressure $cfg(alert,pressurehigh)

    variable smsprovider {
	VoipPlanet {
	    url	http://api.voipplanet.nl/sendsms.php
	    method GET
	    query {
		username	account
		password	password
		smsto		phonenumber
		txt		message
	    }
	    result {
		format		raw
		success		Success
	    }
	}
	VoipBuster {
	    url	https://www.voipbuster.com/myaccount/sendsms.php
	    query {
		username	account
		password	password
		from		sender
		to		phonenumber
		text		message
	    }
	}
	VoipCheap {
	    url	https://www.voipcheap.com/myaccount/sendsms.php
	    query {
		username	account
		password	password
		from		sender
		to		phonenumber
		text		message
	    }
	}
	Spryng {
	    url	http://www.spryng.nl/send.php
	    format <CC><NSN>
	    routes {
		ECONOMY		Economy
		BUSINESS	Business
		0		"User route 0"
		1		"User route 1"
		2		"User route 2"
		3		"User route 3"
		4		"User route 4"
		5		"User route 5"
		6		"User route 6"
		7		"User route 7"
		8		"User route 8"
		9		"User route 9"
	    }
	    defaultroute BUSINESS
	    query {
		USERNAME	account
		PASSWORD	password
		DESTINATION	phonenumber
		SENDER		sender
		BODY		message
		ROUTE		route
	    }
	    result {
		format		raw
		success		1
		mapping {
		    1	"successfully received"
		    100	"missing Parameter"
		    101 "username too short"
		    102	"username too long"
		    103	"password too short"
		    104	"password too long"
		    105	"destination too short"
		    106	"destination too long"
		    107	"sender too long"
		    108	"sender too short"
		    109	"body too short"
		    110	"body too long"
		    200	"security error"
		    201	"unknown route"
		    202 "route access violation"
		    203 "insufficient credits"
		    800 "technical error"
		}
	    }
	}
	Mollie {
	    url	https://api.messagebird.com/xml/sms/
	    routes {
		2	Basic
		4	Business
		1	Business+
		8	Landline
	    }
	    defaultroute 1
	    query {
		username		account
		password		password
		originator		sender
		recipients		phonenumber
		message			message
		gateway			route
		replace_illegal_chars	true
	    }
	    result {
		format		xml
		xpath		string(/response/item/resultcode)
		success		10
		mapping {
		    10	"succesvol verzonden"
		    20	"geen 'username' opgegeven"
		    21	"geen 'password' opgegeven"
		    22	"geen of onjuiste 'originator' opgegeven"
		    23	"geen 'recipients' opgegeven"
		    24	"geen 'message' opgegeven"
		    25	"geen juiste 'recipients' opgegeven"
		    26	"geen juiste 'originator' opgegeven"
		    27	"geen juiste 'message' opgegeven"
		    28	"probleem met charset"
		    29	"andere parameterfout"
		    30	"incorrect username or password"
		    31	"onvoldoende credits om te versturen"
		    98	"gateway onbereikbaar"
		    99	"onbekende fout"
		}
	    }
	}
	CMdirect {
	    url https://secure.cm.nl/smssgateway/cm/gateway.ashx
	    type text/xml
	    query {
		MESSAGES/AUTHENTICATION/PRODUCTTOKEN	account
		MESSAGES/MSG/FROM			sender
		MESSAGES/MSG/TO				phonenumber
		MESSAGES/MSG/BODY			message
	    }
	    result {
		format		raw
		success		""
	    }
	}
    }

    namespace eval log {
	variable log {}
	namespace ensemble create -subcommands {append clear get}
    }
}

proc alert::log::append {str} {
    variable log
    set now [clock milliseconds]
    set ts [format %s.%03d \
      [clock format [expr {$now / 1000}] -format %T] [expr {$now % 1000}]]
    foreach n [split $str \n] {
	lappend log "$ts: $n"
    }
    # Limit log to 2000 lines
    # set log [lreplace $log 0 end-2000]
    set log [lrange $log end-1999 end]
    return
}

proc alert::log::clear {} {
    variable log {}
}

proc alert::log::get {} {
    variable log
    return [join $log \n]
}

proc alert::email {message} {
    global cfg
    log append "Sending email via $cfg(email,server)"
    lappend msg "From: $cfg(email,sender)"
    foreach recipient [split $cfg(email,recipient) ,] {
	lappend msg "To: $recipient"
    }
    lappend msg "Subject: Opentherm gateway alert"
    lappend msg "Date: [smtpdate [clock seconds]]"
    lappend msg "" $message
    # Connect to the SMTP server
    set fd [socket -async $cfg(email,server) $cfg(email,port)]
    # Clean up if the coroutine gets deleted somehow
    set trace [list apply {
	{fd old new op} {
	    alert log append "coroutine was deleted"
	    catch {close $fd}
	}
    } $fd]
    trace add command [info coroutine] delete $trace
    try {
	# Make sure the tls library is loaded if it will be needed
	if {$cfg(email,secure) in {TLS SSL}} {package require tls}
	fileevent $fd writable [info coroutine]
	# Wait for the connection
	yield
	fileevent $fd writable {}
	# Check if the connection succeeded
	set error [fconfigure $fd -error]
	if {$error ne ""} {throw {SMTP open} $error}
	fconfigure $fd -blocking 0 -translation crlf -buffering line
	# Switch on encryption for SSL connections
	if {$cfg(email,secure) eq "SSL"} {
	    tls::import $fd
	    fconfigure $fd -translation crlf -buffering line
	    # Hack that seems to be necessary for ssl to work
	    # We need to send something before the readable event will fire
	    puts $fd ""
	}
	# Read data from the server
	set data [lassign [smtpread $fd 220 2XX] status]
	# Send greeting
	smtpputs $fd "EHLO [lindex [fconfigure $fd -sockname] 1]"
	set data [lassign [smtpread $fd 250 2XX] status]
	if {$cfg(email,secure) eq "TLS"} {
	    smtpputs $fd "STARTTLS"
	    set data [lassign [smtpread $fd 502 220 2XX] status]
	    if {$status eq "502"} {
		throw {SMTP TLS} "server does not support TLS"
	    }
	    tls::import $fd
	    fconfigure $fd -translation crlf -buffering line
	    smtpputs $fd "EHLO [lindex [fconfigure $fd -sockname] 1]"
	    set data [lassign [smtpread $fd 250 2XX] status]
	}
	# Authenticate
	if {$cfg(email,user) ne ""} {
	    smtpauth $fd $data $cfg(email,user) $cfg(email,password)
	}
	# Specify the sender
	smtpputs $fd "MAIL FROM:[smtpaddr $cfg(email,sender)]"
	set data [lassign [smtpread $fd 250 2XX] status]
	# Specify the recipients
	foreach recipient [split $cfg(email,recipient) ,] {
	    smtpputs $fd "RCPT TO:[smtpaddr $recipient]"
	    set data [lassign [smtpread $fd 250 2XX] status]
	}
	# Send the message body
	smtpputs $fd DATA
	set data [lassign [smtpread $fd 354 3XX] status]
	smtpputs $fd [join $msg \n]
	smtpputs $fd .
	set data [lassign [smtpread $fd 250 2XX] status]
	smtpputs $fd QUIT
	set data [lassign [smtpread $fd 221 2XX] status]
    } finally {
	trace remove command [info coroutine] delete $trace
	close $fd
    }
}

proc alert::smtpauth {fd data user password} {
    set auth [lsearch -inline $data {AUTH *}]
    if {"PLAINT" in $auth} {
	set plain [join [list $user $user $password] \0]
	smtpputs $fd "AUTH PLAIN [binary encode base64 $plain]" 11
	set data [lassign [smtpread $fd 235 2XX] status]
    } elseif {"LOGIN" in $auth} {
	smtpputs $fd "AUTH LOGIN"
	set data [lassign [smtpread $fd 334 3XX] status]
	smtpputs $fd [binary encode base64 $user]
	set data [lassign [smtpread $fd 334 3XX] status]
	smtpputs $fd [binary encode base64 $password] 0
	set data [lassign [smtpread $fd 235 2XX] status]
    } else {
	smtpputs $fd "QUIT"
	set data [lassign [smtpread $fd 235 2XX] status]
	throw {SMTP LOGIN} "no supported authentication scheme"
    }
}

proc alert::smtpputs {fd str {hide -1}} {
    puts $fd $str
    if {$hide >= 0} {regsub -all -start $hide . $str * str}
    log append "< [join [split $str \n] "\n  "]"
}

proc alert::smtpread {fd args} {
    fileevent $fd readable [info coroutine]
    foreach n $args {
	lappend patterns [string map {X ?} $n]
    }
    set rc ""
    while {![eof $fd]} {
	yield
	if {[gets $fd line] != -1} {
	    log append "> $line"
	    if {[regexp {^(\d{3})([ -])(.*)} $line -> status cont info]} {
		set ok 0
		foreach n $patterns {
		    if {[string match $n $status]} {set ok 1;break}
		}
		if {!$ok} {
		    throw {SMTP STATUS} "unexpected status code: $status $info"
		}
		lappend rc $info
		if {$cont eq " "} break
	    }
	}
    }
    fileevent $fd readable ""
    return [linsert $rc 0 $status]
}

proc alert::smtpaddr {str} {
    if {![regexp {<.*>} $str addr]} {set addr <$str>}
    return $addr
}

proc alert::smtpdate {time} {
    set str [clock format $time -format "%a, %e %b %Y %T %z"]
    # Remove possible double space before the day of the month
    return [regsub {  } $str { }]
}

proc alert::sms {message} {
    global cfg
    variable smsprovider
    set dict [dict get $smsprovider $cfg(sms,provider)]
    set url [dict get $dict url]
    log append "Sending SMS via $cfg(sms,provider)"
    package require http
    if {[string match https://* $url]} {
	package require tls
	http::register https 443 tls::socket
    }
    # Determine content type
    if {[dict exists $dict type]} {
	set type [dict get $dict type]
    } else {
	set type application/x-www-form-urlencoded
    }
    # Create the query
    dict for {name prop} [dict get $dict query] {
	if {$prop eq "message"} {
	    set value $message
	} elseif {[info exists cfg(sms,$prop)]} {
	    set value $cfg(sms,$prop)
	} else {
	    set value $prop
	}
	if {$prop in {password}} {
	    log append "$name=[regsub -all . $value *]"
	} else {
	    log append "$name=$value"
	}
	lappend q $name $value
    }
    if {$type eq "application/x-www-form-urlencoded"} {
	set query [http::formatQuery {*}$q]
    } elseif {$type in {text/xml application/xml}} {
	# Build the xml document based on the query specification
	package require tdom
	dom createDocumentNode doc
	foreach {name value} $q {
	    set ptr $doc
	    set path ""
	    foreach n [split $name /] {
		lassign [split $n @] tag attr
		append path /$tag
		if {![info exists node($path)]} {
		    $doc createElement $tag node($path)
		    $ptr appendChild $node($path)
		}
		set ptr $node($path)
	    }
	    if {$attr eq ""} {
		$ptr appendChild [$doc createTextNode $value]
	    } else {
		$ptr setAttribute $attr $value
	    }
	}
	set query {<?xml version="1.0"?>}
	append query \n [$doc asXML -indent 2]
	unset doc node
    }
    log append "Query:\n$query"
    log append "Contacting $url"
    if {[dict exists $dict method] && [dict get $dict method] eq "GET"} {
	set token [http::geturl $url?$query -command [info coroutine]]
    } else {
	set token [http::geturl $url \
	  -type $type -query $query -command [info coroutine]]
    }
    # Clean up if the coroutine gets deleted somehow
    set trace [list apply {
        {token old new op} {
	    alert log append "coroutine was deleted"
	    http::cleanup $token
        }
    } $token]
    trace add command [info coroutine] delete $trace
    try {
	yield
	log append "Status: [http::status $token]"
	log append "Code: [http::ncode $token]"
	log append "Headers:"
	foreach {hdr val} [http::meta $token] {
	    log append "  $hdr: $val"
	}
	log append "Data:\n[http::data $token]"
	if {[http::ncode $token] eq "200"} {
	    # Extract the result from the data
	    set data [http::data $token]
	    if {[dict exists $dict result format]} {
		set format [dict get $dict result format]
	    } else {
		set meta [http::meta $token]
		set ctype [lsearch -inline -nocase [dict keys $meta] Content-Type]
		switch -- [dict get $meta $ctype] {
		    text/xml		{set format xml}
		    text/plain		{set format raw}
		    application/json	{set fromat json}
		}
	    }
	    switch -- $format {
		xml {
		    package require tdom
		    dom parse $data doc
		    set xpath [dict get $dict result xpath]
		    set result [$doc selectNodes $xpath]
		}
		raw {
		    set result $data
		}
		json {
		    # Not yet implemented
		}
	    }
	    if {[dict exists $dict result success]} {
		set success [expr {[dict get $dict result success] eq $result}]
	    } else {
		set success 1
	    }
	} else {
	    set success 0
	    set result [http::ncode $token]
	}
	if {[dict exists $dict result mapping $result]} {
	    set result [dict get $dict result mapping $result]
	} elseif {[dict exists $dict result mapping]} {
	    set result "unknown result code: $result"
	}
	if {!$success} {
	    log append "Failed: $result"
	    throw {SMS STATUS} $result
	} else {
	    log append "Success: $result"
	    return $result
	}
    } finally {
	trace remove command [info coroutine] delete $trace
	catch {http::cleanup $token}
    }
}

proc alert::providers {} {
    variable smsprovider
    return $smsprovider
}

proc alert::test {type {w .}} {
    log append "[ts] Generating a test message"
    set message "Opentherm gateway test message"
    switch -- $type {
	email {
	    if {![catch {email $message} result]} {
		set result "Message was sent successfully"
	    }
	}
	sms {
	    if {![catch {sms $message} result]} {
		set result "Message was sent successfully"
	    }
	}
	default {
	    set result "Unknown test type: $type"
	}
    }
    if {[winfo exists $w]} {
	after idle [list tk_messageBox -parent $w -type ok -icon info \
	  -title "Test result" -message [string toupper $result 0 0]]
    }
    log append ""
}

proc alert::alert {type message {longmsg ""}} {
    global cfg
    log append "[ts] Alert type $type"
    if {$cfg(sms,enable) && $cfg(sms,$type)} {
	coroutine coro-sms catch [namespace code [list sms $message]]
    } else {
	set str "SMS messages not enabled"
	if {$cfg(sms,enable)} {
	    append str " for this alert type"
	}
	log append $str.
    }
    if {$cfg(email,enable) && $cfg(email,$type)} {
	if {$longmsg eq ""} {set longmsg $message}
	coroutine coro-email catch [namespace code [list email $longmsg]]
    } else {
	set str "Email messages not enabled"
	if {$cfg(email,enable)} {
	    append str " for this alert type"
	}
	log append $str.
    }
    log append ""
}

proc alert::fault {id {index 7}} {
    global value
    variable fault
    if {[info exists value(4,$id)]} {
	set flags [lindex $value(4,$id) 1]
	if {[string index $flags $index]} {
	    # Fault indication
	    if {[info exists fault($id)] && $fault($id)} {return 0}
	    # This is a new occurrence
	    set fault($id) 1
	    return 1
	}
    }
    set fault($id) 0
    return 0
}

proc alert::boilerfault {args} {
    set errorcode [lindex $args end]
    if {[fault 0]} {
	# Boiler fault
	set message "Central heating system requires service.\
	  OEM fault code $errorcode."
	alert boilerfault $message
    }
}

proc alert::ventilationfault {args} {
    set errorcode [lindex $args end]
    if {[fault 70]} {
	# Ventilation system fault
	set message "Ventilation system requires service.\
	  OEM fault code $errorcode."
	alert boilerfault $message
    }
}

proc alert::solarfault {flags errorcode} {
    if {[fault 101]} {
	# Solar storage system service request
	set message "Solar storage system requires service.\
	  OEM fault code $errorcode."
	alert boilerfault $message
    }
}

proc alert::watchdogtimer {} {
    alert watchdogtimer "The gateway restarted due to a\
      timeout of the watchdog timer."
}

proc alert::commproblem {val} {
    puts [info level 0]
}

proc alert::roomcold {val} {
    global cfg
    variable roomcold
    if {$val < $cfg(alert,roomcold)} {
	if {int($val) < $roomcold} {
	    # Room temperature dropped below the alarm level
	    set msg "The room temperature has dropped below $roomcold degrees.\
	      The current room temperature is $val degrees."
	    alert roomcold $msg
	    # Set a new alarm level
	    set roomcold [expr {int($val)}]
	}
    } elseif {$roomcold < $cfg(alert,roomcold)} {
	if {$val > $cfg(alert,roomcold) + 2} {
	    # Reset the alarm level when the room temperature has reached
	    # a reasonable value again, to prevent excessive alerts
	    set roomcold $cfg(alert,roomcold)
	}
    }
}

proc alert::pressure {val} {
    global cfg
    variable pressure
    if {$val < $cfg(alert,pressurelow)} {
	if {$val < $pressure} {
	    set ref [expr {min($cfg(alert,pressurelow),$pressure)}]
	    set msg "The CH water pressure has dropped below $ref bar.\
	      The current CH water pressure is $val bar."
	    alert pressure $msg
	    # Set a new alarm level
	    set pressure [format %.1f [expr {$val - 0.1}]]
	}
    } elseif {$val > $cfg(alert,pressurehigh)} {
	if {$val > $pressure} {
	    set ref [expr {max($cfg(alert,pressurehigh),$pressure)}]
	    set msg "The CH water pressure has risen above $ref bar.\
              The current CH water pressure is $val bar."
            alert pressure $msg
            # Set a new alarm level
            set pressure [format %.1f [expr {$val + 0.1}]]
	}
    } elseif {$pressure < $cfg(alert,pressurelow) && \
      $val >= $cfg(alert,pressurelow) + 0.2} {
	set pressure $cfg(alert,pressurelow)
    } elseif {$pressure > $cfg(alert,pressurehigh) && \
      $val <= $cfg(alert,pressurehigh) - 0.2} {
	set pressure $cfg(alert,pressurehigh)
    }
}
