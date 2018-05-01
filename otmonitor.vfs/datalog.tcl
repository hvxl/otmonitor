namespace eval gui::datalog {
    namespace path ::gui
    namespace ensemble create -subcommands gui
}

proc gui::datalog::gui {w} {
    global cfg xlate
    toplevel $w.dat
    wm transient $w.dat $w
    wm title $w.dat "Data file layout editor"
    ttk::label $w.dat.l1 -text "Available data values" -font Bold
    ttk::frame $w.dat.f1 -style TEntry -borderwidth 2
    listbox $w.dat.f1.lb -bg white -width 24 -selectmode extended \
      -relief flat -highlightthickness 0 -exportselection 0 \
      -yscrollcommand [list $w.dat.f1.sb set]
    ttk::scrollbar $w.dat.f1.sb -command [list $w.dat.f1.lb yview]
    pack $w.dat.f1.sb -side right -fill y
    pack $w.dat.f1.lb -expand 1 -fill both
    ttk::label $w.dat.l2 -text "Selected data values" -font Bold
    ttk::frame $w.dat.f2 -style TEntry -borderwidth 2
    listbox $w.dat.f2.lb -bg white -width 24 -selectmode extended \
      -relief flat -highlightthickness 0 -exportselection 0 \
      -yscrollcommand [list $w.dat.f2.sb set]
    ttk::scrollbar $w.dat.f2.sb -command [list $w.dat.f2.lb yview]
    pack $w.dat.f2.sb -side right -fill y
    pack $w.dat.f2.lb -expand 1 -fill both

    ttk::button $w.dat.b1 -image [imglist go-next.png] -state disabled \
      -command [namespace code [list add $w]]
    ttk::button $w.dat.b2 -image [imglist go-previous.png] -state disabled \
      -command [namespace code [list del $w]]
    ttk::button $w.dat.b3 -image [imglist go-up.png] -state disabled \
      -command [namespace code [list move $w -1]]
    ttk::button $w.dat.b4 -image [imglist go-down.png] -state disabled \
      -command [namespace code [list move $w +1]]

    ttk::frame $w.dat.f
    ttk::button $w.dat.f.b1 -text Cancel -width 8 \
      -command [namespace code [list done $w.dat]]
    ttk::button $w.dat.f.b2 -text Done -width 8 \
      -command [namespace code [list done $w.dat 1]]
    grid $w.dat.f.b1 $w.dat.f.b2 -padx 20 -pady 15

    grid $w.dat.l1 x $w.dat.l2 -padx 8 -pady 0 -pady {8 0}
    grid $w.dat.f1 $w.dat.b1 $w.dat.f2 $w.dat.b3 -padx 8 -pady 0 -sticky s
    grid ^ $w.dat.b2 ^ $w.dat.b4 -padx 8 -pady 8 -sticky n
    grid $w.dat.f1 $w.dat.f2 -sticky ewns
    grid $w.dat.b1 $w.dat.b2 -padx 0
    grid $w.dat.b3 $w.dat.b4 -padx {0 8}
    grid $w.dat.f - - -
    grid columnconfigure $w.dat $w.dat.f1 -weight 1
    grid columnconfigure $w.dat $w.dat.f2 -weight 1
    grid rowconfigure $w.dat $w.dat.f1 -weight 1

    bind $w.dat.f1.lb <<ListboxSelect>> [namespace code [list list1select $w]]
    bind $w.dat.f2.lb <<ListboxSelect>> [namespace code [list list2select $w]]

    variable list2 [lmap n $cfg(datalog,itemlist) {
	if {![dict exists $xlate $n]} continue
	$w.dat.f2.lb insert end [dict get $xlate $n]
	set n
    }]
    variable list1 [lmap n [lsort -dictionary -indices [dict values $xlate]] {
	set key [lindex [dict keys $xlate] $n]
	if {$key in $list2} continue
	$w.dat.f1.lb insert end [dict get $xlate $key]
	set key
    }]
}

proc gui::datalog::state {win expr} {
    if {[uplevel 1 [list expr $expr]]} {
	$win state !disabled
    } else {
	$win state disabled
    }
}

proc gui::datalog::list1select {w} {
    state $w.dat.b1 {[llength [$w.dat.f1.lb curselection]] != 0}
}

proc gui::datalog::list2select {w} {
    set sel [$w.dat.f2.lb curselection]
    state $w.dat.b2 {[llength $sel] != 0}
    state $w.dat.b3 {[llength $sel] == 1 && [lindex $sel 0] > 0}
    set last [$w.dat.f2.lb index end]
    state $w.dat.b4 {[llength $sel] == 1 && [lindex $sel 0] < $last - 1}
}

proc gui::datalog::add {w} {
    variable list1; variable list2
    set pos [lindex [$w.dat.f2.lb curselection] end]
    if {$pos eq ""} {set pos [llength $list2]}
    foreach n [lreverse [$w.dat.f1.lb curselection]] {
	$w.dat.f2.lb insert $pos [$w.dat.f1.lb get $n]
	$w.dat.f1.lb delete $n
	$w.dat.f2.lb see $pos
	set list2 [linsert $list2 $pos [lindex $list1 $n]]
	set list1 [lreplace $list1 $n $n]
    }
    list1select $w
}

proc gui::datalog::del {w} {
    variable list1; variable list2
    foreach n [lreverse [$w.dat.f2.lb curselection]] {
	set str [$w.dat.f2.lb get $n]
	set pos [lsearch -dictionary -bisect [$w.dat.f1.lb get 0 end] $str]
	$w.dat.f1.lb insert [incr pos] $str
	$w.dat.f2.lb delete $n
	set list1 [linsert $list1 $pos [lindex $list2 $n]]
	set list2 [lreplace $list2 $n $n]
    }
    list2select $w
}

proc gui::datalog::move {w dir} {
    variable list2
    foreach n [$w.dat.f2.lb curselection] {
	set str [$w.dat.f2.lb get $n]
	# Add a temporary entry to avoid undesired scrolling
	$w.dat.f2.lb insert end ""
	$w.dat.f2.lb delete $n
	incr n $dir
	$w.dat.f2.lb insert $n $str
	# Delete the temporary entry again
	$w.dat.f2.lb delete end
	$w.dat.f2.lb selection set $n
	$w.dat.f2.lb see $n
	if {$dir > 0} {incr n -1}
	set x [expr {$n + 1}]
	set list2 [lreplace $list2 $n $x {*}[lreverse [lrange $list2 $n $x]]]
    }
    list2select $w
}

proc gui::datalog::done {w {save 0}} {
    variable list2
    global cfg
    if {$save} {
	set cfg(datalog,itemlist) $list2
    }
    destroy $w
}
