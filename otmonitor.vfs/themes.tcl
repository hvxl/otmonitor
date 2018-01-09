proc themeinit {} {
    global tcl_platform

    if {$tcl_platform(platform) eq "unix"} {
	ttk::setTheme plastik
	array set col [ttk::style configure .]
	option add *background $col(-background) userDefault
	option add *Menu.activeBackground #668aac userDefault
	option add *Menu.activeForeground #ffffff userDefault
	option add *Menu.activeBorderWidth 0 userDefault
	option add *Menu.borderWidth 1 userDefault
	option add *Menu.relief solid userDefault
    } else {
	array set col [ttk::style configure .]
    }

    set theme $::ttk::currentTheme
    switch -- $theme {
	xpnative {
	    set classic 1
	    foreach c1 [winfo rgb . SystemButtonFace] \
	      c2 [winfo rgb . SystemMenu] {
		if {$c1 != $c2} {
		    set classic 0
		    break
		}
	    }
	    if {!$classic} {
		# Widgets on a notebook tab have a different background
		set color #fcfbfc
		ttk::style configure Tab.TFrame -background $color
		ttk::style configure Tab.TLabelframe -background $color
		ttk::style configure Tab.TLabelframe.Label -background $color
		ttk::style configure Tab.TLabel -background $color
		ttk::style configure Tab.TButton -background $color
		ttk::style configure Tab.TCheckbutton -background $color
		ttk::style configure Tab.TRadiobutton -background $color
		ttk::style configure Tab.Slim.TButton -background $color
		ttk::style configure Tab.Check.TButton -background $color
		ttk::style configure Tab.Square.TButton -background $color
	    }
	    option add *Text.background SystemButtonFace userDefault
	}
    }
    option add *Listbox.selectBackground $col(-selectbackground) userDefault
    option add *Listbox.selectForeground $col(-selectforeground) userDefault
    option add *Text.selectBackground $col(-selectbackground) userDefault
    option add *Text.selectForeground $col(-selectforeground) userDefault
    option add *Text.inactiveSelectBackground $col(-selectbackground) userDefault
}
