# Repeat the basic starkit initialization
package require starkit
set argv0 [file normalize [info script]]
starkit::startup
if {$starkit::mode in {unwrapped sourced}} {
    tcl::tm::add {*}[glob -nocomplain [file join $starkit::topdir lib tcl? *]]
}

package require Tk
wm withdraw .
tk appname otmonpwd
wm protocol . WM_DELETE_WINDOW {thread::release}

source [file join [file dirname [info script]] themes.tcl]
themeinit

proc mainthread {cmd} {
    global mainthread
    return [thread::send $mainthread $cmd]
}

if 0 {
    for {set retries 1} {$retries < 10} {incr retries} {
	if {[catch {image create photo icon \
    	  -file [file join $starkit::topdir images users.png]}]} {
	    lappend ::errorLog $::errorInfo
	} else {
	    break
	}
    }
}

proc gui {} {
    image create photo icon -file [file join $starkit::topdir images users.png]

    toplevel .pwd
    place [ttk::frame .pwd.bg] -relwidth 1 -relheight 1
    wm withdraw .pwd
    wm title .pwd "Manage users"
    wm iconphoto .pwd icon

    ttk::frame .pwd.f1 -style TEntry -borderwidth 2
    listbox .pwd.f1.lb -yscrollcommand {.pwd.f1.vs set} \
      -width 20 -background white -relief flat -highlightthickness 0 \
      -selectmode extended -exportselection 0
    ttk::scrollbar .pwd.f1.vs -command {.pwd.f1.lb yview}
    pack .pwd.f1.vs -side right -fill y
    pack .pwd.f1.lb -fill both -expand 1

    ttk::button .pwd.b1 -text "Create new user" -command userdlg
    ttk::button .pwd.b2 -text "Change password" -command {userdlg .pwd.f1.lb} \
      -state disabled
    ttk::button .pwd.b3 -text "Delete user" -command {userdel .pwd.f1.lb} \
      -state disabled
    ttk::button .pwd.b4 -text "Done" -width 6 -command {thread::release}

    pack .pwd.f1 -padx 12 -pady 12 -side left -fill both -expand 1
    pack .pwd.b1 .pwd.b2 .pwd.b3 -side top -pady {12 0} -padx {0 12} -fill x
    pack .pwd.b4 -side bottom -pady 12 -padx {0 12} -anchor e

    bind .pwd.f1.lb <<ListboxSelect>> {usersel %W}
    update

    foreach n [lsort -dictionary [mainthread {security getusers}]] {
	.pwd.f1.lb insert end $n
    }

    tk::PlaceWindow .pwd
    wm deiconify .pwd
}

proc usersel {w} {
    set sel [$w curselection]
    if {[llength $sel] > 0} {
	.pwd.b3 state !disabled
    } else {
	.pwd.b3 state disabled
    }
    if {[llength $sel] == 1} {
	.pwd.b2 state !disabled
    } else {
	.pwd.b2 state disabled
    }
}

proc userdel {w} {
    set sel [$w curselection]
    if {[llength $sel] == 1} {
	set name [$w get [lindex $sel 0]]
	set msg "Delete user $name?"
    } else {
	set msg "Delete [llength $sel] users?"
    }
    set ans [tk_messageBox -default no -icon question -message $msg \
      -parent .pwd -title "Delete users" -type yesno]
    if {$ans eq "yes"} {
	foreach n [lreverse $sel] {
	    set name [$w get $n]
	    mainthread [list security deluser $name]
	    $w delete $n
	}
	usersel $w
    }
}

proc userdlg {{w ""}} {
    global cfg
    toplevel .pwd.dlg
    place [ttk::frame .pwd.dlg.bg] -relwidth 1 -relheight 1
    wm transient .pwd.dlg .pwd
    array set cfg {name "" pass1 "" pass2 ""}

    ttk::frame .pwd.dlg.f1
    ttk::label .pwd.dlg.f1.l1 -text "User name:"
    ttk::entry .pwd.dlg.f1.e1 -textvariable cfg(name)
    ttk::label .pwd.dlg.f1.l2 -text "Password:"
    ttk::entry .pwd.dlg.f1.e2 -textvariable cfg(pass1) -show #
    ttk::label .pwd.dlg.f1.l3 -text "Confirm:"
    ttk::entry .pwd.dlg.f1.e3 -textvariable cfg(pass2) -show #
    
    grid .pwd.dlg.f1.l1 .pwd.dlg.f1.e1 -padx 2 -pady 2 -sticky ew
    grid .pwd.dlg.f1.l2 .pwd.dlg.f1.e2 -padx 2 -pady 2 -sticky ew
    grid .pwd.dlg.f1.l3 .pwd.dlg.f1.e3 -padx 2 -pady 2 -sticky ew
    grid columnconfigure .pwd.dlg.f1 .pwd.dlg.f1.e1 -weight 1
    grid .pwd.dlg.f1 - - - -padx 6 -pady 6
    grid columnconfigure .pwd.dlg .pwd.dlg.f1 -weight 1

    set new [string equal $w ""]
    ttk::button .pwd.dlg.b1 -text OK -width 8 -command [list userchg $new]
    ttk::button .pwd.dlg.b2 -text Cancel -width 8 -command {destroy .pwd.dlg}
    grid x .pwd.dlg.b1 .pwd.dlg.b2 x -padx 12 -pady 8 -sticky ew
    grid columnconfigure .pwd.dlg all -weight 1
    grid columnconfigure .pwd.dlg {.pwd.dlg.b1 .pwd.dlg.b2} \
      -weight 0 -uniform buttons

    if {$new} {
	wm title .pwd.dlg "Create new user"
    } else {
	set sel [$w curselection]
	set cfg(name) [$w get [lindex $sel 0]]
	wm title .pwd.dlg "Change password"
	.pwd.dlg.f1.e1 state readonly
    }

    tk::PlaceWindow .pwd.dlg widget .pwd
    grab .pwd.dlg
}

proc userchg {new} {
    global cfg
    if {$cfg(pass1) ne $cfg(pass2)} {
	tk_messageBox -icon error -message "Passwords don't match" \
	  -parent .pwd.dlg -title [wm title .pwd.dlg] -type ok
	return
    }
    if {!$new} {
	mainthread [list security chguser $cfg(name) $cfg(pass1)]
    } elseif {[catch {mainthread [list security adduser $cfg(name) $cfg(pass1) rw]}]} {
	tk_messageBox -icon error -message "User already exists" \
	  -parent .pwd.dlg -title [wm title .pwd.dlg] -type ok
	return
    } else {
	set w .pwd.f1.lb
	set list [$w get 0 end]
	set x [lsearch -bisect -dictionary $list $cfg(name)]
	if {$x < 0 || [$w get $x] ne $cfg(name)} {
	    $w insert [incr x] $cfg(name)
	}
    }
    destroy .pwd.dlg
}

gui

# Start the event loop
thread::wait
