package require sha1

# Define the ::wibble::ws namespace.
namespace eval ::wibble::ws {
    namespace path ::wibble
}

# Send a WebSocket frame.
proc ::wibble::ws::send {type {msg ""} {final 1}} {
    log "[info coroutine] Tx $type $msg"

    upvar #1 wsversion wsversion
    if {$wsversion eq ""} {
	set str \0$msg\xff
    } else {
	# Compute the opcode.  The opcode is zero for continuation frames.
	upvar #1 fragment fragment
	if {[info exists fragment]} {
	    set opcode 0
	} else {
	    set opcode [dict get {text 1 binary 2 ping 9} $type]
	}
	if {!$final} {
	    set fragment ""
	} else {
	    unset -nocomplain fragment
	}

	# Encode text.
	if {$type eq "text"} {
	    set msg [encoding convertto utf-8 $msg]
	}

	# Assemble the header.
	set header [binary format c [expr {!!$final << 7 | $opcode}]]
	if {[string length $msg] < 126} {
	    append header [binary format c [string length $msg]]
	} elseif {[string length $msg] < 65536} {
	    append header \x7e[binary format Su [string length $msg]]
	} else {
	    append header \x7f[binary format Wu [string length $msg]]
	}
	set str $header$msg
    }

    # Send the frame.
    set socket [namespace tail [info coroutine]]
    chan puts -nonewline $socket $str
    chan flush $socket
}

# Close the current WebSocket connection.
proc ::wibble::ws::close {{reason ""} {description ""}} {
    icc put ::wibble::[namespace tail [info coroutine]] exception close\
        $reason $description
}

# WebSocket analogue of [::wibble::process]
proc ::wibble::ws::process {state socket request response} {
    # Get configuration options.
    if {![dict exists $state options maxlength]} {
        set maxlength 16777216
    } elseif {[dict get $state options maxlength] eq ""} {
        set maxlength 18446744073709551615
    } else {
        set maxlength [dict get $state options maxlength]
    }

    # Create WebSocket event handler wrapper coroutine.
    set fid [namespace current]::$socket
    cleanup ws_unset_feed [list icc destroy $fid]
    icc configure $fid accept connect disconnect text binary close
    coroutine $socket apply {{handler state} {
        try {
	    set wsversion new
	    # [dict get $state request header sec-websocket-version]
            while {1} {
                foreach event [icc get [info coroutine] *] {
                    {*}$handler $state {*}$event
                    if {[lindex $event 0] eq "disconnect"} {
                        return
                    }
                }
            }
        } on error {"" options} {
            panic $options "" "" "" "" [dict get $state request]\
                [dict get $state response]
        }
    } ::wibble::zone} [dict get $state options handler] $state

    # Respond to WebSocket handshake.
    chan puts $socket "HTTP/1.1 101 WebSocket Protocol Handshake"
    chan puts $socket "upgrade: websocket"
    chan puts $socket "connection: upgrade"
    chan puts $socket "sec-websocket-accept:\
	[binary encode base64 [sha1::sha1 -bin \
        [dict get $request header sec-websocket-key\
        ]258EAFA5-E914-47DA-95CA-C5AB0DC85B11]]"
    chan puts $socket ""
    chan flush $socket
    chan configure $socket -translation binary

    # It's necessary to bypass [icc put] in this one case, because it defers
    # event delivery when called from a coroutine.  Consequentially, before it
    # would attempt to send the event, the feed will be destroyed.
    cleanup ws_disconnect [list $fid disconnect]

    # Invoke connect handler.
    icc put $fid connect

    set reason 1000
    try {
        foreach event [icc catch {
            # Main loop.
            set msg ""
            set mode ""
            while {1} {
                # Get basic header.  Abort if reserved bits are set, mask bit
                # isn't set, unexpected continuation frame, fragmented or
                # oversized control frame, or the opcode is unrecognized.
                binary scan [getblock 2] Su header
                set opcode [expr {$header >> 8 & 0xf}]
                set len [expr {$header & 0x7f}]
                if {($header & 0x7080 ^ 0x80) || ($opcode == 0 && $mode eq "")
                 || ($opcode > 7 && (!($header & 0x8000) || $len > 125))
                 || $opcode ni {0 1 2 8 9 10}} {
                    # Send close frame, reason 1002: protocol error.
                    set reason 1002
                    break
                }

                # Determine the effective opcode for this frame.
                if {$mode eq ""} {
                    set mode $opcode
                } elseif {$opcode == 0} {
                    set opcode $mode
                }

                # Get the extended length, if present.
                if {$len == 126} {
                    binary scan [getblock 2] Su len
                } elseif {$len == 127} {
                    binary scan [getblock 8] Wu len
                }

                # Limit the maximum message length.
                if {[string length $msg] + $len > $maxlength} {
                    # Send close frame, reason 1009: frame too big.
                    set reason [list 1009 "limit $maxlength bytes"]
                    break
                }

                # Use an alternate message buffer for control frames.
                if {$opcode > 7} {
                    set oldmsg $msg
                    set msg ""
                }

                # Get mask and data.  Format data as a list of 32-bit integer
                # words and list of 8-bit integer byte leftovers.  Then unmask
                # data, recombine the words and bytes, and append to the buffer.
                binary scan [getblock [expr {4 + $len}]] II*c* mask words bytes
                for {set i 0} {$i < [llength $words]} {incr i} {
                    lset words $i [expr {[lindex $words $i] ^ $mask}]
                }
                for {set i 0} {$i < [llength $bytes]} {incr i} {
                    lset bytes $i [expr {[lindex $bytes $i] ^
                        ($mask >> (24 - 8 * $i))}]
                }
                append msg [binary format I*c* $words $bytes]

                # If FIN bit is set, process the frame.
                if {$header & 0x8000} {
                    switch $opcode {
                    1 {
                        # Text: decode and notify handler.
                        icc put $fid text [encoding convertfrom utf-8 $msg]
                    } 2 {
                        # Binary: notify handler without decoding.
                        icc put $fid binary $msg
                    } 8 {
                        # Close: decode, handle, send close frame, terminate.
                        if {[string length $msg] >= 2} {
                            binary scan [string range $msg 0 1] Su reason
                            icc put $fid close $reason [encoding convertfrom\
                                utf-8 [string range $msg 2 end]]
                        } else {
                            icc put $fid close
                        }
                        set reason ""
                        break
                    } 9 {
                        # Ping: send pong to client, don't notify handler.
                        chan puts -nonewline $socket \x8a[binary format c\
                            [string length $msg]]$msg
                        chan flush $socket
                    }}

                    # Prepare for the next frame.
                    if {$opcode < 8} {
                        # Data frame: reinitialize parser.
                        set msg ""
                        set mode ""
                    } else {
                        # Control frame: restore previous message buffer.
                        set msg $oldmsg
                    }
                }
            }
        }] {
            # Catch exception events and translate them into close reason codes.
            if {[lrange $event 0 1] eq {exception close}} {
                 set reason [lrange $event 2 3]
                 break
            }
        }
    } on error {result options} {
        # Default error close reason.
        set reason {1001 "internal server error"}
        return -options $options $result
    } finally {
        # Send close frame with reason, if one was given.
        catch {
            if {[llength $reason]} {
                set msg [string range [binary format Su [lindex $reason 0]\
                    ][encoding convertto utf-8 [lindex $reason 1]] 0 124]
                chan puts -nonewline $socket \x88[binary format c\
                    [string length $msg]]$msg
            } else {
                chan puts -nonewline $socket \x88\x00
            }
        }
    }

    # Ask Wibble to close the connection.
    return 0
}

proc ::wibble::ws::process-old {state socket request response} {
    # Get configuration options.
    if {![dict exists $state options maxlength]} {
        set maxlength 16777216
    } elseif {[dict get $state options maxlength] eq ""} {
        set maxlength 18446744073709551615
    } else {
        set maxlength [dict get $state options maxlength]
    }

    # Create WebSocket event handler wrapper coroutine.
    set fid [namespace current]::$socket
    cleanup ws_unset_feed [list icc destroy $fid]
    icc configure $fid accept connect disconnect text binary close
    coroutine $socket apply {{handler state} {
        try {
	    set wsversion ""
            while {1} {
                foreach event [icc get [info coroutine] *] {
                    {*}$handler $state {*}$event
                    if {[lindex $event 0] eq "disconnect"} {
                        return
                    }
                }
            }
        } on error {"" options} {
            panic $options "" "" "" "" [dict get $state request]\
                [dict get $state response]
        }
    } ::wibble::zone} [dict get $state options handler] $state

    # Respond to WebSocket handshake.
    package require md5
    set swk1 [dict get $request header sec-websocket-key1]
    set dig1 [regsub -all {[^0-9]} $swk1 {}]
    set cnt1 [regexp -all { } $swk1]
    set key1 [expr {$dig1 / $cnt1}]
    set swk2 [dict get $request header sec-websocket-key2]
    set dig2 [regsub -all {[^0-9]} $swk2 {}]
    set cnt2 [regexp -all { } $swk2]
    set key2 [expr {$dig2 / $cnt2}]
    set nonce [getblock 8]
    set response [md5::md5 [binary format IIa8 $key1 $key2 $nonce]]

    chan puts $socket "HTTP/1.1 101 WebSocket Protocol Handshake"
    chan puts $socket "upgrade: websocket"
    chan puts $socket "connection: upgrade"
    if {[dict exists $request header origin]} {
	chan puts $socket "sec-websocket-origin:\
	  [dict get $request header origin]"
    }
    chan puts $socket [format {sec-websocket-location: ws://%s%s} \
      [dict get $request header host] [dict get $request uri]]
    chan puts $socket ""
    chan configure $socket -translation binary
    chan puts -nonewline $socket $response
    chan flush $socket

    # It's necessary to bypass [icc put] in this one case, because it defers
    # event delivery when called from a coroutine.  Consequentially, before it
    # would attempt to send the event, the feed will be destroyed.
    cleanup ws_disconnect [list $fid disconnect]

    # Invoke connect handler.
    icc put $fid connect

    set reason 1000
    try {
        foreach event [icc catch {
            # Main loop.
            set data ""
            while {1} {
		append data [chan read $socket]
		if {[eof $socket] || [string range $data 0 1] eq "\xff\0"} {
		    break
		}
		if {[string index $data 0] ne "\0"} {
		    set x [string first "\0" $data]
		    if {$x < 0} {
			set data ""
		    } else {
			set data [string replace $data $x end]
		    }
		}
		set x [string first \xff $data 1]
		if {$x > 0} {
		    set msg [string range $data 1 [expr {$x - 1}]]
		    set data [string replace $data 0 $x]
		    icc put $fid text $msg
		    continue
		}
		icc get [info coroutine] readable
            }
        }] {
            # Catch exception events and translate them into close reason codes.
            if {[lrange $event 0 1] eq {exception close}} {
                 set reason [lrange $event 2 3]
                 break
            }
        }
    } on error {result options} {
        # Default error close reason.
        set reason {1001 "internal server error"}
        return -options $options $result
    }

    # Ask Wibble to close the connection.
    return 0
}

# WebSocket upgrade zone handler.
proc ::wibble::zone::websocket {state} {
    set header [dict get $state request header]
    if {[dict exists $header sec-websocket-key]
     && [dict exists $header sec-websocket-version]
     && [dict exists $header connection]
     && [dict exists $header upgrade]
     && [lsearch -nocase [dict get $header connection] upgrade] != -1
     && [string equal -nocase [dict get $header upgrade] websocket]} {
        sendresponse [list nonhttp 1 sendcommand [list ws::process $state]]
    }
    if {[dict exists $header sec-websocket-key1]
     && [dict exists $header sec-websocket-key2]
     && [dict exists $header connection]
     && [dict exists $header upgrade]
     && [lsearch -nocase [dict get $header connection] upgrade] != -1
     && [string equal -nocase [dict get $header upgrade] websocket]} {
	sendresponse [list nonhttp 1 sendcommand [list ws::process-old $state]]
    }
}
