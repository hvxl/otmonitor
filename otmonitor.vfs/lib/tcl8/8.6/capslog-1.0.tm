namespace eval capslog {
    namespace ensemble create \
      -subcommands {start stop track abort upload master} -map {abort {stop 1}}
    variable file ""
    variable cmdqueue {}
    variable handlers {}
    variable state idle message ""
    variable afterid ""
    variable choice 0
    # Number of messages to collect initially
    variable target 500
    # Never disable these messages. They are critical to heating control
    variable needed {0 1 2 3 14 17 25}
    # Do not disable these messages, unless there is no other option
    variable preferred {7 8 28 29 30 31 70 71 77 101 102}
    # Messages that should not be queried, because they may only be written
    variable wronly {1 2 4 7 8 14 16 23 24 37 71 98 124 126}
    # Transparent Slave Parameters and Fault History Data
    variable params {10 11 12 13 88 89 90 91 105 106 107 108}
    # Brand information strings
    variable strings {93 94 95}
}

proc capslog::start {{list {}}} {
    variable file
    variable msg
    variable state
    variable count 0
    if {$state ni {idle done}} {stop 1}
    variable mode ""
    variable demand ""
    variable version ""
    variable choice 0
    variable cmd [namespace which output]
    variable fd [file tempfile file capslog.gz]
    # Compress the data on the fly
    zlib push gzip $fd
    coroutine next sequencer $list
    trace add execution ::output leave $cmd
    array set msg {
	master {}
	slave {}
	skipped {}
	unknown {}
    }
    status init "collecting messages - please wait"
    variable afterid [after 5000 [list [namespace which monitor]]]
}

proc capslog::stop {{abort 0} {msg "data collection aborted"}} {
    variable fd
    variable file
    variable cmd
    variable afterid
    after cancel $afterid
    after cancel [namespace which stop]
    next stop
    trace remove execution ::output leave $cmd
    close $fd
    if {$abort} {
	file delete $file
	set file ""
	status idle $msg
    } else {
	# On windows temp files are created with a .TMP extension
	if {[file extension $file] ne ".gz"} {
	    set name [file rootname $file].gz
	    if {![catch {file rename $file $name}]} {set file $name}
	}
	status done "the log was saved as: [file nativename $file]"
    }
}

proc capslog::track {prefix} {
    variable handlers
    variable state
    variable message
    if {![catch {uplevel #0 [linsert $prefix end $state $message]}]} {
	lappend handlers $prefix
    }
    return
}

proc capslog::status {new {msg ""}} {
    variable state $new
    variable handlers
    variable message
    if {$msg ne ""} {set message $msg}
    set index 0
    foreach n $handlers {
	if {[catch {uplevel #0 [linsert $n end $new $message]} err]} {
	    # Remove bad handlers
	    set handlers [lreplace $handlers $index $index]
	} else {
	    incr index
	}
    }
    if {$new eq "idle"} { 
        variable handlers {}
    }
}

proc capslog::monitor {} {
    variable state
    switch $state {
	init {
	    # No messages have been received. Maybe OTGW is in PS=1 mode
	    sercmd PS=0
	    status reinit
	    variable afterid [after 5000 [list [namespace which monitor]]]
	}
	reinit {
	    # Still no messages
	    stop 1 "no messages are being received"
	}
    }
}

proc capslog::output {cmd code str op} {
    variable fd
    variable demand
    variable choice
    # Skip bitfield details
    if {[string equal -length 8 {        } $str]} return
    puts $fd $str
    if {[scan $str {%*s %[BRAT]%n%1x0%2x%4x%n} \
      src p1 type id data p2] != 6 || $p2 - $p1 != 8} {
	if {[scan $str {%*s PR: %1s=%n%s} ch pos data] == 3} {
	    switch $ch {
		M {
		    variable mode
		    if {$mode eq ""} {set mode $data}
		}
		A {
		    set banner [string range $str $pos end]
		    if {[scan $banner {OpenTherm Gateway %s} ver] == 1} {
			variable version $ver
		    }
		}
	    }
	}
	if {[regexp {\s[0-9.,/-]+$} $str ps] && [string length $ps] > 100} {
	    # Looks like PS=1 command output. We need PS=0.
	    queuecmd PS=0
	    # The requested priority message may have been missed
	    if {$demand ne ""} {
		queuecmd PM=[expr {"0x$demand"}]
	    }
	}
	return
    }
    variable msg
    set type [expr {$type & 7}]
    if {$src eq "T"} {
	dict incr msg(master) $id
    } elseif {$src eq "A"} {
	if {![dict exists $msg(slave) $id]} {dict incr msg(skipped) $id}
    } elseif {$src in {R B}} {
	next $src $type $id $data
    }
}

proc capslog::tracker {args} {
    variable msg
    upvar 1 type type id id data data
    lassign [yieldto list {*}$args] src type id data
    if {$src eq "B"} {
	dict incr msg(slave) $id
	if {$type == 7 && $id < 128} {
	    dict incr msg(unknown) $id
	}
    }
    if {$src in {stop abort}} {
	upvar #1 cleanup cleanup
	foreach n $msg(skipped) {
	    if {[dict exists $msg(unknown) $n]} {dict unset cleanup KI=$n}
	}
	dict for {key cmd} $cleanup {
	    sercmd $cmd
	}
	return -level [info level]
    } else {
	return $src
    }
}

proc capslog::sequencer {wanted} {
    variable msg
    variable target
    variable version
    set cleanup {}
    # Stage 1: Wait for a decent amount of messages from the boiler
    set count 0
    while {$count < $target} {
	if {[tracker] eq "B"} {
	    if {$version eq ""} {
		if {$count >= 5} {
		    stop 1 "cannot determine firmware"
		}
		queuecmd PR=A
	    }
	    if {$count % 5 == 0} {
		status progress [format {collecting messages - %d%%} \
		  [expr {100 * $count / $target}]]
	    }
	    incr count
	    if {$count == 4 * $target / 5 && [dict size $msg(skipped)] == 0} {
		# No skipped messages seen yet. Make sure OTGW is in GW mode.
		queuecmd PR=M
	    }
	}
    }
    # Check for gateway mode
    variable mode
    if {$mode eq "M"} {
	# Can't collect more data in monitor mode
	# Switch to gateway mode
	queuecmd GW=1
	dict set cleanup mode GW=0
    }
    # Determine which additional messages to collect
    variable wronly
    set query [lsort -integer [lmap id $wanted {
	if {[dict exists $msg(slave) $id]} continue
	# Skip write-only messages, as the response would be unreliable
	if {$id in $wronly} {
	    if {[dict exists $msg(skipped) $id]} {
		# This is requested by the thermostat, but replaced by the OTGW
		# The OTGW cannot send Write-Data messages on demand, so just
		# tell it to pass the thermostat message to the boiler again.
		queuecmd KI=$id
		# Arrange to mark the message as unknown when we're done. But
		# only if the boiler accepted it. Then it was manually set.
		dict set cleanup KI=$id UI=$id
	    }
	    continue
	}
	set id
    }]]
    # Check the amount of unknown and skipped messages
    set slots 0
    foreach n {unknown skipped} {
	dict for {key cnt} $msg($n) {incr slots $cnt}
    }
    # Locate a slot for requesting additional messages
    # Looking for at least one slot in 60 messages
    set threshold [expr {$count / 60}]
    set choice 999
    if {$slots <= $threshold} {
	# Not enough slots available. Sacrifice a less important message
	set messages [dict keys $msg(master)]
	set counts [dict values $msg(master)]
	set keys [lmap n [lsort -integer -indices -decreasing $counts] {
	    lindex $messages $n
	}]
	variable needed
	variable preferred
	set choice 0
	foreach id $keys {
	    if {$id >= 128 || $id in $needed} continue
	    if {[dict get $msg(master) $id] <= $threshold && $choice} break
	    set choice $id
	    if {$id ni $preferred} break
	}
	if {$choice} {
	    queuecmd UI=$choice
	    dict set cleanup choice KI=$choice
	} else {
	    # Could not find a sacrificial message
	    yieldto stop
	}
    }
    # Stage 2: Request additional messages from the boiler
    variable params
    variable strings
    # This doesn't really remove the PM. But MsgID 0 should happen frequently,
    # which will clear the PM request flag.
    dict set cleanup demand PM=0
    foreach demand $query {
	if {[dict exists $params $demand]} {
	    params $demand [dict get $params $demand]
	    continue
	} elseif {[package vsatisfies $version 6.5.1-] && $demand in $strings} {
	    strings $demand
	    continue
	} elseif {[dict exists $msg(slave) $demand]} {
	    continue
	}
	queuecmd PM=$demand
	status query "checking message ID $demand"
	while {1} {
	    set rc [tracker]
	    if {$rc eq "R" && $id != $demand} {
		# OTGW sent a different alternative message than requested. One
		# of the sides may have missed something. Request it again.
		queuecmd PM=$demand
	    }
	    if {$rc eq "B"} {
		if {$id == $demand} break
		if {$id == $choice} {
		    # The UI command appears to have been lost
		    queuecmd UI=$choice
		}
	    }
	}
	after 20 [list [info coroutine] timer]
	tracker
    }
    dict unset cleanup demand
    tracker
    yieldto stop
}

proc capslog::params {countid entryid} {
    while 1 {
	queuecmd PM=$countid
	status query "checking message ID $countid"
	while 1 {
	    set rc [tracker]
	    if {$rc eq "R"} {
		if {$id != $countid && $id != $entryid} break
	    }
	    if {$rc eq "B"} {
		if {$id == $countid} {
		    if {$type == 7} return
		    set count [expr {$data >> 8}]
		    if {!$count} return
		    status query "checking message ID $entryid:0"
		}
		if {$id == $entryid} {
		    if {$type == 7} return
		    set index [expr {$data >> 8}]
		    set value [expr {$data & 0xff}]
		    dict set items $index $value
		    # Check if all data items have been collected
		    if {[dict size $items] == $count} return
		    # Check if all higher numbered items have been collected
		    while {[incr index] < $count} {
			if {![dict exists $items $index]} break
		    }
		    # Start over to collect a missed item
		    if {$index >= $count} break
		    status query "checking message ID $entryid:$index"
		}
	    }
	}
    }
}

proc capslog::strings {demand} {
    while 1 {
	queuecmd PM=$demand
	status query "checking message ID $demand:0"
	while 1 {
	    set rc [tracker]
	    if {$rc eq "R"} {
		if {$id != $demand} break
		set index [expr {$data >> 8}]
		set ms [clock milliseconds]
	    }
	    if {$rc eq "B"} {
		if {$type == 7} return
		if {$id == $demand} {
		    set count [expr {$data >> 8}]
		    if {[clock milliseconds] - $ms < 1000} {
			dict set items $index [expr {$data & 0xff}]
			if {[dict size $items] == $count} return
			while {[incr index] < $count} {
			    if {![dict exists $items $index]} break
			}
			# Start over to collect a missed character
			if {$index >= $count} break
			status query "checking message ID $demand:$index"
		    }
		} else {
		    set ms 0
		}
	    }
	}
    }
}

# Execute commands in an idle callback so they will be entered into the log
proc capslog::queuecmd {cmd} {
    variable cmdqueue
    if {[llength $cmdqueue] == 0} {
	coroutine cmdqueuecoro sendcmdqueue
    }
    lappend cmdqueue $cmd
}

proc capslog::sendcmdqueue {} {
    variable cmdqueue
    after idle [list [info coroutine]]
    yield
    # New commands may be added to the queue while waiting for a response
    while {[llength $cmdqueue]} {
	set remain [lassign $cmdqueue cmd]
	for {set i 0} {$i < 3} {incr i} {
	    set ack [sercmd $cmd]
	    if {[scan $ack {%2s: %s} op arg] == 2} {
		if {[string equal -length 2 $op $cmd]} {
		    if {$arg ni {NG SE NS BV NF OR OE}} break
		} else {
		    # Response may have happened during PS=1 output
		    sercmd PS=0
		}
	    }
	    if {$i == 2} {
		stop 1 "communication failure"
	    }
	}
	set cmdqueue $remain
    }
}

proc capslog::upload {url args} {
    variable file
    variable state
    if {$state ne "done" || $file eq ""} return
    if {[info coroutine] eq ""} {
	coroutine capspost upload $url {*}$args
    } else {
	status upload "uploading the log file"
	package require www
	try {
	    set result [www post \
	      -name logfile -type application/gzip -file $file $url {*}$args]
	} on ok {msg} {
	    status idle "log file successfully uploaded"
	} trap {WWW} {msg} {
	    status idle [string trim $msg]
	} on error {msg info} {
	    status idle [string trim $msg]
	    # puts [dict get $info -errorinfo]
	}
    }
}

proc capslog::master {{strict 0}} {
    variable msg
    variable state
    if {!$strict && $state in {idle done}} {return 0}
    return [expr {[info exists msg(master)] && [dict size $msg(master)] > 0}]
}
