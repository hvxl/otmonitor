# Tk has picked up some annoying habits from Windows that do not belong on X11
# This module fixes that

# Spinbox and Combobox mess up the primary selection

proc ttk::spinbox::Spin {w dir} {
    variable State

    if {[$w instate disabled]} { return }

    if {![info exists State($w,values.length)]} {
	set State($w,values.index) -1
	set State($w,values.last) {}
    }
    set State($w,values) [$w cget -values]
    set State($w,values.length) [llength $State($w,values)]

    if {$State($w,values.length) > 0} {
	set value [$w get]
	set current $State($w,values.index)
	if {$value ne $State($w,values.last)} {
	    set current [lsearch -exact $State($w,values) $value]
	    if {$current < 0} {set current -1}
	}
	set State($w,values.index) [Adjust $w [expr {$current + $dir}] 0 \
	  [expr {$State($w,values.length) - 1}]]
	set State($w,values.last) [lindex $State($w,values) $State($w,values.index)]
	$w set $State($w,values.last)
    } else {
	if {[catch {
		set v [expr {[scan [$w get] %f] + $dir * [$w cget -increment]}]
	}]} {
	    set v [$w cget -from]
	}
	$w set [FormatValue $w [Adjust $w $v [$w cget -from] [$w cget -to]]]
    }
    # SelectAll $w
    uplevel #0 [$w cget -command]
}

proc ttk::combobox::TraverseIn {w} {
    $w instate {!readonly !disabled} {
	# $w selection range 0 end
	$w icursor end
    }
}

proc ttk::combobox::SelectEntry {cb index} {
    $cb current $index
    # $cb selection range 0 end
    $cb icursor end
    event generate $cb <<ComboboxSelected>> -when mark
}

# A disabled text widget should not take focus on mouse click
# This was borked by check-in #3ccd19e0a7
bind Text <1> {
    set ::tk::Priv(focus) [focus]
    tk::TextButton1 %W %x %y
    %W tag remove sel 0.0 end
    focus $::tk::Priv(focus)
}

# Bindings
event add <<Clear>> <Control-u>
