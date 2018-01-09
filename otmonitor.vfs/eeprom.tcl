namespace eval gui::eeprom {
    namespace ensemble create -subcommand gui
}

proc gui::eeprom::gui {w} {
    global eeprom
    destroy $w.set
    toplevel $w.set
    wm transient $w.set $w
    wm title $w.set "Transferred EEPROM settings"
    text $w.set.t -width 60 -height 18 -relief flat -highlightthickness 0 \
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
	SavedSettings FunctionGPIO AwaySetpoint FunctionLED ThermostatModel
	AlternativeCmd UnknownFlags
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

    bind $w.set.t <3> [list tk_popup $w.set.t.menu %X %Y]
}

proc gui::eeprom::savedsettings {w data} {
    set val [dict get $data value]
    set ref [expr {($val & 0x1f) - 3}]
    set volt [expr {($val & 0x1f) * 5. / 24}]
    $w insert end "Reference voltage:\t[format %d=%.3fV $ref $volt]\n"
    $w insert end "Ignore transitions:\t[expr {($val & 0x20) != 0}]\n"
    $w insert end "Override high byte:\t[expr {($val & 0x40) != 0}]\n"
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
    $w insert end "Away setpoint:\t[format %.2f [expr {$unit + $frac / 256.}]]\n"
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
    } else {
	set model Default
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
