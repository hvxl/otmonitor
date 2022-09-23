namespace eval capslog {
    namespace ensemble create \
      -subcommands {start stop track abort upload} -map {abort {stop 1}}
    variable file ""
    variable demand ""
    variable cleanup {}
    variable needed {0 1 2 3 14 25} preferred {9 16 24}
    variable wronly {1 2 4 7 8 14 16 23 24 37 71 98 124 126}
    variable queue ""
    variable handlers {}
    variable state idle message ""
    variable target 500
    variable afterid ""
}

proc capslog::start {{list {}}} {
    variable wanted $list
    variable file
    variable msg
    variable state
    variable count 0
    if {$state ne "idle"} {stop 1}
    variable mode ""
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
    after cancel [namespace which stop]
    after cancel $afterid
    foreach sercmd $cleanup {sercmd $sercmd}
    trace remove execution ::output leave $cmd
    close $fd
    if {$abort} {
	file delete $file
	set file ""
	status idle $msg
    } else {
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
	if {[catch {uplevel #0 [linsert $n end $state $message]}]} {
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

proc capslog::onexit {cmd} {
    variable cleanup
    lappend cleanup $cmd
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
	    sercmd PS=0
	    # The requested priority message may have been missed
	    if {$demand ne ""} {
		sercmd PM=[expr {"0x$demand"}]
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
	    # of the sides must have missed something. Request it again.
	    sercmd PM=[expr {"0x$demand"}]
	}
    } elseif {$src eq "B"} {
	dict incr msg(slave) $id
	if {$type == 7} {
	    set n [expr {"0x$id"}]
	    if {$n < 128} {dict incr msg(unknown) $id}
	}
	if {$id eq $demand} {
	    after 20 [namespace which next]
	} elseif {$demand eq ""} {
	    variable count
	    variable target
	    variable state
	    variable afterid
	    if {$state in {init reinit}} {
		after cancel $afterid
		status progress {collecting messages - 0%}
	    }
	    if {$count < 0} {
		# Don't count
	    } elseif {[incr count] >= $target} {
		interim
		next
	    } elseif {($count % 5) == 0} {
		status progress [format {collecting messages - %d%%} \
		  [expr {100 * $count / $target}]]
	    }
	    if {$count == 4 * $target / 5 && [dict size $msg(skipped)] == 0} {
		# No skipped messages seen yet. Make sure OTGW is in GW mode.
		sercmd PR=M
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
	sercmd PM=$id
	status query "checking message ID $id"
    } else {
	variable count -1
	set demand ""
	after 5000 [namespace which stop]
    }
}

proc capslog::interim {} {
    variable wanted
    variable wronly
    variable msg
    variable mode
    if {$mode eq "M"} {
	# Can't collect more data in monitor mode
	# Switch to gateway mode
	sercmd GW=1
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
		# Temporarily instruct OTGW to send it to the boiler again
		sercmd KI=$n
		onexit UI=$n
	    }
	    continue
	}
	set id
    }]]
    if {[dict size $msg(unknown)] == 0 && [dict size $msg(skipped)] == 0} {
	# No slots available. Sacrifice a less important message
	set messages [dict keys $msg(master)]
	set counts [dict value $msg(master)]
	set keys [lmap n [lsort -integer -indices -decreasing $counts] {
	    lindex $messages $n
	}]
	variable count
	variable needed
	variable preferred
	# Looking for a message that is requested at least once a minute
	set choice 0
	set threshold [expr {$count / 60}]
	foreach id $keys {
	    set n [expr {"0x$id"}]
	    if {$n in $needed} continue
	    if {[dict get $msg(master) $id] <= $threshold && $choice} break
	    set choice $n
	    if {$n in $preferred} continue
	    break
	}
	if {$choice} {
	    sercmd UI=$choice
	    onexit KI=$choice
	} else {
	    stop
	}
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
