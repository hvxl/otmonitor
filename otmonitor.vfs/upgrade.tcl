namespace eval upgrade {
    namespace ensemble create -subcommands {readhex loadhex parsehex}
}

proc upgrade::readhex {file} {
    # A firmware file is around 32k max
    if {[catch {open $file} f]} {
	return [list failed "Error: $f"]
    }
    try {
	set data [read $f 65536]
    } on error err {
	return [list failed "Error: $err"]
    } finally {
	close $f
    }
    tailcall parsehex $data
}

proc upgrade::parsehex {hexdata} {
    global mem csize dsize cocmd copct devtype gwversion restore
    variable fwversion 0
    set csize 0
    set dsize 0
    set cocmd 0
    set copct ""
    dict set mem data [lrepeat 256 {}]
    dict set mem code [lrepeat 4096 {}]
    dict set mem conf [lrepeat 9 {}]
    try {
	foreach line [split $hexdata \n] {
	    if {[scan $line :%2x%4x%2x%s size addr tag data] != 4} {
		error "parse error"
	    }
	    if {$size & 1} {error "invalid data size"}
	    if {![string is xdigit -strict $data]} {error "invalid hex data"}
	    binary scan [binary format H* [string range $line 1 end]] cu* list
	    if {[checksum $list] != 0} {error "checksum error"}
	    if {$tag == 0} {
		if {$addr >= 0x4400} {
		    # Bogus addresses
		} elseif {$addr >= 0x4200} {
		    # Data memory
		    set addr [expr {($addr - 0x4200) >> 1}]
		    binary scan [binary format H* $data] su* list
		    dict update mem data data {
			foreach n $list {
			    lset data $addr [format 0x%02x [expr {$n & 0xff}]]
			    incr addr
			}
		    }
		} elseif {$addr >= 0x4000} {
		    # Configuration bits
		    set addr [expr {($addr - 0x4000) >> 1}]
		    binary scan [binary format H* $data] su* list
		    dict update mem conf data {
			foreach n $list {
			    lset data $addr [format 0x%04x $n]
			    incr addr
			}
		    }
		} else {
		    # Program memory
		    set addr [expr {$addr >> 1}]
		    binary scan [binary format H* $data] su* list
		    dict update mem code data {
			foreach n $list {
			    lset data $addr [format 0x%04x $n]
			    incr addr
			}
		    }
		}
	    } elseif {$tag == 4} {
		scan $data %x seg
	    } elseif {$tag == 1} {
		# End of data
		break
	    }
	}
	set csize [llength [lsearch -all -exact -not [dict get $mem code] {}]]
	set dsize [llength [lsearch -all -exact -not [dict get $mem data] {}]]
	set cocmd 0
	set copct 0%
	# Try to determine the version of the new firmware
	set data [lsearch -all -inline -exact -not [dict get $mem data] {}]
	set list [split [binary format c* $data] \0]
	set rec [lsearch -inline $list {*OpenTherm Gateway*}]
	set rec [string trimleft $rec A=]
	scan $rec {OpenTherm Gateway %s} fwversion
	variable eeold [eeprom $gwversion]
	variable eenew [eeprom $fwversion]
	if {[dict size $eenew] > 0 && [dict size $eeold] > 0} {
	    set restore [expr {abs($restore)}]
	    return [list success 1]
	} else {
	    set restore [expr {-abs($restore)}]
	    return [list success 0]
	}
    } on error err {
	return [list failed "Invalid firmware file: $err"]
    }
}

proc upgrade::cogetch {{timeout 2000}} {
    global dev devtype
    set id [after $timeout [list [info coroutine] timeout]]
    fileevent $dev readable [list [info coroutine] data]
    try {
	set rc ""
	while {[set ret [yield]] eq "data"} {
	    if {[binary scan [read $dev 1] cu rc] != 1} continue
	    if {$rc == 255 && $devtype eq "telnet"} {
		binary scan [read $dev 1] cu rc
	    }
	    break
	}
    } finally {
	fileevent $dev readable {}
	if {[info exists id]} {after cancel $id}
    }
    return $rc
}

proc upgrade::cowaitch {match {ms 2000}} {
    set target [expr {[clock milliseconds] + $ms}]
    while {[set ch [cogetch $ms]] != $match} {
	if {$ch eq ""} break
	set ms [expr {$target - [clock milliseconds]}]
    }
    return [expr {$ch == $match}]
}

proc upgrade::checksum {list} {
    return [tcl::mathop::& [tcl::mathop::- 0 {*}$list] 0xff]
}


# 0 Read Version Information
# 1 Read Program Memory
# 2 Write Program Memory
# 3 Erase Program Memory
# 4 Read EEDATA Memory
# 5 Write EEDATA Memory
# 6 Read Config Memory
# 7 Write Config Memory
# 8 Reset

proc upgrade::cocmd {cmd len {data {}} {timeout 2000} {retries 3}} {
    global dev devtype cocmd cocnt copct
    # Build the complete list
    binary scan $data cu* list
    set list [linsert $list 0 $cmd $len]
    # Add the checksum
    lappend list [checksum $list]
    # Escape the special characters
    set escape {5 5 4 5 15 5}
    # Escape 0xff bytes when sending over telnet
    if {$devtype eq "telnet"} {
	lappend escape 255 255
    }
    foreach {n e} $escape {
	foreach x [lreverse [lsearch -exact -all -integer $list $n]] {
	    set list [lreplace $list $x $x $e $n]
	}
    }
    # Wrap the package in <STX>/<ETX>
    set str [binary format cc*c 15 $list 4]
    binary scan $str H* hex
    debug >$hex
    if {$timeout == 0} {
	# Send the command without expecting a response
	puts -nonewline $dev $str
	return
    }
    for {set try 0} {$try < $retries} {incr try} {
	# Send the command
	puts -nonewline $dev $str
	# Get the response
	set resp {}
	set ch [cogetch]
	if {$ch != 15} {
	    # Drain whatever rubbish was received before trying again
	    while {$ch ne ""} {
		puts "ch=$ch"
	    	set ch [cogetch 100]
	    }
	    continue
	}
	while {[set ch [cogetch]] != 4} {
	    if {$ch eq ""} break
	    if {$ch == 5} {set ch [cogetch]}
	    lappend resp $ch
	}
	# Check the checksum
	if {$ch == 4 && [checksum $resp] == 0} break
    }
    # Update command count
    if {$cocnt > 0} {
	incr cocmd
	set copct [expr {100 * $cocmd / $cocnt}]%
    }
    # Return the response
    set rc [binary format c* [lrange $resp 0 end-1]]
    binary scan $rc H* hex
    debug <$hex
    return $rc
}

proc upgrade::sendbreak {} {
    global dev devtype
    if {$devtype eq "telnet"} {
	# Telnet connection
	puts -nonewline $dev [binary format cc 255 243]
	flush $dev
	return 1
    } elseif {$devtype eq "comport"} {
	# Serial port
	fileevent $dev readable {}
	fconfigure $dev -ttycontrol {BREAK 1}
	set id [after 5 [list [info coroutine] sendbreak]]
	while {[yield] ne "sendbreak"} {}
	after cancel $id
	fconfigure $dev -ttycontrol {BREAK 0}
	return 1
    } else {
	# Other device types don't support sending a break
	return 0
    }
}

proc upgrade::loadhex {cmd} {
    global mem dev devtype cocmd cocnt copct restore gwversion
    variable retries
    variable fwversion
    variable eeold
    variable eenew
    set ans ""
    lassign [dict get $mem code] inst1 inst2
    if {$inst1 != 0x158a || ($inst2 & 0x3E00) != 0x2600} {
	set ans [$cmd check magic]
	if {$ans ne "ok"} {return abort}
    }
    try {
	$cmd init
	set handler [fileevent $dev readable]
	set config [fconfigure $dev]
	fconfigure $dev -translation binary -buffering none
    } trap {TCL LOOKUP CHANNEL} err {
	debug $err
	$cmd status "Firmware update failed - not connected"
	$cmd done
	return failed
    } on error err {
	debug $err
	$cmd status "Firmware update failed - $err"
	$cmd done
	return failed
    }
    set retries 0
    set errors 0
    try {
	set cocnt 0
	set cocmd 0
	set copct 0%
	$cmd status "Switching gateway to self-programming mode"
	if {![sendbreak] || ![cowaitch 4 1000]} {
	    if {[package vsatisfies $gwversion 4.0a6-]} {
		# Send a reset serial command. Make sure to terminate with only
		# a \r. Sending \r\n would cut short the delay at the start of
		# the self programming code, possibly mutilating the ETX char.
		puts -nonewline $dev GW=R\r
		cowaitch 4 2000
	    }
	}
	# Check if the gateway is in self-programming mode
	set rc [cocmd 0 3 {} 100 1]
	if {$rc eq ""} {
	    $cmd status "Please manually reset the OpenTherm Gateway"
	    $cmd manual
	    if {![cowaitch 4 60000]} {
		# Failed to get OTGW's attention
		$cmd status \
		  "Could not switch gateway to self-programming mode"
		return failed
	    }
	    set rc [cocmd 0 3]
	}
	if {[binary scan $rc x2cucususu min maj addr1 addr2] != 4} {
	    $cmd status "Could not put gateway into self-programming mode"
	    return failed
	}
	$cmd status [format "Bootloader version %d.%d: %03X-%03X" \
	  $maj $min $addr1 $addr2]

	if {$ans ne "ok" && ($inst2 & 0x7ff | 0x800) != $addr1} {
	    if {[$cmd check call] ne "ok"} {
		# Exit self-programming mode
		cocmd 8 0 {} 0
		return abort
	    }
	}

	# Read the settings, if they should be restored
	if {$restore == 1} {
	    # Collect the data in blocks of 64 bytes
	    for {set list {}; set i 0} {$i < 256} {incr i 64} {
		set data [cocmd 4 64 [binary format s $i]]
		binary scan $data x4cu* tmp
		lappend list {*}$tmp
	    }
	    set list [restore $eeold $eenew $list]
	} else {
	    unset -nocomplain ::eeprom
	    set list [dict get $mem data]
	}

	# Calculate the number of commands to send
	# Fail-save code: erase + program + verify
	incr cocnt 3

	# Program memory
	set code {}
	for {set pc 0} {$pc < 0x1000} {incr pc 32} {
	    if {$pc + 31 >= $addr1 && $pc <= $addr2} continue
	    set row [lrange [dict get $mem code] $pc [expr {$pc + 31}]]
	    set filled [lsearch -all -exact -not $row {}]
	    if {[llength $filled] > 0} {
		set first [expr {$pc + [lindex $filled 0]}]
		set last [expr {$pc + [lindex $filled end]}]
		lappend code [list $first $last]
		incr cocnt 3
	    }
	}
	# Data EEPROM
	set data {}
	set n 0
	while {[set x [lsearch -start $n -exact -not $list {}]] >= 0} {
	    set n [lsearch -start $x -exact $list {}]
	    set n [expr {min($n < 0 ? [llength $list] : $n, $x + 64)}]
	    lappend data [list $x [expr {$n - 1}]]
	    incr cocnt 2
	}
	$cmd progress $cocnt
	set cocmd 0
	set copct 0%

	# Interrupting the download could leave the device in an unrecoverable
	# state, so do not offer the option to cancel the download
	$cmd go

	# Fall-back in case programming the first row fails.
	# An erased row has all ADDLW -1 commands. These will execute without
	# doing any harm. By first putting a jump to the self-programming code
	# in the second row, the device can still be recovered if programming
	# fails between erasing and reprogramming the first row.

	# Create the jump to self-programming code commands
	if {$addr1 & 0x800} {
	    # Self-programming code in the upper bank (normal situation)
	    set prog [list 0x158a]	;# BSF PCLATH,3
	} else {
	    # Self-programming code in the lower bank
	    set prog [list 0x118a]	;# BCF PCLATH,3
	}
	lappend prog [expr {0x2000 + ($addr1 & 0x7ff)}]	;# CALL SelfProg
	lappend prog 0x118a		;# BCF PCLATH,3
	lappend prog 0x2820		;# GOTO 0x20

	# Program the fail-safe code
	loadrow 32 $prog

	# Start programming
	foreach rec $code {
	    lassign $rec first last
	    incr errors \
	      [loadrow $first [lrange [dict get $mem code] $first $last]]
	    $cmd progress $cocnt
	    $cmd status "$retries retries, $errors errors"
	}
	foreach n $data {
	    lassign $n first last
	    set bytes [lrange $list $first $last]
	    set len [llength $bytes]
	    for {set try 0} {$try < 3} {incr try;incr cocnt 2;incr retries} {
		# Write the bytes
		set rc [cocmd 5 $len [binary format sc* $first $bytes]]
		# Verify the bytes
		set rc [cocmd 4 $len [binary format s $first]]
		if {[binary scan $rc x4cu* vfy] != 1} continue
		set mismatch 0; foreach n1 $bytes n2 $vfy {
		    if {$n1 != $n2} {incr mismatch}
		}
		if {$mismatch == 0} break
	    }
	    incr errors $mismatch
	    $cmd progress $cocnt
	    $cmd status "$retries retries, $errors errors"
	}
	debug $cocnt:$cocmd
	set cocmd $cocnt
	set copct 100%
	if {$errors == 0} {
	    # Start the program
	    cocmd 8 0 {} 0
	    $cmd status "Firmware download succeeded - $retries retries"
	    set gwversion $fwversion
	}
	return success
    } on error err {
	debug $err
	puts stderr $::errorInfo
	$cmd status "Firmware update failed - $errors errors"
	return failed
    } finally {
	# fileevent $dev readable $handler
	# fconfigure $dev {*}[dict remove $config -peername -sockname]
	# Get a fresh new connection
	catch {connect reconnect}
	$cmd done
    }
}

proc upgrade::loadrow {addr data} {
    global cocnt
    variable retries
    set str [format %04X: $addr]
    foreach n $data {
	append str [format " %04X" $n]
    }
    set prog [linsert $data 0 {*}[lrepeat [expr {$addr & 3}] {}]]
    while {[llength $prog] & 3} {lappend prog {}}
    set cnt [expr {[llength $prog] >> 2}]
    # Set the empty addresses to all ones
    foreach n [lsearch -all -exact $prog {}] {lset prog $n 0x3fff}
    for {set try 0} {$try < 3} {incr try;incr cocnt 3;incr retries} {
	# Erase the row before reprogramming it
	set rc [cocmd 3 1 [binary format s [expr {$addr & ~31}]]]
	# Program the row
	set rc [cocmd 2 $cnt [binary format ss* $addr $prog]]
	# Verify the row
	set rc [cocmd 1 [llength $data] [binary format s $addr]]
	if {[binary scan $rc x4su* vfy] != 1} continue
	set pc $addr
	set mismatch 0; foreach n1 $data n2 $vfy {
	    if {$n1 ne {} && $n1 != $n2} {
		if {[string is integer -strict $n2]} {
		    debug [format {%04X: %04X/%04X} $pc $n1 $n2]
		} else {
		    debug [format {%04X: %04X/%s} $pc $n1 $n2]
		}
		incr mismatch
	    }
	    incr pc
	}
	if {$mismatch == 0} break
	debug "$mismatch mismatches"
    }
    return $mismatch
}

proc upgrade::eeprom {version} {
    set supported {
	3.0 3.1 3.2 3.3 3.4
	4.0a0 4.0a1 4.0a2 4.0a3 4.0a4 4.0a5 4.0a6 4.0a7 4.0a8
	4.0a9 4.0a9.1 4.0a10 4.0a11 4.0a11.1 4.0a11.2 4.0a12
    }
    if {$version == 0 || \
      $version ni $supported && ![package vsatisfies $version 4.0b0-4.3]} {
	return {}
    }
    set rc {
	SavedSettings {
	    address	0x00
	    size	1
	    mask	0x7F
	}
	FunctionGPIO {
	    address	0x01
	    size	1
	}
	AwaySetpoint {
	    address	0x02
	    size	2
	}
	FunctionLED {
	    address	0x06
	    size	6
	}
	ThermostatModel {
	    address	0x0d
	    size	1
	}
	UnknownFlags {
	    address	0xd0
	    size	16
	}
	AlternativeCmd {
	    address	0xe0
	    size	32
	}
    }

    # GPIO settings and away setpoint were introduced in firmware 4.0a6
    # The amount of LEDs was increase from 4 to 6 in firmware 4.0a6
    if {![package vsatisfies $version 4.0a6-]} {
	dict unset rc FunctionGPIO
	dict unset rc AwaySetpoint
	dict set rc FunctionLED address 0x01
	dict set rc FunctionLED size 4
    }

    # In firmware 4.0a7 and 4.0a8 there was no L= in front of the LED settings
    if {[package vsatisfies $version 4.0a7-4.0a9]} {
	dict set rc FunctionLED address 0x04
    }

    # Manual definition of unknown messages was introduced in firmware 4.0a7
    if {![package vsatisfies $version 4.0a7-]} {
	dict unset rc UnknownFlags
    } else {
	switch -- $version {
	    4.0a7 - 4.0a8 {
		dict set rc UnknownFlags address 0xaa
	    }
	    4.0a9 {
		dict set rc UnknownFlags address 0xaf
	    }
	    4.0a9.1 {
		dict set rc UnknownFlags address 0xb1
	    }
	    4.0a10 - 4.0a11 - 4.0a12 {
		dict set rc UnknownFlags address 0xb3
	    }
	    4.0a11.1 - 4.0a11.2 {
		dict set rc UnknownFlags address 0xb5
	    }
	}
    }

    # Termostat responses were stored in EEPROM between 4.0a3 and 4.0b0
    if {[package vsatisfies $version 4.0a3-4.0b0]} {
	dict set rc ThermResponse {address 0xd8 size 8}
    }

    # Before 4.0b0 only 6 bits of the settings byte were used
    if {![package vsatisfies $version 4.0b0-]} {
	dict set rc SavedSettings mask 0x3F
    }

    # Thermostat model setting was introduced in 4.1
    # Version 4.0.1.1 hardcoded it to Celcia 20
    if {$version eq "4.0.1.1"} {
	dict set rc ThermostatModel value 0x30
    } elseif {![package vsatisfies $version 4.1-]} {
	dict unset rc ThermostatModel
    }
    return $rc
}

proc upgrade::restore {old new data} {
    global mem eeprom
    set list [dict get $mem data]
    set eeprom $new
    dict for {name dict} $old {
	if {![dict exists $new $name]} continue
	# Skip settings that are hardcoded in the new firmware version
	if {[dict exists $new $name value]} continue
	lassign {} mask1 mask2
	set pc1 [dict get $dict address]
	if {[dict exists $dict mask]} {
	    set mask1 [dict get $dict mask]
	}
	set pc2 [dict get $new $name address]
	if {[dict exists $new $name mask]} {
	    set mask2 [dict get $new $name mask]
	}
	set value {}
	set cnt [expr {min([dict get $dict size], [dict get $new $name size])}]
	for {set i 0} {$i < $cnt} {incr i; incr pc1; incr pc2} {
	    if {[dict exists $dict value]} {
		set oldbyte [lindex [dict get $dict value] $i]
	    } else {
		set oldbyte [lindex $data $pc1]
	    }
	    set newbyte [lindex $list $pc2]
	    if {![string is integer -strict $newbyte]} {set newbyte 0}
	    # Apply a bit mask, if applicable
	    set m1 [lindex $mask1 $i]
	    set m2 [lindex $mask2 $i]
	    if {$m1 ne "" || $m2 ne ""} {
		if {$m1 eq ""} {set m1 0xff}
		if {$m2 eq ""} {set m2 0xff}
		set oldbyte [expr {$oldbyte & $m2 | $newbyte & ~$m1}]
	    }
	    lappend value $oldbyte
	    if {$newbyte != $oldbyte} {
		debug [format {%02x: %02x -> %02x} $pc2 $newbyte $oldbyte]
		lset list $pc2 $oldbyte
	    }
	}
	dict set eeprom $name value $value
    }
    return $list
}

namespace eval flash {
    variable status "" dangling 0
    namespace ensemble create -subcommands {
	start status check init manual progress go done
    }

    proc start {} {
	coroutine coro upgrade loadhex [namespace current]
    }

    proc status {msg} {
	variable status
	if {[scan $msg {%d retries, %d errors} n1 n2] == 2} return
	if {$msg ne $status} {
	    variable dangling
	    if {$dangling} {
		puts -nonewline stderr "\r"
		set dangling 0
	    }
	    puts stderr $msg
	    set status $msg
	}
    }

    proc check {what} {
	if {$what eq "magic"} {
	    puts stderr "Warning: The selected firmware does not start\
	      with the recommended instruction sequence.\nThis may render\
	      the device incapable of performing any firmware updates in\
	      the\nfuture.\n"
	} elseif {$what eq "call"} {
	    puts stderr "Warning: The startup instruction sequence calls a 
              different address than the starting\naddress reported by the\
              current self-programming code. This may render the\n device\
              inoperable.\n"
	}
	set ans ""
	while {$ans ni {y n yes no}} {
	    puts -nonewline stderr "Are you sure you want to continue? "
	    flush stderr
	    set ans [string tolower [gets stdin]]
	}
	return [lindex {ok cancel} [expr {!$ans}]]
    }

    proc init {} {}

    proc manual {} {}

    proc progress {max} {
	global cocnt
	set cocnt $max
    }

    proc vartrace {var arg op} {
	global cocmd cocnt
	if {$cocnt > 0} {
	    puts -nonewline stderr [format "\rProgress: %d%%" \
	      [expr {100 * $cocmd / $cocnt}]]
	    variable dangling 1
	}
    }

    proc go {} {
	global cocmd
	trace add variable cocmd write [namespace code vartrace]
    }

    proc done {} {
	trace remove variable cocmd write [namespace code vartrace]
	exit 0
    }
}
