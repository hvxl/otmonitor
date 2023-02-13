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

    switch $cfg(mqtt,version) {
	3.1 - 3 - MQTTv3.1 {
	    set protocol 3
	}
	3.1.1 - 4 - MQTTv3.1.1 {
	    set protocol 4
	}
	default {
	    set protocol 5
	}
    }

    mqttformat

    set mqtt [mqtt new -username $cfg(mqtt,username) \
      -password $cfg(mqtt,password) -keepalive $cfg(mqtt,keepalive) \
      -retransmit [expr {$cfg(mqtt,retransmit) * 1000}] \
      -protocol $protocol -socketcmd [socketcommand $cfg(mqtt,secure)]]
    $mqtt subscribe {$SYS/local/connection} mqttstatus
    $mqtt subscribe $cfg(mqtt,actiontopic)/+ mqttaction
    $mqtt connect $cfg(mqtt,client) $cfg(mqtt,broker) $cfg(mqtt,port)

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

proc mqttformat {{init 1}} {
    global cfg
    set cmd [list apply {args {mqttformat 0}}]
    if {$cfg(mqtt,format) ni {json json1 json2 json3}} {
	if {$init} {
	    # Take the appropriate action when the format is changed
	    trace add variable cfg(mqtt,format) write $cmd
	}
	return
    }
    try {
	json layout json1 {data} {
	    global mqtt
	    # Arrange for multiple values to be published in separate messages
	    dict with data {}
	    if {[llength $value] == 0} {
		return
	    }
	    foreach {n t} [lassign $def name type] v [lassign $value val] {
		set d [dict create def [list $name $type] value $val]
		$mqtt publish $topic [json build object json1 $d] $qos $retain
		set name $n
		set type $t
		set val $v
	    }
	    return [dict create value [list $type $val]]
	}

	json layout json2 {data} {
	    global mqtt
	    # Arrange for multiple values to be published in separate messages
	    dict with data {}
	    foreach {n t} [lassign $def name type] v [lassign $value val] {
		set d [dict create def [list $name $type] value $val]
		$mqtt publish $topic [json build object json2 $d] $qos $retain
		set name $n
		set type $t
		set val $v
	    }
	    set script {}
	    if {[llength $value]} {
		if {$name ne ""} {
		    dict set script name [list string $name]
		} else {
		    dict set script name {string arg}
		    set type string
		}
		dict set script type [list string $type]
		dict set script value [list $type $val]
	    }
	    dict set script timestamp {milliseconds}
	    return $script
	}

	json layout json3 {data} {
	    set script {args {} timestamp {milliseconds}}
	    set args {type {} value {}}
	    foreach {name type} [dict get $data def] \
	      value [dict get $data value] {
		if {$name eq ""} {
		    set name arg[incr argnum]
		    set type string
		}
		dict set args type [list string $type]
		dict set args value [list $type $value]
		dict set script args object::$name [script $args]
	    }
	    return $script
	}

	# Create some object node commands
	json object args
	json attribute name
	json attribute type
	json attribute value
	json attribute timestamp

	# Initialization has been done
	trace remove variable cfg(mqtt,format) write $cmd
    } trap {TCL PACKAGE UNFOUND} {err info} {
	# Could not load the required package (tdom). Fall back to raw format
	set cfg(mqtt,format) raw
	# Keep the trace needs until switching to json succeeds
    }
}

proc mqttsignal {name args} {
    global cfg mqtt signals
    if {!$cfg(mqtt,enable)} return
    set key [lsearch -inline -nocase -exact [dict keys $signals] $name]
    if {$key ne ""} {
	set def [dict get $signals $key]
    } else {
	set def {"" string}
    }
    set topic $cfg(mqtt,eventtopic)/$name
    set qos $cfg(mqtt,qos)
    set retain [expr {[llength $args] > 0 && $name ni {error}}]
    set data [dict create topic $topic def $def value $args qos $qos retain $retain]
    mqttpub $topic $data $qos $retain
}

proc mqttmessage {msg} {
    global cfg
    set data [dict create def {"" string} value $msg]
    mqttpub $cfg(mqtt,eventtopic)/Message $data 0
}

proc mqttpub {topic data {qos 1} {retain 0}} {
    global cfg mqtt
    try {
	switch -- $cfg(mqtt,format) {
	    json - json1 {
		set msg [json build object json1 $data]
	    }
	    json2 {
		set msg [json build object json2 $data]
	    }
	    json3 {
		set msg [json build object json3 $data]
	    }
	    default {
		set msg [dict get $data value]
	    }
	}
	$mqtt publish $topic $msg $qos $retain
    } on error {err info} {
	puts stderr [dict get $info -errorinfo]
    }
}

proc mqttraw {name data} {
    return [join $data ,]
}

proc mqttstatus {topic data retained {prop {}}} {
    global mqttstatus
    if {[dict get $data state] eq "connected"} {
	if {[dict exists $prop AssignedClientIdentifier]} {
	    set name [dict get $prop AssignedClientIdentifier]
	    set mqttstatus "Connected as $name"
	} else {
	    set mqttstatus Connected
	}
    } elseif {[dict exists $data detail]} {
	set mqttstatus [string toupper [dict get $data detail] 0 0]
    } else {
	set mqttstatus [string toupper [dict get $data text] 0 0]
    }
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
	if {[catch {dom parse -json $data doc}]} {
	    # Invalid JSON
	    return
	}
	switch $cfg(mqtt,format) {
	    json - json1 - json2 {
		set path /value
	    }
	    json3 {
		set path /$arg/value
	    }
	    default {
		# Unknown data format
		return
	    }
	}
	set value [$doc selectNodes string($path)]
	
	if {$value eq ""} {
	    # No value specified
	    return
	}
    }
    sercmd $cmd=$value "via MQTT"
}

mqttinit
