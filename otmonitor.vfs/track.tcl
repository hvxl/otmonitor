namespace eval track {
    trace add variable ::gui write [namespace code vartrace]
}

proc track::init {} {
    global graphdef track
    dict for {name data} $graphdef {
	foreach n [dict keys [dict get $data line]] {
	    set track($n) {}
	}
    }
}

proc track::vartrace {var arg op} {
    global track gui timestamp span
    if {[info exists track($arg)]} {
	set value $gui($arg)
	if {![string is double -strict $value]} return
	set now $timestamp
	set last [lindex $track($arg) end]
	if {$last eq ""} {
	    lappend track($arg) $now $value
	} elseif {$value != $last} {
	    lappend track($arg) $now $last $now $value
	}
	# Discard ancient history
	set keep [expr {$timestamp - $span}]
	set first 0
	for {set i 0} {[lindex $track($arg) $i] < $keep} {incr i 2} {
	    set first $i
	}
	if {$first > 0} {
	    set track($arg) [lrange $track($arg) $first end]
	}
    }
}

track::init
