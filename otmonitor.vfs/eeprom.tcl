namespace eval gui::eeprom {
    namespace ensemble create -subcommand gui
}

proc gui::eeprom::gui {w} {
    global eeprom
    destroy $w.set
    toplevel $w.set
    wm transient $w.set $w
    wm title $w.set "Transferred EEPROM settings"
    text $w.set.t -width 60 -height 16 -relief flat -highlightthickness 0 \
      -cursor "" -font TkDefaultFont -wrap word
    ttk::button $w.set.b1 -text Close -command [list destroy $w.set]
    menu $w.set.t.menu -tearoff 0
    $w.set.t.menu add command -label "Select All" \
      -command [list event generate $w.set.t <<SelectAll>>]
    $w.set.t.menu add command -label "Copy" \
      -command [list event generate $w.set.t <<Copy>>]
    pack $w.set.b1 -side bottom -pady 4
    pack $w.set.t -fill both -expand 1 -padx 4 -pady 4
    foreach n {
	Configuration ThermostatModel AwaySetpoint DHWSetpoint MaxCHSetpoint
	SavedSettings FunctionLED FunctionGPIO AlternativeCmd UnknownFlags
    } {
	if {[dict exists $eeprom $n value]} {
	    [string tolower $n] $w.set.t [dict get $eeprom $n]
	}
    }
    $w.set.t delete end-1c
    $w.set.t configure -state disabled
    set font [$w.set.t cget -font]
    set tab 0
    foreach line [split [$w.set.t get 1.0 end] \n] {
	if {[llength [lassign [split $line \t] str]] > 0} {
	    set tab [expr {max($tab, [font measure $font $str])}]
	}
    }
    $w.set.t configure -tabs [incr tab 20]
    $w.set.t tag configure wrap -lmargin2 $tab
    $w.set.t tag add wrap 1.0 end

    lassign [split [$w.set.t index end] .] height
    $w.set.t configure -height $height

    bind $w.set.t <3> [list tk_popup $w.set.t.menu %X %Y]
}

proc gui::eeprom::bool {bool {true On} {false Off}} {
    return [if {$bool} {set true} {set false}]
}

proc gui::eeprom::savedsettings {w data} {
    set val [dict get $data value]
    set ref [expr {voltref($val)}]
    set volt [expr {voltage($ref)}]
    $w insert end "Reference voltage:\t[format %d=%.3fV $ref $volt]\n"
    $w insert end "Ignore transitions:\t[bool [expr {$val & 0x20}]]\n"
    $w insert end "Override high byte:\t[bool [expr {$val & 0x40}]]\n"
}

proc gui::eeprom::functiongpio {w data} {
    global gpiofunc
    lassign [split [format %02x [dict get $data value]] ""] g2 g1
    if {[dict exists $gpiofunc $g1]} {
	set f1 [dict get $gpiofunc $g1]
    } else {
	set f1 None
    }
    if {[dict exists $gpiofunc $g2]} {
	set f2 [dict get $gpiofunc $g2]
    } else {
	set f2 None
    }
    $w insert end "GPIO 1 function:\t$g1=$f1\n"
    $w insert end "GPIO 2 function:\t$g2=$f2\n"
}

proc gui::eeprom::awaysetpoint {w data} {
    lassign [dict get $data value] unit frac
    $w insert end "Away setpoint:\t[float [expr {$unit * 256 + $frac}]]\n"
}

proc gui::eeprom::dhwsetpoint {w data} {
    lassign [dict get $data value] unit frac
    if {$unit} {
	set value [float [expr {$unit * 256 + $frac}]]
    } else {
	set value --
    }
    $w insert end "DHW setpoint:\t$value\n"
}

proc gui::eeprom::maxchsetpoint {w data} {
    lassign [dict get $data value] unit frac
    if {$unit} {
	set value [float [expr {$unit * 256 + $frac}]]
    } else {
	set value --
    }
    $w insert end "Max CH setpoint:\t$value\n"
}

proc gui::eeprom::functionled {w data} {
    global functions
    set val [dict get $data value]
    foreach n [split [binary format c* $val] ""] {
	if {[dict exists $functions $n]} {
	    set func [dict get $functions $n]
	} else {
	    set func Unassigned
	}
	$w insert end "LED [incr num] function:\t$n=$func\n"
    }
}

proc gui::eeprom::thermostatmodel {w data} {
    set val [dict get $data value]
    if {$val & 0x40} {
	set model iSense
    } elseif {$val & 0x20} {
	set model "Celcia 20"
    } elseif {$val & 0x10} {
	set model "Standard"
    } else {
	set model "Auto detect"
    }
    $w insert end "Thermostat model:\t$model\n"
}

proc gui::eeprom::alternativecmd {w data} {
    set list [lsearch -all -inline -exact -not [dict get $data value] 0]
    $w insert end "Alternative IDs:\t[join $list {, }]\n"
}

proc gui::eeprom::unknownflags {w data} {
    binary scan [binary format c* [dict get $data value]] b* bits
    set list [lsearch -all -exact [split $bits ""] 1]
    $w insert end "Blocked MessageIDs:\t[join $list {, }]\n"
}

proc gui::eeprom::configuration {w data} {
    set val [dict get $data value]
    set mask [if {[dict exists $data mask]} {dict get $data mask} {expr 0xff}]

    set dhwmodes {
	"Comfort mode"
	"Economy mode"
	"Thermostat controlled"
    }
    set dtsfuncs {"Return water temperature" "Outside temperature"}
    set dhw [expr {$val & 0x10 ? !($val & 0x20) : 2}]
    # Only report the operating mode if it was transferred.
    if {$mask & 1} {
	set gw [expr {$val & 1}]
	$w insert end "Operating mode:\t[bool $gw Monitor Gateway]\n"
    }
    $w insert end "Comfort setting:\t[lindex $dhwmodes $dhw]\n"
    if {$mask & 4} {
	set func [expr {$val & 4}]
	$w insert end "Temperature sensor:\t[bool $func {*}$dtsfuncs]\n"
    }
    if {$mask & 8} {
	set mode [expr {$val & 8}]
	$w insert end "Force summer mode:\t[bool $mode]\n"
    }
}
