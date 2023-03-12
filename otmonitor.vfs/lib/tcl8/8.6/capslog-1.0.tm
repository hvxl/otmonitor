namespace eval capslog {
    namespace ensemble create \
      -subcommands {start stop track abort upload master} -map {abort {stop 1}}
    variable file ""
    variable cleanup {}
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
}

proc capslog::start {{list {}}} {
    variable wanted $list
    variable file
    variable msg
    variable state
    variable count 0
    if {$state ni {idle done}} {stop 1}
    variable mode ""
    variable demand ""
    variable choice 0
    variable cleanup {}
    variable cmd [namespace which output]
    variable fd [file tempfile file capslog.gz]
    # Compress the data on the fly
    zlib push gzip $fd
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
    variable cleanup
    variable afterid
    after cancel $afterid
    after cancel [namespace which stop]
    set ns [namespace current]
    foreach n $cleanup {
	lassign $n sercmd cond
	if {$cond eq "" || \
	  [catch {namespace eval $ns [list expr $cond]} rc] || $rc} {
	    sercmd $sercmd
	}
    }
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

proc capslog::onexit {cmd {condition ""}} {
    variable cleanup
    lappend cleanup [list $cmd $condition]
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
    if {[scan $str {%*s %[BRAT]%1[0-9A-F]0%2[0-9A-F]%*4[0-9A-F]%c} \
      src type id ch] != 4} {
	if {[scan $str {%*s PR: %s} pr] == 1} {
	    variable mode
	    switch $pr {
		M=M {
		    if {$mode eq ""} {set mode M}
		}
		M=G {
		    if {$mode eq ""} {set mode G}
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
    set type [expr {"0x$type" & 7}]
    if {$src eq "T"} {
	dict incr msg(master) $id
    } elseif {$src eq "A"} {
	if {![dict exists $msg(slave) $id]} {dict incr msg(skipped) $id}
    } elseif {$src eq "R"} {
	if {$demand ne "" && $id ne $demand} {
	    # OTGW sent a different alternative message than requested. One
	    # of the sides may have missed something. Request it again.
	    queuecmd PM=[expr {"0x$demand"}]
	}
    } elseif {$src eq "B"} {
	dict incr msg(slave) $id
	set n [expr {"0x$id"}]
	if {$choice && $n == $choice} {
	    # The UI command appears to have been lost
	    queuecmd UI=$choice
	}
	if {$type == 7} {
	    if {$n < 128} {dict incr msg(unknown) $id}
	}
	if {$id eq $demand} {
	    # Allow time for the message back to the thermostat
	    after 20 [namespace which next]
	} elseif {$demand eq ""} {
	    variable count
	    variable target
	    variable state
	    variable afterid
	    if {$state in {init reinit}} {
		after cancel $afterid
		status progress {collecting messages - 0%}
		# Use whatever was collected, if not finished in 2 hours
		set afterid [after 7200000 [namespace which stop]]
	    }
	    if {$count < 0} {
		# Don't count
	    } elseif {[incr count] >= $target} {
		interim
		if {[next]} {
		    # This doesn't really remove the PM. But MsgID 0 should
		    # happen frequently, which will clear the PM request flag.
		    onexit PM=0 {$demand ne ""}
		}
	    } elseif {($count % 5) == 0} {
		status progress [format {collecting messages - %d%%} \
		  [expr {100 * $count / $target}]]
	    }
	    if {$count == 4 * $target / 5 && [dict size $msg(skipped)] == 0} {
		# No skipped messages seen yet. Make sure OTGW is in GW mode.
		queuecmd PR=M
	    }
	}
    }
}

proc capslog::next {} {
    variable query
    variable demand
    variable msg
    if {[llength $query]} {
	set query [lassign $query demand]
	if {[dict exists $msg(slave) $demand]} {tailcall next}
	set id [expr {"0x$demand"}]
	queuecmd PM=$id
	status query "checking message ID $id"
	return 1
    } else {
	variable count -1 choice 0
	set demand ""
	after 5000 [namespace which stop]
	return 0
    }
}

proc capslog::interim {} {
    variable count
    variable wanted
    variable wronly
    variable msg
    variable mode
    if {$mode eq "M"} {
	# Can't collect more data in monitor mode
	# Switch to gateway mode
	queuecmd GW=1
	onexit GW=0
	# stop
	# return
    }
    variable query [lsort [lmap n $wanted {
	set id [format %02X [expr {$n & 0xff}]]
	if {[dict exists $msg(slave) $id]} continue
	# Skip write-only messages, as the response would be unreliable
	if {$n in $wronly} {
	    if {[dict exists $msg(skipped) $id]} {
		# This is requested by the thermostat, but replaced by the OTGW
		# The OTGW cannot send Write-Data messages on demand, so just
		# tell it to pass the thermostat message to the boiler again.
		queuecmd KI=$n
		# Arrange to mark the message as unknown when we're done. But
		# only if the boiler accepted it. Then it was manually set.
		onexit UI=$n [format {%d ni $msg(unknown)} $n]
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
    # Looking for at least one slot in 60 messages
    set threshold [expr {$count / 60}]
    if {$slots <= $threshold} {
	# Not enough slots available. Sacrifice a less important message
	set messages [dict keys $msg(master)]
	set counts [dict value $msg(master)]
	set keys [lmap n [lsort -integer -indices -decreasing $counts] {
	    lindex $messages $n
	}]
	variable needed
	variable preferred
	variable choice 0
	foreach id $keys {
	    set n [expr {"0x$id"}]
	    if {$n >= 128 || $n in $needed} continue
	    if {[dict get $msg(master) $id] <= $threshold && $choice} break
	    set choice $n
	    if {$n in $preferred} continue
	    break
	}
	if {$choice} {
	    queuecmd UI=$choice
	    onexit KI=$choice
	} else {
	    # Could not find a sacrificial message
	    stop
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
