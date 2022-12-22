# Create a treeview style without an indicator to use as an advanced listbox
ttk::style configure Listbox.Treeview -padding {2 0}
ttk::style layout Listbox.Treeview {
    Treeview.padding -sticky nswe -children {
        Treeview.treearea -sticky nswe
    }
}
ttk::style layout Listbox.Treeview.Item {
    Treeitem.padding -sticky nswe -children {
        Treeitem.image -side left -sticky {}
        Treeitem.focus -side left -sticky {} -children {
            Treeitem.text -side left -sticky {}
        }
    }
}

if {"SeparatorFont" ni [font names]} {
    font create SeparatorFont {*}[font actual TkDefaultFont] -overstrike 1
}

namespace eval gui::customize {
    namespace path ::gui
}

proc gui::customize::dlg {var f def {rst {}}} {
    upvar #0 $var cfg
    set w [toplevel .custom]
    place [ttk::frame $w.bg] -relheight 1 -relwidth 1
    wm title $w "Customize OTmonitor"
    ttk::label $w.l1 -text "Available items" -width ""
    ttk::frame $w.f1 -style TEntry -borderwidth 2 -takefocus 0
    set tv1 [ttk::treeview $w.f1.tv -style Listbox.Treeview -height 12 \
      -show tree -yscrollcommand [list $w.f1.vs set]]
    $tv1 tag configure used -foreground #CCC
    $tv1 tag configure break -font SeparatorFont
    $tv1 tag configure statusflag -image [img flag.png]
    $tv1 tag configure statusvalue -image [img variable.png]
    $tv1 tag configure statuswide -image [img special.png]
    ttk::scrollbar $w.f1.vs -command [list $tv1 yview]
    pack $w.f1.vs -side right -fill y
    pack $tv1 -fill both -expand 1
    ttk::label $w.l2 -text "Displayed items" -width ""
    ttk::frame $w.f2 -style TEntry -borderwidth 2 -takefocus 0
    set tv2 [ttk::treeview $w.f2.tv -style Listbox.Treeview -height 12 \
      -show tree -yscrollcommand [list $w.f2.vs set]]
    $tv2 tag configure break -font SeparatorFont
    $tv2 tag configure statusflag -image [img flag.png]
    $tv2 tag configure statusvalue -image [img variable.png]
    $tv2 tag configure statuswide -image [img special.png]
    ttk::scrollbar $w.f2.vs -command [list $tv2 yview]
    pack $w.f2.vs -side right -fill y
    pack $tv2 -fill both -expand 1
    ttk::button $w.b1 -image [imglist go-next.png] -state disabled \
      -command [namespace code [list add $w]]
    ttk::button $w.b2 -image [imglist go-previous.png] -state disabled \
      -command [namespace code [list del $w]]
    ttk::button $w.b3 -image [imglist go-up.png] -state disabled \
      -command [namespace code [list move $w -1]]
    ttk::button $w.b4 -image [imglist go-down.png] -state disabled \
      -command [namespace code [list move $w +1]]

    ttk::separator $w.sep
    ttk::frame $w.buttons
    ttk::button $w.buttons.b1 -text Defaults \
      -command [namespace code [list reset $w $def $rst]]
    ttk::button $w.buttons.b2 -text Done \
      -command [namespace code [list done $w $f $var $def done]]
    ttk::button $w.buttons.b3 -text Apply \
      -command [namespace code [list done $w $f $var $def apply]]
    ttk::button $w.buttons.b4 -text Cancel \
      -command [namespace code [list done $w $f $var $def cancel]]
    grid $w.buttons.b1 x $w.buttons.b2 $w.buttons.b3 $w.buttons.b4 \
      -padx 4 -pady 4
    grid columnconfigure $w.buttons 1 -weight 1
    if {[llength $rst] == 0} {grid forget $w.buttons.b1}

    $tv1 insert {} end -text [string repeat " " 60] -tags break
    dict for {name cmd} $def {
	lassign $cmd type str suffix
	if {$suffix ne ""} {append str "*"}
	$tv1 insert {} end -id $name -text $str -tags [list $type]
    }
    reset $w $def $cfg
    grid $w.l1 x $w.l2 -padx 8 -sticky s -pady {8 0}
    grid $w.f1 $w.b1 $w.f2 $w.b3 -padx 8 -pady 0 -sticky s
    grid ^ $w.b2 ^ $w.b4 -padx 8 -pady 8 -sticky n
    grid $w.f1 $w.f2 -sticky ewns -pady {0 8}
    grid $w.b1 $w.b2 -padx 0
    grid $w.b3 $w.b4 -padx {0 8}
    grid $w.sep -columnspan 4 -sticky ew -padx 8 -pady 2
    grid $w.buttons -columnspan 4 -sticky ew -padx 4 -pady 4
    grid columnconfigure $w [list $w.f1 $w.f2] -weight 1
    grid rowconfigure $w [list $w.b1 $w.b2] -weight 1

    bind $w.f1.tv <<TreeviewSelect>> [namespace code [list list1select $w]]
    bind $w.f2.tv <<TreeviewSelect>> [namespace code [list list2select $w]]

    ::tk::PlaceWindow $w widget [winfo toplevel $f]
}

proc gui::customize::list1select {w} {
    set tv $w.f1.tv
    $tv tag add sel [$tv selection]
    $tv tag remove sel [$tv tag has used]
    set sel [$tv tag has sel]
    $tv tag remove sel $sel
    if {[llength $sel] != [llength [$tv selection]]} {
	# This triggers the binding again
	$w.f1.tv selection set $sel
    } else {
	state $w.b1 {[llength [$w.f1.tv selection]] != 0}
    }
}

proc gui::customize::list2select {w} {
    set tv $w.f2.tv
    set sel [$tv selection]
    state $w.b2 {[llength $sel] != 0}
    state $w.b3 {[llength $sel] == 1 && [$tv index [lindex $sel 0]] > 0}
    set size [llength [$tv children {}]]
    state $w.b4 \
      {[llength $sel] == 1 && [$tv index [lindex $sel 0]] < $size - 1}
}

proc gui::customize::state {win expr} {
    if {[uplevel 1 [list expr $expr]]} {
	$win state !disabled
    } else {
	$win state disabled
    }
}

proc gui::customize::move {w delta} {
    set tv $w.f2.tv
    set item [lindex [$tv selection] 0]
    set pos [expr {[$tv index $item] + $delta}]
    $tv move $item {} $pos
    $tv see $item
    list2select $w
}

proc gui::customize::add {w} {
    set tv1 $w.f1.tv
    set tv2 $w.f2.tv
    set sel [lindex [$tv2 selection] end]
    set pos [if {$sel eq ""} {llength [$tv2 children {}]} {$tv2 index $sel}]
    foreach n [lreverse [$tv1 selection]] {
	if {[$tv1 tag has break $n]} {
	    $tv2 insert {} $pos -text [$tv1 item $n -text] -tags break
	} else {
	    $tv2 insert {} $pos -id $n \
	      -text [$tv1 item $n -text] -tags [$tv1 item $n -tags]
	    $tv1 tag add used $n
	}
    }
    $tv1 selection set {}
    state $w.b1 0
    list2select $w
}

proc gui::customize::del {w} {
    set tv1 $w.f1.tv
    set tv2 $w.f2.tv
    $tv2 tag add unused [$tv2 selection]
    $tv2 tag remove unused [$tv2 tag has break]
    $tv1 tag remove used [$tv2 tag has unused]
    $tv2 delete [$tv2 selection]
}

proc gui::customize::reset {w def cfg} {
    set tv1 $w.f1.tv
    set tv2 $w.f2.tv
    $tv2 delete [$tv2 children {}]
    $tv1 tag remove used [$tv1 tag has used]
    foreach name $cfg {
	if {$name eq ""} {
	    $tv2 insert {} end -text [string repeat " " 60] -tags break
	} elseif {[dict exists $def $name]} {
	    lassign [dict get $def $name] type str suffix
	    $tv2 insert {} end -id $name -text $str -tags [list $type]
	    $tv1 tag add used $name
	}
    }
    list1select $w
    list2select $w
}

proc gui::customize::done {w f var def {opt done}} {
    upvar #0 $var cfg
    if {$opt in {apply done}} {
	set tv2 $w.f2.tv
	set cfg [$tv2 children {}]
	foreach n [$tv2 tag has break] {
	    lset cfg [$tv2 index $n] ""
	}
	statusarea $f $def $cfg
    }
    if {$opt in {cancel done}} {
	destroy $w
    }
}
