# Support for MQ Telemetry Transport
# Needs a mqtt broker somewehere, for example mosquitto

package require mqtt

set mqttactions {
    setpoint		{temp	TT}
    constant		{temp	TC}
    outside		{temp	OT}
    hotwater		{on	HW}
    gatewaymode		{on	GW}
    setback		{temp	SB}
    maxchsetpt		{temp	SH}
    maxdhwsetpt		{temp	SW}
    maxmodulation	{level	MM}
    ctrlsetpt		{temp	CS}
    chenable		{on	CH}
    ventsetpt		{level	VS}
}

proc mqttinit {} {
    global cfg mqtt signals gui

    set mqtt [mqtt new -username $cfg(mqtt,username) \
      -password $cfg(mqtt,password) -keepalive $cfg(mqtt,keepalive) \
      -retransmit [expr {$cfg(mqtt,retransmit) * 1000}]]
    $mqtt connect $cfg(mqtt,client) $cfg(mqtt,broker) $cfg(mqtt,port)
    $mqtt subscribe $cfg(mqtt,actiontopic)/+ mqttaction

    signalproc mqttsignal

    # Publish all known persistent parameters
    dict for {key args} $signals {
	if {[llength $args] == 0} continue
	set param [string tolower $key]
	if {[info exists gui($param)]} {
	    mqttsignal $param $gui($param)
	}
    }
}

proc mqttsignal {name args} {
    global cfg mqtt signals
    if {!$cfg(mqtt,enable)} return
    set retain [expr {[llength $args] > 0 && $name ni {error}}]
    set key [lsearch -inline -nocase -exact [dict keys $signals] $name]
    switch -- $cfg(mqtt,format) {
	json - json1 {
	    set value [mqttjson1 $key $args]
	}
	json2 {
	    set value [mqttjson2 $key $args]
	}
	json3 {
	    set value [mqttjson3 $key $args]
	}
	default {
	    set value [mqttraw $key $args]
	}
    }
    $mqtt publish $cfg(mqtt,eventtopic)/$name $value $cfg(mqtt,qos) $retain
}

proc mqttjsonvalue {type val} {
    set rc [list [format {"type": "%s"} $type]]
    switch -- $type {
	boolean {
	    lappend rc \
	      [format {"value": %s} [lindex {true false} [expr {!$val}]]]
	}
	float {
	    lappend rc [format {"value": %.2f} $val]
	}
	byte - integer - unsigned {
	    lappend rc [format {"value": %d} $val]
	}
	default {
	    lappend rc [format {"value": "%s"} $val]
	}
    }
    return $rc
}

proc mqttjson1 {name data} {
    global signals
    if {[llength $data] == 1} {
	set value [lindex $data 0]
	if {$name ne ""} {
	    lassign [dict get $signals $name] key type
	} else {
	    set type string
	}
	set value [lindex [mqttjsonvalue $type $value] 1]
    } else {
	set value ""
    }
    return "{$value}"
}

proc mqttjson2 {name data} {
    global signals
    if {[llength $data] == 1} {
	set value [lindex $data 0]
	if {$name ne ""} {
	    lassign [dict get $signals $name] key type
	    set json [mqttjsonvalue $type $value]
	} else {
	    set key arg
	    set json [mqttjsonvalue string $value]
	}
	set json [linsert $json 0 [format {"name": "%s"} $key]]
    }
    lappend json [format {"timestamp": %s} [clock milliseconds]]
    return "{[join $json {, }]}"
}

proc mqttjson3 {name data} {
    global signals
    if {$name ne ""} {
	set def [dict get $signals $name]
    } else {
	set def {}
    }
    set parameters {}
    set argnum 0
    foreach arg [dict keys $def] val $data {
	if {$arg eq ""} {
	    set arg arg[incr argnum]
	    set type string
	} else {
	    set type [dict get $def $arg]
	}
	set value [mqttjsonvalue $type $val]
	lappend parameters [format {"%s": {%s}} $arg [join $value {, }]]
    }
    lappend json [format {"args": {%s}} [join $parameters {, }]]
    lappend json [format {"timestamp": %s} [clock milliseconds]]
    return "{[join $json {, }]}"
}

proc mqttraw {name data} {
    return [join $data ,]
}

proc mqttmessage {msg} {
    global cfg mqtt
    switch -- $cfg(mqtt,format) {
	json - json1 {
	    set value [mqttjson1 "" $msg]
	}
	json2 {
	    set value [mqttjson2 "" $msg]
	}
	json3 {
	    set value [mqttjson3 "" $msg]
	}
	default {
	    set value [mqttraw "" $msg]
	}
    }
    $mqtt publish $cfg(mqtt,eventtopic)/Message $value 0
    
}

proc mqttaction {topic data args} {
    global cfg mqttactions
    set name [lindex [split $topic /] end]
    if {[dict exists $mqttactions $name]} {
	lassign [dict get $mqttactions $name] arg cmd
    } else {
	# Unknown action
	return
    }
    if {$cfg(mqtt,format) eq "raw"} {
	set value $data
    } else {
	package require json
	if {[catch {json::json2dict $data} dict]} {
	    # Invalid JSON
	    return
	}
	switch $cfg(mqtt,format) {
	    json - json1 - json2 {
		if {[dict exists $dict value]} {
		    set value [dict get $dict value]
		} else {
		    # No value specified
		    return
		}
	    }
	    json3 {
		if {[dict exists $dict $arg value]} {
		    set value [dict get $dict $arg value]
		} else {
		    # No value specified
		    return
		}
	    }
	    default {
		# Unknown data format
		return
	    }
	}
    }
    sercmd $cmd=$value "via MQTT"
}

mqttinit
