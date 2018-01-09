# Serial port utilities

namespace eval comport {
    variable map
    if {$tcl_platform(platform) eq "windows"} {
	set map [list enum regenum]
    } elseif {$tcl_platform(os) eq "Darwin"} {
	set map [list enum macenum]
    } else {
	set map [list enum devenum]
    }
    namespace ensemble create -map $map
}

proc comport::regenum {} {
    if {[catch regsmart rc] || [llength $rc] == 0} {
	set rc [list COM1 COM2 COM3 COM4]
    }
    return $rc
}

proc comport::regsmart {} {
    package require registry
    set base {HKEY_LOCAL_MACHINE\HARDWARE\DEVICEMAP\SERIALCOMM}

    set rc {}
    foreach n [registry values $base] {
	lappend rc [registry get $base $n]
    }

    return [lsort -dictionary $rc]
}

proc comport::devenum {} {
    if {[catch devsmart rc] || [llength $rc] == 0} {
	set rc {}
	foreach dev [list /dev/ttyS0 /dev/ttyS1 /dev/ttyS2 /dev/ttyS3] {
	    if {[devcheck $dev]} {
		lappend rc $dev
	    }
	}
    }
    return $rc
}

proc comport::devsmart {} {
    set rc ""
    # Find hot-pluggable devices
    foreach n [glob -nocomplain /dev/serial/by-path/*] {
	set dev [file normalize [file join [file dirname $n] [file link $n]]]
	if {[devcheck $dev]} {
	    lappend rc $dev
	}
    }
    # Find the regular serial devices
    foreach n [glob -nocomplain /sys/class/tty/*/device/driver] {
	set dev [file join /dev [lindex [file split $n] 4]]
	if {$dev ni $rc && [devcheck $dev]} {
	    lappend rc $dev
	}
    }
    return $rc
}

proc comport::devcheck {dev} {
    if {[file exists $dev] && ![catch {open $dev {RDWR NOCTTY NONBLOCK}} fd]} {
	set rc [dict exists [fconfigure $fd] -xchar]
	close $fd
	return $rc
    }
    return 0
}

proc comport::macenum {} {
    if {[catch macsmart rc] || [llength $rc] == 0} {
	set rc [list]
    }
    return $rc
}

proc comport::macsmart {} {
    set rc {}
    foreach n [glob -nocomplain /dev/cu.*] {
	if {[devcheck $dev]} {
	    lappend rc $dev
	}
    }
    return $rc
}
