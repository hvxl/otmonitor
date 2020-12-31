# Create a DBus interface, if the dbus package is available

if {[catch {package require dbif} err]} return

dbif default -bus $dbus -interface com.tclcode.otmonitor

# Get a dbus name for the first instance
if {[catch {dbif connect com.tclcode.otmonitor} err]} return

proc dbussignal {name args} {
    global dbussignal
    set name [string tolower $name]
    if {[info exists dbussignal($name)]} {
	dbif generate $dbussignal($name) {*}$args
    }
}

signalproc dbussignal

if {[settings get debug dbusname] ne ""} {
    # Get a dbus name for the last instance
    dbif connect -replace -yield [settings get debug dbusname]

    dbif method /Debug Eval command result {
	return [uplevel #0 $command]
    }
}

proc dbusinit {path def} {
    global dbussignal
    set ch {boolean b string s float d byte y integer n unsigned q}
    dict for {name arglist} $def {
	set args {}
	dict for {arg type} $arglist {
	    if {[dict exists $ch $type]} {
		lappend args $arg:[dict get $ch $type]
	    } else {
		lappend args $name
	    }
	}
	set lower [string tolower $name]
	set dbussignal($lower) [dbif signal $path $name {*}$args]
    }
}

dbusinit / $signals

dbif method -async / Command cmd result {
    coroutine dbus-$msgid apply {
	{cmd msgid} {
	    set details [format {via dbus, sender %s} [dbif get $msgid sender]]
	    dbif return $msgid [sercmd $cmd $details]
	}
    } $cmd $msgid
}

dbif method / Version {} version {return $::version}

dbif method -async / Quit {
    # Provide a response to the caller before quitting
    dbif return $msgid ""
    exit
}

dbif method / Report {} list:a{sv} {
    global gui
    set rc {}
    foreach {name var sig} {
	BoilerWaterTemperature	boilertemp	d
	BoilerWaterTemperature2	boilertemp2	d
	CHEnable		chenable	b
	CH2Enable		ch2enable	b
	CHSetpoint		chsetpoint	d
	CentralHeating		chmode		b
	CentralHeating2		ch2mode		b
	ControlSetpoint		controlsp	d
	ControlSetpoint2	controlsp2	d
	DHWEnable		dhwenable	b
	DHWSetpoint		dhwsetpoint	d
	DHWTemperature		dhwtemp		d
	DHWTemperature2		dhwtemp2	d
	Fault			fault		b
	Flame			flame		b
	HotWater		dhwmode		b
	Modulation		modulation	d
	OutsideTemperature	outside		d
	ReturnWaterTemperature	returntemp	d
	RoomTemperature		roomtemp	d
	RoomTemperature2	roomtemp2	d
	Setpoint		setpoint	d
	Setpoint2		setpoint2	d
    } {
	if {[info exists gui($var)] && $gui($var) ne "???"} {
	    dict set rc $name [list $sig $gui($var)]
	}
    }
    return $rc
}

dbif method / Connect {device} {
    global cfg
    if {[llength [lassign [split $device :] dev port]]} {
	error "Specify <device>|<host>:<port>"
    }
    set bkup [array get cfg connection,*]
    if {$port ne ""} {
	set cfg(connection,type) tcp
	set cfg(connection,host) $dev
	set cfg(connection,port) $port
    } else {
	set cfg(connection,type) serial
	set cfg(connection,device) $dev
    }
    if {[catch {connect manual} msg]} {
	# Restore the original settings
	array set cfg $bkup
	dbif error $msgid $msg
    } else {
	set cfg(connection,enable) true
	dbif return $msgid $msg
    }
}

dbif method / Disconnect {} {
    connect disconnect
}

dbif method / Reconnect {} {
    global cfg
    set rc [connect manual]
    set cfg(connection,enable) true
    return $rc
}

dbif property / Connected:b connected

dbif method /Security AddUser {user password} result {
    security adduser $user $password rw
}

dbif method /Security DeleteUser user result {
    security deluser $user
}

dbif method /Security ChangePassword {user password} result {
    security chguser $user $password
}

dbif method /Security AddCertificate {file access} result {
    security addcert $file $access
}

dbif method /Security RevokeCertificate serialno result {
    security delcert $serialno
}

# Debug

dbus method $dbus / com.tclcode.debug.Eval {
    apply {{info str} {uplevel #0 $str}}
}
dbus method $dbus / com.tclcode.debug.Log {
    apply {info {join [lappend ::surprise] \n\n}}
}
