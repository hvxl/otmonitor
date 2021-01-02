# A file selection mega widget
# Copyright (C) Schelte Bron.  Freely redistributable.
# Version 2.0 - 20 Mar 2020

namespace eval ttk::fsdialog {
    package require Tk 8.6.6-
    package require matchbox
    if {[catch {package require fswatch}]} {
	proc ::fswatch args {}
    }

    namespace export tk_getOpenFile tk_getSaveFile tk_chooseDirectory
    namespace ensemble create -subcommands {preferences configfile history}

    variable config {
	prefs {
	    details	0
	    duopane	0
	    hidden  	0
	    mixed    	0
	    reverse  	0
	    sort	name
	}
	history {}
	filedialog {
	    geometry	700x480
	    sashpos	240
	}
	dirdialog {
	    geometry	400x380
	}
    }

    variable defaultcfgfile [file normalize ~/.config/tcltk/fsdialog.cfg]
    variable cfgfile $defaultcfgfile cfgtime 0

    package require msgcat
    msgcat::mcload [file join [file dirname [info script]] msgs]
}

proc ttk::fsdialog::tk_getOpenFile {args} {
    return [dialog getOpenFile __ttk_filedialog $args]
}

proc ttk::fsdialog::tk_getSaveFile {args} {
    return [dialog getSaveFile __ttk_filedialog $args]
}

proc ttk::fsdialog::tk_chooseDirectory {args} {
    return [dialog chooseDirectory __ttk_dirdialog $args]
}

proc ttk::fsdialog::joinfile {path file} {
    # Join a file name to a path name. The "file join" command will
    # break if the filename begins with ~
    if {[string match {~*} $file] && [file exists $path/$file]} {
	return [file join $path ./$file]
    } else {
	return [file join $path $file]
    }
}

proc ttk::fsdialog::dialog {cmd child arglist} {
    variable result
    if {[llength $arglist] % 2 == 0 && [dict exists $arglist -parent]} {
	set parent [dict get $arglist -parent]
    } else {
	set parent .
    }
    if {[winfo exists $parent]} {
	if {$parent eq "."} {
	    set w .$child
	} else {
	    set w $parent.$child
	}
    } else {
	return -code error "bad window path name \"$parent\""
    }
    set var [namespace which -variable result]($w)
    $cmd $w {*}$arglist -resultvariable $var
    wm transient $w $parent
    vwait $var
    return $result($w)
}

proc ttk::fsdialog::preferences {args} {
    variable config
    variable cfgtime
    if {$cfgtime == 0} readcfg
    set prefs [dict get $config prefs]
    set argc [llength $args]
    if {$argc == 0} {
	return $prefs
    } elseif {$argc == 1} {
	set arg [lindex $args 0]
	if {[dict exists $prefs $arg]} {
	    return [dict get $prefs $arg]
	} else {
	    error "unknown preference name: \"$arg\""
	}
    } elseif {$argc % 2 == 0} {
	set merge [dict merge $prefs $args]
	if {[dict size $merge] > [dict size $prefs]} {
	    error "unknown preference name:\
	      \"[lindex [dict keys $merge] [dict size $prefs]]\""
	}
	dict set config prefs $merge
	savecfg
    } else {
	error "missing value for preference: \"[lindex $args end]\""
    }
    return
}

proc ttk::fsdialog::configfile {{file ""}} {
    if {[llength [info level 0]] < 2} {
	variable defaultcfgfile
	set file $defaultcfgfile
    }
    variable cfgfile [file normalize $file]
    if {$cfgfile eq ""} return
    # Create the containing directory, if necessary.
    file mkdir [file dirname $cfgfile]
    # Create the config file if it does not exists.
    # This will not change the timestamp if the file does exist.
    close [open $cfgfile {WRONLY CREAT}]
    readcfg
}

proc ttk::fsdialog::readcfg {} {
    variable cfgfile
    variable cfgtime
    variable config
    if {[file readable $cfgfile] && [file mtime $cfgfile] > $cfgtime \
      && ![catch {open $cfgfile RDONLY} fd]} {
	set data [read $fd]
	close $fd
	set cfgtime [file mtime $cfgfile]
        catch {
	    if {[dict exists $data history]} {
		set history [lmap n [dict get $data history] {
		    set file [string trimleft $n]
		    if {$file eq ""} continue
		    set file
		}]
		dict set config history $history
	    }
	}
	catch {
	    dict set data prefs \
	      [dict remove $data history filedialog dirdialog]
	}
	foreach n {prefs filedialog dirdialog} {
	    catch {
		if {![dict exists $data $n]} continue
		set merge [dict merge [dict get $config $n] [dict get $data $n]]
		foreach k [dict keys [dict get $config $n]] {
		    dict set config $n $k [dict get $merge $k]
		}
	    }
	}
    } elseif {$cfgtime == 0} {
	set cfgtime [clock seconds]
    }
    if {[llength [dict get $config history]] == 0} {
	set history {}
	foreach n [list / ~/.. ~ ~/Documents ~/Desktop [pwd]] {
	    set dir [file nativename [file normalize $n]]
	    if {$dir ni $history} {lappend history $dir}
	}
	dict set config history $history
    }
    return $config
}

proc ttk::fsdialog::savecfg {} {
    variable cfgfile
    variable config
    # Only save the configuration if the file already exists
    if {[catch {open $cfgfile {WRONLY TRUNC}} fd]} return
    dict for {key val} [dict get $config prefs] {
	puts $fd [list $key $val]
    }
    append hist \n "    " [join [dict get $config history] "\n    "] \n
    puts $fd [list history $hist]
    foreach n {filedialog dirdialog} {
	set str ""
	set settings [lmap {key val} [dict get $config $n] {
	    list $key $val
	}]
	append str \n "    " [join $settings "\n    "] \n
	puts $fd [list $n $str]
    }
    close $fd
    variable cfgtime [clock seconds]
}

proc ttk::fsdialog::history {args} {
    variable config
    set history [dict get $config history]
    if {[llength $args] == 0} {
	return $history
    }
    foreach entry $args {
	set history [lsearch -all -inline -exact -not $history $entry]
    }
    dict set config history [lrange [linsert $history 0 {*}$args] 0 49]
    return
}

proc ttk::fsdialog::histdirs {{size 10}} {
    # Only return existing directories
    set rc {}
    foreach n [glob -nocomplain {*}[history]] {
	if {![file isdirectory $n]} {set n [file dirname $n]}
	if {$n ni $rc} {lappend rc $n}
    }
    return [lrange $rc 0 [expr {$size - 1}]]
}

proc ttk::fsdialog::histfiles {{size 10}} {
    # Only return existing files
    return [lrange \
      [glob -nocomplain -type f {*}[history]] 0 [expr {$size - 1}]]
}

proc ttk::fsdialog::subdirs {dir} {
    file stat $dir stat
    return [expr {$stat(nlink) != 2}]
}

proc ttk::fsdialog::fontwidth {font args} {
    return [::tcl::mathfunc::max {*}[lmap str $args {font measure $font $str}]]
}

proc ttk::fsdialog::geometry {dlg args} {
    variable config
    if {$dlg ni {filedialog dirdialog}} {
	error "invalid dialog: \"$dlg\"; must be: filedialog or dirdialog"
    }
    set data [dict get $config $dlg]
    set argc [llength $args]
    if {$argc == 0} {
	return $data
    } elseif {$argc == 1} {
	set arg [lindex $args 0]
	if {[dict exists $data $arg]} {
           return [dict get $data $arg]
       } else {
           error "unknown option: \"$arg\""
       }
   } elseif {$argc % 2 == 0} {
        set merge [dict merge $data $args]
        if {[dict size $merge] > [dict size $data]} {
            error "unknown preference name:\
              \"[lindex [dict keys $merge] [dict size $data]]\""
        }
        dict set config $dlg $merge
    } else {
        error "missing value for option: \"[lindex $args end]\""
    }
    return
}

if {$::tcl_platform(platform) eq "windows"} {
    proc ttk::fsdialog::subdirs {dir} {
	try {
	    set subdirs [glob -nocomplain -directory $dir -types d *]
	    set hidden [glob -nocomplain -directory $dir -types {hidden d} *]
	    return [expr {[llength $subdirs] + [llength $hidden] > 2}]
	} on error {} {
	    return 0
	}
    }
}

proc ttk::fsdialog::posixerror {w errorcode {problem "Operation failed"} args} {
    set top [winfo toplevel $w]
    set reason [mc [string toupper [lindex $errorcode end] 0 0]]
    # Avoid multple popups for the same error. Last one wins.
    coroutine warning#$top warning $top [mc $problem {*}$args].\n$reason.
}

proc ttk::fsdialog::warning {w message} {
    set coro [list [info coroutine]]
    after cancel $coro
    after idle $coro
    yield
    protect $w {
	tk_messageBox -type ok -icon warning -parent $w -message $message
    }
}

proc ttk::fsdialog::buttonname {str} {
    return [string tolower [string map {& ""} $str]]
}

proc ttk::fsdialog::protect {w body} {
    # Destroying any toplevel in the path leading up to a tk_messageBox
    # causes a segfault. As a work-around, clicking the close button on
    # any of those toplevel windows is temporarily disabled.
    set win $w
    set stack {}
    while {$win ne ""} {
	set win [winfo toplevel $win]
	lappend stack $win [wm protocol $win WM_DELETE_WINDOW]
	wm protocol $win WM_DELETE_WINDOW { }
	set win [winfo parent $win]
    }
    set rc [uplevel 1 $body]
    foreach {win cmd} $stack {
	wm protocol $win WM_DELETE_WINDOW $cmd
    }
    return $rc
}

proc ttk::fsdialog::dim {image} {
    return [image create photo \
      -data [$image cget -data] -format {png -alpha 0.3}]
}

proc ttk::fsdialog::optadd {pattern option {priority userDefault}} {
    set style [ttk::style configure .]
    if {[dict exists $style $option]} {
	option add $pattern [dict get $style $option] $priority
    }
}

proc ttk::fsdialog::mc {args} {
    ::msgcat::mc {*}$args
}

# Create the images if they did not already exist.
namespace eval ::ttk::fsdialog {
    variable image
    if {![info exists ::tk::Priv(updirImage)]} {
	set ::tk::Priv(updirImage) [image create photo -data {
	    iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAAABmJLR0QA/gD+AP7rGN
	    SCAAAACXBIWXMAAA3WAAAN1gGQb3mcAAAACXZwQWcAAAAWAAAAFgDcxelYAAAENUlE
	    QVQ4y7WUbWiVZRjHf/f9POcc9+Kc5bC2aIq5sGG0XnTzNU13zAIlFMNc9CEhTCKwCC
	    JIgt7AglaR0RcrolAKg14+GBbiGL6xZiYyy63cmzvu7MVznnOe537rw7bDyvlBoT/c
	    n+6L3/3nf13XLZLJJP+HfICysjKvqqpq+rWKysvLR1tbW+11g+fPn/+bEGIe4KYqCs
	    Owu66u7oG2trah6wJrrRc0NTVhjME5h7Vj5pxzCCE4duxYZUdHx/aGhoZmgJ+yb+wF
	    uCO19RmAffv25f8LFslkktraWtvU1CS6u7vRWmOtxVpbAPu+T0tLS04pFU/J34Wd3S
	    cdFtlfZWeZBU4IcaS5uXn1ZLAEMMY4ay1aa4wx/zpKKYIgoL6+vmjxqoXe5ZLTcsPq
	    bTyycjODpe1y3WMrvDAMV14jCuW0VhhjiJQpOJ5w7Zwjk8/y9R+vsHHNNq6oFMrkeX
	    BxI+8d2sktap3YvOPD0lRQrH+Z81fE7t3WB4gihVKazsuaA20aKSUgAG/seQdy2l6W
	    37+EyopqTv39I6HJUT2zlnlza2jLdgiTaxwmDov6alLHcZUTzXPGGAauWJbfO4dHl9
	    bgJs3HyfNf0N4ZsOa+jbT3/ownY/hO09p1kBULtjBw+Tvq7xzwauds4dWPDleAcP5E
	    xlprgtBRUZRgYCRPTzoHwEi2g6OnX+eFrW/RM9qBE4p43CeTz5ATaU6nDrFm2cPs/+
	    E1SopqkZ7MFJqntXZaa7IKppckwIEvJbg8LWd28OT6nVihCPQQ8UScWCLGqO4hXuQx
	    qDtJ204eWrqWb1ufRspwtABWaqx5gRKUFSdwDnxPcuLcyyxbuIyaqntIBV34MY9YzC
	    Owg+S9YeJFkniRpGPkCLMrZzG3+jbktA/KClMxFoUhiKC0OAbAhd79CO8i6xe/STyW
	    4O7KVRgUJ/sP0heeJV4kEVKw/vZd40sFKxat4mLvp6VLdvnb/XHHGGPIKwBBpC1/9n
	    3DpfRZnn9/AwCxRII9O79kVPdjvByxuET6Ai8mePeTt4lyheXzhOSpCcdWa00uckTG
	    kckbGu76nEhbIm2xznH4VB3OWYaiXqQn8GKSWGIMHuXyPL76LBcupmhp69pz4uMnXi
	    w4VloTGcdQRtGdzmHs1f+RdYZslMZJhzUOHVnceN1ooEiP5JUzdqCQMWCD0JCIeQzn
	    NNpO+clhrCYf5rC+A2cxWmDUWG2oHEOZMEKIwclgMnnLrTeXUV7sUzpNXgU9DmijWV
	    v9LEKCkAIhKIBnlvpks6F21qUZ31u/sbExPa9h0/RzwzMov2nGlG5TmW1YOzzlnSfL
	    mVnyGf19Q7lwZHBp+1fPtflAIgiC7389n9qkihP+lWyeqfUO15ZwQTqlw9H+o2cOvN
	    QJCAHEgEqgYnI0NyALjAJdyWQy7wMa6AEujUdzo3LjcAXwD/XCTKIRjWytAAAAJXRF
	    WHRjcmVhdGUtZGF0ZQAyMDA5LTA0LTA2VDIxOjI1OjQxLTAzOjAw8s+uCAAAACV0RV
	    h0bW9kaWZ5LWRhdGUAMjAwOC0wMS0wM1QxNTowODoyMS0wMjowMJEc/44AAAAZdEVY
	    dFNvZnR3YXJlAHd3dy5pbmtzY2FwZS5vcmeb7jwaAAAAAElFTkSuQmCC
	}]
    }
    if {![info exists ::tk::Priv(folderImage)]} {
	set ::tk::Priv(folderImage) [image create photo -data {
	    iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAABHNCSVQICAgIfAhkiA
	    AAAAlwSFlzAAAN1wAADdcBQiibeAAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBl
	    Lm9yZ5vuPBoAAAHCSURBVDiNpZAxa5NRFIafc+9XLCni4BC6FBycMnbrLpkcgtDVX6
	    C70D/g4lZX/4coxLlgxFkpiiSSUGm/JiXfveee45AmNlhawXc53HvPee55X+l2u/yP
	    qt3d3Tfu/viatwt3fzIYDI5uBJhZr9fr3TMzzAx3B+D09PR+v98/7HQ6z5fNOWdCCG
	    U4HH6s67oAVDlnV1UmkwmllBUkhMD29nYHeLuEAkyn06qU8qqu64MrgIyqYmZrkHa7
	    3drc3KTVahFjJITAaDRiPB4/XFlQVVMtHH5IzJo/P4EA4MyB+erWPQB7++zs7ccYvl
	    U5Z08pMW2cl88eIXLZeDUpXzsBkNQ5eP1+p0opmaoCTgzw6fjs6gLLsp58FB60t0Dc
	    K1Ul54yIEIMQ43Uj68pquDmCeJVztpwzuBNE2LgBoMVpslHMCUEAFgDVxQbzVAiA+a
	    K5uGPmmDtZF3VpoUm2ArhqQaRiUjcMf81p1G60UEVhcjZfAFTVUkrgkS+jc06mDX9n
	    vq4YhJ9nlxZExMwMEaHJRutOdWuIIsJFUoBSuTvHJ4YIfP46unV4qdlsjsBRZRtb/X
	    fHd5+C8+P7+J8BIoxFwovfRxYhnhxjpzEAAAAASUVORK5CYII=
	}]
    }
    if {![info exists ::tk::Priv(fileImage)]} {
	set ::tk::Priv(fileImage) [image create photo -data {
	    iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAABmJLR0QA/wD/AP+gva
	    eTAAAACXBIWXMAAAsTAAALEwEAmpwYAAAAB3RJTUUH1QQWFA84umAmQgAAANpJREFU
	    OMutkj1uhDAQhb8HSLtbISGfgZ+zbJkix0HmFhwhUdocBnMBGvqtTIqIFSReWKK8ai
	    x73nwzHrVt+zEMwwvH9FrX9TsA1trpqKy10+yUzME4jnjvAZB0LzXHkojjmDRNVyh3
	    A+89zrlVwlKSqKrqVy/J8lAUxSZBSMny4ZLgp54iyPM8UPHGNJ2IomibAKDv+9VlWZ
	    bABbgB5/0WQgSSkC4PF2JF4JzbHN430c4vhAm0TyCJruuClefph4yCBCGT3T3Isoy/
	    KDHGfDZNcz2SZIx547/0BVRRX7n8uT/sAAAAAElFTkSuQmCC
	}]
    }
    if {![info exists ::tk::Priv(upImage)]} {
	set ::tk::Priv(upImage) [image create photo -data {
	    iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAAABHNCSVQICAgIfAhk
	    iAAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAAL/SURBVDiN
	    tZRNaFxVFMd/5368eZkxRmQsbTEGxbZC0IWMpU5SbCmxILapFCO2LgSlWbhLbFJB
	    cKErP0BcCIqCdeEiUAviQoJIwIgW3biwCoYGjTImTIXWTjsz7+O4yLzwUkuSgjlw
	    uPdd7vmd/z33vCuqymaY2RTqZoLdRjfunXTvg2zfNh8PT01p8r+AByf9S9vv6DuG
	    QWr627vA6Hox65ZiYMIdva1Ufvlg9WhpaM+RYs+t5eN7J4IX1ouTtbpicCyoFEul
	    macOniidr8+SpBG7ynv4dPrjxpVW48i3b0Rf3rTiR8al13o3/cSBZ0uLV+f46/IF
	    apfmWLh8nsf2PVnyzp0ZnAx33RR4cFK6U2dnDu97pie1LS5c/BFnHNZ4fl36nkZS
	    Z6h6qBuNv6qOye0bAo+MiFXc54/uHundUt5qfln6Dmt8xx2I8MPCF5RuKcrAg0Nb
	    jHfTlVHx64Jrd9v3qv1Du/t3VPxPta+xYvHOUwgCfGBQ28Z45dzCWfruvMfdf+9D
	    /V099vSa4IEX/fh9d1WO7a8Mhz/XZjFOCMMCYVggCD2RaeAKQlAw4CPO/XmGygMP
	    h33bdg5XJ/ypPGulK6rj7vG+rTumnjt0qss5j5KikjAzf5pYWtSvzXMt+Wc5SuHw
	    zpNoqmgKzXaLs9OfXK1f/OPp2bfizyD3gxgr478vznW98sHzAFgvzVdPfBj6wNFo
	    LxLZBt4bBFAF44R3PnqtGbc17CCKOBkDVoNnX4/2X1cWNdbiA8+V1hK+YDAGEEFV
	    sVaI2xp+82Yk19d3FfhGZozQiP9GbYwLBOMEEUFTRewNeRsEi6WZXkIMGCs4bzBO
	    iNspsjZ3dVfIsjkRKWRrzbgBCppCmihJpGgC6EpMUUQKIrJKpMuAgO98u84cVTjQ
	    O4pKirEgIizfHqTpyhvTDcRAJCJxNne5BDYHdUD95NvHy2sfmHomImcKJKKqmeI8
	    NBuzZKbjHb2kHY+BJFMJtIG2qqb/eTY7SWzOM6jtbElz8CQHV83B/gXtSQriGSyg
	    6AAAAABJRU5ErkJggg==
	}]
    }
    if {![info exists ::tk::Priv(prevImage)]} {
	set ::tk::Priv(prevImage) [image create photo -data {
	    iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAAABHNCSVQICAgIfAhk
	    iAAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAANNSURBVDiN
	    tZVNaFxVGIaf75xz782fUvsjGI00BY2IoILGmJks2igRqcH6H4pdSOmmK2sToS6i
	    iBsRhIouTDetYnVRjSJCLbYbFSKdKiiIQZRY04ihNmnoZGbuufdzMXeSMaZjXPTA
	    yzmLj+d7v5d77hFV5Uosc0WogPs/xb37gwERDoRtvv/UqPpGtWt23DcS7r1+U+eH
	    RmzfWgz9J1heEpMbdm/e3HH7q3sGD7RY49K1GGnYeWBYWnPixrtv3Zq/r/vRpsCF
	    a2E2Buefl3bBneq/e0fnnV33Bt9Of07P5kGMo1JecIu5/cE/6sUwG7T69lr2q4Jz
	    I+Ed1jSdGNy285rrNt1gJ6Y+BZQkTXhh11vNRgyCILKc5OjY7vXgHbA6uPc5t721
	    ue3ow1ufbjORMjH1CUYs1gR8MXkYIw4jBmssgkFEyG95vHEUueFg37qrN7y8o39X
	    y/nFKX4+ewZrApwJSDUlTROscRix+NRgMsdJGqMosho4P+IOtm/seGYg/1jL5Plv
	    mJ77aRmoCYGkpLZCRTyJxqDgCInsVXiNWXmDlx0b2jGIkhD7EmVfJBaLotgQwGNQ
	    jBXEVL1pqmgJiumFf0WxlP5XzckT5/78/dBHJ9+9dNOGbrquvYeyL5KaEtgKLoKw
	    2RK1WJpaLVFr9Rw0G1KpXB6so5p+/Zrf99fsheFjxw8X14cd9HQ+RBAE2MDgQkMQ
	    mSp8CWpxkcFYQYGFc8u8pShEJACiiTf8B7c9VZwZT947cn/v9ra+zielMPsxaio8
	    uOVZnHPYwKCqpF5JfHVHYOYMLSISq2rsMqgDwkzRD+8n392Y55Hjfvyd3F3bNuZv
	    2elOzx5DU3j90CvlcjGOVo4uMDd/FgOEIpLUHNtMrqbfvkz+mP+VocSfPDh/cb4r
	    1zMUaiLEZQ0KY/6B8kUWgHKmUrbXWK7hT2h+moXC28neQuH0yc9OjJcXi6VG5fUr
	    rTlOMvk69xVAfAktjKUvVoZ+mbxUPLKHNI3EUMxcxlmdX6FqFKrqRSSLqtqxrpED
	    3PdHk7HK4MyP6zbL7iRmLhvd18FjYBEoqapK/Y2RKj0Aomx3dRNIJs1UP2UZKKsu
	    vypyucdURCzV79zWqTZNbaIESHQVyN9x5li6vCTOrQAAAABJRU5ErkJggg==
	}]
    }
    if {![info exists ::tk::Priv(nextImage)]} {
	set ::tk::Priv(nextImage) [image create photo -data {
	    iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAAABHNCSVQICAgIfAhk
	    iAAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAAM0SURBVDiN
	    tZVbaB1VFIa/NbPn5GLtRSkpKNYnb+2DhQo1idCCVgRBRa36IlKlFHxpSUkLgqJg
	    UaQ+9EVQS2nMQ4haCiliSzSGJqYqmhY1NMZL1KSxxgTTk+TMZc9ePpw5dZI20Yd0
	    wc/MhjXf2v/ai9miqlyN8K4K9f+CG5uDrvom8+CSg9WxeW3dLe83Nhd2LykYYMfD
	    L1Svu3njq/fsNW9v2yb+koF9P+CRzdtrNq27/+nza03nludl2WL5Jr9oaA7+wFF3
	    WXUjoXO2+sz5Tho3bK1asWxVw8d9bf2b9sqW06/ryJXAkh+3hj2B7t/ZMidB1aEo
	    Th1dQ60IHnesaWBsfNQd62r521p77+cH4v7/BL+y411O/dSeQRXFkboUpw6nltRZ
	    UrXcVnc3Gnsc/eTwTCksPnXqDdsxx+X8SqmzRLZEZEvEaUhkQ5I0IklDYhsSpyGx
	    LfHN7ye4mI7x5AM7r1lx7eq2hj1B06Jg6xJKSZHJ2TEuFIcZn/6NqdKfhLZIQkgq
	    EU5inMQMXOhhaOILHrvvmdob6256ubHZHKxwzHxwMZxkeOJblHKLxAM/8PCd4Ac+
	    BVPAMz7iBCcpaqLyUxBEblgQnLhoDjSo8jCFsjwjeL4FLM4pt66sZ03hdj48cWR2
	    anriUG9tumtBcD78wMMPPEyVd6mAZwRPPNav2oo/u5y2jsOz01Mz+04fTN8B4KV5
	    YBEJ6pvKy8c37EMAz0gZbgTfCCfH3qS2poY7r3+I8ZEpPXa8ZWbyl+jZ79pdN1AL
	    GBGJVDUxGdQABYXxt9r2r75s50bi3c+9WKj2l7Pxukc59/25tPOzkxPDvbp9tM8N
	    ATX8OwgqImllxz7g9x2w64GqTNWV9/om0+tS5a6VT9DT3RN/ffbLnwc+sLsujvAX
	    UAAckGaygFm0x/kISyEffdoRDw4O9pw54l5LI2YWSXcVcL6anykGBMoj0n68Nf71
	    h9FDZ99zrVlukinOvsur3ApVtSJCBiJnzQImTfSrH/tHWgaOuu6skMtBKvAEKAGh
	    quqcf4WU6UHW24Dy1FQcSM6BznMZAZGq2kushS5TEfEpn7SfU8VN/rBSvQLkHy0n
	    h7/z4dY0AAAAAElFTkSuQmCC
	}]
    }
    if {![info exists ::tk::Priv(homeImage)]} {
	set ::tk::Priv(homeImage) [image create photo -data {
	    iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAAABmJLR0QA/wD/AP+g
	    vaeTAAAACXBIWXMAAA3XAAAN1wFCKJt4AAAAB3RJTUUH1QoOFCMCb8BVTwAAAyVJ
	    REFUOMullcFvG0UUh7+Z7Dq1G+NtnEBdRG0hVTSiqkAoNFIvHCCgKmotWVUiCMpf
	    4FO1FQKVf2CFVEgFJyCIHIKg0jpSLz330AMHGkI5EEEPkRM1iZ1CXLvx7gyHXa/W
	    TZ1E6kij3Z2Z9703v3lvVnCINg85oBp+vjkNv/G8bR7emge9Y9t6x7b1POjQ0b5N
	    HAQFfi3adte46zgAJ6ZhrZetPAz00Z070XhtcZHQUXW/yOVB0Na9ewxks13zh4GL
	    /aDeygrSMJCFQmf7FG2bzUoFKQSDFy/2lEX2gupqFZlOR9A/Jy6w+uEUruMwdOkS
	    ntb7Ri5i0Gngx6Jto+v1YPLYMVzHofHxR2ycfo2XXjzOqfo2q1evUrRt1isVEj0i
	    j4N10bah2YTdXchkcB2HJ/YV/n35BCMjr5NKJmm1WqTW1nkwMxPAXZeElBF8OmQa
	    IfRIx4FuNhGDg7iOg/7CQWazvJEvkM/ng3kNu6+cxLx1i4VSialymXXX3XN4RvhM
	    RdqE0L7vv8UzTM6fG8OyrMhAaw2AZVlk795lYWyMqXL54HS7fvMX/LnvaBsGo6Nv
	    MzAwgO/7Xb3dbuP7Pv3ZLOP377MwOxtPANml8e2zZ2ceLi3NnVv5i08/+2RPBDe+
	    +hqlFNe/nEWLPrTXQhhH0P4TPr92jUo6zdCZM+UPlpdvxKVgfGnph8uTpbkLg0Ex
	    jIycRgiBEIFv3/fRWqOFpK8wjreyiMi/h35wG601lckShZOvfsPy8rOl6GiYSCQw
	    TRPDMDBNE6VUBK9u7QDw+9+b+L6KbBzH0c/S2IiDpZRIKUnIVQxRQymFUgqPBH/8
	    swXAw/pjPNEf2RBkl4hL0QccjYM7EihyNFsBNJfL8c75Ud5PHkXq47wrTTbWiIOz
	    BAXiGaEHoxcY+kkmQSkFwKP6JmJ7q/tSqtX2VLIRG5AdbS3LIpPJIJAEfMHw8DCN
	    RoOJiYk9GZNKRWXQAHQHKEIp0pcnS7Xn+dv8/NNNE/DioXfk6A8P4IVQryEgGc75
	    4dqd8L0NbAP/ARvA49iarvtYPCWLAMzYrogZ6rD7YddPR/8/aWZWKFzoJj8AAAAA
	    SUVORK5CYII=
	}]
    }
    if {![info exists ::tk::Priv(reloadImage)]} {
	set ::tk::Priv(reloadImage) [image create photo -data {
	    iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAAABHNCSVQICAgIfAhk
	    iAAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAATmSURBVDiN
	    tZVpTBRnGMf/7zszO7uzSzmWW+QQa5GgFkWoaBuPmiatMWnaEIKamKYC1k+2TROT
	    Jv3SNDE1adJaFCQ1toCkNGm1sUdiPEqtCgRBWwVCPRAWAXGBved4n35gIRx+8Esn
	    +WeSmWd+85tnnpmXERH+j40/S1FZWYv0LHUb9jdnl77bkgAA7GnGJZXfrlAU9SMw
	    bDVNK00QFIkzP+ds1BJ0QZBoERT4o6O20pi55qV9p1MEp79MC1s76ysezAMzBlb6
	    XnM9wMpffnGpbWVOsuxyquCcQdcNBEIGHjyatG70egIj4wGJMRz2c+ULl6Rz6Lzd
	    EmIFMZHVUbtnYB5444Hmk9lpcWV7Xl+tRQwLE/4wYjQVmqpA4gDjDKBpA38wgkud
	    98PX/x7SScCzqTBr2a3+EWNyIph37cSuQXkGWlT1XUmCS3t7e/Ey7euWdjHmDXLO
	    AWEREYOZ6naFSgoynIUvpEpEQMggbF2fay/Kz7D3P3wS82pRFuvqHTZ1IYl5L88u
	    K9XPuVRn/ZlOmgoYzGFXwpYQ31+rreAhjhTPiH/7uda+Hz79pjXY1jNMTlXC0HgI
	    TwIm1uenM0XmsCwB2R6eDwbDawPDk8wdF+Ndnp16Q9dNLyA+B4CbNRXe9vqKtis1
	    5eWGbm38/Upf+4kfO4LxDo7MJA2Xbo1CkTgsIVhkoTEJqJpDHcrMSK6N1ewNYLzP
	    Ipt34cS01VV06YZ5aCqgSzEOBUPjIQgAdoXDsogpQhYAMNtjS4hgosvxZYzD/rOu
	    q48pwk7FLE2eWgguqmpcpcjS2eq3itSkeA1piU5sLkiGqkgwBTGbtQDsSEvPOYvL
	    4szeNwQAoHLFovkuqmpIY8R/syzSjra0R0gQiADC9F4IsulWQABzPpDiqqYxBrgW
	    0QAQwce42P7E5u5x+UYcT6sBAIWgtp/aO0oEkuccj2v4ZIdskzkABsaAsG7i47rW
	    yP2RyfevH9/dHa2LTNvXKUC8VlpQGHbH6PHd/z4sHRx9XEeExHmtABGz22RcuDUC
	    BkJpXhKazt+JDIz6jrYd39Ww0E4WzhRJFcdUh++nybBImvD7q2yybM2cnzNu05aG
	    KZCR6AQD0N0/RpyxVcXvNC9d9NwSnrMssWHSF9x9+97gh75AOJtx3J298awwiDEA
	    a3LiMDgexJCX48iBLfam8z3bzl3p7ympbvpKWNQBYgNcsWQi6YhDVeJ67g5ttikS
	    uWM1wzsRql8EnpZmCIZ05C+JRcS00HnPi1cKM6Xi/HSt487wB57HvrBnzMfGJ4JO
	    ycaQ4taQl5OMxDgna/ylK6yZeuMiMGeM3X80hUM1lyY4A9+xablty7osuzdgwiKg
	    MC9NLrBSXYxN988QBNMUmPBH0PjrDb9lGAcvntwbnpUkIjDGpPWVDUas0xbo77q4
	    w9Nx5lHulsqd7iW51aufT8vIz01RMlNjmdNhQ8QQMEwLkwEdXb0ecfXmQz04MXK4
	    +/TBGgBhAGEi0mfA9nX7Grx+z+2y3nOf/QPAEY09fe3ONSkrt5UrWvxacKY6VcUI
	    RkyJCBAR35+jfa3HBq42dQMIRRMkouAMmK3efezNmw37LwOwA1DnRIlGkpxuJSGj
	    ICHoHfYGRvu8APToXEeiUB+ACBHRoqWJMSbNgc1EBiBh+jdvRWNEowMwiciay/kP
	    KWlcmnLc32AAAAAASUVORK5CYII=
	}]
    }
    if {![info exists ::tk::Priv(newfolderImage)]} {
	set ::tk::Priv(newfolderImage) [image create photo -data {
	    iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAAABmJLR0QAAAAAAAD5
	    Q7t/AAAACXBIWXMAAA3XAAAN1wFCKJt4AAAAB3RJTUUH1QsRDwMVXP7WwgAAAtNJ
	    REFUOMvVlU1rE0Ecxn8zO4lNNFWrNlRBhQpCTQ9aQRREv4E3ETz5dhJRz4LgF7An
	    ERVvXop4qBc9qdCDoGhrqyVpfUHUNmnaNG3eNtndGQ/ZjTFabRUPDjyzM/vf/c0z
	    /52Zhf+tCIALF89f8bR7uTVYq9UA0J4+duvm7YEVg8+dP2tOnTiz5EPXb1wjl8vt
	    vTtw70VrzM0cEUAIcFR80PwA3r/vAOl0ekn48KuXOI6DMaYhSxoOH4j1nz6aTwJh
	    YBgYVvHBsgpe7OnZhZTWkuDNm7d817csQ+f6OUJ66GLN2ptFtCulUx+FTve7mSMD
	    Ksjl+PgbHk0YRr4sJ4OGHfEFjh9MsWfnblx1bJOlOihVhtbPZO5f7o6nXzQcJxK9
	    XH08yqWTh7Ad75dYicvG6Du616WJRrqw1AaEkCgrQr4S7gbWNsCvX48BMF+qkV2s
	    /uaLa4pRxWq5FikmiVlDhEI7cZ2XvE+H6dtOTgLYtk0i0bvspWSQzFc28Wamj1R2
	    K9nZp+RzA3yekzwc2Qow9YPj5RbPKGbLnRRr7XzKd7NKVbBUF28zYwAFBVAul+uO
	    H4+ucH9JbDeK7UYBWBNyqTpqUsUHjfxTxz8rCwsFpLtYrA/ZtCoAImGrKZf4mwG0
	    MWgNWhu0Nni+3CaV7SrSeBMAKth9gWPX01RdDSYAg8BghN/BYBD1oDBgBAbDmjbF
	    zPy8I71yCZANcCLRS1/yGdKSVB1dZwgaA7SC8Otgah0xSWZ2UUg7+wRQyj9AGBtP
	    0r6uk3S+iu07DngNeHNtaIwciyiqjiabL3hq7jlAWAFRgLauHrbFLJLTJQSgmxPd
	    aPtpqNvHUDewKqT5PJkyhUKp8Ck5UQQiCqiMjo6d+XBn5Nbfnu3F1IP+6anpqWAu
	    FtAGxICI3w77K0Z8y/R3Z3hwzwCer5qvCrAomuDKV6gJSgtYtFy1H9OA2yT9z/55
	    XwFw92OAfbBE1wAAAABJRU5ErkJggg==
	}]
    }
    if {![info exists ::tk::Priv(optionsmenuImage)]} {
	set ::tk::Priv(optionsmenuImage) [image create photo -data {
	    iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAAABmJLR0QA/wD/AP+g
	    vaeTAAAACXBIWXMAAAsRAAALEQF/ZF+RAAAAB3RJTUUH1QkaCxgledlRSQAABAxJ
	    REFUOMullX9MlHUcx1/PcQIp4KGWcoSIzWlWwgmjDe4WhbgWCs5labKmFstq/eFY
	    Cxnu25PEUf/QBuTI1ppjLcwtc9omsWkt2JQfZzupQyV2uziQHpEuQLg7nqc/5Lkd
	    50Ftfbdnez7Pvs9r7+/n834/j0TEEkII4P258j2gV5bldv7vEkJoo7dHtJmZac3l
	    +k0TQmgVFRXFgPQvr0qAQS8MUTaYmz49gaaqpJrN7Nu3l4SEhPOAthA8p7wl5YMT
	    59Sc8pZTkWBJCJEFIMvyMGC2133EzPQ9MjIyIlVFQrMA77HDOzEvZ01OeUu7Dpaq
	    q6tlwCGEOK7DrVYrkvTAgdQogh1dn+2np6eHg/nLCi3p8YUARmBJTEzMsTcPl2OI
	    iX0XqN6yZQubNm1E01QkScI/M3lFCJEly/K1KGoZGBjA4/Hw4feTAObQ0Zqbm52l
	    JTufXLr0IQJ+P5qmoWlaCJBkSqa21g5gnmuVDnV0Nr1E3tun9a2W7pNl10JgIURK
	    fHz8r89vLzQ9/sRTSJIUmpVv/O59+HITtfY6APMF74bVgONq8yvB3De+MgJF3SfL
	    2qMOQwiRlZ6e/rnb7c7Wn+Xm5ga2bStc8vdf42iaxrLEJFpbW2nqjOXnhhexvnNm
	    nspwrrSIn1MAG9BaVXWUsTsK12/+wcdn3Xx7vJiCI2cXhAKa9B8CkwU41lqKOXHh
	    Bt9U5VP1RTclmwO4XP2WsIHq/Yvuy3DTK0Mer16vSk3jcv0uDtS1scsSz8slRdTU
	    1OgDHQVmFzV8OHTP9o1kbl6PoozxScsVVqWmUbEjBbPJyPqMdaQ+moYsywCWSCsa
	    FoO+WmpFnVBINJkotCShDHlw9f6EzWYjPi6WO3/e5v43C4ee3KhgHfr67kwO7X6G
	    tos/8GNPPxiMzAaDIa/KsszKh1cjSdKCcEMk9OhrVvYX53H6u3a6+gbJs9lwuW4R
	    8E8D4PP5FL/fny3LMitWPQIQgsfFxYXgBj1FypDHK7/1LHu2Z3PqzEUGPV6Kiktw
	    uW7hdd+ko1/FGBzdUF9ff9dut98YGRmx6spn/H4OHjxAZWUlgCMEVoY8jiNlT1Na
	    kEnrucsMerzYniucBw2M9lqmFHcSsAJY6XQ6A06ns1iWZcypaTQ2NuLz+UKdMOp3
	    6evSmFU1RocGH4BO/N5WoLguBeaEJAOGzs7OIDA8MTGxt6Gh4euxsTFUVb0aCATs
	    oeSte8Gu7cg3Y8m28FiKiV/6bnG1q4uOfpUp96X80b42JWImaphVZ4EZYBKYBoLA
	    rBFgxZqUrec7vL16g+5NTdDRrxJnmCxQk1PHASXM9zpQ/6Ooc/CgDp0X6a2HvrSM
	    jQz36nVCYuza660VI+ExDYNKUWKszl0aoP0DjPbe8WKg6ioAAAAASUVORK5CYII=
	}]
	variable arrow [image create photo -data {
	    iVBORw0KGgoAAAANSUhEUgAAAAgAAAAFCAQAAADSmGXeAAAAJUlEQVQI12NM/s+A
	    ApgY0AAjAwOymrmMjAwMCKG5jHCZ5P8wQQAXTQgsrBlJzwAAAABJRU5ErkJggg==
	}]
	$::tk::Priv(optionsmenuImage) copy $arrow -to 15 18
	image delete $arrow
	unset arrow
    }
    if {![info exists ::tk::Priv(sortdownImage)]} {
	set ::tk::Priv(sortdownImage) [image create photo -data {
	    iVBORw0KGgoAAAANSUhEUgAAAAwAAAAICAYAAADN5B7xAAAAa0lEQVQY06XQsQ2D
	    UBAD0AdSoKAgHb/NLozBBozAENAwAnOxAiPQHBKJoigCSy7O9km+4yIqtKi/eHV4
	    FeQhPtBhQHEKF6F1kXlDwoIJZXAKLR2h7GPpiRlrzC/02H7d02AMNv8+IZ1r3MIO
	    qOkJqF7di88AAAAASUVORK5CYII=
	}]
    }
    if {![info exists ::tk::Priv(sortupImage)]} {
	set ::tk::Priv(sortupImage) [image create photo -data {
	    iVBORw0KGgoAAAANSUhEUgAAAAwAAAAICAYAAADN5B7xAAAAZElEQVQY063QsQmA
	    UBAD0IeCFhb+ToexdChnsBBHsHEfl7G3uUJULMRA4EgCCcdPaIM35A9agwEdNuxn
	    M7uEE6YI7XGntxkrZpTBObTbvIQFI4qTXoS2XJsq9Kgfmuvwqk/vOwC8jgvQxnTb
	    GgAAAABJRU5ErkJggg==
	}]
    }

    # Create dimmer versions of images for the disabled state
    set ::tk::Priv(upDimImage) [dim $::tk::Priv(upImage)]
    set ::tk::Priv(prevDimImage) [dim $::tk::Priv(prevImage)]
    set ::tk::Priv(nextDimImage) [dim $::tk::Priv(nextImage)]

    image create photo ::ttk::fsdialog::blank16 -height 16 -width 16
    image create photo ::ttk::fsdialog::radio16 -data {
	R0lGODlhEAAQAMIAAJyZi////83OxQAAAP///////////////yH5BAEKAAEALAAA
	AAAQABAAAAMtGLrc/jCAOaNsAGYn3A5DuHTMFp4KuZjnkGJK6waq8qEvzGlNzQlA
	n2VILC4SADs=
    }
    image create photo ::ttk::fsdialog::check16 -data {
	R0lGODlhEAAQAMIAAExOTFRSVPz+/AQCBP///////////////yH5BAEKAAQALAAA
	AAAQABAAAAM4CAHcvkEAQqu18uqat+4eFoTEwE3eYFLCWK2lelqyChMtbd84+sqX
	3IXH8pFwrmNPyRI4n9CoIAEAOw==
    }

    variable stylesettings [ttk::style configure .]
    if {[dict exists $stylesettings -selectbackground]} {
	option add *TkFDialog*selectBackground \
	  [dict get $stylesettings -selectbackground] userDefault
	option add *TkFDialog*inactiveSelectBackground \
	  [dict get $stylesettings -selectbackground] userDefault
	option add *TkFDialog*Menu.activeBackground \
	  [dict get $stylesettings -selectbackground] userDefault
	option add *TkFDialog*Menu.activeBorderWidth 0 userDefault
    }
    if {[dict exists $stylesettings -selectforeground]} {
	option add *TkFDialog*selectForeground \
	  [dict get $stylesettings -selectforeground] userDefault
	option add *TkFDialog*Menu.activeForeground \
	  [dict get $stylesettings -selectforeground] userDefault
    }
    option add *TkFDialog*Menu.borderWidth 1 startupFile
    option add *TkFDialog*Menu.relief solid startupFile
}

# Borderless treeview
ttk::style configure Borderless.Treeview -borderwidth 0 -padding 1

# Create a treeview style without an indicator
ttk::style layout Listbox.Treeview {
    Treeview.padding -sticky nswe -children {
	Treeview.treearea -sticky nswe
    }
}
ttk::style configure Listbox.Treeview.Heading -padding {4 0}
ttk::style configure Listbox.Treeview.Item -padding {2 0}
ttk::style layout Listbox.Treeview.Item {
    Treeitem.padding -sticky nswe -children {
	Treeitem.image -side left -sticky {}
	Treeitem.focus -side left -sticky {} -children {
	    Treeitem.text -side left -sticky {}
	}
    }
}

# Helper megawidgets

::tk::Megawidget create ::ttk::fsdialog::FocusWidget ::tk::SimpleWidget {
    variable w hull options

    method GetSpecs {} {
	return {
	    {-cursor cursor Cursor {}}
	    {-takefocus takeFocus TakeFocus ::ttk::takefocus}
	}
    }

    method CreateHull {} {
	set hull [ttk::frame $w -style TEntry -padding 2]
	bind $w <FocusIn> [namespace code [list theWidget state focus]]
	bind $w <FocusOut> [namespace code [list theWidget state !focus]]
    }
}

::tk::Megawidget create ::ttk::fsdialog::dirlist ::ttk::fsdialog::FocusWidget {
    variable hull options
    destructor {
	my variable fd
	fswatch close $fd
	next
    }

    method GetSpecs {} {
	return {
	    {-cursor cursor Cursor {}}
	    {-height height Height 300}
	    {-takefocus takeFocus TakeFocus {}}
	    {-title {} {} {}}
	    {-width width Width 200}
	}
    }

    method CreateHull {} {
	my variable w
	next
	$w configure -height $options(-height) -width $options(-width)
	grid propagate $w 0
    }

    method Create {} {
	my variable options
	variable watch {}
	variable tv $hull.treeview
	ttk::treeview $tv -style Borderless.Treeview -selectmode browse \
	  -columns watch -displaycolumns {} \
	  -yscrollcommand [list $hull.vscroll set] \
	  -xscrollcommand [list $hull.hscroll set]
	if {$options(-title) eq ""} {
	    $tv configure -show tree
	} else {
	    $tv configure -show {tree headings}
	    $tv heading #0 -text $options(-title) -anchor w
	}
	$tv tag configure dir -image $::tk::Priv(folderImage)
	$tv column #0 -width 40 -stretch 1
	ttk::scrollbar $hull.vscroll -orient vertical \
	  -command [list $tv yview]
	ttk::scrollbar $hull.hscroll -orient horizontal \
	  -command [list $tv xview]
	grid $tv $hull.vscroll -sticky ns
	grid $hull.hscroll -sticky ew
	grid $tv -sticky nesw
	grid columnconfigure $hull $tv -weight 1
	grid rowconfigure $hull $tv -weight 1

	oo::define [self class] forward selection $tv selection

	bind $tv <Map> [list [namespace which my] Map %W]
	bind $tv <<TreeviewOpen>> [list [namespace which my] Open]
	bind $tv <<TreeviewClose>> [list [namespace which my] Close]
	bind $tv <<TreeviewSelect>> \
	  [list event generate $hull <<ListboxSelect>>]

	variable fd [fswatch create [list [namespace which my] Watch]]
    }

    method Build {path} {
	my variable tv
	if {![$tv exists $path]} {
	    set parent [file dirname $path]
	    if {$parent ne $path} {
		my Build $parent
	    } else {
		foreach n [file volumes] {
		    $tv insert {} end \
		      -id $n -text [file nativename $n] -tags dir
		    $tv insert $n end -id $n.
		}
	    }
	    if {![$tv exists $path]} {
		my Glob $parent {.* *}
	    }
	    my Glob $path
	}
    }

    method Open {} {
	my variable tv
	try {
	    set path [$tv focus]
	    if {![$tv tag has visited $path]} {
		my Glob $path
	    }
	    set dirpath {}
	    while {$path ne ""} {
		lappend dirpath $path
		set path [$tv parent $path]
	    }
	    $tv tag add open $dirpath
	    set dir [file nativename $path]
	} trap POSIX {- err} {
	    ttk::fsdialog::posixerror $tv [dict get $err -errorcode] \
	      {Cannot change to the directory "%s"} [file nativename $path]
	    after idle [list $tv item $path -open false]
	}
    }

    method Close {} {
	my variable tv
	$tv tag remove open [list [$tv focus]]
    }

    method Glob {dir {pat *}} {
	my variable tv fd watch
	set list [glob -nocomplain -directory $dir -tails -type d {*}$pat]
	set sort [lsort -dictionary $list]
	$tv delete [$tv children $dir]
	set w [$tv column #0 -width]
	set offs [expr {[llength [file split $dir]] * 20 + 40}]
	foreach d $sort {
	    if {$d in {. ..}} continue
	    if {[string match */ $dir]} {set id $dir$d} else {set id $dir/$d}
	    $tv insert $dir end -id $id -text $d -tags dir
	    set w [expr {max($w, $offs + [font measure TkDefaultFont $d])}]
	    if {[ttk::fsdialog::subdirs $id]} {
		$tv insert $id end -id [file join $id .]
	    }
	}
	$tv tag add visited [list $dir]
	if {[$tv set $dir watch] eq ""} {
	    set id [fswatch add $fd $dir \
	      {create delete move deleteself moveself}]
	    $tv set $dir watch $id
	    dict set watch $id $dir
	}
	$tv column #0 -width $w
    }

    method Watch {event} {
	my variable tv fd watch
	set id [dict get $event watch]
	if {[dict get $event isdir] == 0} {
	    if {[dict get $event event] eq "ignored"} {
		fswatch remove $fd $id
		dict unset watch $id
	    }
	    return
	}
	if {![dict exists $watch $id]} return
	set dir [dict get $watch $id]
	set name [dict get $event name]
	set node $dir/$name
	switch [dict get $event event] {
	    delete - movedfrom {
		set cwd [lindex [$tv selection] 0]
		$tv delete [list $node]
		while {![$tv exists $cwd]} {
		    if {$cwd eq [set cwd [file dirname $cwd]]} break
		    if {[$tv exists $cwd]} {
			$tv selection set [list $cwd]
		    }
		}
	    }
	    create - movedto {
		set list [lmap n [$tv children $dir] {$tv item $n -text}]
		set x [lsearch -bisect -dictionary $list $name]
		if {![$tv exists $node]} {
		    $tv insert $dir [incr x] -id $node \
		      -text $name -open 0 -tags dir
		}
		if {[ttk::fsdialog::subdirs $node]} {
		    $tv insert $node end -id [file join $node .]
		}
	    }
	}
    }

    method Map {tv} {
	# Make sure the selected directory is in view when the window
	# becomes visible for the first time
	bind $tv <Map> {}
	$tv see [lindex [$tv selection] 0]
    }

    method close {dir} {
	my variable tv
	$tv item $dir -open 0
	$tv tag remove open [list $dir]
    }

    method open {dir} {
	my variable tv
	$tv item $dir -open 1
	$tv focus $dir
	my Open
    }

    method set {dir} {
	my variable tv
	if {![$tv exists $dir]} {
	    if {[file isdirectory $dir]} {
		my Build [file normalize $dir]
	    } else {
		throw {POSIX ENOENT {no such file or directory}} \
		  "couldn't change working directory to \"$dir\":\
		  no such file or directory"
	    }
	}
	my open $dir
	$tv selection set [list $dir]
	$tv yview moveto 1
	$tv see $dir
    }

    method get {} {
	my variable tv
	return [lindex [$tv selection] 0]
    }

    method reload {} {
	my variable tv
	set cwd [lindex [$tv selection] 0]
	foreach dir [$tv tag has open] {
	    if {[$tv exists $dir]} {
		$tv item $dir -open 1
		$tv tag add open [list $dir]
		my Glob $dir
	    }
	}
	while {![$tv exists $cwd]} {
	    if {$cwd eq [set cwd [file dirname $cwd]]} return
	}
	my set $cwd
    }

    forward state theWidget state
}

::tk::Megawidget create ::ttk::fsdialog::FileList {} {
    constructor {args} {
	namespace path [linsert [namespace path] end ::ttk::fsdialog]
	next {*}$args
    }

    destructor {
	my variable fd
	fswatch close $fd
	next
    }

    method GetSpecs {} {
	return {
	    {-command "" "" ""}
	    {-cursor "" "" ""}
	    {-filter "" "" *}
	    {-font "" "" "TkIconFont"}
	    {-hidden "" "" 0}
	    {-mixed "" "" files}
	    {-multiple "" "" 0}
	    {-reverse "" "" 0}
	    {-sortkey "" "" name}
	}
    }

    method Create {} {
	variable files {} watchid {} modified {}
	variable fd [fswatch create [list [namespace which my] Watch]]
    }

    method Watch {event} {
	my variable fd modified options
	switch [dict get $event event] {
	    delete - movedfrom {
		my Delete [dict get $event name]
	    }
	    create - movedto {
		if {![dict get $event isdir] || $options(-mixed) ne "files"} {
		    my Insert [dict get $event name]
		}
	    }
	    attrib {
		my Update [dict get $event name]
	    }
	    modify - closewrite {
		set name [dict get $event name]
		if {$name ni $modified} {
		    lappend modified $name
		}
	    }
	}
    }

    method Hidden {name} {
	my variable cwd
	global tcl_platform
	if {$tcl_platform(platform) eq "unix"} {
	    return [expr {[string index $name 0] eq "."}]
	} else {
	    set attr [file attributes [jojnfile $cwd $name]]
	    return [dict get $attr -hidden]
	}
    }

    method Delete {name} {
	my variable files
	set files [lsearch -all -inline -exact -not -index 0 $files $name]
    }

    method Insert {name} {
	my variable cwd files sortargs
	try {
	    set file [joinfile $cwd $name]
	    set new [my FileStat $name [my Hidden $name]]
	    set val [lindex $new [lindex $sortargs 1]]
	    set x [lsearch -bisect {*}$sortargs $files $val]
	    set files [linsert $files [incr x] $new]
	    return $new
	} on error {- err} {
	    # puts [dict get $err -errorinfo]
	    return
	}
    }

    method Update {name} {
	my variable files
	try {
	    set new [my FileStat $name [my Hidden $name]]
	    set x [lsearch -index 0 -exact $files $name]
	    lset files $x $new
	    return $new
	} on error {- err} {
	    # puts [dict get $err -errorinfo]
	    return
	}
    }

    method FileStat {name hidden} {
	file stat $name stat
	if {$stat(type) eq "directory"} {
	    set type dir
	} else {
	    set type file
	}
	if {$hidden} {
	    set hide hidden
	} else {
	    set hide $type
	}
	return [list [regsub {^\./} [file tail $name] {}] $stat(size) \
	  $stat(mtime) $stat(mode) $stat(uid) $stat(gid) $type $hide]
    }

    method SortFiles {} {
	my variable files options sortargs modified

	# Update any modified files
	foreach n $modified {
	    set x [lsearch -index 0 -exact $files $n]
	    if {$x >= 0} {lset files $x [my FileStat $n [my Hidden $n]]}
	}
	set modified {}

	switch $options(-sortkey) {
	    date {
		set sortargs [list -index 2 -integer]
	    }
	    size {
		set sortargs [list -index 1 -integer]
	    }
	    default {
		set sortargs [list -index 0 -dictionary]
	    }
	}
	if {$options(-reverse)} {
	    lappend sortargs -decreasing
	}
	set files [lsort {*}$sortargs $files]
	my Refresh
    }

    method Refresh {} {
	set sel [my selection get]
	my Display [my Filter]
	my selection set $sel
    }

    method Filter {} {
	my variable files options
	if {$options(-hidden)} {
	    if {$options(-mixed) ne "files"} {
		set list $files
	    } else {
		set list [lsearch -all -inline -index 6 -exact $files file]
	    }
	} elseif {$options(-mixed) eq "files"} {
	    set list [lsearch -all -inline -index 7 -exact $files file]
	} else {
	    set list [lsearch -all -inline -index 7 -exact -not $files hidden]
	}
	if {$options(-mixed) eq "split"} {
	    set list [lsort -index 6 $list]
	}
	if {$options(-filter) eq "*"} {
	} elseif {$options(-mixed) eq "files"} {
	    set list [lsearch -all -inline -index 0 $list $options(-filter)]
	} else {
	    set keep [lsearch -all -index 0 $list $options(-filter)]
	    set k [lindex $keep [set x 0]]
	    set i -1
	    set list [lmap n $list {
		if {[incr i] == $k} {
		    set k [lindex $keep [incr x]]
		} elseif {[lindex $n 6] eq "file"} {
		    continue
		}
		set n
	    }]
	}
	return $list
    }

    method configure {args} {
	my variable options files
	set save [array get options]
	set rc [next {*}$args]
	dict for {key val} $save {
	    if {$options($key) eq $val} {dict unset save $key}
	}
	if {[dict exists $save -sortkey]} {
	    my SortFiles
	} elseif {[dict exists $save -reverse]} {
	    set files [lreverse $files]
	}
	if {[dict size [dict remove $save -cursor -multiple -sortkey]]} {
	    my Refresh
	}
	return $rc
    }

    method changedir {dir} {
	my variable cwd files fd watchid modified
	set modified {}
	if {$watchid ne ""} {
	    fswatch remove $fd $watchid
	}
	set cwd [file join [pwd] [file normalize $dir]]
	set files {}
	foreach n [glob -nocomplain -directory $cwd *] {
	    # Dangling symbolic links may produce an error
	    catch {lappend files [my FileStat $n 0]}
	}
	foreach n [glob -nocomplain -directory $cwd -types hidden *] {
	    catch {lappend files [my FileStat $n 1]}
	}
	set watchid [fswatch add $fd $cwd \
	  {create delete move attrib closewrite modify}]
	my SortFiles
    }

    method clear {} {
	my variable fd watchid
	if {$watchid ne ""} {
	    fswatch remove $fd $watchid
	    set watchid ""
	}
    }

    method invoke {} {
	my variable options
	if {$options(-command) ne "" && [llength [my selection]]} {
	    uplevel #0 $options(-command)
	}
    }
}

auto_load tk::IconList

::tk::Megawidget create ::ttk::fsdialog::ShortFileList \
  {::ttk::fsdialog::FileList tk::IconList} {
    method Create {} {
	my variable parts image
	set parts {}
	dict set image dir $::tk::Priv(folderImage)
	dict set image file $::tk::Priv(fileImage)
	next
	nextto tk::IconList
    }

    method Update {name} {
	my variable modified
	if {$name ni $modified} {lappend modified $name}
    }

    method Display {list} {
	my variable image options
	set names [lmap n $list {lindex $n 0}]
	my deleteall
	my add [dict get $image file] $names
	if {$options(-mixed) ne "files"} {
	    set img [dict get $image dir]
	    foreach n [lsearch -all -index 6 -exact $list dir] {
		my ItemImage $n $img
	    }
	}
    }

    method ItemImage {item image} {
	my variable canvas list
	set iTag [lindex $list $item 0]
	$canvas itemconfigure $iTag -image $image
    }

    method Position {str} {
	my variable itemList
	set rec [lsearch -index 2 -exact -inline \
	  [dict values [array get itemList]] $str]
	return [lindex $rec 3]
    }

    method SelectRange {item1 item2} {
	set i1 [my index $item1]
	set i2 [my index $item2]
	if {$i1 eq "" || $i2 eq ""} return
	if {$i1 > $i2} {lassign [list $i2 $i1] i1 i2}
	set items {}
	for {set j $i1} {$j <= $i2} {incr j} {
	    lappend items [my get $j]
	}
	my selection set $items
    }

    method Btn1 {x y} {
	my variable canvas
	focus $canvas
	set i [my index @$x,$y]
	if {$i eq ""} return
	my selection set [list [my get $i]]
	my selection anchor $i
    }

    method CtrlBtn1 {x y} {
	my variable options canvas
	if {$options(-multiple)} {
	    focus $canvas
	    set i [my index @$x,$y]
	    if {$i eq ""} return
	    set str [my get $i]
	    if {$str in [my selection]} {
		my selection remove [list $str]
	    } else {
		my selection add [list $str]
		my selection anchor $i
	    }
	} else {
	    my Btn1 $x $y
	}
    }

    method ShiftBtn1 {x y} {
	my variable options canvas
	if {$options(-multiple)} {
	    focus $canvas
	    set i [my index @$x,$y]
	    if {$i eq ""} return
	    if {[my index anchor] eq ""} {
		my selection anchor $i
	    }
	    my SelectRange anchor $i
	} else {
	    my Btn1 $x $y
	}
    }

    method Motion1 {x y} {
	variable oldX $x oldY $y
	set i [my index @$x,$y]
	if {$i eq ""} return
	my selection set [list [my get $i]]
    }

    method ShiftMotion1 {x y} {
	variable oldX $x oldY $y
	set i [my index @$x,$y]
	if {$i eq ""} return
	my SelectRange anchor $i
    }

    method FocusOut {} {
	my state !focus
    }

    method deleteall {} {
	my variable canvas sbar index selected rect list itemList
	my variable maxIW maxIH maxTW maxTH numItems noScroll selection
	$canvas delete all
	unset -nocomplain selected rect list itemList
	set maxIW 1
	set maxIH 1
	set maxTW 1
	set maxTH 1
	set numItems 0
	set noScroll 1
	set selection {}
	set index(anchor) ""
    }

    method deleteall {} {
	my variable canvas sbar
	set xview [$canvas xview]
	next
	$canvas xview moveto [lindex $xview 0]
    }

    method image {type img} {
	my variable image
	dict set image $type $img
    }

    method clear {} {
	my deleteall
	next
    }

    method exists {item} {
	return [expr {[my Position $item] ne ""}]
    }

    method selection {{method get} {items {}}} {
	switch $method {
	    get {
		return [lmap n [next $method $items] {my get $n}]
	    }
	    set - add {
		if {$method eq "set"} {next clear 0 end}
		foreach n $items {
		    set x [my Position $n]
		    if {$x ne ""} {next set $x}
		}
	    }
	    anchor {
		return [next $method {*}$items]
	    }
	}
    }

    method see {item} {
	next [my Position $item]
    }

    unexport add deleteall
}

::tk::Megawidget create ::ttk::fsdialog::LongFileList \
  {::ttk::fsdialog::FileList ::ttk::fsdialog::FocusWidget} {
    method Create {} {
	my variable w tv options
	variable owner {} group {} perm {} timeformat {%Y-%m-%d %T}
	variable sort {item none dir down}

	next
	set tv [ttk::treeview $w.tv -style Listbox.Treeview \
	  -yscrollcommand [list $w.vs set] -xscrollcommand [list $w.hs set] \
	  -columns {size date perm owner group filler}]
	if {$::tcl_platform(platform) eq "windows"} {
	    $tv configure -displaycolumns {size date perm}
	}
	oo::define [self class] forward exists $tv exists
	ttk::scrollbar $w.vs -orient vertical \
	  -command [list $tv yview]
	ttk::scrollbar $w.hs -orient horizontal \
	  -command [list $tv xview]
	grid $tv $w.vs -sticky ns
	grid $tv -sticky nesw
	grid $w.hs -sticky ew
	grid columnconfigure $w $tv -weight 1
	grid rowconfigure $w $tv -weight 1
	$tv heading #0 -text [mc Name] -anchor w \
	  -command [namespace code [list my ToggleSort name]]
	$tv column #0 -stretch 0
	$tv heading size -text [mc Size] -anchor w \
	  -command [namespace code [list my ToggleSort size]]
	$tv column size -width 100 -anchor e -stretch 0
	$tv heading date -text [mc Date] -anchor w \
	  -command [namespace code [list my ToggleSort date]]
	$tv column date -width [fontwidth TkDefaultFont \
	  [clock format 0 -format *$timeformat*]] -stretch 0
	$tv heading perm -text [mc Permissions] -anchor w
	$tv column perm -stretch 0 \
	  -width [fontwidth TkDefaultFont *[mc Permissions]* drwxrwxrwx]
	$tv heading owner -text [mc Owner] -anchor w
	$tv column owner -stretch 0 \
	  -width [fontwidth TkDefaultFont *[mc Owner]*]
	$tv heading group -text [mc Group] -anchor w
	$tv column group -stretch 0 \
	  -width [fontwidth TkDefaultFont *[mc Group]*]
	$tv column filler -width 0 -minwidth 0 -stretch 1

	$tv tag configure dir -image $::tk::Priv(folderImage)
	$tv tag configure file -image $::tk::Priv(fileImage)

	bind $tv <<TreeviewSelect>> \
	  [list event generate $w <<ListboxSelect>>]
	bind $tv <Double-1> "[list [namespace which my] invoke];break"
    }

    method Owner {file uid gid} {
	my variable cwd owner group
	if {![dict exists $owner $uid] || ![dict exists $group $gid]} {
	    set attr [file attributes [joinfile $cwd $file]]
	    if {[dict exists $attr -owner]} {
		dict set owner $uid [dict get $attr -owner]
	    } else {
		dict set owner $uid $uid
	    }
	    if {[dict exists $attr -group]} {
		dict set group $gid [dict get $attr -group]
	    } else {
		dict set group $gid $gid
	    }
	}
	return [list [dict get $owner $uid] [dict get $group $gid]]
    }

    method Permissions {type mode} {
	my variable perm
	if {![dict exists $perm $type $mode]} {
	    if {$type eq "file"} {
		set str -
	    } else {
		set str [string index $type 0]
	    }
	    set chars {r w x r w x r w x}
	    if {$mode & 0o4000} {lset chars 2 s}
	    if {$mode & 0o2000} {lset chars 5 s}
	    if {$mode & 0o1000} {lset chars 8 t}
	    set bits [split [format %09b [expr {$mode & 0o777}]] {}]
	    foreach b $bits c $chars {
		if {$b} {append str $c} else {append str -}
	    }
	    dict set perm $type $mode $str
	} 
	return [dict get $perm $type $mode]
    }

    method Values {rec} {
	my variable timeformat
	lassign $rec name size time mode uid gid type
	set perm [my Permissions $type $mode]
	set date [clock format $time -format $timeformat]
	lassign [my Owner $name $uid $gid] owner group
	return [list $name $type $size $date $perm $owner $group]
    }

    method Display {list} {
	my variable tv
	$tv delete [$tv children {}]
	foreach n $list {
	    set values [lassign [my Values $n] name type]
	    $tv insert {} end -id $name -text $name -tags $type -values $values
	}
    }

    method Delete {name} {
	my variable tv
	if {[$tv exists $name]} {
	    $tv delete $name
	}
	next $name
    }

    method Insert {name} {
	my variable tv
	set rec [next $name]
	if {[llength $rec] == 0} return
	set list [my Filter]
	set x [lsearch -index 0 -exact $list $name]
	if {$x < 0} return
	set values [lassign [my Values $rec] name type]
	$tv insert {} $x -id $name -text $name -tags $type -values $values
    }

    method Update {name} {
	my variable tv options
	set rec [next $name]
	if {[llength $rec] == 0} return
	if {[$tv exists $name]} {
	    set old [linsert [$tv item $name -values] 0 [$tv item $name -text]]
	    $tv item $name -values [lassign [my Values $rec] - -]
	    set x [dict get {name 0 size 1 date 2} $options(-sortkey)]
	    if {[lindex $rec $x] != [lindex $old $x]} {
		my SortFiles
	    }
	}
    }

    method ToggleSort {column} {
	my variable w options
	dict set opts -sortkey $column
	dict set opts -reverse \
	  [expr {$options(-sortkey) eq $column && !$options(-reverse)}]
	my configure {*}$opts
	event generate $w <<FileListSort>>
    }

    method configure {args} {
	my variable tv options
	set sortkey $options(-sortkey)
	next {*}$args
	if {$options(-sortkey) ne $sortkey} {
	    if {$sortkey ni [$tv cget -columns]} {
		$tv heading #0 -image {}
	    } else {
		$tv heading $sortkey -image {}
	    }
	}
	if {$options(-reverse)} {
            set image $::tk::Priv(sortupImage)
        } else {
            set image $::tk::Priv(sortdownImage)
        }
	if {$options(-sortkey) ni [$tv cget -columns]} {
	    $tv heading #0 -image $image
	} else {
	    $tv heading $options(-sortkey) -image $image
	}
	if {$options(-multiple)} {
	    $tv configure -selectmode extended
	} else {
	    $tv configure -selectmode browse
	}
    }

    method clear {} {
	my variable tv
	$tv delete [$tv children {}]
	next
    }

    method selection {{method get} {items {}}} {
	# oo::objdefine [self] forward selection $tv selection
	my variable tv
	switch $method {
	    get {
		return [$tv selection]
	    }
	    default {
		$tv selection $method [lmap n $items {
		    if {![$tv exists $n]} continue
		    set n
		}]
	    }
	}
    }

    method see {item} {
	my variable tv
	if {[$tv exists $item]} {$tv see $item}
    }
}

::tk::Megawidget create ::ttk::fsdialog::chooseDirectory {} {
    constructor {args} {
	variable result ""
	namespace path [linsert [namespace path] end ::ttk::fsdialog]
	next {*}$args
    }

    destructor {
	my variable options result
	next
	savecfg
	uplevel #0 [list set $options(-resultvariable) $result]
    }

    method GetSpecs {} {
	return {
	    {-initialdir "" "" ""}
	    {-parent "" "" ""}
	    {-resultvariable "" "" ""}
	    {-title "" "" ""}
	}
    }

    method CreateHull {} {
	my variable w hull
	toplevel $w -class TkFDialog
	# The framework will add a <Destroy> binding to the hull widget. This
	# means the hull widget should never be a toplevel, because a toplevel
	# widget receives <Destroy> events for all of its children.
	place [set hull [ttk::frame $w.bg]] -relwidth 1 -relheight 1
	wm protocol $w WM_DELETE_WINDOW [list [namespace which my] Cancel]
    }

    method Create {} {
	my variable w options cwd
	namespace upvar ::tk Priv img

	wm geometry $w [dict get [readcfg] dirdialog geometry]

	variable toolbar [ttk::frame $w.toolbar]
	set list [histdirs]
	foreach n [file volumes] {if {$n ni $list} {lappend list $n}}
	variable dirbox [ttk::matchbox $w.toolbar.dir \
	  -matchcommand [list [namespace which my] DirMatchCommand] \
	  -textvariable [my varname dir] \
	  -values [lmap n $list {file nativename $n}]]
	foreach n {home reload newfolder} {
	    set image [list $img(${n}Image)]
	    if {[info exists img(${n}DimImage)]} {
		lappend image disabled $img(${n}DimImage)
	    }
	    ttk::button $w.toolbar.$n -style Toolbutton -image $image \
	      -command [list [namespace which my] Button[string totitle $n]]
	    pack $w.toolbar.$n -side left
	}
	pack $toolbar.dir -fill x -expand 1 -padx 2
	grid $toolbar -sticky news -padx 2
	grid [ttk::separator $w.sep] -padx 0 -pady 2 -sticky ew
	variable dirlist [dirlist $w.list -width 400 \
	  -title Folder]
	grid $w.list -sticky news -padx 4 -pady 2
	grid columnconfigure $w all -weight 1
	grid rowconfigure $w $w.list -weight 1
	ttk::frame $w.buttonbar
	ttk::button $w.buttonbar.cancel -text [mc Cancel] -width 0 \
	  -command [list [namespace which my] Cancel]
	ttk::button $w.buttonbar.ok -text [mc OK] -width 0 \
	  -command [list [namespace which my] Done]
	grid $w.buttonbar.cancel $w.buttonbar.ok -padx 4 -pady 4 -sticky ew
	grid columnconfigure $w.buttonbar all -uniform buttons
	grid $w.buttonbar -sticky e

	if {$options(-title) ne ""} {
	    wm title $w $options(-title)
	} else {
	    wm title $w "Choose Directory"
	}
	set cwd [file normalize [file join . $options(-initialdir)]]
	$dirlist set $cwd
	$dirbox set [file nativename $cwd]
	$dirbox icursor end
	$dirbox xview moveto 1
	$dirbox validate

	bind $dirbox <<MatchSelected>> \
	  [namespace code {my ChangeDir [%W get]}]
	bind $dirbox <<MismatchSelected>> \
	  [namespace code {my ChangeDir [%W get]}]
	bind $dirbox <<ComboboxSelected>> \
	  [namespace code {my ChangeDir [%W get]}]
	bind $dirlist <<ListboxSelect>> \
	  [namespace code {my ChangeDir [%W get]}]
    }

    method GlobEscape {str} {
	set map {\\ \\\\ ? \\? * \\* [ \\[ ] \\] \{ \\\{ \} \\\}}
	return [string map $map $str]
    }

    method DirMatchCommand {str} {
	set str [file normalize $str]
	if {[string index $str 0] ni {{} ~} } {
	    set esc [my GlobEscape $str]
	    set list [lsort -dictionary [glob -nocomplain -types d -- $esc*]]
	    return [lmap n $list {file nativename $n}]
	}
    }

    method ChangeDir {dir} {
	my variable cwd dirlist dirbox
	try {
	    set path [file join $cwd [file normalize $dir]]
	    set dir [file nativename $path]
	    if {$path ne $cwd} {
		$dirlist set $path
		set cwd $path
	    } else {
		$dirbox set $dir
		$dirbox icursor end
		$dirbox xview moveto 1
		$dirbox validate
	    }
	} trap POSIX {- err} {
	    posixerror $dirlist [dict get $err -errorcode] \
	      {Cannot change to the directory "%s"} $dir
	}
	return $cwd
    }

    method ReloadDir {} {
	my variable dirlist
	$dirlist reload
    }

    method ButtonHome {} {
	my ChangeDir [file normalize ~]
    }

    method ButtonReload {} {
	my ReloadDir
    }

    method ButtonNewfolder {} {
	my variable w cwd dirlist
	set top [toplevel $w.new]
	place [ttk::frame $top.b] -relwidth 1 -relheight 1
	wm transient $top $w
	wm title $top [mc "New Folder"]
	ttk::label $top.l \
	  -text "[mc {Create new folder in}]:\n[file nativename $cwd]"
	grid $top.l -columnspan 4 -sticky ew -padx 8 -pady {8 0}
	ttk::entrybox $top.e -width 40
	grid $top.e -columnspan 4 -sticky ew -padx 8 -pady 4
	ttk::separator $top.sep
	grid $top.sep -columnspan 4 -sticky ew -padx 8 -pady 4
	ttk::button $top.b1 -width 0 -text [mc Cancel] \
	  -command [list destroy $top]
	ttk::button $top.b2 -width 0 -text [mc OK] \
	  -command [list [namespace which my] MakeDir $top.e]
	grid x $top.b1 $top.b2 x -padx 12 -sticky ew -pady {4 12}
	grid columnconfigure $top all -weight 1
	grid columnconfigure $top [list $top.b1 $top.b2] \
	  -uniform buttons -weight 0
	grab $top
	wm resizable $top 0 0
	focus $top.e

	bind $top.e <Escape> [list $top.b1 invoke]
	bind $top.e <Return> [list $top.b2 invoke]
    }

    method MakeDir {e} {
	my variable w cwd
	try {
	    set dir [file normalize [joinfile $cwd [$e get]]]
	    set name [file tail $dir]
	    file mkdir $dir
	    destroy [winfo toplevel $e]
	    my ChangeDir $dir
	} trap POSIX {- err} {
	    posixerror $e [dict get $err -errorcode] \
	      {Cannot create directory "%s"} [file nativename $dir]
	}
    }

    method Done {} {
	my variable cwd result
	set result $cwd
	history $result
	my Cancel
    }

    method Cancel {} {
	my variable w
	set geometry [lindex [split [wm geometry $w] +] 0]
	geometry dirdialog geometry $geometry
	my destroy
    }
}

::tk::Megawidget create ::ttk::fsdialog::getSaveFile \
  ::ttk::fsdialog::chooseDirectory {
    variable options

    destructor {
	set ::tk::Priv(button) ""
	next
    }

    method GetSpecs {} {
	return {
	    {-confirmoverwrite "" "" "1"}
	    {-defaultextension "" "" ""}
	    {-filetypes "" "" ""}
	    {-initialdir "" "" ""}
	    {-initialfile "" "" ""}
	    {-parent "" "" ""}
	    {-title "" "" ""}
	    {-typevariable "" "" ""}
	    {-resultvariable "" "" ""}
	}
    }

    method CreateHull {} {
	my variable w hull
	toplevel $w -class TkFDialog
	# The framework will add a <Destroy> binding to the hull widget. This
	# means the hull widget should never be a toplevel, because a toplevel
	# widget receives <Destroy> events for all of its children.
	place [set hull [ttk::frame $w.bg]] -relwidth 1 -relheight 1
	wm protocol $w WM_DELETE_WINDOW [list [namespace which my] Cancel]
    }

    method Create {{title {Save As}} {action Save}} {
	my variable w dir cwd filter pref
	variable text {} files {} owner {} group {} result {}
	array set pref [dict get [readcfg] prefs]
	namespace upvar ::tk Priv img

	set geometry [geometry filedialog]
	wm geometry $w [dict get $geometry geometry]

	# Build the toolbar
	variable toolbar [ttk::frame $w.toolbar]
	foreach n {up prev next home reload newfolder} {
	    set image [list $img(${n}Image)]
	    if {[info exists img(${n}DimImage)]} {
		lappend image disabled $img(${n}DimImage)
	    }
	    ttk::button $w.toolbar.$n -style Toolbutton -image $image \
	      -command [list [namespace which my] Button[string totitle $n]]
	    pack $w.toolbar.$n -side left
	}
	ttk::menubutton $w.toolbar.options -style Toolbutton \
	  -image [list $img(optionsmenuImage)]
	$w.toolbar.options configure \
	  -menu [menu $w.toolbar.options.menu -tearoff 0]
	$w.toolbar.options.menu add cascade -label " [mc Sorting]" \
	  -compound left -image ::ttk::fsdialog::blank16 \
	  -menu [menu $w.toolbar.options.menu.sort -tearoff 0]
	$w.toolbar.options.menu add separator
	$w.toolbar.options.menu add radiobutton -label [mc "Short View"] \
	  -compound left -image ::ttk::fsdialog::blank16 -indicatoron 0 \
	  -selectimage ::ttk::fsdialog::radio16 \
	  -variable [my varname pref(details)] -value 0 \
	  -command [list [namespace which my] Layout]
	$w.toolbar.options.menu add radiobutton -label [mc "Detailed View"] \
	  -compound left -image ::ttk::fsdialog::blank16 -indicatoron 0 \
	  -selectimage ::ttk::fsdialog::radio16 \
	  -variable [my varname pref(details)] -value 1 \
	  -command [list [namespace which my] Layout]
	$w.toolbar.options.menu add separator
	$w.toolbar.options.menu add checkbutton -label [mc "Show Hidden Files"] \
	  -compound left -image ::ttk::fsdialog::blank16 -indicatoron 0 \
	  -selectimage ::ttk::fsdialog::check16 \
	  -variable [my varname pref(hidden)] \
	  -command [list [namespace which my] Reconfigure]
	$w.toolbar.options.menu add checkbutton -label [mc "Separate Folders"] \
	  -compound left -image ::ttk::fsdialog::blank16 -indicatoron 0 \
	  -selectimage ::ttk::fsdialog::check16 \
	  -variable [my varname pref(duopane)] \
	  -command [list [namespace which my] Layout]
	$w.toolbar.options.menu.sort add radiobutton -label [mc "By Name"] \
	  -compound left -image ::ttk::fsdialog::blank16 -indicatoron 0 \
	  -selectimage ::ttk::fsdialog::radio16 \
	  -variable [my varname pref(sort)] -value name \
	  -command [list [namespace which my] Reconfigure]
	$w.toolbar.options.menu.sort add radiobutton -label [mc "By Date"] \
	  -compound left -image ::ttk::fsdialog::blank16 -indicatoron 0 \
	  -selectimage ::ttk::fsdialog::radio16 \
	  -variable [my varname pref(sort)] -value date \
	  -command [list [namespace which my] Reconfigure]
	$w.toolbar.options.menu.sort add radiobutton -label [mc "By Size"] \
	  -compound left -image ::ttk::fsdialog::blank16 -indicatoron 0 \
	  -selectimage ::ttk::fsdialog::radio16 \
	  -variable [my varname pref(sort)] -value size \
	  -command [list [namespace which my] Reconfigure]
	$w.toolbar.options.menu.sort add separator
	$w.toolbar.options.menu.sort add checkbutton -label [mc "Reverse"] \
	  -compound left -image ::ttk::fsdialog::blank16 -indicatoron 0 \
	  -selectimage ::ttk::fsdialog::check16 \
	  -variable [my varname pref(reverse)] \
	  -command [list [namespace which my] Reconfigure]
	$w.toolbar.options.menu.sort add checkbutton -label [mc "Folders First"] \
	  -compound left -image ::ttk::fsdialog::blank16 -indicatoron 0 \
	  -selectimage ::ttk::fsdialog::check16 \
	  -variable [my varname pref(mixed)] -onvalue 0 -offvalue 1 \
	  -command [list [namespace which my] Reconfigure]
	pack $w.toolbar.options -side left
	$w.toolbar.prev state disabled
	$w.toolbar.next state disabled
	set list [histdirs]
	foreach n [file volumes] {if {$n ni $list} {lappend list $n}}
	variable dirbox [ttk::matchbox $w.toolbar.dir \
	  -matchcommand [list [namespace which my] DirMatchCommand] \
	  -textvariable [my varname dir] \
	  -values [lmap n $list {file nativename $n}]]
	pack $dirbox -fill x -expand 1 -padx 2 -pady 2
	grid $w.toolbar - - -sticky ew

	ttk::separator $w.separator
	grid $w.separator - - -sticky ew

	# Build the file area
	ttk::panedwindow $w.filearea -orient horizontal -width 700 -height 400
	ttk::label $w.fnlab -anchor e -text [mc Location]:
	variable dirlist [dirlist $w.filearea.dirs -width 250]
	ShortFileList $w.filearea.files -command [list $w.openbutton invoke]
	LongFileList $w.filearea.details -command [list $w.openbutton invoke]
	if {$pref(duopane)} {
	    $w.filearea add $dirlist
	    bind $w.filearea <Map> \
	      [list $w.filearea sashpos 0 [dict get $geometry sashpos]]
	    bind $w.filearea <Map> +[list bind $w.filearea <Map> {}]
	}
	if {$pref(details)} {
	    variable filelist $w.filearea.details
	} else {
	    variable filelist $w.filearea.files
	}
	$w.filearea add $filelist
	grid $w.filearea - - -sticky nesw -padx 2 -pady 2
	grid rowconfigure $w $w.filearea -weight 1

	# Build the control area
	ttk::matchbox $w.fnent -textvariable [my varname text] -validate key \
	  -validatecommand [list [namespace which my] FileValidate %P] \
	  -matchcommand [list [namespace which my] FileMatchCommand]
	ttk::label $w.ftlab -anchor e -text [mc Filter]:
	ttk::matchbox $w.ftent -textvariable [my varname filter]
	ttk::button $w.openbutton -width 0 \
	  -command [list [namespace which my] Done]
	ttk::button $w.cancbutton -width 0 -text [mc Cancel] \
	  -command [list [namespace which my] Cancel]
	variable types [::tk::FDGetFileTypes $options(-filetypes)]
	if {[llength $types] == 0} {
	    set options(-filetypes) [list [list [mc {All files}] *]]
	    set types [::tk::FDGetFileTypes $options(-filetypes)]
	}
	$w.ftent configure -values [lmap n $types {lindex $n 0}]
	set select 0
	if {$options(-typevariable) ne ""} {
	    upvar #0 $options(-typevariable) type
	    if {[info exists type]} {
		set select [lsearch -exact -index 0 $options(-filetypes) $type]
		if {$select < 0} {$w.ftent set $type}
	    }
	}
	if {$select >= 0} {$w.ftent current $select}
	grid $w.fnlab $w.fnent $w.openbutton -sticky ew -padx 2 -pady 2
	grid $w.ftlab $w.ftent $w.cancbutton -sticky ew -padx 2
	grid columnconfigure $w $w.fnent -weight 1

	if {$options(-title) ne ""} {
	    wm title $w $options(-title)
	} else {
	    wm title $w [mc $title]
	}
	$w.openbutton configure -text [mc $action]

	set cwd [file normalize $options(-initialdir)]
	if {![file isdirectory $cwd]} {set cwd [pwd]}
	$w.fnent set $options(-initialfile)
	my SelectFilter $w.ftent
	my Reconfigure
	variable trail [list $cwd] pos 0
	my TrailPos $pos

	# Bindings
	bind $w.fnent <Return> [list $w.openbutton invoke]
	bind $w.fnent <<MatchSelected>> \
	  [list [namespace which my] SelectFile %W]
	bind $w.ftent <<MatchSelected>> \
	  [list [namespace which my] SelectFilter %W]
	bind $w.ftent <<MismatchSelected>> \
	  [list [namespace which my] SelectFilter %W]
	bind $w.ftent <<ComboboxSelected>> \
	  [list [namespace which my] SelectFilter %W]
	bind $dirbox <<MatchSelected>> \
	  [namespace code {my ChangeDir [%W get]}]
	bind $dirbox <<MismatchSelected>> \
	  [namespace code {my ChangeDir [%W get]}]
	bind $dirbox <<ComboboxSelected>> \
	  [namespace code {my ChangeDir [%W get]}]
	bind $dirlist <<ListboxSelect>> \
	  [namespace code {my ChangeDir [%W get]}]
	bind $w.filearea.files <<ListboxSelect>> \
	  [list after idle [list [namespace which my] ListBrowse 1]]
	bind $w.filearea.details <<ListboxSelect>> \
	  [list [namespace which my] ListBrowse 2]
	bind $w.filearea.details <<FileListSort>> \
	  [list [namespace which my] UpdateSortPrefs %W]
    }

    method ListBrowse {args} {
	my variable w cwd text filelist
	set list [$filelist selection]
	if {[llength $list] != 1} return
	set file [lindex $list 0]
	set path [joinfile $cwd $file]
	if {[file isdirectory $path]} {
	    my ChangeDir $path
	} else {
	    set text $file
	}
    }

    method ButtonUp {} {
	my variable cwd
	my ChangeDir [file dirname $cwd]
    }

    method ButtonPrev {} {
	my variable pos
	if {$pos > 0} {
	    my TrailPos [incr pos -1]
	}
    }

    method ButtonNext {} {
	my variable trail pos
	if {$pos < [llength $trail] - 1} {
	    my TrailPos [incr pos]
	}
    }

    method SelectFile {win} {
	my variable cwd text
	set file [joinfile $cwd [$win get]]
	if {[file isdir $file]} {
	    my ChangeDir $file
	    set text ""
	} else {
	    $win validate
	}
    }

    method SelectFilter {win} {
	my variable w types filelist text
	set type [$win current]
	if {$type < 0} {
	    set pat [$win get]
	} else {
	    set pat [lindex $types $type 1]
	}
	$filelist configure -filter $pat

	set values [lsearch -all -inline [histfiles] $pat]
	$w.fnent configure -values $values
	my FileValidate $text
    }

    method ChangeDir {dir} {
	my variable cwd trail pos
	if {$cwd ne [next $dir]} {
	    set trail [lrange $trail 0 $pos]
	    lappend trail $cwd
	    my TrailPos [incr pos]
	}
    }

    method TrailPos {index} {
	my variable cwd trail pos toolbar dirbox dirlist
	set pos $index
	$dirlist set [lindex $trail $pos]
	set cwd [$dirlist get]
	$dirbox set [file nativename $cwd]
	$dirbox icursor end
	$dirbox xview moveto 1
	$dirbox validate
	if {[file dirname $cwd] ne $cwd} {
	    $toolbar.up state !disabled
	} else {
	    $toolbar.up state disabled
	}
	if {$pos > 0} {
	    $toolbar.prev state !disabled
	} else {
	    $toolbar.prev state disabled
	}
	if {$pos < [llength $trail] - 1} {
	    $toolbar.next state !disabled
	} else {
	    $toolbar.next state disabled
	}
	my ReloadDir
    }

    method ReloadDir {} {
	my variable w filelist cwd types
	try {
	    next
	    set type [$w.ftent current]
	    if {$type < 0} {
		set pat [$w.ftent get]
	    } else {
		set pat [lindex $types $type 1]
	    }
	    $filelist changedir $cwd
	    my FileValidate [$w.fnent get]
	} trap POSIX {- err} {
	    posixerror $w [dict get $err -errorcode] \
	      {Cannot change to the directory "%s"} $cwd
	}
    }

    method Reconfigure {} {
	my variable filelist pref
	if {$pref(duopane)} {
	    set show files
	} elseif {$pref(mixed)} {
	    set show mixed
	} else {
	    set show split
	}
	$filelist configure -sortkey $pref(sort) -reverse $pref(reverse) \
	  -hidden $pref(hidden) -mixed $show
	preferences {*}[array get pref]
    }

    method Layout {} {
	my variable w pref dirlist filelist
	set panes [$w.filearea panes]
	if {$pref(duopane)} {
	    if {$dirlist ni $panes} {
		$w.filearea insert 0 $dirlist
		$w.filearea sashpos 0 [geometry filedialog sashpos]
	    }
	} else {
	    if {$dirlist in $panes} {
		geometry filedialog sashpos [$w.filearea sashpos 0]
		$w.filearea forget $dirlist
	    }
	}
	if {$pref(details)} {
	    set newfilelist $w.filearea.details
	} else {
	    set newfilelist $w.filearea.files
	}
	if {$newfilelist ne $filelist} {
	    $filelist clear
	    if {$filelist in $panes} {
		$w.filearea forget $filelist
	    }
	    set filelist $newfilelist
	    my SelectFilter $w.ftent
	    my Reconfigure
	    $w.filearea add $filelist
	    my ReloadDir
	} else {
	    my Reconfigure
	}
    }

    method FileMatchCommand {str} {
	my variable cwd
	if {$str eq ""} return
	set esc [my GlobEscape $str]
	if {[file pathtype $str] eq "relative" || [string index $str 0] eq "~"} {
	    set l [expr {[string length $cwd] + 1}]
	    set list [lmap n [glob -nocomplain -dir $cwd -- $esc*] {
		string range $n $l end
	    }]
	} else {
	    set list [glob -nocomplain -- $esc*]
	}
	return [lsort -dictionary $list]
    }

    method FileValidate {str} {
	my variable cwd filelist
	if {$str ne "" && [file isfile [set file [joinfile $cwd $str]]]} {
	    set file [file normalize $file]
	    $filelist selection set [list $str]
	    $filelist see $str
	} else {
	    $filelist selection set {}
	}
	return true
    }

    method UpdateSortPrefs {w} {
	my variable pref
	set pref(sort) [$w cget -sortkey]
	set pref(reverse) [$w cget -reverse]
	preferences {*}[array get pref]
    }

    method Result {value {multiple 0}} {
	my variable w types result
	set result $value
	if {$multiple} {history {*}$value} else {history $value}
	if {$options(-typevariable) ne ""} {
	    upvar #0 $options(-typevariable) pattern
	    set type [$w.ftent current]
            if {$type < 0} {
                set pattern [$w.ftent get]
            } else {
                set pattern [lindex $options(-filetypes) $type 0]
            }
	}
	my Cancel
    }

    method Cancel {} {
	my variable w
	set geometry [lindex [split [wm geometry $w] +] 0]
        geometry filedialog geometry $geometry
	if {[llength [$w.filearea panes]] > 1} {
	    geometry filedialog sashpos [$w.filearea sashpos 0]
	}
	my destroy
    }

    method Done {} {
	global answer
	my variable w options cwd text
	if {$text eq ""} return
	set file [file normalize [joinfile $cwd $text]]
	if {[file isdirectory $file]} {
	    my ChangeDir $file
	    $w.fnent set ""
	} else {
	    if {$options(-confirmoverwrite)} {
		if {[file exists $file]} {
		    $w.fnent set $text
		    $w.fnent icursor end
		    set answer [protect $w {
			tk_messageBox -type yesno -icon warning -parent $w \
			  -message [mc {File "%s" already exists.\
			  Do you want to overwrite it?} [file nativename $file]]
		    }]
		    if {$answer ne "yes"} return
		}
	    }
	    my Result $file
	}
    }
}

::tk::Megawidget create ::ttk::fsdialog::getOpenFile \
  ::ttk::fsdialog::getSaveFile {
    variable options

    method GetSpecs {} {
	set spec \
	  [lsearch -all -inline -exact -not -index 0 [next] -confirmoverwrite]
	return [linsert $spec end {-multiple "" "" "0"}]
    }

    method Create {} {
	next Open Open
	if {$options(-multiple)} {
	    my variable w
	    $w.filearea.files configure -multiple 1
	    $w.filearea.details configure -multiple 1
	}
    }

    method FileSplit {str} {
	if {[string is list $str]} {return $str}
	set list {}
	foreach {l s} [split $str {"}] {
	    lappend list {*}[split $l { }] $s
	}
	return $list
    }

    method FileValidate {str} {
	if {!$options(-multiple)} {return [next $str]}
	my variable filelist cwd
	set list [lmap n [my FileSplit $str] {
	    set file [file normalize [joinfile $cwd $n]]
	    if {[file dirname $file] ne $cwd} continue
	    set name [file tail $file]
	    if {![$filelist exists $name]} continue
	    set name
	}]
	$filelist selection set $list
	return true
    }

    method ListBrowse {args} {
        if {!$options(-multiple)} {return [next]}
	my variable w cwd text filelist
	set sel [$filelist selection]
	set new {}
	set chg 0
	set list [lmap n [my FileSplit $text] {
            set file [file normalize [joinfile $cwd $n]]
            if {[file dirname $file] eq $cwd} {
                regsub {^./} [file tail $file] {} name
                if {[$filelist exists $name]} {
                    if {$name ni $sel} {set chg 1;continue}
		    lappend new $name
                }
            }
            set n
        }]
	foreach file $sel {
	    if {$file ni $new} {set chg 1;lappend list $file}
	}
	if {$chg} {
	    set text $list
	    $w.fnent icursor end
	}
    }

    method NormalizeFileList {} {
	if {$options(-multiple)} {
	    my variable w cwd text
	    set text [lmap n [my FileSplit $text] {
		set file [file normalize [joinfile $cwd $n]]
		if {[file exists $file]} {
		    set file
		} else {
		    set n
		}
	    }]
	    $w.fnent icursor end
	}
    }

    method ChangeDir {dir} {
	my variable cwd
	if {$dir ne $cwd} {my NormalizeFileList}
	next $dir
    }

    method TrailPos {index} {
	my variable cwd trail
	if {[lindex $trail $index] ne $cwd} {my NormalizeFileList}
	next $index
    }

    method Done {} {
	my variable w dir text
	if {$options(-multiple)} {
	    set files [my FileSplit $text]
	    if {[llength $files] == 0} return
	    set missing {}
	    set list [lmap s $files {
		set file [file normalize [joinfile $dir $s]]
		if {![file exists $file]} {
		    lappend missing [mc {File "%s" does not exist.} \
		      [file nativename $file]]
		    continue
		}
		set file
	    }]
	    if {[llength $missing]} {
		protect $w {
		    tk_messageBox -type ok -icon warning -parent $w \
		      -message [join $missing \n]
		}
	    }
	    if {[llength $list]} {
		my Result $list 1
	    }
	} elseif {$text ne ""} {
	    set file [file normalize [joinfile $dir $text]]
	    if {[file isdirectory $file]} {
		my ChangeDir $file
		$w.fnent set ""
	    } elseif {[file exists $file]} {
		my Result $file
	    } else {
		$w.fnent set $text
		protect $w {
		    tk_messageBox -type ok -icon warning -parent $w \
		      -message [mc {File "%s" does not exist.} \
		      [file nativename $file]]
		}
	    }
	}
    }
}

namespace import -force ::ttk::fsdialog::*

package provide fsdialog 2.0
