# Search dialog for a text widget

oo::class create ::ttk::search {
    superclass ::oo::class
    self method unknown {w args} {
	if {[winfo exists $w] && [winfo class $w] eq "Text"} {
	    my create $w.search $w {*}$args
	    return $w.search
	}
	error "usage: ::ttk::search <textwidget>"
    }

    # Disallow the normal object creation methods
    unexport new create

    constructor {text {title Search}} {
	# Juggle some names around to end up with a toplevel with a widget
	# path equal to the name of the current object, which can be accessed
	# using the private top command
	variable txt $text w [namespace tail [self]] history {}
	rename [self] obj
	toplevel $w
	rename ::$w top
	rename [self] ::$w

	wm transient $w $txt
	wm title $w $title
	wm protocol $w WM_DELETE_WINDOW [list $w.done invoke]
	if {"found" ni [$txt tag names]} {
	    $txt tag configure found -background yellow
	}

	my variable opt
	array set opt {case 0 regexp 0 wrap 1 str ""}
	set var [namespace which -variable opt]
	ttk::frame $w.f1
	ttk::label $w.prompt -text "Find:"
	ttk::matchbox create $w.str -width 40 -textvariable ${var}(str)
	# ttk::combobox $w.str -width 40 -textvariable ${var}(str)
	pack $w.prompt -in $w.f1 -side left -padx 2
	pack $w.str -in $w.f1 -fill x -expand 1 -padx 2
	ttk::frame $w.f2
	ttk::label $w.opts -text "Search options:"
	ttk::checkbutton $w.case -text "Match case" -variable ${var}(case)
	ttk::checkbutton $w.regexp -text "Regular expression" \
	  -variable ${var}(regexp)
	ttk::checkbutton $w.wrap -text "Wrap around" -variable ${var}(wrap)
	pack $w.opts -in $w.f2 -side left -anchor n -padx 2
	pack $w.case $w.regexp $w.wrap -in $w.f2 -anchor w -fill x -padx 2
	ttk::frame $w.f3
	ttk::button $w.next -text Next -width 8 \
	  -command [list [namespace which my] Find forward]
	ttk::button $w.prev -text Previous -width 8 \
	  -command [list [namespace which my] Find reverse]
	ttk::button $w.done -text Cancel -width 8 \
	  -command [list [namespace which my] hide]
	grid x $w.next $w.prev $w.done -in $w.f3 -padx 4
	grid .nb.f1.t.search.next .nb.f1.t.search.done -sticky e
	grid .nb.f1.t.search.prev -sticky w
	grid columnconfigure $w.f3 {all 0} -weight 1 -uniform 1
	pack $w.f1 $w.f2 $w.f3 -side top -fill x -pady 4
	pack $w.f3 -pady {16 4}

	bind $txt <<Search>> [list $w show]
	bind $w.str <Return> [list $w.next invoke]

	my hide
    }

    method Find {dir} {
	my variable opt w txt history
	if {$opt(str) eq ""} return
	set args [list -count count]
	if {$dir ne "reverse"} {
	    set start found.last
	    set stop end
	} else {
	    lappend args -backwards
	    set start found.first
	    set stop 1.0
	}
	if {!$opt(case)} {lappend args -nocase}
	if {$opt(regexp)} {lappend args -regexp}
	if {[llength [$txt tag ranges found]] == 0} {set start insert}
	lappend args $opt(str) $start
	if {!$opt(wrap)} {lappend args $stop}
	set x [$txt search {*}$args]
	if {$x ne ""} {
	    $txt tag remove found 1.0 end
	    $txt tag add found $x "$x + $count chars"
	    $txt see $x
	}
	if {$opt(str) ni $history} {
	    set history [linsert $history 0 $opt(str)]
	    $w.str configure -values $history
	}
    }

    method show {} {
	my variable w txt
	::tk::PlaceWindow $w widget $txt
	wm deiconify $w
	raise $w
    }

    method hide {} {
	my variable w txt
	wm withdraw $w
	$txt tag remove found 1.0 end
    }
}
