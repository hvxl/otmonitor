set argv [list]

try {
    package require Tk
} trap {TK NO_DISPLAY} err {
    puts stderr [string toupper $err 0]
    puts stderr "To run otmonitor without its GUI, use the --daemon option."
    exit 1
} trap {TCL PACKAGE UNFOUND} err {
    puts stderr [string toupper $err 0]
    exit 1
}

# Stop the annoying auto-selection of comboboxes
bind TCombobox <<ComboboxSelected>> {%W selection clear}

include themes.tcl

namespace eval gui {
    variable tvsort {
	hex		ascii
	dec		integer
	direction	dictionary
	name		dictionary
	frequency	integer
	value		dictionary
    }
    variable widget {}

    namespace ensemble create -unknown ::gui::passthrough \
      -subcommands {output tvtrace connected scroll}
    

    # Create a namespace for images
    namespace eval img {}
}

proc gui::passthrough {cmd subcmd args} {return [list $subcmd]}

proc gui::img {fn {disabled 0}} {
    global imgdir
    set name ::gui::img::[file rootname $fn]
    set fmt [string range [file extension $fn] 1 end]
    if {$disabled && $fmt eq "png"} {
	lappend fmt -alpha 0.3
	append name _disabled
    }
    if {$name in [image names]} {return $name}
    set file [file join $imgdir $fn]
    return [image create photo $name -file $file -format $fmt]
}

proc gui::imglist {fn} {
    return [list [img $fn] disabled [img $fn 1]]
}

proc gui::start {} {
    global cfg
    upvar #0 cfg(connection,type) devtype

    themeinit

    ttk::style layout Indicator.TCheckbutton {
	Checkbutton.padding -sticky nswe -children {
	    Checkbutton.indicator -side right -sticky {}
	    Checkbutton.focus -side left -sticky w -children {
		Checkbutton.label -sticky nswe
	    }
	}
    }

    ttk::style configure West.TButton -anchor w

    wm iconphoto . -default [img icon48.gif] [img icon.gif]
    set font [font actual TkDefaultFont]
    set size [expr {round([dict get $font -size] * 0.8)}]
    font create Small {*}$font -size $size
    font create Bold {*}$font -weight bold
    font create Big {*}$font -size [expr {2 * $size}] -weight bold
    wm title . "Opentherm Monitor"
    place [ttk::label .bg] -relwidth 1 -relheight 1
    ttk::separator .sep

    ttk::frame .f1
    grid columnconfigure .f1 0 -weight 1
    ttk::frame .f2
    grid columnconfigure .f2 0 -weight 1
    ttk::frame .f3
    grid columnconfigure .f3 0 -weight 1
    ttk::separator .sep1 -orient vertical
    ttk::separator .sep2 -orient vertical
    ttk::checkbutton .v1 -class TLabel -style Indicator.TCheckbutton \
      -variable gui(dhwenable) -text "Domestic hot water enable "
    ttk::checkbutton .v2 -class TLabel -style Indicator.TCheckbutton \
      -variable gui(dhwmode) -text "Domestic hot water mode "
    ttk::checkbutton .v3 -class TLabel -style Indicator.TCheckbutton \
      -variable gui(fault) -text "Fault indication "
    ttk::checkbutton .v4 -class TLabel -style Indicator.TCheckbutton \
      -variable gui(flame) -text "Flame status "
    ttk::checkbutton .v5 -class TLabel -style Indicator.TCheckbutton \
      -variable gui(diag) -text "Diagnostic indication "
    ttk::checkbutton .v15 -class TLabel -style Indicator.TCheckbutton \
      -variable gui(chmode) -text "Central heating mode "
    ttk::checkbutton .v19 -class TLabel -style Indicator.TCheckbutton \
      -variable gui(chenable) -text "Central heating enable "
    ttk::label .l6 -text "Boiler water temperature"
    ttk::label .v6 -textvariable gui(boilertemp) -anchor e -width 6
    ttk::label .l7 -text "Control setpoint"
    ttk::label .v7 -textvariable gui(controlsp) -anchor e -width 6
    ttk::label .l8 -text "DHW setpoint"
    ttk::label .v8 -textvariable gui(dhwsetpoint) -anchor e -width 6
    ttk::label .l9 -text "Max CH water setpoint"
    ttk::label .v9 -textvariable gui(chwsetpoint) -anchor e -width 6
    ttk::label .l10 -text "Relative modulation level"
    ttk::label .v10 -textvariable gui(modulation) -anchor e -width 6
    ttk::label .l11 -text "Room temperature"
    ttk::label .v11 -textvariable gui(temperature) -anchor e -width 6
    ttk::label .l12 -text "Room setpoint"
    ttk::label .v12 -textvariable gui(setpoint) -anchor e -width 6
    ttk::label .l13 -text "Return water temperature"
    ttk::label .v13 -textvariable gui(returntemp) -anchor e -width 6
    ttk::label .l14 -text "Outside temperature"
    ttk::label .v14 -textvariable gui(outside) -anchor e -width 6
    ttk::label .l16 -text "CH water pressure"
    ttk::label .v16 -textvariable gui(pressure) -anchor e -width 6
    ttk::label .l17 -text "Max relative modulation level"
    ttk::label .v17 -textvariable gui(maxmod) -anchor e -width 6
    ttk::label .l18 -text "DHW temperature"
    ttk::label .v18 -textvariable gui(dhwtemp) -anchor e -width 6
    ttk::label .l20 -text "Remote override room setpoint"
    ttk::label .v20 -textvariable gui(override) -anchor e -width 6
    ttk::label .l21 -text "OEM fault code"
    ttk::label .v21 -textvariable gui(faultcode) -anchor e -width 6

    grid .v4 -in .f1 -sticky we -padx 2 -pady 1
    grid .v15 -in .f1 -sticky we -padx 2 -pady 1
    grid .v19 -in .f1 -sticky we -padx 2 -pady 1
    grid .v2 -in .f1 -sticky we -padx 2 -pady 1
    grid .v1 -in .f1 -sticky we -padx 2 -pady 1
    grid .v5 -in .f1 -sticky we -padx 2 -pady 1
    grid .v3 -in .f1 -sticky we -padx 2 -pady 1

    grid .l14 .v14 -in .f2 -sticky we -padx 2 -pady 1
    grid .l11 .v11 -in .f2 -sticky we -padx 2 -pady 1
    grid .l12 .v12 -in .f2 -sticky we -padx 2 -pady 1
    grid .l20 .v20 -in .f2 -sticky we -padx 2 -pady 1
    grid .l10 .v10 -in .f2 -sticky we -padx 2 -pady 1
    grid .l17 .v17 -in .f2 -sticky we -padx 2 -pady 1
    grid .l16 .v16 -in .f2 -sticky we -padx 2 -pady 1

    grid .l6 .v6 -in .f3 -sticky we -padx 2 -pady 1
    grid .l13 .v13 -in .f3 -sticky we -padx 2 -pady 1
    grid .l7 .v7 -in .f3 -sticky we -padx 2 -pady 1
    grid .l9 .v9 -in .f3 -sticky we -padx 2 -pady 1
    grid .l18 .v18 -in .f3 -sticky we -padx 2 -pady 1
    grid .l8 .v8 -in .f3 -sticky we -padx 2 -pady 1
    grid .l21 .v21 -in .f3 -sticky we -padx 2 -pady 1

    ttk::separator .sep3
    
    ttk::notebook .nb
    .nb add [set tab(graph) [graphframe .nb]] -text Graph -padding 4
    .nb add [set tab(stats) [statsframe .nb]] -text Statistics -padding 4
    .nb add [set tab(log) [logframe .nb]] -text Log -padding 4
    bind .nb <<NotebookTabChanged>> [namespace code selection]

    # Status bar
    ttk::separator .sep4
    ttk::frame .bar

    ttk::label .bar.stat -textvariable status -width 1
    ttk::separator .bar.sep1 -orient vertical
    ttk::label .bar.l1 -text "Error 01:" -width 0
    ttk::label .bar.v1 -textvariable error(1) -width 0 -anchor e
    ttk::separator .bar.sep2 -orient vertical
    ttk::label .bar.l2 -text "Error 02:" -width 0
    ttk::label .bar.v2 -textvariable error(2) -width 0 -anchor e
    ttk::separator .bar.sep3 -orient vertical
    ttk::label .bar.l3 -text "Error 03:" -width 0
    ttk::label .bar.v3 -textvariable error(3) -width 0 -anchor e
    ttk::separator .bar.sep4 -orient vertical
    ttk::label .bar.l4 -text "Error 04:" -width 0
    ttk::label .bar.v4 -textvariable error(4) -width 0 -anchor e
    ttk::separator .bar.sep5 -orient vertical
    ttk::label .bar.con \
      -image [list [img disconnect.png] selected [img connect.png]]
    grid {*}[winfo children .bar] -sticky ew -padx 2
    grid .bar.sep1 .bar.sep2 .bar.sep3 .bar.sep4 .bar.sep5 -sticky ns
    grid columnconfigure .bar .bar.stat -weight 1

    grid .sep -padx 2 -sticky ew -columnspan 5
    grid .f1 .sep1 .f2 .sep2 .f3 -sticky ns -pady 2 -padx 4
    grid .sep3 -padx 2 -sticky ew -columnspan 5
    grid .nb -columnspan 5 -sticky news -padx 8 -pady 8
    grid .sep4 -padx 2 -sticky ew -columnspan 5
    grid .bar -sticky ew -columnspan 5

    update idletasks
    if {[info exists tab($cfg(view,tab))]} {
	.nb select $tab($cfg(view,tab))
    }

    grid columnconfigure . {.sep1 .sep2} -weight 1
    grid rowconfigure . .nb -weight 1

    set state [lindex {normal disabled} [expr {$devtype eq "file"}]]

    . configure -menu [menu .m -relief flat]
    .m add cascade -label File -menu [menu .m.file -tearoff 0]
    .m.file add command -label "Firmware upgrade ..." -state $state \
      -command [namespace code upgradedlg]
    .m.file add separator
    .m.file add command -label "Diagnostics" -state $state \
      -command {package require diagnostics;diagnostics}
    .m.file add separator
    .m.file add command -label Quit -command [namespace code finish]
    .m add cascade -label Edit -menu [menu .m.edit -tearoff 0]
    .m.edit add command -label "Copy" -state disabled \
      -command {event generate .nb.f1.t <<Copy>>} \
      -accelerator [accelerator <<Copy>>]
    .m.edit add command -label "Select all" -state disabled \
      -command {event generate .nb.f1.t <<SelectAll>>} \
      -accelerator [accelerator <<SelectAll>>]
    .m add cascade -label Options -menu [menu .m.opts -tearoff 0] -state $state
    .m.opts add command -label "Thermostat" -accelerator F2 -state $state \
      -command [namespace code [list configdlg thermostat]]
    .m.opts add command -label "Heater" -accelerator F3 -state $state \
      -command [namespace code [list configdlg heater]]
    .m.opts add command -label "I/O pins" -accelerator F4 -state $state \
      -command [namespace code [list configdlg io]]
    .m.opts add command -label "Settings" -accelerator F5 -state $state \
      -command [namespace code [list configdlg settings]]
    .m.opts add command -label "Counters" -accelerator F6 -state $state \
      -command [namespace code [list configdlg counters]]
    .m.opts add command -label "Miscellaneous" -accelerator F7 -state $state \
      -command [namespace code [list configdlg misc]]
    .m.opts add separator
    .m.opts add command -label "Connection" -state $state \
      -command [namespace code [list configdlg connect]]
    .m.opts add separator
    .m.opts add command -label "Logging" -state $state \
      -command [namespace code [list configdlg logging]]
    .m.opts add command -label "Alerts" -state $state \
      -command [namespace code [list configdlg alerts]]
    .m.opts add separator
    .m.opts add command -label "Web server" -state $state \
      -command [namespace code [list configdlg wibble]]
    .m.opts add command -label "Remote access" -state $state \
      -command [namespace code [list configdlg remote]]
    .m.opts add command -label "MQTT" -state $state \
      -command [namespace code [list configdlg mqtt]]
    .m.opts add command -label "ThingSpeak" -state $state \
      -command [namespace code [list configdlg tspeak]]

    .m add cascade -label Help -menu [menu .m.help -tearoff 0]
    .m.help add command -label "About Opentherm Monitor" \
      -command [namespace code about]

    if {$state eq "normal"} {
	bind .bar.con <1> [namespace code connection]
	bind all <F2> [namespace code [list configdlg thermostat]]
	bind all <F3> [namespace code [list configdlg heater]]
	bind all <F4> [namespace code [list configdlg io]]
	bind all <F5> [namespace code [list configdlg settings]]
	bind all <F6> [namespace code [list configdlg counters]]
	bind all <F7> [namespace code [list configdlg misc]]
    }

    makegrid

    tk appname otmonitor

    wm protocol . WM_DELETE_WINDOW [namespace code finish]
}

proc gui::finish {} {
    configsave
    exit
}

proc gui::logframe {w} {
    ttk::frame $w.f1 -style TEntry -borderwidth 2 -takefocus 0
    set x 0
    lappend tabs [incr x [font measure TkDefaultFont "00:00:00.000000  "]] left
    lappend tabs [incr x [font measure TkDefaultFont "W00000000  "]] left
    lappend tabs [incr x [font measure TkDefaultFont "Unk-DataId  "]] left
    text $w.f1.t -yscrollcommand [list $w.f1.vs set] -background white \
      -relief flat -highlightthickness 0 -font TkDefaultFont -cursor "" \
      -wrap none -tabs $tabs -state disabled
    $w.f1.t mark set cursor 1.0
    $w.f1.t tag configure write -foreground #000080
    $w.f1.t tag configure unknown -foreground #800080
    $w.f1.t tag configure invalid -foreground #800000
    $w.f1.t tag configure error -foreground #FF0000
    ttk::scrollbar $w.f1.vs -command [list $w.f1.t yview]
    grid $w.f1.t $w.f1.vs -sticky wnse
    grid columnconfigure $w.f1 $w.f1.t -weight 1
    grid rowconfigure $w.f1 $w.f1.t -weight 1
    bind $w.f1.t <<Selection>> [namespace code selection]
    return $w.f1
}

proc gui::graphframe {w} {
    global graph
    ttk::frame $w.f2 -style TEntry -borderwidth 2 -takefocus 0
    canvas $w.f2.c -background white -borderwidth 0 -highlightthickness 0 \
      -yscrollcommand [list $w.f2.vs set] -xscrollcommand [list $w.f2.hs set]
    ttk::scrollbar $w.f2.vs -command [list $w.f2.c yview] -orient vertical
    ttk::scrollbar $w.f2.hs -command [list $w.f2.c xview] -orient horizontal
    label $w.f2.c.info -bd 1 -background #FFFFA0 -relief solid
    bindtags $w.f2.c.info [linsert [bindtags $w.f2.c.info] 1 1 $w.f2.c]
    grid $w.f2.c $w.f2.vs -sticky news
    grid $w.f2.hs x -sticky news
    grid columnconfigure $w.f2 $w.f2.c -weight 1
    grid rowconfigure $w.f2 $w.f2.c -weight 1
    dict for {name data} $graph {
	dict for {name dict} [dict get $data line] {
	    set tags [list $name graph]
	    set color [dict get $dict color]
	    if {[dict get $data type] eq "polygon"} {
    		$w.f2.c create polygon 0 -1 1 -1 -tags $tags \
    		  -fill $color -outline $color
	    } else {
		$w.f2.c create line 0 -1 0 -1 -tags $tags -fill $color
	    }
	}
    }
    bind $w.f2.c <1> [namespace code [list information $w.f2.c %x %y]]
    bind $w.f2.c <4> [list $w.f2.c yview scroll -1 unit]
    bind $w.f2.c <5> [list $w.f2.c yview scroll 1 unit]
    bind $w.f2.c <MouseWheel> \
      [format {%s yview scroll [expr {%%D/-abs(%%D)}] unit} $w.f2.c]
    return $w.f2
}

proc gui::statsframe {w} {
    global cfg
    ttk::frame $w.f3
    ttk::treeview $w.f3.tv -columns {hex dec direction name frequency value} \
      -show headings -yscrollcommand [list $w.f3.vs set]
    ttk::scrollbar $w.f3.vs -command [list $w.f3.tv yview]
    grid $w.f3.tv $w.f3.vs -sticky wnse
    grid columnconfigure $w.f3 $w.f3.tv -weight 1
    grid rowconfigure $w.f3 $w.f3.tv -weight 1

    $w.f3.tv column hex -width [sizeof .Hex.] -stretch 0
    $w.f3.tv column dec -width [sizeof 0000] -anchor e -stretch 0
    $w.f3.tv column direction -width [sizeof .Direction.] -stretch 0
    $w.f3.tv column name -width 300 -stretch 1
    $w.f3.tv column frequency -width [sizeof .Interval.] -anchor e -stretch 0
    $w.f3.tv column value -width [sizeof ".00000000  00000000."] \
      -anchor e -stretch 0

    $w.f3.tv heading hex -text Hex \
      -command [namespace code [list tvsort $w.f3.tv hex toggle]]
    $w.f3.tv heading dec -text Dec \
      -command [namespace code [list tvsort $w.f3.tv dec toggle]]
    $w.f3.tv heading direction -text Direction \
      -command [namespace code [list tvsort $w.f3.tv direction toggle]]
    $w.f3.tv heading name -text Description \
      -command [namespace code [list tvsort $w.f3.tv name toggle]]
    $w.f3.tv heading frequency -text Interval \
      -command [namespace code [list tvsort $w.f3.tv frequency toggle]]
    $w.f3.tv heading value -text Value \
      -command [namespace code [list tvsort $w.f3.tv value toggle]]

    tvsort $w.f3.tv $cfg(view,sort)

    bind $w.f3.tv <<TreeviewSelect>> [namespace code tvselect]
    return $w.f3
}

proc gui::output {str tag} {
    global logsize
    set tail [llength [.nb.f1.t bbox end-1c]]
    .nb.f1.t configure -state normal
    if {[.nb.f1.t compare cursor > 1.0]} {.nb.f1.t insert cursor \n}
    .nb.f1.t insert cursor "$str" $tag
    foreach t [.nb.f1.t tag names cursor] {.nb.f1.t tag remove $t cursor}
    foreach t $tag {.nb.f1.t tag add $t cursor}
    .nb.f1.t delete 1.0 "end-$logsize lines"
    .nb.f1.t configure -state disabled
    if {$tail} {.nb.f1.t yview end}
}

proc gui::tvsort {tv col {order keep}} {
    global cfg
    variable tvsort
    if {$col ne $cfg(view,sort)} {
	set cfg(view,order) increasing
    } elseif {$order eq "keep"} {
	# No change
    } elseif {$cfg(view,order) ne "increasing"} {
	set cfg(view,order) increasing
    } else {
	set cfg(view,order) decreasing
    }
    set list {}
    foreach n [$tv children {}] {
	lappend list [list $n [$tv set $n $col]]
    }
    if {![dict exists $tvsort $col]} {set col name}
    set sort {}
    foreach n [lsort -[dict get $tvsort $col] -$cfg(view,order) -index 1 $list] {
	lappend sort [lindex $n 0]
    }
    $tv children {} $sort
    set cfg(view,sort) $col
}

proc gui::tvselect {} {
    foreach n [lsearch -all -inline [.nb.f1.t tag names] id-*] {
	.nb.f1.t tag configure $n -background "" -foreground ""
    }
    foreach n [.nb.f3.tv selection] {
	scan $n id-%d,%d type id
	foreach t [lsearch -all -inline [.nb.f1.t tag names] id-*,$id] {
    	    .nb.f1.t tag configure $t -background cyan
	}
    }
}

proc gui::selfile {str} {
    set types {
	{"Text Files"		.txt}
	{"All Files"		*}
    }
    set dir [file dirname [file normalize $str]]
    set name [file tail $str]
    set file [tk_getSaveFile -defaultextension .txt -parent . \
      -initialdir $dir -initialfile $name -filetypes $types]
    return $file
}

proc gui::datafile {} {
    global cfg
    set file [selfile $cfg(datalog,file)]
    if {$file ne ""} {
	set cfg(datalog,file) $file
	cfgdatalog
    }
}

proc gui::datalayout {} {
    include datalog.tcl
    datalog gui .cfg
}

proc gui::cfgselectdir {} {
    global cfg
    set dir [tk_chooseDirectory -initialdir $cfg(logfile,directory) \
      -parent .cfg -title "Select the directory for log files"]
    if {$dir ne ""} {
	set cfg(logfile,directory) $dir
    }
}

proc gui::tvtrace {type msgid} {
    global message value start count cfg timestamp
    if {$type ni {1 4 6 7}} return
    set tv .nb.f3.tv
    set id id-$type,$msgid
    if {![$tv exists $id]} {
	$tv insert {} end -id $id -values [list [format %02X $msgid] $msgid]
	$tv set $id direction [dict get {4 Read 1 Write 6 Invalid 7 Unk} $type]
	if {[info exists message($msgid)]} {
    	    $tv set $id name [lindex $message($msgid) 0]
	} else {
	    $tv set $id name [format {Message ID %d} $msgid]
	}
	set resort 1
    } else {
	set resort [expr {$cfg(view,sort) in {frequency value}}]
    }
    set sec [expr {double($timestamp - $start)}]
    $tv set $id frequency [expr {round($sec / $count($type,$msgid))}]
    $tv set $id value $value($type,$msgid)
    if {$resort} {tvsort $tv $cfg(view,sort)}
}

proc gui::makegrid {} {
    global graph height span period
    .nb.f2.c delete grid
    set y 0
    set x [expr {$span / $period}]
    dict for {name data} $graph {
	incr y 8
	dict with data {
    	    set origin [expr {$y + $max * $zoom}]
	    for {set v $min} {$v <= $max} {incr v $scale} {
		set i [expr {$origin - $v * $zoom}]
		.nb.f2.c create line 0 $i $x $i -fill #eee -tags grid
		.nb.f2.c create text -4 $i -text $v -anchor e -tags grid \
		  -font Small -fill #000
	    }
	}
	incr y [expr {round(($max - $min) * $zoom)}]
    	dict set graph $name origin $origin
    }
    set height [incr y 16]
    .nb.f2.c lower grid
}

proc gui::scroll {} {
    global graph track period gui start height now zero span devtype timestamp
    set now $timestamp
    set zero [expr {max($now - $span, $start)}]
    dict for {name data} $graph {
	dict with data {
	    foreach n [dict keys $line] {
		if {[llength $track($n)] == 0} continue
    		set coords {}
    		set last [lindex $track($n) end]
		set values [linsert $track($n) end $now $last]
		foreach {time value} $values {
		    set x [expr {($time - $zero) / $period}]
		    set v [expr {$origin - $value * $zoom}]
		    if {$x < 0} {
			set coords [list 0 $v]
		    } else {
			lappend coords $x $v
		    }
		}
		if {$type eq "polygon"} {
		    lassign $coords x y
		    if {$y != $origin} {
			set coords [linsert $coords 0 $x $origin]
		    }
	    	    if {$value != 0} {
			set x [expr {($now - $zero) / $period}]
		    	lappend coords $x $origin
		    }
		}
		catch {.nb.f2.c coords $n $coords}
	    }
	}
    }
    set max [lindex [.nb.f2.c xview] 1]
    .nb.f2.c configure -scrollregion \
      [list -30 0 [expr {($now - $zero) / $period}] $height]
    if {$max > 0.999999} {
        .nb.f2.c xview moveto 1.0
    }
    timeline $now
    if {$devtype ne "file"} {
	set cmd [namespace code scroll]
	after cancel $cmd
	set ms [clock milliseconds]
	set wait [expr {($ms / 1000 / $period + 1) * $period * 1000 - $ms}]
	after $wait $cmd
    }
}

proc gui::timeline {now} {
    global period start height span
    set space [expr {$period * 60}]
    set zero [expr {max($now - $span, $start)}]
    set n [expr {$zero / $space * $space}]
    for {set i 1} {[incr n $space] <= $now} {incr i} {
        set x [expr {($n - $zero) / $period}]
        set time [clock format $n -format %H:%M]
        if {[.nb.f2.c type marker$i] ne ""} {
            .nb.f2.c coords marker$i $x 0 $x $height
        } else {
	    set tags [list marker$i grid]
	    .nb.f2.c create line $x 0 $x $height -tags $tags -fill #eee
            .nb.f2.c lower marker$i
        }
    }
    while {[.nb.f2.c type marker$i] ne ""} {
        .nb.f2.c delete marker$i
        incr i
    }

}

proc gui::nearest {w x y {delta 3}} {
    # Avoid getting false positives from the grid
    $w itemconfigure grid -state hidden
    # Check that there are items within a reasonable distance
    set x1 [expr {$x - $delta}]
    set x2 [expr {$x + $delta}]
    set y1 [expr {$y - $delta}]
    set y2 [expr {$y + $delta}]
    if {[llength [$w find overlapping $x1 $y1 $x2 $y2]] > 0} {
	# Now find the closest one
	set rc [$w find closest $x $y]
    } else {
	set rc ""
    }
    # Switch the grid back on
    $w itemconfigure grid -state normal
    return $rc
}

proc gui::information {w x y} {
    global track zero period infoid now graph
    focus $w
    $w delete info
    set cx [expr {int([$w canvasx $x])}]
    set cy [expr {int([$w canvasy $y])}]
    set id [nearest $w $cx $cy]
    if {![llength $id]} {return}
    set id [lindex $id 0]
    set object [lindex [$w gettags $id] 0]
    set time [expr {min($now, $zero + int($cx) * $period)}]
    set v "";foreach {n1 n2} $track($object) {
	if {$n1 > $time} {break}
	set v $n2
    }
    if {$v eq ""} return
    foreach n [dict values $graph] {
	if {[dict exists $n line $object name]} {
	    set fmt [dict get $n format]
	    if {$fmt eq "%s"} {set v [lindex {On Off} [expr {!$v}]]}
	    set v [format $fmt $v]
	    set name [dict get $n line $object name]
	    break
	}
    }
    $w.info configure \
      -text [format "%s @%s: %s" $name [clock format $time -format %T] $v]
    if {$y < [winfo height $w] - 40} {
        set anchor n
        incr cy 4
    } else {
        set anchor s
        incr cy -4
    }
    if {$x < 200} {
        append anchor w
    } else {
        append anchor e
    }
    $w create window $cx $cy -window $w.info -anchor $anchor -tags info
    catch {after cancel $infoid}
    set infoid [after 10000 $w delete info]
}

proc gui::setsetpoint {{cmd TC}} {
    global setpt gwversion value start
    if {![package vsatisfies $gwversion 4.0a6-]} {
	if {[info exists value(1,2)] && [info exists value(1,126)]} {
	    lassign $value(1,2) bits id
	    lassign $value(1,126) type version
	    if {$bits eq "00000000" && $id == 11 && $type == 20} {
		# Definitely a Celcia 20
		set cmd TR
	    }
	} elseif {[clock seconds] - 420 < $start} {
	    # Possibly a Celcia, issue the Celcia command just to be safe
	    sercmd TR=$setpt
	}
    }
    sercmd $cmd=$setpt
}

proc gui::setpoint {var value} {
    upvar #0 $var setpt
    set setpt [format %.2f $value]
}

proc gui::voltref {} {
    global voltref
    sercmd [format {VR=%d} $voltref]
}

proc gui::about {} {
    global version
    destroy .a
    toplevel .a
    wm title .a "About Opentherm Monitor"
    if {"About" ni [font names]} {
	font create About {*}[font actual TkDefaultFont] -size -40 -weight bold
    }
    ttk::frame .a.f -style About.TLabelframe
    ttk::style configure About.TLabelframe -background #efefef
    canvas .a.f.c -width 420 -height 140 -background #efefef -bd 0 \
      -highlightthickness 0
    .a.f.c create image 210 4 -image [img otmonitor.gif] -anchor n
    .a.f.c create text 211 110 -anchor center -fill #aaa -tag about
    .a.f.c create text 209 108 -anchor center -fill #808 -tag about
    .a.f.c itemconfigure about -text "Version $version" -font About
    pack .a.f.c -padx 10 -pady 10
    pack .a.f -side top -padx 10 -pady 10

    ttk::button .a.b -text Close -command {destroy .a} -width 8
    pack .a.b -side right -padx 10 -pady {0 10}
    ::tk::PlaceWindow .a widget .
    wm transient .a .
    wm resizable .a 0 0
}

proc gui::configdlg {{section thermostat}} {
    global cfgtitle

    destroy .cfg
    toplevel .cfg
    wm title .cfg "Configuration"
    place [ttk::frame .cfg.bg] -relheight 1 -relwidth 1
    frame .cfg.tf -background white
    grid columnconfigure .cfg.tf 0 -weight 1
    grid rowconfigure .cfg.tf {0 1 2 3 4 5 6 7 8 9 10 11 12} -uniform tabs
    place [ttk::frame .cfg.tfbg -style TEntry -takefocus 0] \
      -in .cfg.tf -x -2 -y -2 -height 4 -width 4 -relheight 1 -relwidth 1
    raise .cfg.tf

    frame .cfg.lfbg -bd 1 -relief solid
    ttk::frame .cfg.lf -width [expr {[sizeof 0] * 60}]
    pack .cfg.lf -in .cfg.lfbg -fill both -expand 1
    pack propagate .cfg.lf 0
    label .cfg.lf.t -textvariable cfgtitle -background #969696 -font Big \
      -borderwidth 1 -relief solid -anchor w -padx 8 -pady 3
    pack .cfg.lf.t -side top -fill x -padx 12 -pady {12 0}

    ttk::button .cfg.b1 -text Done -width 6 \
      -command [namespace code configdone]

    set cfgtitle ""
    variable widget {}

    set w(thermostat) [configtab "Thermostat" [img thermostat.png] cfgtemp]
    set w(heater) [configtab "Heater" [img heater.png] cfgheater]
    set w(io) [configtab "I/O pins" [img leds.png] cfgleds]
    set w(settings) [configtab "Settings" [img settings.png] cfgtweak]
    set w(counters) [configtab "Counters" [img counters.png] cfgcounters]
    set w(misc) [configtab "Miscellaneous" [img general.png] cfggeneral]
    set w(connect) [configtab "Connection" [img connection.png] cfgconnection]
    set w(logging) [configtab "Logging" [img logging.png] cfglogging]
    set w(alerts) [configtab "Alerts" [img alerts.png] cfgalerts]
    set w(wibble) [configtab "Web server" [img webserver.png] cfgwibble]
    set w(remote) [configtab "Remote access" [img remote.png] cfgremote]
    set w(mqtt) [configtab "MQTT" [img mqtt.png] cfgmqtt]
    set w(tspeak) [configtab "ThingSpeak" [img tspeak.png] cfgtspeak]

    if {[info exists w($section)]} {
	$w($section) invoke
    } else {
	$w(thermostat) invoke
    }

    grid .cfg.tf .cfg.lfbg -padx 8 -pady {8 4} -sticky nsew
    grid .cfg.b1 - -padx 8 -pady {4 8} -sticky e
    grid .cfg.tf -ipadx 2

    wm protocol .cfg WM_DELETE_WINDOW {.cfg.b1 invoke}

    ::tk::PlaceWindow .cfg widget .
    wm transient .cfg .
    wm resizable .cfg 0 0
}

proc gui::configtab {text img proc} {
    set w [format .cfg.tf.b%d [expr {[llength [winfo children .cfg.tf]] + 1}]]
    radiobutton $w -text $text -image $img -compound left -bd 0 \
      -background white -indicatoron 0 -width 120 -highlightthickness 0 \
      -anchor w -selectcolor #678DB2 -variable section -value $proc \
      -activebackground white \
      -command [namespace code [list configsel $w $text]]
    grid $w -sticky ew
    return $w
}

proc gui::configsel {w text} {
    global cfgtitle section
    if {$cfgtitle eq $text} return
    set cfgtitle $text
    foreach n [winfo children .cfg.tf] {
	$n configure -foreground black -activeforeground black
    }
    $w configure -foreground white -activeforeground white

    configwidget
    destroy [set f .cfg.lf.f]
    variable widget {}
    pack [ttk::frame $f] -fill both -expand 1 -padx 12 -pady {8 12}

    if {[catch {$section $f}]} {
	puts $::errorInfo
    }
}

proc gui::cfgtemp {w} {
    global gui setpt
    ttk::labelframe $w.f1 -text "Setpoint"
        grid $w.f1 -sticky ew -padx 6 -pady 4
    ttk::scale $w.f1.s -from 5 -to 30 \
      -variable setpt -command [namespace code {setpoint setpt}]
    ttk::spinbox $w.f1.e -state readonly -width 5 \
      -format %.2f -from 5 -to 30 -increment 0.1 -textvariable setpt
    ttk::frame $w.f1.f
    ttk::button $w.f1.f.b3 -text "Schedule" -width 0 \
      -command [namespace code {sercmd TT=0}]
    ttk::button $w.f1.f.b1 -text "Temporary" -width 0 \
      -command [namespace code {setsetpoint TT}]
    ttk::button $w.f1.f.b2 -text "Constant" -width 0 \
      -command [namespace code {setsetpoint TC}]
    grid $w.f1.f.b3 x $w.f1.f.b1 $w.f1.f.b2 -sticky ew -padx 6
    grid columnconfigure $w.f1.f all -uniform buttons
    grid columnconfigure $w.f1.f 1 -weight 1 -uniform {}
    grid $w.f1.s $w.f1.e -sticky ew -padx 6 -pady 6
    grid $w.f1.f - -sticky ew -padx 0 -pady 6
    grid columnconfigure $w.f1 $w.f1.s -weight 1
    pack $w.f1 -fill x -side top

    ttk::labelframe $w.f2 -text "Clock"
    ttk::label $w.f2.l1 -text "Current time:"
    ttk::label $w.f2.l2 -textvariable timestr
    ttk::separator $w.f2.sep
    ttk::checkbutton $w.f2.c1 -text "Send the current date to the gateway" \
      -variable cfg(clock,date) -onvalue true -offvalue false
    ttk::checkbutton $w.f2.c2 -text "Send the current year to the gateway" \
      -variable cfg(clock,year) -onvalue true -offvalue false
    ttk::checkbutton $w.f2.c3 -text "Automatically update the gateway clock" \
      -variable cfg(clock,auto) -onvalue true -offvalue false \
      -command [namespace code cfgclocksync]
    ttk::button $w.f2.b1 -text "Set Clock" -width 0 -command {sync 1}
    grid $w.f2.l1 $w.f2.l2 -sticky we -padx 6 -pady 0
    grid $w.f2.sep - -sticky we -padx 4 -pady 3
    grid $w.f2.c1 - -sticky we -padx 6 -pady {0 6}
    grid $w.f2.c2 - -sticky we -padx 6 -pady {0 6}
    grid $w.f2.c3 - -sticky we -padx 6 -pady {0 6}
    grid $w.f2.b1 - -padx 6 -pady {0 6}
    grid columnconfigure $w.f2 $w.f2.l2 -weight 1
    pack $w.f2 -fill x -side top -pady 8
    bind $w.f2.l1 <Destroy> [list after cancel [namespace code cfgtimestr]]
    
    cfgtimestr
    if {[info exists gui(setpoint)]} {
    	setpoint setpt [set setpt $gui(setpoint)]
    } else {
	setpoint setpt [set setpt 20]
    }
}

proc gui::cfgtimestr {} {
    global timestr
    set cmd [namespace code cfgtimestr]
    after cancel $cmd
    set timestr [clock format [clock seconds] -format "%A %d %B %Y, %H:%M"]
    after [expr {60000 - [clock milliseconds] % 60000}] $cmd
}

proc gui::cfgclocksync {} {
    global cfg
    after cancel sync
    if {$cfg(clock,auto)} {
	after [expr {60000 - [clock milliseconds] % 60000}] sync
    }
}

proc gui::cfgheater {w} {
    global chsetpoint dhwsetpoint
    ttk::labelframe $w.f1 -text "DHW setpoint"
    ttk::scale $w.f1.s -from 0 -to 9 -variable dhwsetpoint \
      -command [namespace code {setpoint dhwsetpoint}] -from 20 -to 80
    ttk::spinbox $w.f1.e -state readonly -textvariable dhwsetpoint -width 5 \
      -from 20 -to 80 -format %.2f
    ttk::button $w.f1.b -text Set -width 0 \
      -command [namespace code {sercmd SW=$dhwsetpoint}]
    grid $w.f1.s $w.f1.e $w.f1.b -sticky ew -padx 6 -pady 6
    grid columnconfigure $w.f1 $w.f1.s -weight 1
    pack $w.f1 -fill x -side top

    ttk::labelframe $w.f2 -text "Max CH setpoint"
    ttk::scale $w.f2.s -from 0 -to 9 -variable chsetpoint \
      -command [namespace code {setpoint chsetpoint}] -from 10 -to 90
    ttk::spinbox $w.f2.e -state readonly -textvariable chsetpoint -width 5 \
      -from 10 -to 90 -format %.2f
    ttk::button $w.f2.b -text Set -width 0 \
      -command [namespace code {sercmd SH=$chsetpoint}]
    grid $w.f2.s $w.f2.e $w.f2.b -sticky ew -padx 6 -pady 6
    grid columnconfigure $w.f2 $w.f2.s -weight 1
    pack $w.f2 -fill x -side top -pady 8

    ttk::labelframe $w.f3 -text "Comfort setting"
    ttk::radiobutton $w.f3.c1 -text "Comfort mode" \
      -variable comfort -value "1" -command {sercmd HW=1}
    ttk::radiobutton $w.f3.c2 -text "Economy mode" \
      -variable comfort -value "0" -command {sercmd HW=0}
    ttk::radiobutton $w.f3.c3 -text "Thermostat controlled" \
      -variable comfort -value "A" -command {sercmd HW=A}
    grid $w.f3.c1 -sticky ew -padx 6 -pady 2
    grid $w.f3.c2 -sticky ew -padx 6 -pady 2
    grid $w.f3.c3 -sticky ew -padx 6 -pady 2
    pack $w.f3 -fill x -side top

    foreach {n v} {
        4,56 dhwsetpoint 5,56 dhwsetpoint 4,57 chsetpoint 5,57 chsetpoint
    } {
        if {[info exists value($n)]} {set $v $value($n)}
    }
    setpoint dhwsetpoint $dhwsetpoint
    setpoint chsetpoint $chsetpoint

    learn HW
}

proc gui::cfggeneral {w} {
    ttk::labelframe $w.f1 -text "Operating mode"
    ttk::label $w.f1.l1 -textvariable gwmode
    ttk::button $w.f1.b1 -text "Gateway" -width 0 \
      -command [namespace code {sercmd GW=1}]
    ttk::button $w.f1.b2 -text "Monitor" -width 0 \
      -command [namespace code {sercmd GW=0}]
    grid $w.f1.l1 $w.f1.b1 $w.f1.b2 -sticky we -padx 6 -pady 6
    grid columnconfigure $w.f1 $w.f1.l1 -weight 1
    grid columnconfigure $w.f1 [list $w.f1.b1 $w.f1.b2] -uniform buttons
    pack $w.f1 -fill x -side top

    ttk::labelframe $w.f2 -text "Free format command"
    ttk::entry $w.f2.e -textvariable command
    ttk::button $w.f2.b -text Send -width 5 \
      -command [namespace code {sercmd $command}]
    bind $w.f2.e <Return> [list $w.f2.b invoke]
    grid $w.f2.e $w.f2.b -sticky ew -pady 6 -padx {6 2}
    grid $w.f2.b -padx {2 6}
    grid columnconfigure $w.f2 $w.f2.e -weight 1
    pack $w.f2 -fill x -side top -pady 8

    learn GW
}

proc gui::cfgconnection {w} {
    global cfg
    set values [comport enum]
    ttk::radiobutton $w.r1 -text "Serial port" -variable cfg(connection,type) \
      -value serial -command [namespace code [list cfgconnectedit $w.f1 $w.f2]]
    ttk::labelframe $w.f1 -labelwidget $w.r1
    ttk::label $w.f1.l -text "Serial device:"
    ttk::combobox $w.f1.e -values $values -width 20 \
      -textvariable cfg(connection,device) -validate key \
      -validatecommand [namespace code cfgconnectedit]
    grid $w.f1.l $w.f1.e -sticky w -padx 6 -pady {0 6}
    grid columnconfigure $w.f1 $w.f1.e -weight 1
    pack $w.f1 -fill x -side top

    ttk::radiobutton $w.r2 -text "TCP connection" -variable cfg(connection,type) \
      -value tcp -command [namespace code [list cfgconnectedit $w.f2 $w.f1]]
    ttk::labelframe $w.f2 -labelwidget $w.r2
    ttk::label $w.f2.l1 -text "Remote host:"
    ttk::entry $w.f2.e1 -textvariable cfg(connection,host) -validate key \
      -validatecommand [namespace code cfgconnectedit]
    ttk::label $w.f2.l2 -text "Remote port:"
    ttk::entry $w.f2.e2 -textvariable cfg(connection,port) -validate key \
      -validatecommand [namespace code cfgconnectedit]
    grid $w.f2.l1 $w.f2.e1 -sticky ew -padx 6
    grid $w.f2.l2 $w.f2.e2 -sticky w -padx 6 -pady 6
    grid columnconfigure $w.f2 $w.f2.e1 -weight 1
    pack $w.f2 -fill x -side top -pady 8

    pack [ttk::frame $w.f3] -fill x -side top

    ttk::button $w.f3.b -text Connect -width 10 -command {tryconnect .cfg}
    pack $w.f3.b -side right

    if {$cfg(connection,type) eq "serial"} {
	radio $w.f1 $w.f2
    } else {
	radio $w.f2 $w.f1
    }

    bind $w.f1.e <<ComboboxSelected>> [namespace code cfgconnectedit]
}

proc gui::cfgconnectedit {args} {
    # Stop autoconnecting
    connect configure
    if {[llength $args]} {radio {*}$args}
    # Allow use as validation command
    return 1
}

proc gui::cfgleds {w} {
    global gpio gpiofunc gpiostr led functions ledstr
    ttk::labelframe $w.f1 -text GPIO
    foreach l {A B} {
	set gpiostr($l) [dict get $gpiofunc $gpio($l)]
	ttk::label $w.f1.l$l -text "GPIO port $l:"
	ttk::combobox $w.f1.b$l -width 20 -state readonly \
	  -values [dict values $gpiofunc] -textvariable gpiostr($l)
	bind $w.f1.b$l <<ComboboxSelected>> \
	  [namespace code [list cfgselect %W G$l gpiofunc]]
	grid $w.f1.l$l $w.f1.b$l -padx 2 -pady 2
    }
    grid rowconfigure $w.f1 [lindex [grid size $w.f1] 1] -minsize 4
    pack $w.f1 -fill x -side top

    ttk::labelframe $w.f2 -text LEDs
    foreach l {A B C D E F} {
	set ledstr($l) [dict get $functions $led($l)]
	ttk::label $w.f2.l$l -text "LED $l:"
	ttk::combobox $w.f2.b$l -width 32 -state readonly \
	  -values [dict values $functions] -textvariable ledstr($l)
	bind $w.f2.b$l <<ComboboxSelected>> \
          [namespace code [list cfgselect %W L$l functions]]
	grid $w.f2.l$l $w.f2.b$l -padx 2 -pady 2
    }
    grid rowconfigure $w.f2 [lindex [grid size $w.f2] 1] -minsize 4
    pack $w.f2 -fill x -side top -pady 8

    set cmd [namespace code cfgledstrace]
    trace add variable led {write} $cmd
    bind $w.f1 <Destroy> +[list trace remove variable led {write} $cmd]
    trace add variable gpio {write} $cmd
    bind $w.f1 <Destroy> +[list trace remove variable gpio {write} $cmd]
    learn LA LB LC LD LE LF GA GB
}

proc gui::cfgledstrace {var arg op} {
    if {$var eq "led"} {
	global led ledstr functions
	set ledstr($arg) [dict get $functions $led($arg)]
    } elseif {$var eq "gpio"} {
	global gpio gpiostr gpiofunc
	set gpiostr($arg) [dict get $gpiofunc $gpio($arg)]
    }
}

proc gui::cfgselect {w cmd var} {
    upvar #0 $var config
    set key [lindex [dict keys $config] [$w current]]
    sercmd $cmd=$key
}

proc gui::cfgtweak {w} {
    global voltref gwversion
    ttk::checkbutton $w.b1 -text "Ignore multiple mid-bit transitions" \
      -variable midbit -command [namespace code {sercmd IT=$midbit}]
    pack $w.b1 -fill x -side top

    ttk::checkbutton $w.b2 \
      -text "Return the Remote Override Function flags in both data bytes" \
      -variable overridehb -command [namespace code {sercmd OH=$overridehb}]
    pack $w.b2 -fill x -side top

    if {![package vsatisfies $gwversion 4.0b0-]} {
	$w.b2 state disabled
    }

    ttk::labelframe $w.f1 -text "Reference voltage"
    ttk::scale $w.f1.s -from 0 -to 9 -variable voltref \
      -command {voltage voltref}
    ttk::entry $w.f1.e -state readonly -textvariable voltage -width 5
    ttk::button $w.f1.b -text Set -width 0 -command [namespace code voltref]
    grid $w.f1.s $w.f1.e $w.f1.b -sticky ew -padx 6 -pady 6
    grid columnconfigure $w.f1 $w.f1.s -weight 1
    pack $w.f1 -fill x -side top -pady 8

    ttk::labelframe $w.f2 -text "Setback temperature"
    ttk::scale $w.f2.s -from 5 -to 30 \
      -variable setback -command [namespace code {setpoint setback}]
    ttk::spinbox $w.f2.e -state readonly -width 5 \
      -format %.2f -from 5 -to 30 -increment 0.1 -textvariable setback
    ttk::button $w.f2.b1 -text "Set" -width 0 \
      -command [namespace code {sercmd SB=$setback}]
    grid $w.f2.s $w.f2.e $w.f2.b1 -sticky ew -padx 6 -pady 6
    grid columnconfigure $w.f2 $w.f2.s -weight 1
    pack $w.f2 -fill x -side top

    voltage voltref $voltref

    learn VR IT SB OH
}

proc gui::cfgcounters {w} {
    ttk::labelframe $w.f1 -text "Domestic Hot Water"
    ttk::label $w.f1.l1 -text "Domestic Hot Water Pump Starts"
    ttk::label $w.f1.v1 -textvariable gui(dhwps) -anchor e -width 6
    ttk::button $w.f1.b1 -text "Reset" -command [namespace code {sercmd RS=WPS}]
    ttk::label $w.f1.l2 -text "Domestic Hot Water Pump Hours"
    ttk::label $w.f1.v2 -textvariable gui(dhwph) -anchor e -width 6
    ttk::button $w.f1.b2 -text "Reset" -command [namespace code {sercmd RS=WPH}]
    ttk::label $w.f1.l3 -text "Domestic Hot Water Burner Starts"
    ttk::label $w.f1.v3 -textvariable gui(dhwbs) -anchor e -width 6
    ttk::button $w.f1.b3 -text "Reset" -command [namespace code {sercmd RS=WBS}]
    ttk::label $w.f1.l4 -text "Domestic Hot Water Burner Hours"
    ttk::label $w.f1.v4 -textvariable gui(dhwbh) -anchor e -width 6
    ttk::button $w.f1.b4 -text "Reset" -command [namespace code {sercmd RS=WBH}]
    grid $w.f1.l1 $w.f1.v1 $w.f1.b1 -padx 4 -pady 4 -sticky ew
    grid $w.f1.l2 $w.f1.v2 $w.f1.b2 -padx 4 -pady 4 -sticky ew
    grid $w.f1.l3 $w.f1.v3 $w.f1.b3 -padx 4 -pady 4 -sticky ew
    grid $w.f1.l4 $w.f1.v4 $w.f1.b4 -padx 4 -pady 4 -sticky ew
    grid columnconfigure $w.f1 $w.f1.v1 -weight 1
    pack $w.f1 -fill x -side top

    ttk::labelframe $w.f2 -text "Central Heating"
    ttk::label $w.f2.l1 -text "Central Heating Pump Starts"
    ttk::label $w.f2.v1 -textvariable gui(chps) -anchor e -width 6
    ttk::button $w.f2.b1 -text "Reset" -command [namespace code {sercmd RS=HPS}]
    ttk::label $w.f2.l2 -text "Central Heating Pump Hours"
    ttk::label $w.f2.v2 -textvariable gui(chph) -anchor e -width 6
    ttk::button $w.f2.b2 -text "Reset" -command [namespace code {sercmd RS=HPH}]
    ttk::label $w.f2.l3 -text "Central Heating Burner Starts"
    ttk::label $w.f2.v3 -textvariable gui(chbs) -anchor e -width 6
    ttk::button $w.f2.b3 -text "Reset" -command [namespace code {sercmd RS=HBS}]
    ttk::label $w.f2.l4 -text "Central Heating Burner Hours"
    ttk::label $w.f2.v4 -textvariable gui(chbh) -anchor e -width 6
    ttk::button $w.f2.b4 -text "Reset" -command [namespace code {sercmd RS=HBH}]
    grid $w.f2.l1 $w.f2.v1 $w.f2.b1 -padx 4 -pady 4 -sticky ew
    grid $w.f2.l2 $w.f2.v2 $w.f2.b2 -padx 4 -pady 4 -sticky ew
    grid $w.f2.l3 $w.f2.v3 $w.f2.b3 -padx 4 -pady 4 -sticky ew
    grid $w.f2.l4 $w.f2.v4 $w.f2.b4 -padx 4 -pady 4 -sticky ew
    grid columnconfigure $w.f2 $w.f2.v1 -weight 1
    pack $w.f2 -fill x -side top -pady 8
}

proc gui::cfgalerts {w} {
    global cfg
    ttk::notebook $w.nb

    set f [ttk::frame $w.nb.f1 -style Tab.TFrame]
    ttk::labelframe $f.f1 -style Tab.TLabelframe -text "Events"
    ttk::label $f.f1.l1 -style Tab.TLabel -text "Boiler fault"
    ttk::checkbutton $f.f1.c1a -style Tab.TCheckbutton -text "Email" \
      -variable cfg(email,boilerfault) -onvalue true -offvalue false
    ttk::checkbutton $f.f1.c1b -style Tab.TCheckbutton -text "SMS" \
      -variable cfg(sms,boilerfault) -onvalue true -offvalue false
    ttk::label $f.f1.l2 -style Tab.TLabel -text "Ventilation/heat-recovery fault"
    ttk::checkbutton $f.f1.c2a -style Tab.TCheckbutton -text "Email" \
      -variable cfg(email,ventilationfault) -onvalue true -offvalue false
    ttk::checkbutton $f.f1.c2b -style Tab.TCheckbutton -text "SMS" \
      -variable cfg(sms,ventilationfault) -onvalue true -offvalue false
    ttk::label $f.f1.l3 -style Tab.TLabel -text "Solar storage fault"
    ttk::checkbutton $f.f1.c3a -style Tab.TCheckbutton -text "Email" \
      -variable cfg(email,solarfault) -onvalue true -offvalue false
    ttk::checkbutton $f.f1.c3b -style Tab.TCheckbutton -text "SMS" \
      -variable cfg(sms,solarfault) -onvalue true -offvalue false
    ttk::label $f.f1.l4 -style Tab.TLabel -text "Gateway watchdog timer"
    ttk::checkbutton $f.f1.c4a -style Tab.TCheckbutton -text "Email" \
      -variable cfg(email,watchdogtimer) -onvalue true -offvalue false
    ttk::checkbutton $f.f1.c4b -style Tab.TCheckbutton -text "SMS" \
      -variable cfg(sms,watchdogtimer) -onvalue true -offvalue false
    ttk::label $f.f1.l5 -style Tab.TLabel -text "Communication problem"
    ttk::checkbutton $f.f1.c5a -style Tab.TCheckbutton -text "Email" \
      -variable cfg(email,commproblem) -onvalue true -offvalue false
    ttk::checkbutton $f.f1.c5b -style Tab.TCheckbutton -text "SMS" \
      -variable cfg(sms,commproblem) -onvalue true -offvalue false
    ttk::label $f.f1.l6 -style Tab.TLabel \
      -text "Room temperature below $cfg(alert,roomcold)\u00b0C"
    ttk::checkbutton $f.f1.c6a -style Tab.TCheckbutton -text "Email" \
      -variable cfg(email,roomcold) -onvalue true -offvalue false
    ttk::checkbutton $f.f1.c6b -style Tab.TCheckbutton -text "SMS" \
      -variable cfg(sms,roomcold) -onvalue true -offvalue false
    ttk::label $f.f1.l7 -style Tab.TLabel -text "CH water pressure low/high"
    ttk::checkbutton $f.f1.c7a -style Tab.TCheckbutton -text "Email" \
      -variable cfg(email,pressure) -onvalue true -offvalue false
    ttk::checkbutton $f.f1.c7b -style Tab.TCheckbutton -text "SMS" \
      -variable cfg(sms,pressure) -onvalue true -offvalue false

    grid $f.f1.l1 $f.f1.c1a $f.f1.c1b -sticky we -padx 4 -pady 2
    grid $f.f1.l2 $f.f1.c2a $f.f1.c2b -sticky we -padx 4 -pady 2
    grid $f.f1.l3 $f.f1.c3a $f.f1.c3b -sticky we -padx 4 -pady 2
    grid $f.f1.l4 $f.f1.c4a $f.f1.c4b -sticky we -padx 4 -pady 2
    # grid $f.f1.l5 $f.f1.c5a $f.f1.c5b -sticky we -padx 4 -pady 2
    grid $f.f1.l6 $f.f1.c6a $f.f1.c6b -sticky we -padx 4 -pady 2
    grid $f.f1.l7 $f.f1.c7a $f.f1.c7b -sticky we -padx 4 -pady 2
    grid columnconfigure $f.f1 $f.f1.l1 -weight 1
    pack $f.f1 -fill x -side top -pady 4 -padx 4
    $w.nb add $f -text Events

    set f [ttk::frame $w.nb.f2 -style Tab.TFrame]
    ttk::checkbutton $f.c1 -style Tab.TCheckbutton -text "Email" \
      -variable cfg(email,enable) -onvalue true -offvalue false
    ttk::labelframe $f.f1 -style Tab.TLabelframe -labelwidget $f.c1
    ttk::label $f.f1.l1 -style Tab.TLabel -text Sender:
    ttk::entry $f.f1.e1 -style Tab.TEntry -textvariable cfg(email,sender)
    ttk::label $f.f1.l2 -style Tab.TLabel -text Server:
    ttk::entry $f.f1.e2 -style Tab.TEntry -textvariable cfg(email,server)
    ttk::label $f.f1.l3 -style Tab.TLabel -text Port:
    ttk::entry $f.f1.e3 -style Tab.TEntry -textvariable cfg(email,port) -width 8
    ttk::label $f.f1.l4 -style Tab.TLabel -text User:
    ttk::entry $f.f1.e4 -style Tab.TEntry -textvariable cfg(email,user)
    ttk::label $f.f1.l5 -style Tab.TLabel -text Password:
    ttk::entry $f.f1.e5 -style Tab.TEntry -textvariable cfg(email,password) -show *
    ttk::label $f.f1.l6 -style Tab.TLabel -text Encryption:
    ttk::combobox $f.f1.e6 -textvariable cfg(email,secure) \
      -values {Plain TLS SSL} -width 5 -state readonly
    ttk::label $f.f1.l7 -style Tab.TLabel -text Recipients:
    ttk::frame $f.f1.e7 -style Tab.TEntry -borderwidth 2 -takefocus 0
    text $f.f1.e7.t -background white -relief flat -highlightthickness 0 \
      -wrap none -font TkDefaultFont
    pack $f.f1.e7.t -fill both -expand 1
    grid $f.f1.l1 $f.f1.e1 - - -sticky ew -padx 4 -pady 4
    grid $f.f1.l2 $f.f1.e2 $f.f1.l3 $f.f1.e3 -sticky ew -padx 4 -pady 4
    grid $f.f1.l4 $f.f1.e4 - - -sticky ew -padx 4 -pady 4
    grid $f.f1.l5 $f.f1.e5 $f.f1.e6 - -sticky ew -padx 4 -pady 4
    grid $f.f1.l7 $f.f1.e7 - - -sticky ew -padx 4 -pady 4
    grid $f.f1.e7 -rowspan 2 -sticky wens -pady {4 6}
    grid $f.f1.l3 -padx 0
    grid columnconfigure $f.f1 $f.f1.e2 -weight 1
    grid rowconfigure $f.f1 {0 1 2 3 4} -uniform entry
    grid rowconfigure $f.f1 5 -weight 1
    ttk::frame $f.f2 -style Tab.TFrame
    pack $f.f2 -fill x -side bottom -pady 4 -padx 4
    pack $f.f1 -fill both -side top -pady 4 -padx 4
    ttk::button $f.f2.b -style Tab.TButton -text Test -width 6 \
      -command [namespace code {configtest email}]
    pack $f.f2.b -side right
    bind $f.f1.e7 <FocusIn> {%W state focus}
    bind $f.f1.e7 <FocusOut> {%W state !focus}
    $w.nb add $f -text Email

    variable widget
    dict set widget maillist $f.f1.e7.t email,recipient
    $f.f1.e7.t insert end [join [split $cfg(email,recipient) ,] \n]

    set f [ttk::frame $w.nb.f3 -style Tab.TFrame]
    place [ttk::frame $f.bg -style Tab.TFrame] -relwidth 1 -relheight 1
    ttk::checkbutton $f.c1 -style Tab.TCheckbutton -text "Text message" \
      -variable cfg(sms,enable) -onvalue true -offvalue false
    ttk::labelframe $f.f1 -style Tab.TLabelframe -labelwidget $f.c1
    ttk::label $f.f1.l1 -style Tab.TLabel -text "Destination:"
    ttk::entry $f.f1.e1 -style Tab.TEntry -textvariable cfg(sms,phonenumber)
    ttk::label $f.f1.l2 -style Tab.TLabel -text Provider:
    ttk::combobox $f.f1.e2 -textvariable cfg(sms,provider) -width 12 \
      -values [lsort [dict keys [alert providers]]] -state readonly
    ttk::label $f.f1.l3 -style Tab.TLabel -text "Account:"
    ttk::entry $f.f1.e3 -style Tab.TEntry -textvariable cfg(sms,account)
    ttk::label $f.f1.l4 -style Tab.TLabel -text "Password:"
    ttk::entry $f.f1.e4 -style Tab.TEntry -textvariable cfg(sms,password) -show *
    ttk::label $f.f1.l5 -style Tab.TLabel -text "Sender:"
    ttk::entry $f.f1.e5 -style Tab.TEntry -textvariable cfg(sms,sender)
    ttk::label $f.f1.l6 -style Tab.TLabel -text Route:
    ttk::combobox $f.f1.e6 -textvariable routeid -width 16 -state readonly

    dict set widget routeid $f.f1.e6 sms,route
    
    grid $f.f1.l1 $f.f1.e1 -sticky ew -padx 4 -pady 4
    grid $f.f1.l2 $f.f1.e2 -sticky w -padx 4 -pady 4
    grid $f.f1.l3 $f.f1.e3 -sticky ew -padx 4 -pady 4
    grid $f.f1.l4 $f.f1.e4 -sticky w -padx 4 -pady 4
    grid $f.f1.l5 $f.f1.e5 -sticky ew -padx 4 -pady 4
    grid $f.f1.l6 $f.f1.e6 -sticky w -padx 4 -pady 4
    grid columnconfigure $f.f1 $f.f1.e1 -weight 1
    pack $f.f1 -fill x -side top -pady 4 -padx 4
    ttk::frame $f.f2 -style Tab.TFrame
    pack $f.f2 -fill x -side top -pady 4 -padx 4
    ttk::button $f.f2.b -style Tab.TButton -text Test -width 6 \
      -command [namespace code {configtest sms}]
    pack $f.f2.b -side right
    $w.nb add $f -text SMS
    # Make sure an existing provider is selected
    if {[$f.f1.e2 current] < 0} {$f.f1.e2 current 0}
    cfgprovider $f.f1.e2
    bind $f.f1.e2 <<ComboboxSelected>> [namespace code {cfgprovider %W}]

    pack $w.nb -fill both -expand 1 -side top
}

proc gui::cfgprovider {cb} {
    global cfg
    # Obtain the fields needed for the selected provider
    set dict [dict get [alert providers] [$cb get]]
    set fields [dict values [dict get $dict query]]
    # Configure the state of the sibling entry fields of the combobox
    foreach w [winfo children [winfo parent $cb]] {
	if {[winfo class $w] eq "TEntry"} {
	    set var [$w cget -textvariable]
	    if {[string match {cfg(sms,*)} $var]} {
		set prop [string range $var 8 end-1]
		if {$prop in $fields} {
		    set state !disabled
		} else {
		    set state disabled
		}
	    } else {
		continue
	    }
	} elseif {[winfo class $w] eq "TCombobox"} {
	    set var [$w cget -textvariable]
	    if {$var eq "routeid"} {
		if {[dict exists $dict routes]} {
		    set values [dict values [dict get $dict routes]]
		    $w configure -values $values
		    if {[dict exists $dict routes $cfg(sms,route)]} {
			set val [dict get $dict routes $cfg(sms,route)]
		    } elseif {[dict exists $dict defaultroute]} {
			set rt [dict get $dict defaultroute]
			set val [dict get $dict routes $rt]
		    } else {
			set val [lindex $values 0]
		    }
		    $w set $val
		    set state !disabled
		} else {
		    set state disabled
		}
	    } else {
		continue
	    }
	} else {
	    continue
	}
	# Find the matching label
	regsub {\.e(\d+)$} $w {.l\1} l
	# Set the state on both widgets
	$w state $state
	$l state $state
    }
}

proc gui::cfgwibble {w} {
    global cfg wibblesock theme docpath webstatus
    webstatus
    set values ""
    foreach dir $docpath {
	foreach n [glob -nocomplain -dir $dir -tails theme-*.css] {
	    lappend values [string range $n 6 end-4]
	}
    }
    set values [lsort -dictionary $values]

    ttk::labelframe $w.f1 -text "Settings"
    ttk::label $w.f1.l1 -text "Server port:"
    ttk::entry $w.f1.e1 -textvariable cfg(web,port) -width 8
    ttk::label $w.f1.l3 -text "Secure port:"
    ttk::entry $w.f1.e3 -textvariable cfg(web,sslport) -width 8
    ttk::label $w.f1.l2 -text "Web theme:"
    ttk::combobox $w.f1.e2 -state readonly -values $values -width 16
    ttk::checkbutton $w.f1.c4 -text "Passwordless access on standard port" \
      -variable cfg(web,nopass) -onvalue true -offvalue false
    ttk::checkbutton $w.f1.c5 -text "Require client certificate on secure port" \
      -variable cfg(web,certonly) -onvalue true -offvalue false

    grid $w.f1.l1 $w.f1.e1 $w.f1.l3 $w.f1.e3 -sticky w -padx 6 -pady 3
    grid $w.f1.l3 $w.f1.e3 -sticky w -padx 6 -pady 3
    grid $w.f1.l2 $w.f1.e2 - - -sticky w -padx 6 -pady 3
    grid $w.f1.c4 - - - -sticky we -padx 6 -pady 3 
    grid $w.f1.c5 - - - -sticky we -padx 6 -pady {3 6}
    grid columnconfigure $w.f1 [list $w.f1.e1 $w.f1.e3] -weight 1
    pack $w.f1 -fill x -side top

    ttk::labelframe $w.f2 -text "Control"
    ttk::label $w.f2.l1 -text "Status:"
    ttk::label $w.f2.l2 -textvariable webstatus
    ttk::button $w.f2.b1 -text "Start" -width 8 -command {wibblecmd start}
    ttk::button $w.f2.b2 -text "Stop" -width 8 -command {wibblecmd stop}
    grid $w.f2.l1 $w.f2.l2 $w.f2.b1 $w.f2.b2 -sticky ew -pady 6 -padx 6
    grid columnconfigure $w.f2 $w.f2.l2 -weight 1
    pack $w.f2 -fill x -side top -pady 8

    ttk::labelframe $w.f3 -text "Security"
    ttk::button $w.f3.b1 -text "Passwords ..." -width 0 \
      -command [namespace code [list fork passwd.tcl]]
    ttk::button $w.f3.b2 -text "Certificates ..." -width 0 \
      -command [namespace code [list fork sslwiz.tcl]]
    grid anchor $w.f3 center
    grid x $w.f3.b1 x $w.f3.b2 x -pady {2 6} -sticky ew
    grid columnconfigure $w.f3 {0 2 4} -uniform space -weight 1
    grid columnconfigure $w.f3 [list $w.f3.b1 $w.f3.b2] \
      -uniform buttons -weight 0
    pack $w.f3 -fill x -side top -pady 0

    $w.f1.e2 set $cfg(web,theme)

    bind $w.f1.e2 <<ComboboxSelected>> {
	apply {
	    w {
		global cfg theme
		set cfg(web,theme) [$w get]
		set theme theme-$cfg(web,theme)
	    }
	} %W
    }

    cfgwibbletrc $w.f2
    set cmd [namespace code [list cfgwibbletrc $w.f2]]
    trace add variable webstatus write $cmd
    bind $w.f2 <Destroy> [list trace remove variable webstatus write $cmd]

    if {!$security::available} {
	$w.f3.b1 state disabled
	$w.f3.b2 state disabled
    }
}

proc gui::cfgwibbletrc {w args} {
    global webstatus
    if {$webstatus ne "Stopped"} {
	$w.b1 state disabled
	$w.b2 state !disabled
    } else {
	$w.b1 state !disabled
	$w.b2 state disabled
    }	
}

proc gui::cfgremote {w} {
    global clients
    ttk::checkbutton $w.c1 -text "Enable relay server" \
      -variable cfg(server,enable) -onvalue true -offvalue false \
      -command [namespace code relaytoggle]
    ttk::labelframe $w.f1 -labelwidget $w.c1
    ttk::label $w.f1.l1 -text "Server port:"
    ttk::entry $w.f1.e1 -textvariable cfg(server,port) -width 8
    ttk::checkbutton $w.f1.c2 -variable cfg(server,relay) \
      -text "Relay opentherm messages" -onvalue true -offvalue false
    grid $w.f1.l1 $w.f1.e1 -sticky w -padx 6 -pady 3
    grid $w.f1.c2 - -sticky w -padx 6 -pady 3
    grid columnconfigure $w.f1 $w.f1.e1 -weight 1

    pack $w.f1 -fill x -side top

    ttk::labelframe $w.f2 -text Connections
    ttk::frame $w.f2.f -style TEntry -borderwidth 2
    listbox $w.f2.f.lb -height 6 -background white \
      -relief flat -highlightthickness 0
    ttk::scrollbar $w.f2.f.sb
    pack $w.f2.f.sb -side right -fill y
    pack $w.f2.f.lb -fill both
    ttk::button $w.f2.b -text Terminate -width 10 -state disabled \
      -command [namespace code [list cfgremotekill $w.f2.f.lb]]
    grid $w.f2.f $w.f2.b -padx 6 -pady 3 -sticky wes
    grid columnconfigure $w.f2 $w.f2.f -weight 1

    pack $w.f2 -fill x -side top -pady 8

    bind $w.f2.f.lb <<ListboxSelect>> \
      [namespace code [list cfgremotesel %W $w.f2.b]]
    set cmd [namespace code [list cfgremotetrc $w.f2.f.lb]]
    trace add variable clients write $cmd
    bind $w.f2.f.lb <Destroy> [list trace remove variable clients write $cmd]

    if {[info exists clients]} {cfgremotetrc $w.f2.f.lb}
}

proc gui::relaytoggle {} {
    set msg [relayserver]
    if {$msg ne ""} {
	tk_messageBox -icon error -message [string toupper $msg 0 0] \
	  -parent .cfg -title "Relay server error" -type ok
    }
}

proc gui::cfgremotetrc {w args} {
    global clients
    set sel [lmap n [$w curselection] {$w get $n}]
    $w delete 0 end
    foreach n [dict keys $clients] {
	$w insert end $n
	if {$n in $sel} {$w selection set end}
    }
    event generate $w <<ListboxSelect>>
}

proc gui::cfgremotesel {w b} {
    if {[llength [$w curselection]]} {
	$b state !disabled
    } else {
	$b state disabled
    }
}

proc gui::cfgremotekill {w} {
    global clients
    foreach n [lreverse [$w curselection]] {
	set fd [dict get $clients [$w get $n]]
	catch {server-$fd terminate}
    }
}

proc gui::cfglogging {w} {
    global cfg trc
    ttk::checkbutton $w.c1 -text "Include details of bit fields" \
      -variable cfg(view,bitflags) -onvalue true -offvalue false
    pack $w.c1 -fill x -side top

    ttk::checkbutton $w.c2 -text "Logfile" \
      -variable cfg(logfile,enable) -onvalue true -offvalue false
    ttk::labelframe $w.f1 -labelwidget $w.c2
    ttk::label $w.f1.l1 -text "Directory:"
    ttk::entry $w.f1.e1 -textvariable cfg(logfile,directory)
    ttk::button $w.f1.b1 -text "..." -width 0 \
      -command [namespace code cfgselectdir]
    ttk::label $w.f1.l2 -text "Name pattern:"
    ttk::entry $w.f1.e2 -textvariable cfg(logfile,pattern)
    grid $w.f1.l1 $w.f1.e1 $w.f1.b1 -sticky we -padx 6 -pady 3
    grid $w.f1.l2 $w.f1.e2 -sticky we -padx 6 -pady 3
    grid columnconfigure $w.f1 $w.f1.e1 -weight 1
    
    pack $w.f1 -fill x -side top

    ttk::checkbutton $w.c3 -text "Datafile" \
      -variable cfg(datalog,enable) -onvalue true -offvalue false \
      -command [namespace code cfgdatalog]
    ttk::labelframe $w.f2 -labelwidget $w.c3
    ttk::label $w.f2.l1 -text "File name:"
    ttk::entry $w.f2.e1 -textvariable cfg(datalog,file)
    ttk::button $w.f2.b1 -text "..." -width 0 \
      -command [namespace code datafile]
    ttk::label $w.f2.l2 -text "Interval:"
    ttk::spinbox $w.f2.e2 -textvariable trc(datalog,interval) \
      -from 1 -to 86400 -increment 1 -width 8 -validate all \
      -validatecommand [namespace code [list loginterval %W %P]]
    ttk::frame $w.f2.f
    ttk::checkbutton $w.f2.c1 -text "Append data to file" \
      -variable cfg(datalog,append) -onvalue true -offvalue false
    ttk::button $w.f2.b2 -text "Configure" -command [namespace code datalayout]
    grid $w.f2.l1 $w.f2.e1 $w.f2.b1 -sticky ew -pady 3 -padx 6
    grid $w.f2.l2 $w.f2.e2 - -sticky w -pady 3 -padx 6
    grid $w.f2.f - - -sticky ew -pady 3 -padx 4
    grid columnconfigure $w.f2 $w.f2.e1 -weight 1
    grid $w.f2.c1 $w.f2.b2 -in $w.f2.f -sticky ew -padx 2    
    grid columnconfigure $w.f2.f $w.f2.c1 -weight 1
    pack $w.f2 -fill x -side top -pady 8

    $w.f2.e2 set [expr {round($cfg(datalog,interval) / 1000.)}]

    set cmd [namespace code [list cfgintervaltrc]]
    trace add variable trc(datalog,interval) write $cmd
    bind $w.f2.e2 <Destroy> \
      [list trace remove variable trc(datalog,interval) write $cmd]
}

proc gui::cfgdatalog {} {
    global cfg
    if {$cfg(datalog,enable)} dump
}

proc gui::loginterval {w val} {
    if {![string is integer $val]} {return 0}
    set min [$w cget -from]
    set max [$w cget -to]
    return [expr {$val >= $min && $val <= $max}]
}

proc gui::cfgintervaltrc {varname sub op} {
    upvar 1 $varname var
    global cfg
    set cfg($sub) [expr {$var($sub) * 1000}]
}

proc gui::cfgmqtt {w} {
    global cfg
    ttk::checkbutton $w.c1 -text "Enable MQTT" -command mqttserver \
      -variable cfg(mqtt,enable) -onvalue true -offvalue false
    ttk::labelframe $w.f1 -labelwidget $w.c1
    ttk::label $w.f1.l1 -text "Broker Address:"
    ttk::entry $w.f1.e1 -textvariable cfg(mqtt,broker)
    ttk::label $w.f1.l2 -text "Broker Port:"
    ttk::entry $w.f1.e2 -textvariable cfg(mqtt,port) -width 8
    ttk::label $w.f1.l3 -text "Client Identifier:"
    ttk::entry $w.f1.e3 -textvariable cfg(mqtt,client)
    ttk::label $w.f1.l4 -text "User Name:"
    ttk::entry $w.f1.e4 -textvariable cfg(mqtt,username)
    ttk::label $w.f1.l5 -text "Password:"
    ttk::entry $w.f1.e5 -textvariable cfg(mqtt,password) -show *
    ttk::label $w.f1.l6 -text "Event topic prefix:"
    ttk::entry $w.f1.e6 -textvariable cfg(mqtt,eventtopic)
    ttk::label $w.f1.l7 -text "Action topic prefix:"
    ttk::entry $w.f1.e7 -textvariable cfg(mqtt,actiontopic)
    ttk::label $w.f1.l11 -text "Data Format:"
    set valdict {
	json1 "Simple JSON"
	json2 "Standard JSON"
	json3 "Extended JSON"
	raw "Unformatted"
    }
    ttk::combobox $w.f1.e11 -state readonly -width 15 \
      -values [dict values $valdict]
    set func {{w list} {set ::cfg(mqtt,format) [lindex $list [$w current]]}}
    bind $w.f1.e11 <<ComboboxSelected>> \
      [list apply $func %W [dict keys $valdict]]
    if {[dict exists $valdict $cfg(mqtt,format)]} {
	$w.f1.e11 set [dict get $valdict $cfg(mqtt,format)]
    } else {
	$w.f1.e11 current 0
    }
    ttk::checkbutton $w.f1.c11 -text "All Messages" \
      -variable cfg(mqtt,messages) -onvalue true -offvalue false
    ttk::label $w.f1.l10 -text "Quality of Service:"
    ttk::combobox $w.f1.e10 -state readonly \
      -values {{Fire and forget} {Acknowledged delivery} {Assured delivery}}
    bind $w.f1.e10 <<ComboboxSelected>> {set cfg(mqtt,qos) [%W current]}
    $w.f1.e10 current $cfg(mqtt,qos)
    ttk::label $w.f1.l8 -text "Keep-alive Interval:"
    ttk::spinbox $w.f1.e8 -to 65536 -textvariable cfg(mqtt,keepalive) -width 8
    ttk::label $w.f1.l9 -text "Retransmit Time:"
    ttk::spinbox $w.f1.e9 -to 65536 -textvariable cfg(mqtt,retransmit) -width 8

    grid $w.f1.l1 $w.f1.e1 - -sticky we -padx 6 -pady 3
    grid $w.f1.l2 $w.f1.e2 - -sticky we -padx 6 -pady 3
    grid $w.f1.l3 $w.f1.e3 - -sticky we -padx 6 -pady 3
    grid $w.f1.l4 $w.f1.e4 - -sticky we -padx 6 -pady 3
    grid $w.f1.l5 $w.f1.e5 - -sticky we -padx 6 -pady 3
    grid $w.f1.l6 $w.f1.e6 - -sticky we -padx 6 -pady 3
    grid $w.f1.l7 $w.f1.e7 - -sticky we -padx 6 -pady 3
    grid $w.f1.l11 $w.f1.e11 $w.f1.c11 -sticky we -padx 6 -pady 3
    grid $w.f1.l10 $w.f1.e10 - -sticky we -padx 6 -pady 3
    grid $w.f1.l8 $w.f1.e8 - -sticky we -padx 6 -pady 3
    grid $w.f1.l9 $w.f1.e9 - -sticky we -padx 6 -pady 3
    grid $w.f1.e2 $w.f1.e8 $w.f1.e9 $w.f1.e10 $w.f1.e11 -sticky w
    grid columnconfigure $w.f1 $w.f1.e11 -weight 1
    
    pack $w.f1 -fill x -side top
}

proc gui::cfgtspeak {w} {
    global cfg xlate
    namespace eval ::tspeak {}
    set dict [dict merge [dict create "" Unused] $xlate]
    ttk::checkbutton $w.c1 -text "Enable ThingSpeak" -command tspeakserver \
      -variable cfg(tspeak,enable) -onvalue true -offvalue false
    ttk::labelframe $w.f1 -labelwidget $w.c1
    ttk::label $w.f1.l0 -text "Write key:"
    ttk::entry $w.f1.e0 -textvariable cfg(tspeak,key) -width 20
    grid $w.f1.l0 $w.f1.e0 - -sticky w -padx 6 -pady 3
    ttk::label $w.f1.l20 -text "Interval:"
    ttk::spinbox $w.f1.e20 -textvariable cfg(tspeak,interval) \
      -from 15 -to 86400 -increment 1 -width 8 -validate all \
      -validatecommand [namespace code [list loginterval %W %P]]
    ttk::checkbutton $w.f1.c20 -text Synchronized \
      -variable cfg(tspeak,sync) -onvalue true -offvalue false
    grid $w.f1.l20 $w.f1.e20 $w.f1.c20 -sticky w -padx 6 -pady 3
    ttk::separator $w.f1.sep1
    ttk::label $w.f1.sepl1 -text Fields
    grid $w.f1.sep1 $w.f1.sepl1 -column 0 -columnspan 3 -padx 6 -pady 3
    grid $w.f1.sep1 -sticky ew
    for {set i 1} {$i <= 8} {incr i} {
	ttk::label $w.f1.l$i -text "Field $i:"
	ttk::combobox $w.f1.e$i -state readonly -width 28 \
	  -values [dict values $dict]
	$w.f1.e$i set [dict get $dict $cfg(tspeak,field$i)]
	grid $w.f1.l$i $w.f1.e$i - -sticky w -padx 6 -pady 3
	bind $w.f1.e$i <<ComboboxSelected>> \
	  [namespace code [list cfgtspeakselect %W field$i]]
    }
    ttk::separator $w.f1.sep2
    ttk::label $w.f1.sepl2 -text Status
    grid $w.f1.sep2 $w.f1.sepl2 -column 0 -columnspan 3 -padx 6 -pady 3
    grid $w.f1.sep2 -sticky ew
    ttk::label $w.f1.l99 -textvariable tspeak::status -width 1
    grid $w.f1.l99 - - -sticky we -padx 6 -pady 3

    grid columnconfigure $w.f1 $w.f1.c20 -weight 1
    
    pack $w.f1 -fill x -side top    
}

proc gui::cfgtspeakselect {w fld} {
    global cfg xlate
    set cfg(tspeak,$fld) [lindex [dict keys $xlate] [expr {[$w current] - 1}]]
}

proc gui::configwidget {} {
    global cfg
    variable widget
    # Save data from widgets that don't have a textvariable
    dict for {type dict} $widget {
	switch -- $type {
	    maillist {
		dict for {w key} $dict {
		    set rec {}
		    foreach n [split [$w get 1.0 end] ,\n] {
			set line [string trim $n]
			if {$line ne ""} {lappend rec $line}
		    }
		    set cfg($key) [join $rec ,]
		}
	    }
	    routeid {
		set info [dict get [alert providers] $cfg(sms,provider)]
		if {[dict exists $info routes]} {
		    set routes [dict keys [dict get $info routes]]
		    dict for {w key} $dict {
			set cfg($key) [lindex $routes [$w current]]
		    }
		}
	    }
	}
    }
}

proc gui::configdone {} {
    # Save data from widgets that don't have a textvariable
    configwidget
    destroy .cfg
    configsave
}

proc gui::configtest {type} {
    configwidget
    coroutine $type alert test $type .cfg
}

proc gui::radio {active args} {
    tree !disabled $active
    tree disabled {*}$args
}

proc gui::tree {state args} {
    foreach w $args {
	if {[winfo class $w] in {ComboboxPopdown}} continue
	if {[catch {$w state $state} err]} {
	    puts "$w: $err"
	}
	tree $state {*}[winfo children $w]
    }
}

proc gui::connected {state} {
    .bar.con state [lindex {selected !selected} [expr {!$state}]]
}

proc gui::connection {} {
    if {[.bar.con instate selected]} {
	connect disconnect
    } else {
	tryconnect
    }
}

proc gui::upgradedlg {} {
    global hexfile eeprom
    destroy .fw
    toplevel .fw
    wm title .fw "Firmware upgrade"
    wm transient .fw .
    place [ttk::frame .fw.bg] -relheight 1 -relwidth 1
    ttk::label .fw.l3a -text "Firmware file:"
    ttk::entry .fw.fn3 -textvariable hexfile
    ttk::button .fw.b3 -text ... -width 0 -command [namespace code hexfile]
    ttk::label .fw.l1a -text "Code memory:"
    ttk::progressbar .fw.pb1 -length 400 -maximum 4096 -variable csize
    ttk::label .fw.l1b -width 5 -anchor e
    ttk::label .fw.l2a -text "Data memory:"
    ttk::progressbar .fw.pb2 -length 400 -maximum 256 -variable dsize
    ttk::label .fw.l2b -width 5 -anchor e
    ttk::label .fw.l5a -text "Progress:"
    ttk::progressbar .fw.pb5 -length 400 -variable cocmd
    ttk::label .fw.l5b -width 5 -anchor e -textvariable copct
    ttk::checkbutton .fw.cb1 -variable restore -state disabled \
      -text "Transfer old EEPROM settings to the new firmware"
    ttk::button .fw.bb1 -image [img view.png] \
      -command [namespace code showsettings]
    ttk::label .fw.l6a -text "Status:"
    ttk::label .fw.l6b -width 1 -textvariable fwstatus
    ttk::separator .fw.sep
    ttk::frame .fw.f4
    ttk::button .fw.f4.b1 -text "Program" -width 8 -state disabled \
      -command [namespace code [list loadhex start]]
    ttk::button .fw.f4.b2 -text "Done" -width 8 -command {destroy .fw}
    grid .fw.f4.b1 .fw.f4.b2 -padx 20 -pady 4
    grid .fw.l3a .fw.fn3 .fw.b3 -padx 2 -pady 2 -sticky ew
    grid x .fw.cb1 .fw.bb1 -padx 2 -pady 2 -sticky ew
    grid .fw.l1a .fw.pb1 .fw.l1b -padx 2 -pady 2 -sticky ew
    grid .fw.l2a .fw.pb2 .fw.l2b -padx 2 -pady 2 -sticky ew
    grid .fw.l5a .fw.pb5 .fw.l5b -padx 2 -pady 2 -sticky ew
    grid .fw.f4 - - -padx 2 -pady 5
    grid .fw.bb1 -column 2 -row 5
    grid .fw.sep - - -padx 2 -sticky ew
    grid .fw.l6b - - -padx 2 -pady 0 -sticky ew
    ::tk::PlaceWindow .fw widget .
    fwstatus "Please select a firmware file"
    catch {readhex $hexfile}
    bind .fw.fn3 <Return> [namespace code {catch {readhex $hexfile}}]
    grab .fw
    if {![info exists eeprom]} {grid remove .fw.bb1}
}

proc gui::showsettings {} {
    include eeprom.tcl
    eeprom gui .fw
}

proc gui::hexfile {} {
    global hexfile
    set dir [file dirname [append hexfile ""]]
    set name [file tail $hexfile]
    set types {
        {"Firmware files"       .hex}
        {"All files"            *}
    }
    set name [tk_getOpenFile -filetypes $types -defaultextension .hex \
      -initialdir $dir -initialfile $name -parent .fw \
      -title "Choose firmware file"]
    if {$name ne ""} {
        set hexfile $name
        readhex $hexfile
    }
}

proc gui::readhex {file} {
    global csize dsize devtype restore
    .fw.l1b configure -text ""
    .fw.l2b configure -text ""
    .fw.f4.b1 state disabled
    lassign [upgrade readhex $file] rc arg
    if {$rc eq "failed"} {
	fwstatus $arg
    } else {
	.fw.l1b configure -text [format %d%% [expr {100 * $csize / 4096}]]
	.fw.l2b configure -text [format %d%% [expr {100 * $dsize / 256}]]
	if {$devtype ne "none"} {
	    .fw.f4.b1 state !disabled
	    fwstatus "Click 'Program' to download the firmware"
	}
	if {$arg} {
	    .fw.cb1 state !disabled
	} else {
	    .fw.cb1 state disabled
	}
    }
}

namespace eval gui::loadhex {
    namespace ensemble create -subcommands {
	start status check init manual progress go done
    }

    proc start {} {
	coroutine coro upgrade loadhex [namespace current]
    }

    proc status {msg} {
	fwstatus $msg
    }

    proc check {what} {
	if {$what eq "magic"} {
	    set msg "Warning: The selected firmware does not start with\
	      the recommended instruction sequence. This may render the\
	      device incapable of performing any firmware updates in the\
	      future.\n\nAre you sure you want to continue?"
	} elseif {$what eq "call"} {
	    set msg "Warning: The startup instruction sequence calls a\
	      different address than the starting address reported by the\
	      current self-programming code. This may render the device\
	      inoperable.\n\nAre you sure you want to continue?"
	}
	return [tk_messageBox -type okcancel -parent .fw -icon warning \
	  -default cancel -title "Suspected bad firmware" -message $msg]
    }

    proc init {} {
	grab .fw.f4
	wm protocol .fw WM_DELETE_WINDOW { }
	.fw.f4.b1 state disabled
	.fw.f4.b2 state disabled
    }

    proc manual {} {
	.fw.f4.b1 configure -text Cancel \
	  -command [list [info coroutine] cancel]
	.fw.f4.b1 state !disabled
    }

    proc progress {max} {
	.fw.pb5 configure -maximum $max
    }

    proc go {} {
	.fw.f4.b1 state disabled
    }

    proc done {} {
	global eeprom
	destroy .diag
	wm protocol .fw WM_DELETE_WINDOW {}
	.fw.f4.b1 configure -text Program -command [namespace code start]
	.fw.f4.b1 state !disabled
	.fw.f4.b2 state !disabled
	grab .fw
	if {[info exists eeprom]} {grid .fw.bb1}
    }
}

proc gui::accelerator {name} {
    set acc [string trim [lindex [event info $name] 0] <>]
    set rc ""
    foreach n [split $acc -] {
	switch -- $n {
	    Control {
		append rc "Ctrl+"
	    }
	    Shift {
		append rc "Shift+"
	    }
	    Meta {
		append rc "Alt+"
	    }
	    Key {
	    }
	    slash {
		append rc "/"
	    }
	    default {
		append rc [string toupper $n]
	    }
	}
    }
    return $rc
}

proc gui::selection {} {
    if {[.nb tab current -text] eq "Log"} {
	if {[llength [.nb.f1.t tag ranges sel]]} {
	    set st1 normal
	} else {
	    set st1 disabled
	}
	set st2 normal
    } else {
	set st1 disabled
	set st2 disabled
    }
    .m.edit entryconfigure 0 -state $st1
    .m.edit entryconfigure 1 -state $st2
}

proc gui::fork {file} {
    variable fork
    upvar 0 fork($file) id
    # Some helper programs are quite processor intensive and don't really
    # need access to data of the main program, so run them in separate thread.
    package require Thread
    # Avoid starting up the same helper multiple times
    if {[info exists id] && [thread::exists $id]} return
    set id [thread::create [list source [file join $starkit::topdir $file]]]
    thread::send -async $id [list set mainthread [thread::id]]
}

namespace eval gui {
    if {[catch start]} {
	puts $errorInfo
	exit
    }

    scroll
}

interp alias {} fwstatus {} setstatus fwstatus

if {[settings get debug console n] && $tcl_platform(platform) eq "windows"} {
    bind all <F12> {console show}
}
