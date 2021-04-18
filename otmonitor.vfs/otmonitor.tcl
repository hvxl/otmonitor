#!/usr/bin/wish8.6
## -*- tcl -*-
# Opentherm monitor utility.
# For more information, see http://otgw.tclcode.com/otmonitor.html

set version 5.1
set reportflags 0
set appendlog 0
set setpt 20.00
set setback 16.00
set voltref 3
set dhwsetpoint 60.00
set chsetpoint 75.00
set devtype none
set fwvariant ""
set fwversion 0
set gwmode Unknown
set midbit 1
set docpath {}
set restore -1
set span 7200
set cmdline [linsert $argv 0 [file normalize $argv0]]
set wibblesock {}
set userauth {{} {mtime 0}}
set signalproc {}
set clients {}
set connected 0

# Allow users to override the built-in pages
lappend docpath [file join [file dirname $starkit::topdir] html]

# Top directory for static web content
lappend docpath [file join $starkit::topdir docroot]

# Location of images to be used by the GUI and the web server
set imgdir [file join $starkit::topdir images]

set types {
    Read-Data
    Write-Data
    Inv-Data
    Reserved
    Read-Ack
    Write-Ack
    Data-Inv
    Unk-DataId
}

set functions {
    R	"Receiving an Opentherm message"
    X	"Transmitting an Opentherm message"
    T	"Thermostat communication"
    B	"Boiler communication"
    O	"Setpoint override"
    F	"Flame status"
    H	"Central heating status"
    W	"Domestic hot water status"
    C	"Domestic hot water enable"
    E	"Transmission error"
    M	"Boiler requires maintenance"
    P	"Raised power mode active"
}

set gpiofunc {
    0	"None"
    1	"Ground (0V)"
    2	"Vcc (5V)"
    3	"LED E"
    4	"LED F"
    5	"Setback (low)"
    6	"Setback (high)"
    7	"Temp sensor"
}

array set error {
    1	0
    2	0
    3	0
    4	0
}

array set gpio {A 0 B 0}
array set led {A F B X C O D M E P F C}

array set learn {
    LA PR=L LB PR=L LC PR=L LD PR=L LE PR=L LF PR=L GA PR=G GB PR=G
    VR PR=V GW PR=M IT PR=T SB PR=S HW PR=W
}

# Translation of internal names
set xlate {
    airpresfault	"Air pressure fault"
    boilertemp		"Boiler water temperature"
    boilertemp2		"Boiler water temperature 2"
    exhausttemp		"Boiler exhaust temperature"
    ch2enable		"Central heating 2 enable"
    ch2mode		"Central heating 2 mode"
    chenable		"Central heating enable"
    chmode		"Central heating mode"
    chwsetpoint		"Central heating setpoint"
    chbh		"CH burner hours"
    chbs		"CH burner starts"
    chph		"CH pump hours"
    chps		"CH pump starts"
    pressure		"CH water pressure"
    controlsp		"Control setpoint"
    controlsp2		"Control setpoint 2"
    coolingenable	"Cooling enable"
    coolingstatus	"Cooling status"
    diag		"Diagnostic indication"
    dhwbh		"DHW burner hours"
    dhwbs		"DHW burner starts"
    dhwflowrate		"DHW flow rate"
    dhwph		"DHW pump hours"
    dhwps		"DHW pump starts"
    dhwenable		"Domestic hot water enable"
    dhwmode		"Domestic hot water mode"
    dhwsetpoint		"Domestic hot water setpoint"
    dhwtemp		"Domestic hot water temp"
    dhwtemp2		"Domestic hot water temp 2"
    fault		"Fault indication"
    flame		"Flame"
    flamefault		"Gas/flame fault"
    lockoutreset	"Lockout-reset"
    lowpressure		"Low water pressure"
    maxmod		"Max rel modulation level"
    modulation		"Modulation"
    faultcode		"OEM fault/error code"
    otcstate		"Outside temp compensation"
    outside		"Outside temperature"
    override    	"Rem override room setpoint"
    returntemp		"Return water temperature"
    setpoint		"Room setpoint"
    setpoint2		"Room setpoint 2"
    roomtemp		"Room temperature"
    roomtemp2		"Room temperature 2"
    service		"Service request"
    timestamp		"Time stamp"
    overtemp		"Water over-temperature"
}

# Graph definitions used by both gui and web
set graphdef {
    dhwmode {
	origin 0 type polygon min 0 max 1 scale 2 zoom 12 format {%s}
	line {
	    dhwenable	{color #ccf name "Domestic hot water enable"}
	    dhwmode	{color #00f name "Domestic hot water mode"}
	}
	color #00f name "Domestic hot water"
    }
    chmode {
	origin 0 type polygon min 0 max 1 scale 2 zoom 12 format {%s}
	line {
	    chenable	{color #cfc name "Central heating enable"}
	    chmode	{color #0c0 name "Central heating mode"}
	}
	color #0c0 name "Central heating"
    }
    chmode2 {
	origin 0 type polygon min 0 max 1 scale 2 zoom 12 format {%s}
	line {
	    ch2enable	{color #cf4 name "Central heating 2 enable"}
	    ch2mode	{color #8c0 name "Central heating 2 mode"}
	}
	color #8c0 name "Central heating 2"
    }
    flame {
	origin 0 type polygon min 0 max 1 scale 2 zoom 12 format {%s}
	line {
	    flame	{color #f00 name "Flame status"}
	}
    }
    modulation {
	origin 0 type line min 0 max 110 scale 25 zoom .75 format {%.2f%%}
	line {
	    maxmod	{color #ccc name "Max rel modulation level"}
	    modulation	{color #000 name "Relative modulation level"}
	}
    }
    temperature {
	origin 0 type line min -20 max 92 scale 5 zoom 4 format "%.2f\u00b0C"
	line {
	    controlsp	{color #ccc name "Control setpoint"}
	    returntemp	{color #00f name "Return water temperature"}
	    boilertemp	{color #f00 name "Boiler water temperature"}
	    dhwtemp	{color #f80 name "DHW temperature"}
	    setpoint	{color #0cc name "Room setpoint"}
	    outside	{color #0c0 name "Outside temperature"}
	    roomtemp	{color #c0c name "Room temperature"}
	}
    }
    temperature2 {
	origin 0 type line min -20 max 92 scale 5 zoom 4 format "%.2f\u00b0C"
	line {
	    controlsp2	{color #ccc name "Control setpoint"}
	    returntemp2	{color #00f name "Return water temperature"}
	    boilertemp2	{color #f00 name "Boiler water temperature"}
	    dhwtemp2	{color #f80 name "DHW temperature"}
	    setpoint2	{color #0cc name "Room setpoint"}
	    outside2	{color #0c0 name "Outside temperature"}
	    roomtemp2	{color #c0c name "Room temperature"}
	}
    }
}
	    
set period 5
set logsize 15000
set masterid dummy
set interval 30000
set tab 0
set verbose 0
set sercmd {}
set lock ""
set override ""
set msglog {}

set options {
    01	want
    03	want
    18	can
}

set sync {date "" year ""}

# Definition of possible signals and their parameters
set signals {
    PowerMode			{mode		string}
    Thermostat  		{connected	boolean}
    Error			{code		byte}
    Flame			{on		boolean}
    HotWater			{on		boolean}
    CentralHeating		{on		boolean}
    Fault			{on		boolean}
    Diagnostic			{on		boolean}
    Cooling			{on		boolean}
    CentralHeating2		{on		boolean}
    Electricity			{on		boolean}
    RoomTemperature		{temp		float}
    RoomTemperature2		{temp		float}
    OutsideTemperature		{temp		float}
    Setpoint			{temp		float}
    Setpoint2			{temp		float}
    ControlSetpoint		{temp		float}
    ControlSetpoint2		{temp		float}
    DHWEnable			{on		boolean}
    DHWSetpoint			{temp		float}
    DHWTemperature		{temp		float}
    DHWTemperature2		{temp		float}
    CHEnable			{on		boolean}
    CHSetpoint			{temp		float}
    Modulation			{level		float}
    MaxModulation		{level		float}	
    BoilerWaterTemperature	{temp		float}
    BoilerWaterTemperature2	{temp		float}
    ReturnWaterTemperature	{temp		float}
    CHWaterPresure		{bar		float}
    RemoteOverrideRoomSetpoint	{temp		float}
    CHWaterDeltaT		{temp		float}
    ExhaustTemperature		{temp		float}
    DHWFlowRate			{rate		float}
    CHBurnerStarts		{count		unsigned}
    CHPumpStarts		{count		unsigned}
    DHWPumpStarts 		{count		unsigned}
    DHWBurnerStarts 		{count		unsigned}
    CHBurnerHours 		{count		unsigned}
    CHPumpHours 		{count		unsigned}
    DHWPumpHours 		{count		unsigned}
    DHWBurnerHours 		{count		unsigned}
    GatewayReset		{}
}

# Standard NRE helper proc
proc yieldm {value} {
    yieldto return -level 0 $value
}

proc flag {val} {
    binary scan [binary format c $val] B8 bits
    return $bits
}

proc unsigned {val} {
    return [format %d $val]
}

proc signed {val} {
    return [format %d [expr {$val > 32767 ? 65536 - $val : $val}]]
}

proc unsigned8 {val} {
    return [format %d $val]
}

proc signed8 {val} {
    return [format %d [expr {$val > 127 ? 256 - $val : $val}]]
}

proc float {val} {
    if {$val & 0x8000} {set val [expr {$val - 65536}]}
    return [format %.2f [expr {$val / 256.}]]
}

proc time {val} {
    set min [expr {$val & 255}]
    set hr [expr {($val >> 8) & 31}]
    set dow [lindex {Unk Mon Tue Wed Thu Fri Sat Sun} [expr {$val >> 13}]]
    return [format {%s %02d:%02d} $dow $hr $min]
}

proc date {val} {
    set day [expr {$val & 255}]
    set m [expr {($val >> 8) & 31}]
    set mon [lindex {Unk Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec} $m]
    return [format {%s %d} $mon $day]
}

proc debug {str} {
    global verbose
    if {$verbose} {puts $str}
}

proc configsave {} {
    global cfg devtype
    # Don't save settings when reading messages from file
    if {$devtype eq "file"} return

    gui savedialogs
    foreach n [array names cfg] {
        lassign [split $n ,] group name
        if {$name in {password}} {
            # Encrypt passwords
            settings set $group $name [binary encode base64 $cfg($n)]
        } else {
            settings set $group $name $cfg($n)
        }
    }
    settings flush
}

proc receive {{data ""}} {
    global dev
    if {[eof $dev] || [catch {gets $dev line} len]} {
	connect reconnect
    } elseif {$len != -1} {
	process [append data $line]
    }
}

proc response {str} {
    global sercmd
    switch -glob $str {
	"PR: ?=*" {
	    set pat PR:[string index $str 4]
	}
	"PR: ??" {
	    set pat PR:?
	}
	"??: *:" {
	    set pat [string range $str 0 2]
	}
	default {
	    set pat *
	}
    }
    set x [lsearch -index 0 $sercmd $pat]
    if {$x >= 0} {
	set rec [lindex $sercmd $x]
	set sercmd [lreplace $sercmd $x $x]
	if {$x == 0} {
	    after cancel cancel
	    if {[llength $sercmd] > 0} {
		set ms [lindex $sercmd 0 2]
		after [expr {$ms + 2000 - [clock milliseconds]}] cancel
	    }
	}
	[lindex $rec 1] $str
    }
}

proc process {line} {
    global fwvariant fwversion cfg clients
    if {$cfg(server,relay)} {
	dict for {client fd} $clients {
	    if {[catch {puts $fd $line}]} {
		catch {close $fd}
		dict unset clients $client
	    }
	}
    }
    if {[scan $line {%1[ABRT]%1x%1x%2x%4x} src type res id data] == 5} {
	otmessage [clock microseconds] $line [expr {$type & 7}] $id $data
	if {$fwversion eq "0" && $src eq "B"} {
	    global count
	    # Stop after a few attempts, in case the report format changes
	    if {[array size count] <= 10} {
		sercmd PR=A
	    } else {
		set fwversion 4.0a9
	    }
	}
    } elseif {[scan $line {Error %2x} errno] == 1} {
	output "[ts]\t$line" error
	global error
	incr error($errno)
	signal error $errno
    } elseif {[scan $line {Opentherm gateway diagnostics - Version %s} ver] == 1} {
	set fwvariant diagnose
	set fwversion $ver
	gui diagnostics $ver
	output "[ts]\t$line"
    } elseif {[set x [string first "OpenTherm Interface " $line]] >= 0} {
	if {[scan [string range $line $x end] {%*s %*s %s} ver] == 1} {
	    # Make sure a valid version number was found
	    if {![catch {package vcompare $ver $ver}]} {
		set fwvariant interface
		set fwversion $ver
	    }
	}
	output "[ts]\t$line"
	response $line
    } elseif {[set x [string first "OpenTherm Gateway " $line]] >= 0} {
	if {$x == 0 || [string index $line [expr {$x - 1}]] ne "="} {
	    set reset 1
	    status "Gateway reset" 5000
	    signal gatewayreset
	    # Assume thermostat is connected unless told otherwise
	    after 50 {signal thermostat 1}
	} else {
	    set reset 0
	}
	output "[ts]\t$line"
	if {[scan [string range $line $x end] {%*s %*s %s} gwver] == 1} {
	    # Make sure a valid version number was found
	    if {![catch {package vcompare $gwver $gwver}]} {
		# Send the time when the gateway version was not yet known,
		# or after a reset of the gateway
		if {$fwversion eq "0" || $reset} {
		    global cfg
		    if {$cfg(clock,auto)} {sync 1}
		}
		set fwvariant gateway
		set fwversion $gwver
	    }
	}
	if {$reset && ![package vsatisfies $fwversion 4.2.8-]} {
	    # Before firmware 4.2.8, the OTGW is in gateway mode after a reset
	    gwmode 1
	}
	response $line
    } elseif {[string match {*WDT reset!*} $line]} {
	output "[ts]\t$line"
	alert watchdogtimer
    } else {
	# Filter out non-printable characters
	output "[ts]\t[regsub -all {[\0-\x1f]} $line {}]"
	response $line
	switch -- $line {
	    "Thermostat disconnected" {
		status "Thermostat disconnected"
		after cancel {signal thermostat 1}
		signal thermostat 0
	    }
	    "Thermostat connected" {
		status "Thermostat connected" 5000
		signal thermostat 1
	    }
	    "High power" {
		status "High power"
		signal powermode high
	    }
	    "Medium power" {
		status "Medium power"
		signal powermode medium
	    }
	    "Low power" {
		status "Low power" 5000
		signal powermode low
	    }
	    default {
		setting $line
	    }
	}
    }
}

proc setting {str} {
    switch -glob $str {
	"PR: L=*" {
	    set str [string range $str 6 11]
	    foreach ch [split $str ""] l {A B C D E F} {
		know L$l $ch
	    }
	}
	"PR: G=[0-7][0-7]" {
	    know GA [string index $str 6]
	    know GB [string index $str 7]
	}
	"PR: V=[0-9]" {
	    know VR [string index $str 6]
	}
	"PR: T=[01]" {
	    know IT [string index $str 6]
	}
	"PR: T=[01][01]" {
	    know IT [string index $str 6]
	    know OH [string index $str 7]
	}
	"PR: M=[GM]" {
	    know GW [expr {[string index $str 6] eq "G"}]
	}
	"PR: S=*" {
	    know SB [string range $str 6 end]
	}
	"PR: W=[01A]" {
	    know HW [string index $str 6]
	}
	"GW: P" {
	    sercmd PR=M
	}
	"L[A-F]: [A-Z]" -
	"G[AB]: [0-7]" -
	"IT: [01]" -
	"OH: [01]" -
	"GW: [01]" -
	"HW: [01A]" -
	"VR: [0-9]" {
	    set set [string range $str 0 1]
	    know $set [string range $str 4 end]
	}
    }
}

proc know {str {val ""}} {
    global know
    if {[llength [info level 0]] > 2} {
	set know($str) $val
    } elseif {[info exists know($str)]} {
	set val $know($str)
    } else {
	return
    }
    switch -- $str {
	LA - LB - LC - LD - LE - LF {
	    global led
	    set led([string index $str 1]) $val
	}
	GA - GB {
	    global gpio
	    set gpio([string index $str 1]) $val
	}
	SB {
	    set ::setback $val
	}
	VR {
	    voltage voltref $val
	}
	IT {
	    set ::midbit $val
	}
	OH {
	    set ::overridehb $val
	}
	GW {
	    gwmode $val
	}
	HW {
	    set ::comfort $val
	}
    }
}

proc learn {args} {
    global know learn
    set cmds {}
    # Check what is already known
    foreach n $args {
	if {[info exists know($n)]} {
	    know $n
	} elseif {[info exists learn($n)]} {
	    if {$learn($n) ni $cmds} {
		lappend cmds $learn($n)
	    }
	}
    }
    # Ask the questions to obtain the missing knowledge
    foreach n $cmds {
	sercmd $n
    }
}

proc voltage {name val} {
    global voltage
    upvar #0 $name var
    set var [expr {round($val)}]
    set voltage [format %.3f [expr {($var + 3) * 5. / 24}]]
}

proc ts {{ts ""}} {
    global timestamp
    if {$ts eq ""} {set ts [clock microseconds]}
    set timestamp [expr {$ts / 1000000}]
    set sec [expr {$ts / 1000000}]
    set us [expr {$ts % 1000000}]
    format %s.%06d [clock format $sec -format %T] $us
}

proc setstatus {var str {delay 0}} {
    upvar #0 $var status
    set cmd [list setstatus $var ""]
    after cancel $cmd
    if {$delay > 0} {after $delay $cmd}
    set status $str
}

proc gwmode {sw} {
    global gwmode
    if {$sw} {
	set gwmode "Gateway mode"
    } else {
	set gwmode "Monitor mode"
    }
}

interp alias {} status {} setstatus status

proc output {str {tag ""}} {
    global cfg timestamp msglog
    gui output $str $tag
    set str [untab $str 17 28 40 48 56 64 72 80]
    # set msglog [lreplace [linsert $msglog end $str] 0 end-1000]
    set msglog [lrange [linsert $msglog end $str] end-999 end]
    if {$cfg(logfile,enable)} {
	set file [file join $cfg(logfile,directory) \
	  [clock format $timestamp -format $cfg(logfile,pattern)]]
	if {![catch {open $file a} fd]} {
	    puts $fd $str
	    catch {close $fd}
	}
    }
}

proc untab {str args} {
    set parts [lassign [split $str \t] rc]
    set tabs [lrange $args 0 [expr {[llength $parts] - 1}]]
    foreach s $parts n $tabs {
	append rc [string repeat " " [expr {$n - [string length $rc]}]] $s
    }
    return $rc
}

proc otdecode {var type id} {
    global types message cfg
    upvar 1 $var data
    set str [lindex $types $type]
    if {[info exists message($id)]} {
	lassign $message($id) msg args
	if {[llength $args] > 1} {
	    set data [list [expr {$data >> 8}] [expr {$data & 255}]]
	}
	set vallist {}
	foreach arg $args val $data {
	    switch $arg {
		flag8 {lappend vallist [flag $val]}
		u8 {lappend vallist [unsigned8 $val]}
		s8 {lappend vallist [signed8 $val]}
		f8.8 {lappend vallist [float $val]}
		u16 {lappend vallist [unsigned $val]}
		s16 {lappend vallist [signed $val]}
		nu {# Not used}
		default {lappend vallist [$arg $val]}
	    }
	}
	set val [join $vallist]
    } else {
	set msg "Message ID $id"
	set val $data
    }
    if {$cfg(view,messageid)} {
	append msg " (MsgID=$id)"
    }
    return [list $str $msg $val]
}

proc otmessage {us src type id data} {
    global special last count value after override timestamp cfg

    set ts [ts $us]
    if {$cfg(mqtt,enable) && $cfg(mqtt,messages)} {mqttmessage $src}
    lassign [otdecode data $type $id] str msg val
    set str [format "%-10s\t%s: %s" $str $msg $val]
    set op [lindex {read write res res read write invalid unknown} $type]
    output "$ts\t$src\t$str" [list id-$type,$id $op]

    set ch [string index $src 0]
    set ref [format %x%02x $type $id]
    if {$override ne "" && ($override != $ref || $ch ni {A R})} {
	# Complete any pending coroutine
	specialcoro flush
    }

    # Perform special treatment of the message, if any
    if {[info exists special($type,$id)]} {
	if {[coroutine specialcoro {*}$special($type,$id) $data]} {
	    if {$ch in {A R}} {
		# Can't override A or R messages
		specialcoro force
	    } else {
		set override $ref
	    }
	}
    }

    switch -- $type,$id {
	4,5 - 4,115 {
	    alert boilerfault {*}$val
	}
	4,72 - 4,73 {
	    alert ventilationfault {*}$val
	}
	4,102 {
	    alert solarfault {*}$val
	}
	1,24 {
	    alert roomcold $val
	}
	4,18 {
	    alert pressure $val
	}
    }

    if {$type == 7} {
	set value($type,$id) ???
    } else {
    	set value($type,$id) $val
    }
    incr count($type,$id)
    gui tvtrace $type $id
    set now $timestamp
    lappend last($type,$id)
    set index [expr {[llength $last($type,$id)] - 1}]
    if {$index > 4 && [lindex $last($type,$id) $index] < $now - 60} {
	incr index -1
    }
    set last($type,$id) [linsert [lrange $last($type,$id) 0 $index] 0 $now]
}

proc register {id argtypes desc} {
    global message
    set message($id) [list $desc $argtypes]
}

proc special {type id args} {
    global special after
    set after($type,$id) dummy
    set special($type,$id) $args
}

proc reportflags {msb lsb vals} {
    global cfg
    if {!$cfg(view,bitflags)} {return 0}
    foreach data [list $msb $lsb] val $vals {
	foreach bit [split [string reverse [flag $val]] ""] {str list} $data {
	    if {$str eq ""} continue
	    output "\t\t   - $str: [lindex $list $bit] ($bit)"
	}
    }
    return 0
}

proc reportenum {name list val} {
    global cfg
    if {!$cfg(view,bitflags)} return
    output "\t\t   - $name: [lindex $list $val] ($val)"
}

proc dump {} {
    global gui cfg
    after cancel dump
    set now [clock milliseconds]
    set wait [expr {$cfg(datalog,interval) - $now % $cfg(datalog,interval)}]
    after $wait dump
    set access [lindex {a w} [expr {!$cfg(datalog,append)}]]
    if {![catch {open $cfg(datalog,file) $access} fd]} {
	foreach n $cfg(datalog,itemlist) {dict set dump $n ""}
	set rec [dict merge $dump [array get gui]]
	dict set rec timestamp \
	  [clock format [clock seconds] -format {%Y%m%d;%T}]
	set len [llength $cfg(datalog,itemlist)]
	puts $fd [join [lrange [dict values $rec] 0 [expr {$len - 1}]] {;}]
	catch {close $fd}
    }
}

proc overridedelay {{delay 50}} {
    global override
    # Delay a while to allow a second message to override the initial value
    # This can happen when the gateway modifies the message and follows the
    # T or B message with a R or A message for the same MsgID. In such a
    # case, the coroutine will be recreated, which automatically cancels the
    # yield. The after event does have to be canceled separately, which is
    # done when the new coroutine calls this proc.
    set cmd [list [info coroutine] timer]
    after cancel $cmd
    set id [after $delay $cmd]
    set rc [yield 1]
    after cancel $id
    set override ""
    return 0
}

proc masterstatus {list} {
    global masterid
    reportflags {
	"CH enable"		{disabled enabled}
	"DHW enable"		{disabled enabled}
	"Cooling enable"	{disabled enabled}
	"OTC active"		{"not active" active}
	"CH2 enable"		{disabled enabled}
	"Summer/winter mode"	{winter summer}
	"DHW blocking"		{unblocked blocked}
    } {
    } $list
    overridedelay 100
    guiflag chenable [expr {([lindex $list 0] & 1) != 0}] chenable
    guiflag dhwenable [expr {([lindex $list 0] & 2) != 0}] dhwenable
    guiflag coolingenable [expr {([lindex $list 0] & 4) != 0}]
    guiflag otcstate [expr {([lindex $list 0] & 8) != 0}]
    guiflag ch2enable [expr {([lindex $list 0] & 16) != 0}]
    return 0
}

proc slavestatus {list} {
    reportflags {
    } {
	"Fault indication"	{"no fault" fault}
	"CH mode"		{"not active" active}
	"DHW mode"		{"not active" active}
	"Flame status"		{"flame off" "flame on"}
	"Cooling status"	{"not active" active}
	"CH2 mode"		{"not active" active}
	"Diagnostic indication"	{"no diagnostics" "diagnostic event"}
	"Electricity production" {"not active" active}
    } $list
    overridedelay
    guiflag fault [expr {([lindex $list 1] & 1) != 0}] fault
    guiflag chmode [expr {([lindex $list 1] & 2) != 0}] centralheating
    guiflag dhwmode [expr {([lindex $list 1] & 4) != 0}] hotwater
    guiflag flame [expr {([lindex $list 1] & 8) != 0}] flame
    guiflag coolingstatus [expr {([lindex $list 1] & 16) != 0}] cooling
    guiflag ch2mode [expr {([lindex $list 1] & 32) != 0}] centralheating2
    guiflag diag [expr {([lindex $list 1] & 64) != 0}] diagnostic
    guiflag electricity [expr {([lindex $list 1] & 128) != 0}] electricity
    return 0
}

proc masterconfig {list} {
    reportflags {
	"Smart power" {"not supported" supported}
    } {
    } $list
    return 0
}

proc slaveconfig {list} {
    reportflags {
	"DHW"	    			{"not present" present}
	"Control type"			{modulating on/off}
	"Cooling"   			{"not supported" supported}
	"DHW"	    			{instantaneous "storage tank"}
	"Master pump control"		{allowed "not allowed"}
	"CH2"		    		{"not present" present}
	"Remote water filling"		{available/unknown "not available"}
	"Heat/cool mode control"	{heat cool}
    } {
    } $list
    lassign $list flags vendor
    guiflag ch2 [expr {($flags & 32) != 0}]
    ### For testing !!!
    # guiflag ch2 [expr {($flags & 64) != 0}]
    return 0
}

proc mastersolar {list} {
    reportenum "Solar mode" {
	"Off"
	"DHW eco"
	"DHW comfort"
	"DHW single boost"
	"DHW continuous boost"
    } [expr {[lindex $list 0] & 7}]
    return 0
}

proc slavesolar {list} {
    set flags [lindex $list 1]
    reportenum "Fault indication" {"no fault" fault} [expr {$flags & 1}]
    reportenum "Solar mode" {
	"off"
	"DHW eco"
	"DHW comfort"
	"DHW single boost"
	"DHW continuous boost"
    } [expr {$flags >> 1 & 7}]
    reportenum "Solar status" {
	"standby"
	"loading by sun"
	"loading by boiler"
	"anti-legionella"
    } [expr {$flags >> 4 & 3}]
    return 0
}

proc asfflags {list} {
    global gui
    reportflags {
	"Service request"		{no yes}
	"Lockout-reset"			{disabled enabled}
	"Low water pressure"		{"no fault" fault}
	"Gas/flame fault"   		{"no fault" fault}
	"Air pressure fault"		{"no fault" fault}
	"Water over-temperature"	{"no fault" fault}
    } {
    } $list
    lassign $list flags value
    guiflag service [expr {($flags & 1) != 0}]
    guiflag lockoutreset [expr {($flags & 2) != 0}]
    guiflag lowpressure [expr {($flags & 4) != 0}]
    guiflag flamefault [expr {($flags & 8) != 0}]
    guiflag airpresfault [expr {($flags & 16) != 0}]
    guiflag overtemp [expr {($flags & 32) != 0}]
    if {[catch {expr {$value != $gui(faultcode)}} rc] || $rc} {
	set gui(faultcode) $value
    }
    return 0
}

proc returntemp {list} {
    global gui
    guifloat returntemp returnwatertemperature $list
    if {[info exists gui(boilertemp)]} {
	set value [format %.2f [expr {$gui(boilertemp) - $gui(returntemp)}]]
	signal chwaterdeltat $value
	set gui(deltatemp) $value
    }
}

proc readwrite {msgtype cmd name args} {
    global readwrite
    if {$msgtype == 1} {
	set readwrite($name) [lindex $args end]
    } elseif {$msgtype >= 4} {
	if {$msgtype == 7} {
	    if {[info exists readwrite($name)]} {
		lset args end $readwrite($name)
	    } else {
		tailcall unknownid $name 0
	    }
	}
	set rc [$cmd $name {*}$args]
	unset -nocomplain readwrite($name)
	return $rc
    }
    return 0
}

proc guifloat {name args} {
    global gui
    overridedelay
    lassign [lreverse $args] value signal
    set float [float $value]
    if {[catch {expr {$float != $gui($name)}} rc] || $rc} {
	set gui($name) $float
	if {$signal ne ""} {
	    signal $signal $float
	    set gui($signal) $float
	}
    }
    return 0
}

proc guishort {name args} {
    global gui
    overridedelay
    lassign [lreverse $args] value signal
    set short [unsigned8 $value]
    if {[catch {expr {$short != $gui($name)}} rc] || $rc} {
	set gui($name) $short
	if {$signal ne ""} {
	    signal $signal $short
	    set gui($signal) $short
	}
    }
    return 0
}

proc guiflag {name value {signal ""}} {
    global gui
    if {[catch {expr {$value != $gui($name)}} rc] || $rc} {
	set gui($name) $value
	if {$signal ne ""} {
	    signal $signal $value
	    set gui($signal) $value
	}
    }
}

proc unknownid {name value} {
    global gui
    overridedelay
    # Avoid unnecessary triggering of variable traces
    if {[catch {expr {$gui($name) ne "???"}} rc] || $rc} {
	set gui($name) ???
    }
    return 0
}

proc sizeof {str {font TkDefaultFont}} {
    return [font measure $font $str]
}

proc connected {flag} {
    variable connected [expr {!!$flag}]
    gui connected $flag
}

proc connect {type} {
    if {$type ne "disconnect"} {
	coroutine connect connectcoro $type
	trace add command connect delete borked
    }
}

proc surprise {info args} {
    global surprise
    set msg [linsert $args 0 [clock format [clock seconds]]]
    set info [dict merge {-errorcode "" -errorinfo ""} $info]
    lappend msg [dict get $info -errorcode] [dict get $info -errorinfo]
    # Only keep the last 25 surprises
    set surprise [lrange [lappend surprise [join $msg \n]] end-24 end]
}

proc borked {name args} {
    global errorCode errorInfo
    set info [dict create -errorcode $errorCode -errorinfo $errorInfo]
    surprise $info "Command $name was deleted unexpectedly"
}

proc socketresult {fd type} {
    global devtype cfg
    set error [fconfigure $fd -error]
    if {$error ne ""} {
	if {$type ne "reconnect"} {
	    status [string toupper $error 0 0]
	}
	connect failed
	connected false
    } else {
	fileevent $fd writable {}
	fconfigure $fd -encoding binary
	fconfigure $fd -blocking 0 -buffering line -translation {crlf cr}
	fileevent $fd readable sockdata
	set devtype socket
	connect success
	connected true
	status ""
	if {$type in {manual}} {set cfg(connection,enable) true}
    }
}

proc connectcoro {type} {
    global dev cfg tcl_platform know devtype
    set delay {ms 7500 total 0 id ""}
    while 1 {
	try {
	    if {$cfg(connection,type) eq "tcp"} {
		set dev \
		  [socket -async $cfg(connection,host) $cfg(connection,port)]
		fileevent $dev writable [list socketresult $dev $type]
		if {$type ne "reconnect"} {
		    status "Connecting ..."
		}
	    } elseif {$cfg(connection,type) eq "file"} {
		set dev [open $cfg(connection,device)]
		set devtype file
		coroutine otsim filedata [file mtime $cfg(connection,device)]
	    } elseif {$tcl_platform(platform) eq "windows"} {
		if {[scan [string toupper $cfg(connection,device)] COM%d num] == 1} {
		    set device [format COM%d $num]
		    if {$num > 9} {set device [format {\\.\com%d} $num]}
		}
		set dev [open $device RDWR]
		fconfigure $dev -mode 9600,n,8,1
		fileevent $dev readable receive
		set devtype comport
	    } else {
		set dev [open $cfg(connection,device) {RDWR NOCTTY NONBLOCK}]
		fconfigure $dev -mode 9600,n,8,1
		fileevent $dev readable receive
		set devtype comport
	    }
	    if {$devtype ni {none file}} {
		fconfigure $dev -blocking 0 -buffering line -translation {crlf cr}
	    }
	} on ok {err errinfo} {
	    # Forget everything we know, it may have changed
	    array unset know
	    if {$devtype ne "none"} {
		connected true
		if {$type in {reconnect}} {status ""}
		if {$type in {manual}} {set cfg(connection,enable) true}
	    }
	    while {[set ev [yield]] ni {disconnect reconnect manual failed}} {}
	    # Make sure data is flushed before closing
	    if {[catch {fconfigure $dev -blocking 1} err errinfo]} {
		surprise $errinfo
	    }
	    if {[catch {close $dev} err errinfo]} {
		surprise $errinfo
	    }
	    unset dev
	    set devtype none
	    connected false
	    if {$ev ne "failed"} {
		set type $ev
		dict set delay ms 7500
		dict set delay total 0
	    }
	    if {$type eq "disconnect"} {
		set cfg(connection,enable) false
		# Wait for a reconnect 
		while {[set type [yield]] in {disconnect}} {}
	    }
	    if {$ev ne "failed"} continue
	    set msg ""
	} trap {POSIX ENOENT} {err errinfo} {
	    set msg "Serial device does not exist"
	} trap {POSIX EISDIR} {err errinfo} {
	    set msg "Invalid serial device"
	} trap {POSIX EACCES} {err errinfo} {
	    set msg "Insufficient permissions to access the serial device"
	} trap {POSIX ECONNREFUSED} {err errinfo} {
	    set msg "Connection refused"
	} trap {POSIX EHOSTUNREACH} {err errinfo} {
	    set msg "Host is unreachable"
	} on error {err errinfo} {
	    set msg [string toupper $err 0 0]
	}
	set devtype none
	if {$type in {startup reconnect}} {
	    dict with delay {
		set id [after $ms [list [info coroutine] reconnect]]
		incr total $ms
		# Double the retry interval every 2 minutes to a maximum of 60s
		if {$total >= 120000 && $ms < 60000} {
		    incr ms $ms
		    set total 0
		}
	    }
	}
	while 1 {
	    if {$type eq "manual" && $msg ne ""} {
		# Return the result to the caller
		set type [yieldto return -options $errinfo $msg]
	    } else {
		if {$msg ne ""} {status $msg}
		set type [yield]
	    }
	    after cancel [dict get $delay id]
	    if {$type ne "configure"} break
	    set msg ""
	}
    }
    surprise $errinfo \
      "Broken out of endless loop in proc connectcoro" type=$type
}

proc tryconnect {{w .}} {
    if {[catch {connect manual} msg]} {
	tk_messageBox -parent $w -icon error -title "Connection failed" \
	  -type ok -message "Connection failed: $msg"
    }
}

proc lock {id} {
    global lock
    if {$lock eq ""} {set lock $id}
    return [expr {$lock eq $id}]
}

proc unlock {id} {
    global lock
    if {$lock eq $id} {set lock ""}
    return [expr {$lock eq ""}]
}

proc sercmd {cmd {details ""} {timeout 2000}} {
    global dev sercmd devtype lock
    if {$devtype eq "none" || ![info exists dev]} {
	status "Error: Not connected" 5000
    } elseif {$devtype eq "file"} {
	# Can't send a command to a file
    } elseif {$lock ne ""} {
	# Serial port locked
	if {$details ne ""} {
	    output "[ts]\tIgnored ($details): $cmd"
	} else {
	    output "[ts]\tIgnored: $cmd"
	}
    } elseif {[catch {puts $dev $cmd} err]} {
        status "Error: [string toupper $err 0 0]" 5000
    } else {
	if {$details ne ""} {
	    output "[ts]\tCommand ($details): $cmd"
	} else {
	    output "[ts]\tCommand: $cmd"
	}
	set coro [info coroutine]
	if {$coro ne ""} {
	    switch -glob $cmd {
		PR=[A-Z] {
		    set pat PR:[string index $cmd 3]
		}
		[A-Z][A-Z]=* {
		    set pat [string range $cmd 0 1]:
		}
		default {
		    set pat $cmd
		}
	    }
	    set ms [clock milliseconds]
	    lappend sercmd [list $pat $coro $ms]
	    after cancel cancel
	    set first [lindex $sercmd 0 2]
	    after [expr {$first + $timeout - $ms}] cancel
	    return [yield]
	}
    }
}

proc cancel {} {
    global sercmd
    set now [clock milliseconds]
    set i 0
    while {[llength $sercmd] > $i} {
	if {[lindex $sercmd 0 2] < $now} {
	    set sercmd [lassign $sercmd rec]
	    lassign $rec cmd coro ms
	    $coro timeout
	} else {
	    incr i
	}
    }
}

proc relayserver {} {
    global cfg relayfd clients
    if {$cfg(server,enable)} {
	try {
	    set relayfd [socket -server {apply {
		    {fd args} {coroutine server-$fd server $fd {*}$args}
	    }} $cfg(server,port)]
	} on error msg {
	    set cfg(server,enable) false
	    return $msg
	}
    } else {
	# Close the server socket and all client connections
	catch {close $relayfd}
	foreach n [dict values $clients] {
	    catch {server-$n terminate}
	}
    }
    return
}

# Coroutine for handling incoming TCP connections
proc server {fd host port} {
    global cfg clients
    if {[string first : $host] >= 0} {
	# Decorate IPv6 addresses
	set host [format {[%s]} $host]
    }
    dict set clients $host:$port $fd
    fconfigure $fd -blocking 0 -buffering line
    fileevent $fd readable [list [info coroutine] data]
    set telcmd 0
    while {![catch {eof $fd} eof] && !$eof} {
	if {[yield] eq "terminate"} break
	if {[catch {gets $fd line} cnt]} break
	if {$cnt <= 0} continue
	set details "via relay server, from $host:$port"
	if {$cfg(server,relay)} {
	    # Send the command outside of the coroutine
	    after idle [list sercmd $line $details]
	} else {
	    # Start a coroutine to wait for the response, while the current
	    # proc continues to possibly receive new commands simultaneously
	    coroutine telcmd-[incr telcmd] apply {
		{fd line details} {catch {puts $fd [sercmd $line $details]}}
	    } $fd $line $details
	}
    }
    catch {close $fd}
    dict unset clients $host:$port
}

proc iac {flag option} {
    set x [dict get {dont 254 do 253 wont 252 will 251} $flag]
    return [binary format ccc 255 $x $option]
}

proc filedata {endtime} {
    global dev start
    lassign [fileanal] def tsfmt
    set base [clock add $endtime -6 hours]
    set last 0
    while {[gets $dev line] != -1} {
	if {[binary scan $line $def ts frac otmsg] < 3} continue
	if {[scan $otmsg {%1[ABRT]%1x0%2x%4x%n} src type id data end] != 5} {
	    continue
	}
	try {
	    set sec [clock scan $ts -base $base -format $tsfmt]
	    set us [expr {$sec * 1000000 + [scan $frac %d]}]
	    if {$start > $sec} {set start $sec}
	    if {$sec > $last + 60} {
		set last $sec
		status "Time: [clock format $sec -format %H:%M]"
		gui scroll
		after 0 [list after idle [info coroutine]]
		yield
	    }
	    otmessage $us $otmsg [expr {$type & 7}] $id $data
	} on error err {
	    puts "$line: $err"
	}
    }
    gui scroll
    status ""
}

proc fileanal {} {
    global dev
    # Try to determine the timestamp format

    set freq {}
    # Read a couple of lines
    set re {\m[ABRT][0-9A-F]{8}\M}
    set lines [lsearch -all -inline -regexp [split [read $dev 16384] \n] $re]
    seek $dev 0
    # Check how many times the pattern occurs on a specific position
    foreach n $lines {
	regexp -indices $re $n x
	dict incr freq [lindex $x 0]
    }
    # Get the position that was found most frequently
    lassign [lsort -integer -decreasing -stride 2 -index 1 $freq] pos
    # Determine the format based on the position of the pattern
    switch -- $pos {
	16 {
	    # 17:06:07.297356
	    return [list a8xa6xa9 %T]
	}
	17 {
	    # 00:01:24.385959
	    return [list a8xa6x2a9 %T]
	}
	18 {
	    # 1387251888.153641
	    return [list a10xa6xa9 %s]
	}
	21 {
	    # 1387251888.153641352
	    return [list a10xa9xa9 %s]
	}
	22 {
	    # 20131214 07:43:28.006
	    return [list a17xa3xa9 {%Y%m%d %T}]
	}
	23 {
	    # 20131217-074805.135096
	    return [list a15xa6xa9 %Y%m%d-%H%M%S]
	}
	26 {
	    # 20131217-074805.135096813
	    return [list a15xa9xa9 %Y%m%d-%H%M%S]
	}
    }
}

proc sockdata {} {
    global dev
    if {[eof $dev]} {
	connect reconnect
    } else {
	set data [read $dev 1]
	if {[binary scan $data cu iac] == 0} {
	    return
	} elseif {$iac == 255} {
	    global telnet options devtype
	    set devtype telnet
	    set telnet($dev) $options
	    fileevent $dev readable telnet
	    telnet $data
	} else {
	    fileevent $dev readable receive
	    receive $data
	}
    }
}

proc telnet {{data ""}} {
    global dev telnet
    upvar #0 buffer($dev) buffer
    # http://www.networksorcery.com/enp/protocol/telnet.htm
    if {[eof $dev]} {
	connect reconnect
	unset buffer
    } else {
	if {[gets $dev line] != -1} {
	    append data $line \n
	} elseif {[chan pending input $dev]} {
	    append data [read $dev]
	} else {
	    return
	}
	set response ""
	foreach n [lassign [split $data \xff] str] {
	    if {[binary scan $n cucu* opcode args] == 0} {
		set args 255
	    } else {
		set opc [format %02x $opcode]
		if {[dict exists $telnet($dev) $opc]} {
		    set opt [dict get $telnet($dev) $opc]
		} else {
		    set opt cant
		}
		debug $opc:$opt
		switch -- $opc {
		    fe {
			# don't
			set args [lassign $args option]
			debug [format "Don't %02x" $option]
			append response [iac wont $option]
		    }
		    fd {
			# do
			set args [lassign $args option]
			debug [format "Do %02x" $option]
			if {$opt in {want hate can}} {
			    append response [iac will $option]
			    dict set telnet($dev) $opc will
			} elseif {$opt in {cant}} {
			    append response [iac wont $option]
			    dict set telnet($dev) $opc wont
			}
		    }
		    fc {
			# won't
			set args [lassign $args option]
			debug [format "Won't %02x" $option]
			if {$opt ni {dont}} {
			    append response [iac dont $option]
			    dict set telnet($dev) $opc dont
			}
		    }
		    fb {
			# will
			set args [lassign $args option]
			debug [format "Will %02x" $option]
			if {$opt in {want hate can}} {
			    append response [iac do $option]
			    dict set telnet($dev) $opc do
			} elseif {$opt in {cant}} {
			    append response [iac dont $option]
			    dict set telnet($dev) $opc dont
			}
		    }
		    fa {
			# subnegotiation
			set args [lassign $args option sb]
			switch -- [format %02x%02x $option $sb] {
			    1801 {
				# Send terminal type
				append response [binary format cccca*cc \
				  255 250 24 0 XTERM 255 240]
			    }
			    1800 {
				# Terminal type is
				debug "Terminal is [binary format c* $args]"
			    }
			}
			set args ""
		    }
		    f3 {
			# break
		    }
		    f0 {
			# end of subnegotiation
		    }
		}
	    }
	    append str [binary format c* $args]
	}
	if {$response ne ""} {
	    puts -nonewline $dev $response
	    flush $dev
	}
	append buffer $str
	set lines [split [string map [list \r\n \n \r \n] $buffer] \n]
	set buffer [lindex $lines end]
	foreach line [lrange $lines 0 end-1] {
	    process $line
	}
    }
}

proc sync {{force 0}} {
    global cfg sync
    after cancel sync
    set now [clock seconds]
    sercmd [clock format $now -format {SC=%H:%M/%u}]
    if {$cfg(clock,date)} {
	set cmd [clock format $now -format {SR=21:%m,%d}]
	if {$force || [dict get $sync date] ne $cmd} {
	    sercmd $cmd
	    dict set sync date $cmd
	}
    }
    if {$cfg(clock,year)} {
	set y [clock format $now -format %Y]
	set cmd [format {SR=22:%d,%d} [expr {$y >> 8}] [expr {$y & 0xff}]]
	if {$force || [dict get $sync year] ne $cmd} {
	    sercmd $cmd
	    dict set sync year $cmd
	}
    }
    if {$cfg(clock,auto)} {
	after [expr {60000 - [clock milliseconds] % 60000}] sync
    }
}

proc signal {args} {
    global signalproc
    foreach n $signalproc {
	if {[catch {uplevel 1 $n $args} err info]} {
	    puts [dict get $info -errorinfo]
	}
    }
}

proc signalproc {proc} {
    global signalproc
    if {$proc ni $signalproc} {
	lappend signalproc $proc
    }
}

proc webstatus {} {
    global wibblesock webstatus cfg
    set open {}
    dict for {key data} $wibblesock {
	if {[dict exists $data fd] != 0} {lappend open $key}
    }
    if {[llength $open] > 0} {
	set webstatus "Running ([join $open { and }])"
	set cfg(web,enable) true
    } else {
	set webstatus Stopped
	set cfg(web,enable) false
    }
}

proc wibblecmd {cmd} {
    global wibblesock cfg theme
    if {$cmd eq "stop"} {
	dict for {svc data} $wibblesock {
	    if {[dict exists $data fd]} {
		if {[catch {close [dict get $data fd]} rc]} {
		    # puts $rc
		}
		dict unset wibblesock $svc fd
	    }
	}
    } elseif {$cmd eq "start"} {
	set theme theme-$cfg(web,theme)
	include web.tcl
    }
    webstatus
}

proc mqttserver {} {
    global cfg mqtt
    if {$cfg(mqtt,enable)} {
	try {
	    if {[llength [info procs ::mqttinit]] == 0} {
		include mqtt.tcl
	    } else {
		mqttinit
	    }
	} on error result {
	    set cfg(mqtt,enable) false
	}
    } else {
	catch {$mqtt destroy}
    }
}

proc tspeakserver {} {
    global cfg
    if {$cfg(tspeak,enable) && [llength [info procs ::tspeak::run]] == 0} {
	if {[catch {include tspeak.tcl} result]} {
	    set cfg(tspeak,enable) false
	    return $result
	}
    } else {
	tspeak::run
    }
    return
}

proc upgrade {args} {
    include upgrade.tcl
    tailcall upgrade {*}$args
}

package require getopt 2
package require settings
package require comport
package require homedir

set timestamp [clock seconds]
set start $timestamp
set now $start
set daemon 0
set dbus session
set configfile ""
set firmware ""

getopt flag arg $argv {
    -f: - --configfile:FILE {
	# use settings from a configuration file
	set configfile $arg
    }
    -o: - --outputfile:FILE {
	# write the message log to a file.
	set optcfg(logfile,directory) [file dirname $arg]
	set optcfg(logfile,pattern) [file tail $arg]
	set optcfg(logfile,enable) true
    }
    -d: - --datafile:FILE {
	# periodically write some parameters to a file.
	set optcfg(datalog,file) $arg
	set optcfg(datalog,enable) true
    	set now [clock milliseconds]
	set wait [expr {$interval - $now % $interval}]
	after $wait dump
    }
    -l - --log {
	# on startup, show the log tab.
	settings set view tab [set optcfg(view,tab) log]
    }
    -g - --graph {
	# on startup, show the graph tab.
	settings set view tab [set optcfg(view,tab) graph]
    }
    -s - --statistics {
	# on startup, show the statistics tab.
	settings set view tab [set optcfg(view,tab) stats]
    }
    -p: - --port:PORT {
	# relay server port, default: 7686.
	set optcfg(server,port) $arg
	set optcfg(server,enable) true
    }
    -w: - --webserver:PORT {
	# start a web server on the specified port
	set optcfg(web,port) $arg
	set optcfg(web,enable) true
    }
    --theme:THEME {
	# select a web server theme
	set optcfg(web,theme) $arg
    }
    -v - --version {
	# display the program version and exit.
	puts "Opentherm Monitor version $version"
	exit
    }
    -a - --append {
	# append to the datafile instead of overwriting it
	set optcfg(datalog,append) true
	set optcfg(datalog,enable) true
    }
    -b - --bitflags {
	# show bit flag details in the message log
	set optcfg(view,bitflags) true
    }
    --upgrade:FILE {
	# perform a firmware upgrade and exit
	set firmware $arg
    }
    --daemon {
	# run as daemon in the background without a gui
	set daemon 1
    }
    --system {
	# Connect to the system dbus instead of the session dbus
	set dbus system
    }
    --debug {
	set verbose 1
    }
    --dbfile:FILE {
	set dbfile $arg
    }
    -h - --help {
	# display this help and exit.
	help
    }
    arglist {
	# [<device>|<host>:<port>]
	lassign $arg fn
	if {[llength $arg] > 1} {
	    help
	} elseif {[llength $arg] == 0} {
	    # Use default/saved connection settings
	} elseif {[regexp {^([^/]+):(.+)} $fn -> host port]} {
	    set optcfg(connection,type) tcp
	    set optcfg(connection,host) $host
	    set optcfg(connection,port) $port
	    set optcfg(connection,enable) true
	} elseif {[file exists $fn] && [file type $fn] in {file}} {
	    set optcfg(connection,type) file
	    set optcfg(connection,device) $fn
	    set optcfg(connection,enable) true
	    set span 86400
	} else {
	    set optcfg(connection,type) serial
	    set optcfg(connection,device) $fn
	    set optcfg(connection,enable) true
	}
    }
}

# Set some defaults
array set cfg {
    view,tab		graph
    view,sort		name
    view,order		increasing
    view,bitflags	false
    view,messageid	false
    datalog,file	otdata.txt
    datalog,enable	false
    datalog,append	false
    datalog,interval	30000
    logfile,pattern	otlog-%Y%m%d.txt
    logfile,enable	false
    connection,type	serial
    connection,device	com1
    connection,host	localhost
    connection,port	25238
    connection,enable	false
    web,port		8080
    web,theme		default
    web,enable		false
    web,sslport		0
    web,sslprotocols	tls1,tls1.1,tls1.2
    web,nopass		true
    web,certonly	false
    web,graphlegend	false
    server,port		7686
    server,enable	true
    server,relay	false
    clock,date		false
    clock,year		false
    clock,auto		false
    email,boilerfault	true
    email,ventilationfault	true
    email,solarfault	true
    email,watchdogtimer	true
    email,commproblem	true
    email,roomcold	true
    email,pressure	true
    email,enable	false
    email,sender	""
    email,server	""
    email,port		25
    email,user		""
    email,password	secret
    email,secure	TLS
    email,recipient	""
    sms,boilerfault	true
    sms,ventilationfault	false
    sms,solarfault	false
    sms,watchdogtimer	false
    sms,commproblem	false
    sms,roomcold	true
    sms,pressure	false
    sms,enable		false
    sms,phonenumber	""
    sms,provider	VoipPlanet
    sms,account		""
    sms,password	secret
    sms,sender		""
    sms,route		""
    alert,roomcold	14
    alert,pressurehigh	2.0
    alert,pressurelow	1.5
    mqtt,enable		false
    mqtt,broker		localhost
    mqtt,port		1883
    mqtt,client		""
    mqtt,username	""
    mqtt,password	""
    mqtt,eventtopic	events/central_heating/otmonitor
    mqtt,actiontopic	actions/otmonitor
    mqtt,format		json2
    mqtt,messages	false
    mqtt,keepalive	120
    mqtt,qos		1
    mqtt,retransmit	10
    tspeak,enable	false
    tspeak,interval	120
    tspeak,sync		false
    tspeak,key		""
    tspeak,field1	roomtemp
    tspeak,field2	setpoint
    tspeak,field3	boilertemp
    tspeak,field4	returntemp
    tspeak,field5	controlsp
    tspeak,field6	modulation
    tspeak,field7	""
    tspeak,field8	""
    firmware,hexfile	""
    fsdialog,sort	name
    fsdialog,reverse	0
    fsdialog,duopane	0
    fsdialog,mixed	0
    fsdialog,hidden	0
    fsdialog,details	1
    fsdialog,historylist	{}
}
set cfg(datalog,itemlist) {
    flame
    dhwmode
    chmode
    dhwenable
    diag
    fault
    outside
    roomtemp
    setpoint
    modulation
    boilertemp
    returntemp
    controlsp
    dhwsetpoint
    chwsetpoint
    timestamp
}
set cfg(datalog,file) [file join [homedir] otdata.txt]
set cfg(logfile,directory) [homedir]
set cfg(connection,device) [lindex [comport enum] 0]
set cfg(mqtt,client) [lindex [split [info hostname] .] 0]-otmon

# Override the defaults with saved settings, if any
if {$configfile ne ""} {
    settings file $configfile
}
foreach n [array names cfg] {
    lassign [split $n ,] group name
    if {$name in {password}} {
	# Decrypt passwords
	set cfg($n) [binary decode base64 \
	  [settings get $group $name [binary encode base64 $cfg($n)]]]
    } else {
	set cfg($n) [settings get $group $name $cfg($n)]
    }
}

if {[settings get mqtt deviceid] ne ""} {
    set devid [settings get mqtt deviceid]
    set devtype [settings get mqtt devicetype central_heating]
    set cfg(mqtt,eventtopic) events/$devtype/$devid
    set cfg(mqtt,actiontopic) actions/$devid
    settings unset mqtt deviceid
    settings unset mqtt devicetype
}

# Now override with the collected command line options
foreach n [array names optcfg] {
    set cfg($n) $optcfg($n)
}
array unset optcfg

if {$cfg(connection,type) eq "file"} {
    # When reading messages from file some options don't make sense
    set cfg(datalog,enable) false
    set cfg(server,enable) false
    # set cfg(web,enable) false
    set daemon 0
    set firmware ""
    proc alert args {}
} else {
    include alerts.tcl
}

# Create a stub for all gui operations
proc gui args {}

proc diagnostics {{ver ""}} {
    rename diagnostics {}
    package require diagnostics
    tailcall diagnostics $ver
}

if {$firmware eq ""} {
    # Start tracking values
    if {!$daemon || $cfg(web,enable)} {
	include track.tcl
    }
    # Create a GUI
    if {!$daemon} {
	include gui.tcl
    }
}

if {$cfg(connection,enable)} {
    after idle {connect startup}
} elseif {$firmware ne ""} {
    puts stderr "Not connected"
    exit 1
}

if {$firmware eq ""} {
    relayserver

    include security.tcl

    # Datalog
    if {$cfg(datalog,enable)} dump

    # Web server
    if {$cfg(web,enable)} {
	set theme theme-$cfg(web,theme)
	include web.tcl
	webstatus
    }

    # MQTT
    if {$cfg(mqtt,enable)} {
	include mqtt.tcl
    }

    # ThingSpeak
    if {$cfg(tspeak,enable)} {
	include tspeak.tcl
    }
}

special 0 0 masterstatus
special 4 0 slavestatus
special 1 2 masterconfig
special 5 2 masterconfig
special 4 3 slaveconfig
special 4 5 asfflags
special 4 6 reportflags {
    "DHW setpoint transfer"	{disabled enabled}
    "max CH setpoint transfer"	{disabled enabled}
} {
    "DHW setpoint"		{read-only read/write}
    "max CH setpoint"		{read-only read/write}
}
special 0 70 reportflags {
    "Ventilation"		{disabled enabled}
    "Bypass position"		{close open}
    "Bypass mode"		{manual automatic}
    "Free ventilation mode"	{"not active" active}
} {
}
special 4 70 reportflags {
} {
    "Fault indication"		{"no fault" fault}
    "Ventilation mode"		{"not active" active}
    "Bypass status"		{closed open}
    "Bypass automatic status"	{manual automatic}
    "Free ventilation status"	{"not active" active}
    ""				{}
    "Diagnostic indication"	{"no diagnostics" "diagnostic event"}
}
special 4 72 reportflags {
    "Service request"		{no yes}
    "Exhaust fan fault"		{"no fault" fault}
    "Inlet fan fault"		{"no fault" fault}
    "Frost protection"		{"not active" active}
} {
}
special 4 74 reportflags {
    "System type"		{"central exaust" "heat-recovery"}
    "Bypass"			{"not present" present}
    "Speed control"		{"3-speed" variable}
} {
}
special 4 86 reportflags {
    "Nominal ventilation value transfer"	{disabled enabled}
} {
    "Nominal ventilation value"			{read-only read/write}
}
special 4 100 reportflags {
} {
    "Manual change priority"	{"disable overrule" "enable overrule"}
    "Program change priority"	{"disable overrule" "enable overrule"}
}
special 4 103 reportflags {
    "System type"		{"DHW preheat" "DHW parallel"}
} {
}
special 4 28 returntemp

special 1 1 guifloat controlsp controlsetpoint
special 1 8 guifloat controlsp2 controlsetpoint2
special 4 9 guifloat override remoteoverrideroomsetpoint
special 1 56 guifloat dhwsetpoint dhwsetpoint
special 4 56 guifloat dhwsetpoint dhwsetpoint
special 1 57 guifloat chwsetpoint chsetpoint
special 4 57 guifloat chwsetpoint chsetpoint
special 4 17 guifloat modulation modulation
special 1 14 guifloat maxmod maxmodulation
special 1 24 guifloat roomtemp roomtemperature
special 1 37 guifloat roomtemp2 roomtemperature2
special 1 16 guifloat setpoint setpoint
special 1 23 guifloat setpoint2 setpoint2
special 1 27 readwrite 1 guifloat outside outsidetemperature
special 4 27 readwrite 4 guifloat outside outsidetemperature
special 5 27 readwrite 5 guifloat outside outsidetemperature
special 7 27 readwrite 7 guifloat outside outsidetemperature
special 4 18 guifloat pressure chwaterpresure
special 4 25 guifloat boilertemp boilerwatertemperature
special 4 31 guifloat boilertemp2 boilerwatertemperature2
special 4 26 guifloat dhwtemp dhwtemperature
special 4 32 guifloat dhwtemp2 dhwtemperature2
special 7 17 unknownid modulation
special 7 28 unknownid returntemp
special 7 18 unknownid pressure
special 7 26 unknownid dhwtemp
special 0 101 mastersolar
special 4 101 slavesolar
special 4 19 guifloat dhwflowrate dhwflowrate
special 4 33 guifloat exhausttemp exhausttemperature
special 4 116 guishort chbs chburnerstarts
special 4 117 guishort chps chpumpstarts
special 4 118 guishort dhwps dhwpumpstarts
special 4 119 guishort dhwbs dhwburnerstarts
special 4 120 guishort chbh chburnerhours
special 4 121 guishort chph chpumphours
special 4 122 guishort dhwph dhwpumphours
special 4 123 guishort dhwbh dhwburnerhours

# Class 1: Control and Status Information
register 0	{flag8 flag8}	"Status"
register 1	{f8.8}		"Control setpoint"
register 5	{flag8 u8}	"Application-specific flags"
register 8	{f8.8}		"Control setpoint 2"
register 70	{flag8 flag8}	"Status V/H"
register 71	{nu u8}		"Control setpoint V/H"
register 72	{flag8 u8}	"Fault flags/code V/H"
register 73	{u16}		"OEM diagnostic code V/H"
register 101	{flag8 flag8}	"Solar storage mode and status"
register 102	{flag8 u8}	"Solar storage fault flags"
register 115	{u16}		"OEM diagnostic code"

# Class 2: Configuration Information
register 2	{flag8 u8}	"Master configuration"
register 3	{flag8 u8}	"Slave configuration"
register 74	{flag8 u8}	"Configuration/memberid V/H"
register 75	{f8.8}		"OpenTherm version V/H"
register 76	{u8 u8}		"Product version V/H"
register 103	{flag8 u8}	"Solar storage config/memberid"
register 104	{u8 u8}		"Solar storage product version"
register 124	{f8.8}		"OpenTherm version Master"
register 125	{f8.8}		"OpenTherm version Slave"
register 126	{u8 u8}		"Master product version"
register 127	{u8 u8}		"Slave product version"

# Class 3: Remote Commands
register 4	{u8 u8}		"Remote command"

# Class 4: Sensor and Informational Data
register 16	{f8.8}		"Room setpoint"
register 17	{f8.8}		"Relative modulation level"
register 18	{f8.8}		"CH water pressure"
register 19	{f8.8}		"DHW flow rate"
register 20	{time}		"Day of week and time of day"
register 21	{date}		"Date"
register 22	{u16}		"Year"
register 23	{f8.8}		"Room Setpoint CH2"
register 24	{f8.8}		"Room temperature"
register 25	{f8.8}		"Boiler water temperature"
register 26	{f8.8}		"DHW temperature"
register 27	{f8.8}		"Outside temperature"
register 28	{f8.8}		"Return water temperature"
register 29	{f8.8}		"Solar storage temperature"
register 30	{f8.8}		"Solar collector temperature"
register 31	{f8.8}		"Flow temperature CH2"
register 32	{f8.8}		"DHW2 temperature"
register 33	{s16}		"Exhaust temperature"
register 34	{f8.8}		"Boiler heat exchanger temperature"
register 35	{u8 u8}		"Boiler fan speed and setpoint"
register 77	{nu u8}		"Relative ventilation"
register 78	{u8 u8}		"Relative humidity exhaust air"
register 79	{u16}		"CO2 level exhaust air"
register 80	{f8.8}		"Supply inlet temperature"
register 81	{f8.8}		"Supply outlet temperature"
register 82	{f8.8}		"Exhaust inlet temperature"
register 83	{f8.8}		"Exhaust outlet temperature"
register 84	{u16}		"Exhaust fan speed"
register 85	{u16}		"Inlet fan speed"
register 113	{u16}		"Unsuccessful burner starts"
register 114	{u16}		"Flame signal too low count"
register 116	{u16}		"Burner starts"
register 117	{u16}		"CH pump starts"
register 118	{u16}		"DHW pump/valve starts"
register 119	{u16}		"DHW burner starts"
register 120	{u16}		"Burner operation hours"
register 121	{u16}		"CH pump operation hours"
register 122	{u16}		"DHW pump/valve operation hours"
register 123	{u16}		"DHW burner operation hours"

# Class 5: Pre-defined Remote Boiler Parameters
register 6	{flag8 flag8}	"Remote parameter flags"
register 48	{s8 s8}		"DHW setpoint boundaries"
register 49	{s8 s8}		"Max CH setpoint boundaries"
register 50	{s8 s8}		"OTC heat curve ratio boundaries"
register 51	{s8 s8}		"Remote parameter 4 boundaries"
register 52	{s8 s8}		"Remote parameter 5 boundaries"
register 53	{s8 s8}		"Remote parameter 6 boundaries"
register 54	{s8 s8}		"Remote parameter 7 boundaries"
register 55	{s8 s8}		"Remote parameter 8 boundaries"
register 56	{f8.8}		"DHW setpoint"
register 57	{f8.8}		"Max CH water setpoint"
register 58	{f8.8}		"OTC heat curve ratio"
register 59	{f8.8}		"Remote parameter 4"
register 60	{f8.8}		"Remote parameter 5"
register 61	{f8.8}		"Remote parameter 6"
register 62	{f8.8}		"Remote parameter 7"
register 63	{f8.8}		"Remote parameter 8"
register 86	{flag8 flag8}	"Remote parameter settings V/H"
register 87	{u8 nu}		"Nominal ventilation value"

# Class 6: Transparent Slave Parameters
register 10	{u8 nu}		"Number of TSPs"
register 11	{u8 u8}		"TSP setting"
register 88	{u8 nu}		"Number of TSPs V/H"
register 89	{u8 u8}		"TSP setting V/H"
register 105	{u8 nu}		"Number of TSPs solar storage"
register 106	{u8 u8}		"TSP setting solar storage"

# Class 7: Fault History Data
register 12	{u8 nu}		"Size of fault buffer"
register 13	{u8 u8}		"Fault buffer entry"
register 90	{u8 nu}		"Size of fault buffer V/H"
register 91	{u8 u8}		"Fault buffer entry V/H"
register 107	{u8 u8}		"Size of fault buffer solar storage"
register 108	{u8 u8}		"Fault buffer entry solar storage"

# Class 8: Control of Special Applications
register 7	{f8.8}		"Cooling control signal"
register 9	{f8.8}		"Remote override room setpoint"
register 14	{f8.8}		"Maximum relative modulation level"
register 15	{u8 u8}		"Boiler capacity and modulation limits"
register 100	{nu flag8}	"Remote override function"

if {$firmware ne ""} {
    include upgrade.tcl
    puts -nonewline stderr "Current firmware version: "
    set id [after 5000 {set fwversion 0}]
    vwait fwversion
    if {$fwversion == 0} {
	puts stderr unknown
    } else {
	puts stderr $fwversion
    }
    lassign [upgrade readhex $firmware] result arg
    if {$result eq "success"} {
	puts stderr "Target firmware version: $upgrade::fwversion"
	set restore $arg
	flash start
	vwait forever
    } else {
	puts $arg
	exit 1
    }
}

include dbus.tcl

catch {include extra.tcl}

# In case we don't have Tk
vwait forever
