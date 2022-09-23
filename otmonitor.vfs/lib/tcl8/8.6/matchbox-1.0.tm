# A combobox widget with suggestions
# Copyright (C) Schelte Bron.  Freely redistributable.
# Version 1.0 - 26 Nov 2017

namespace eval ::ttk::matchbox {
    # /usr/share/icons/oxygen/16x16/actions/edit-clear-locationbar-rtl.png
    variable clear [image create photo [namespace current]::clear -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAMAAAAoLQ9TAAAAA3NCSVQICAjb4U/g
	AAAACXBIWXMAAAG7AAABuwE67OPiAAAAGXRFWHRTb2Z0d2FyZQB3d3cuaW5rc2Nh
	cGUub3Jnm+48GgAAATVQTFRF////AAAAOkI6AAAALDIsAAAAICAgAAAAFRUSAAAA
	BQUFPT48AAAAPT47Y2NjAAAAAQEBMDEvAgICJCUkAgICGBgXBAQEDQ0NAQEBAgIC
	BAQEBQUFBgYGBwcHCAgIDAwMDQ0NEBAQFBQTFBQUGRkZICAgISIhIiIiJycmLzAu
	MTExMjMxNzc3Ojo6PT47Pz8/QUFBQUI/REVDRUVFR0dHSkpKSktIS0tLTU5LTk5O
	Tk9NUFBQU1NTVFRUVlZVVldUWFlWWVlZW1tbZGRjZGZiZmhkaGhoampqamtncXFx
	dXV1eXl5enp6hISEhoaGioqKkJCQn5+frKysrq6usrKxt7i3wcHBxMXExsbGz9DP
	1NTU3t7e4eHh5+fn6enp6urq7e3t8PDw8/Pz9PT0+vr6+/v7/Pz8dUr3qgAAABh0
	Uk5TAB8fLi4/P1RUZWW4ysrU5eXl8PD4+P39CqmsmgAAAJ1JREFUGBmdwQMWAgEA
	BcCfbdu2bdt2W3v/I4Q9QO81A/yJLgpTBPhiyurjQb837LR9+GArijNiUh8R86Ib
	b1xVqrZ/3BcEecnZAfA10UyydHg8yVshYgQg8UdCweCUJJ9Tj1MLgKe2WG2Jw/V0
	PeZ0OrxxlAb99rwpr887lx4fLLkjvszHKqtGwIAvhtSbrja7rWrWBApNaKaI8dsL
	XHIcGL0rDy8AAAAASUVORK5CYII=
    }]

    variable blank [image create photo [namespace current]::blank \
      -width 16 -height 16]

    event add <<Clear>> <Control-u>

    proc Motion {w x y} {
	$w instate {!readonly !disabled} {
	    set elem [$w identify $x $y]
	    if {$elem eq "textarea" || \
	      $elem eq "TMatchbox.clrbutton" && [$w instate alternate]} {
		ttk::setCursor $w text
		return
	    }
	}
	ttk::setCursor $w ""
    }

    proc Press {w x y} {
	if {[winfo exists $w.top] && [winfo ismapped $w.top]} {
	    grab release $w
	    wm withdraw $w.top
	    return
	}
	set e [$w identify element $x $y]
	if {$e eq "TMatchbox.clrbutton" \
	  && [$w instate {!disabled !readonly}]} {
	    focus $w
	    event generate $w <<Clear>>
	} elseif {[winfo class $w] eq "TMatchbox"} {
	    ::ttk::combobox::Press "" $w $x $y
	} else {
	    ::ttk::entry::Press $w $x
	}
    }

    proc ThemeInit {} {
	# Unfortunately there is no `ttk::style layout exists` command
	if {"TMatchbox.clrbutton" in [ttk::style element names]} return

	variable blank
	variable clear

	ttk::style element create TMatchbox.clrbutton \
	  image [list $blank {!alternate !readonly !disabled} $clear] -sticky e

	ttk::style layout TMatchbox {
	    Combobox.field -sticky nswe -children {
		Combobox.downarrow -side right -sticky ns 
		Combobox.padding -expand 1 -sticky nswe -children {
		    TMatchbox.clrbutton -side right
		    Combobox.textarea -sticky nswe
		}
	    }
	}

	ttk::style layout ClrTEntry {
	    Entry.field -sticky nswe -children {
		Entry.padding -sticky nswe -children {
		    TMatchbox.clrbutton -side right
		    Entry.textarea -sticky nswe
		}
	    }
	}
    }

    proc ReconfigurePopdown {w} {
	set font [ttk::style lookup TCombobox -font {} TkDefaultFont]
	set bg [ttk::style lookup TCombobox -fieldbackground {} white]
	set fg [ttk::style lookup TCombobox -foreground {} black]
	set selfg [ttk::style lookup TCombobox -selectforeground {} white] 
	set selbg [ttk::style lookup TCombobox -selectbackground {} darkblue]

	if {[winfo class $w] eq "ComboboxPopdown"} {
	    set lb $w.f.l
	} else {
	    $w configure -background $fg
	    set lb $w.lb
	}
	$lb configure -font $font -foreground $fg -background $bg \
	  -selectforeground $selfg -selectbackground $selbg
    }

    ::ttk::copyBindings TCombobox TMatchbox
    ::ttk::copyBindings TEntry ClrTEntry

    bind TMatchbox <<Clear>> {%W delete 0 end}
    bind TMatchbox <Motion> [list [namespace current]::Motion %W %x %y]
    bind TMatchbox <1> [list [namespace current]::Press %W %x %y]
    bind TMatchbox <<ThemeChanged>> [list [namespace current]::ThemeInit]
    bind ClrTEntry <<Clear>> {%W delete 0 end}
    bind ClrTEntry <Motion> [list [namespace current]::Motion %W %x %y]
    bind ClrTEntry <1> [list [namespace current]::Press %W %x %y]
    bind ClrTEntry <<ThemeChanged>> [list [namespace current]::ThemeInit]
    bind TMatchboxPopdown <<ThemeChanged>> \
      [list [namespace current]::ReconfigurePopdown %W]

    option add *TMatchbox*Listbox.font TkTextFont
    option add *TMatchbox*Listbox.relief flat
    option add *TMatchbox*Listbox.highlightThickness 0
    switch -- [tk windowingsystem] {
	x11 {
	    option add *TMatchbox*Listbox.background white
	}
	aqua {
	    option add *TMatchbox*Listbox.borderWidth 0
	}
    }
}

::tk::Megawidget create ::ttk::entrybox {} {
    constructor {args} {
	my ThemeInit
	next {*}$args
    }

    destructor {
	my variable options
	my VarUntrace $options(-textvariable)
    }

    method GetSpecs {} {
	my variable w
	if {![winfo exists $w]} {
	    ttk::entry $w -class ClrTEntry -style ClrTEntry
	    return [$w configure]
	} else {
	    return [theWidget configure]
	}
    }

    method CreateHull {} {
	my variable w hull
	set hull $w
    }

    method Create {} {
	my variable w options
	$w configure {*}[dict remove [array get options] -class -style]

	my VarTrace
	my UpdateIcon
    }

    method VarUntrace {var} {
	if {$var ne ""} {
	    set cmd [list [namespace which my] UpdateIcon]
	    trace remove variable $var write $cmd
	}
    }

    method VarTrace {{oldvar ""}} {
	my variable options
	my VarUntrace $oldvar
	set var $options(-textvariable)
	if {$var ne ""} {
	    set cmd [list [namespace which my] UpdateIcon]
	    trace add variable $var write $cmd
	}
    }

    method Update {} {
	my UpdateIcon
    }

    method UpdateIcon {{var {}} {arg {}} {op command}} {
	if {$op eq "command"} {
	    set str [theWidget get]
	} elseif {[uplevel 1 [list array exists $var]]} {
	    upvar 1 ${var}($arg) str
	} else {
	    upvar 1 $var str
	}
	if {[info exists str] && $str ne ""} {
	    theWidget state !alternate
	} else {
	    theWidget state alternate
	}
    }

    method configure {args} {
	my variable options
	set saved [array get options]
	set rc [next {*}$args]
	if {[llength $rc]} {return $rc}
	set opts [dict map {opt val} $args {set options($opt)}]
	if {[dict get $saved -textvariable] != $options(-textvariable)} {
	    my VarTrace [dict get $saved -textvariable]
	}
	theWidget configure {*}[dict remove $opts -matchcommand -class -style]
	return
    }

    method delete {args} {
	set rc [theWidget delete {*}$args]
	my Update
	return $rc
    }

    method insert {index value} {
	set rc [theWidget insert $index $value]
	my Update
	return $rc
    }

    method set {value} {
	set disabled [theWidget state !disabled]
	theWidget delete 0 end
	set rc [theWidget insert end $value]
	theWidget state $disabled
	my UpdateIcon
	return $rc
    }

    forward bbox theWidget bbox
    forward current theWidget current
    forward get theWidget get
    forward icursor theWidget icursor
    forward identify theWidget identify
    forward index theWidget index
    forward instate theWidget instate
    forward selection theWidget selection
    forward state theWidget state
    forward validate theWidget validate
    forward xview theWidget xview
    forward ThemeInit ::ttk::matchbox::ThemeInit
}

::tk::Megawidget create ::ttk::matchbox ::ttk::entrybox {
    method GetSpecs {} {
	return {
	    {-height height Height 10}
	    {-postcommand postCommand PostCommand {}}
	    {-values values Values {}}
	    {-exportselection exportSelection ExportSelection 1}
	    {-font font Font TkTextFont}
	    {-invalidcommand invalidCommand InvalidCommand {}}
	    {-justify justify Justify left}
	    {-show show Show {}}
	    {-state state State normal}
	    {-textvariable textVariable Variable {}}
	    {-validate validate Validate none}
	    {-validatecommand validateCommand ValidateCommand {}}
	    {-width width Width 20}
	    {-xscrollcommand xScrollCommand ScrollCommand {}}
	    {-foreground textColor TextColor {}}
	    {-background windowColor WindowColor {}}
	    {-takefocus takeFocus TakeFocus ttk::takefocus}
	    {-cursor cursor Cursor {}}
	    {-style style Style TMatchbox}
	    {-class {} {} TMatchbox}
	    {-matchcommand matchCommand MatchCommand {}}
	}
    }

    method CreateHull {} {
	my variable w hull options
	set opts [dict remove [array get options] -matchcommand]
	set hull [ttk::combobox $w {*}$opts]
    }

    method Create {} {
	my variable w listbox matchlist
	variable str
	set listbox [toplevel $w.top -relief flat -borderwidth 1]
	frame $listbox.wf
	listbox $listbox.lb -width 1 -exportselection 0 \
	  -listvariable [namespace which -variable matchlist] \
	  -yscrollcommand [list $listbox.sb set]
	ttk::scrollbar $listbox.sb -command [list $listbox.lb yview]
	wm overrideredirect $listbox 1
	grid $listbox.lb $listbox.sb -sticky ns
	grid $listbox.lb -sticky nesw -padx 0
	grid $listbox.wf - -row 0
	grid columnconfigure $listbox $listbox.lb -weight 1
	wm withdraw $listbox
	bindtags $listbox [linsert [bindtags $listbox] end-1 TMatchboxPopdown]
	set popdown [ttk::combobox::PopdownWindow $w]
	bindtags $popdown [linsert [bindtags $popdown] end-1 TMatchboxPopdown]
	event generate $listbox <<ThemeChanged>>

	bind $w <Down> [namespace code [list my Arrow down]]
	bind $w <Up> [namespace code [list my Arrow up]]
	bind $w <Return> [namespace code [list my Select]]
	bind $w <Escape> [namespace code [list my Escape]]
	bind $listbox.lb <Enter> [list $w configure -cursor ""]
	bind $listbox.lb <<ListboxSelect>> [namespace code [list my Pick]]
	# If the listbox steals the focus, give it back to the rightful owner
	bind $listbox.lb <FocusIn> [list focus $w]

	my VarTrace
	my UpdateIcon
    }

    method Update {} {
	my variable options matchlist listbox str
	set str [theWidget get]
	my UpdateIcon
	set cmd $options(-matchcommand)
	if {$cmd ne ""} {
	    set matchlist [uplevel #0 [linsert $cmd end $str]]
	    $listbox.lb selection clear 0 end
	    set size [llength $matchlist]
	    set exact [expr {$size == 1 && [lindex $matchlist 0] eq $str}]
	    if {$size && !$exact} {
		if {$size > 15} {
		    grid $listbox.sb
		    $listbox.lb configure -height 15
		} else {
		    grid remove $listbox.sb
		    $listbox.lb configure -height 0
		}
		if {![winfo ismapped $listbox]} {my MapListBox}
	    } else {
		if {[winfo ismapped $listbox]} {my UnmapListBox}
	    }
	}
    }

    method MapListBox {} {
	my variable w listbox
	set x [expr {[winfo rootx $w] + 5}]
	set y [expr {[winfo rooty $w] + [winfo height $w] - 4}]
	set h [expr {[winfo reqheight $listbox.lb] + 2}]
	if {$y + $h > [winfo screenheight $w]} {
	    set y [expr {[winfo rooty $w] - [winfo screenheight $w] + 4}]
	}
	set l [expr {[winfo width $w] - 2 - 10}]
	$listbox.wf configure -width $l
	$listbox.lb selection clear 0 end
	wm geometry $listbox [format {%+d%+d} $x $y]
	wm deiconify $listbox
	grab -global $w
    }

    method UnmapListBox {} {
	my variable w listbox
	wm withdraw $listbox
	grab release $w
    }

    method Arrow {dir} {
	my variable listbox
	if {![winfo ismapped $listbox]} return
	set sel [$listbox.lb curselection]
	if {[llength $sel] != 1} {
	    set x -1
	} else {
	    set x [lindex $sel 0]
	}
	set size [$listbox.lb size]
	$listbox.lb selection clear $x
	if {$dir eq "down"} {
	    if {[incr x] >= $size} {set x 0}
	} else {
	    if {[incr x -1] < 0} {set x [expr {$size - 1}]}
	}
	$listbox.lb selection set $x
	$listbox.lb see $x
	theWidget set [$listbox.lb get $x]
	theWidget icursor end
	theWidget xview moveto 1
	theWidget validate
	return -code break
    }

    method Select {} {
	my variable w str listbox
	if {[winfo ismapped $listbox]} {
	    my UnmapListBox
	    set str [theWidget get]
	    my UpdateIcon
	    event generate $w <<MatchSelected>>
	} else {
	    event generate $w <<MismatchSelected>>
	}
    }

    method Escape {} {
	my variable str
	my UnmapListBox
	theWidget set $str
    }

    method Pick {} {
	my variable w listbox str
	foreach n [$listbox.lb curselection] {
	    theWidget set [$listbox.lb get $n]
	    theWidget icursor end
	    theWidget xview moveto 1
	    theWidget validate
	    my UpdateIcon
	    break
	}
	my UnmapListBox
    }

    method set {value} {
	variable str $value
	set rc [theWidget set $value]
	my UpdateIcon
	my UnmapListBox
	return $rc
    }

    forward current theWidget current
    forward selection theWidget selection
}

package provide matchbox 1.0
