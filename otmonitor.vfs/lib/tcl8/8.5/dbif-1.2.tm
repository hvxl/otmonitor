# The DBus interface package provides functions that make it easy to
# provide a number of standard DBus interfaces in a Tcl application.
#
# The following interfaces are supported:
#	org.freedesktop.DBus.Peer
#	org.freedesktop.DBus.Introspectable
#	org.freedesktop.DBus.Properties

package require dbus 2.1
package provide dbif 1.2
package provide dbus-intf 1.2

namespace eval dbus::dbif {
    # Setup some defaults in case the user doesn't specify certain options
    variable defaults [dict create bus session intf com.tclcode.default]

    # Store a copy of the message info of the last received message so it
    # won't be necessary to pass it around all the time
    variable info

    # Information about the available methods, signals and properties is
    # stored in an array of dicts
    variable dbif

    # Information about listeners is stored in a separate array to be able
    # to keep the introspection code simpler
    variable hear

    # Information about signals is stored for easy access by ID
    variable signal

    # Automatically emit a PropertiesChanged signal when properties change
    variable trace 1
    # PropertiesChanged signal definition to be reused for every path/intf
    set signal(PropertiesChanged) {
	bus ""
	path ""
	interface org.freedesktop.DBus.Properties
	name PropertiesChanged
	signature sa{sv}as
	command ::dbus::dbif::propchanged
	interp {}
	meta {}
	args {
	    interface_name s
	    changed_properties a{sv}
	    invalidated_properties as
	}
    }

    # Various counters for generating unique IDs
    variable msgid 0 sigid 0

    # Expiry time for messages waiting for a response
    variable timeout 25000

    # Create the dbif ensemble command
    namespace ensemble create -command ::dbif -subcommands {
	default connect method signal property generate listen \
	  return error get delete
    } -map {return {respond return} error {respond error}}
}

########################################################################
# Helper procedures
########################################################################

# Procedure for returning error messages to the caller
#
proc dbus::dbif::dbuserr {type bus args} {
    upvar #1 data data
    if {[dict get $data noreply]} {return -level [info level] -async 1}
    set error org.freedesktop.DBus.Error.Failed
    switch -- $type {
	path {
	    lassign $args path
	    set msg "No such object path '$path'"
	    set error org.freedesktop.DBus.Error.UnknownObject
	}
	member {
	    lassign $args path intf member sig
	    set msg "No such method '$member' in interface '$intf'\
	      at object path '$path' (signature '$sig')"
	    set error org.freedesktop.DBus.Error.UnknownMethod
	}
	interface {
	    lassign $args path intf
	    set msg "No such interface '$intf' at object path '$path'"
	    set error org.freedesktop.DBus.Error.UnknownInterface
	}
	property {
	    lassign $args path intf name
	    set msg "No such property '$name' in interface '$intf'\
	      at object path '$path'"
	    set error org.freedesktop.DBus.Error.InvalidArgs
	}
	propunset {
	    lassign $args path intf name
	    set msg "Property '$name' in interface '$intf'\
	      at object path '$path' has currently no value"
	    set error org.freedesktop.DBus.Error.NoValue
	}
	signature {
	    lassign $args path intf name sig exp
	    set msg "Signature '$sig' does not match for property '$name'\
	      in interface '$intf' at object path '$path' (expected '$exp')"
	    set error org.freedesktop.DBus.Error.SignatureMismatch
	}
	access {
	    lassign $args path intf name op
	    set msg "Property '$name' in interface '$intf'\
	      at object path '$path' does not allow $op access"
	    set error org.freedesktop.DBus.Error.AccessViolation
	}
	default {
	    set msg "Invalid $type"
	}
    }
    dbus error $bus -name $error \
      [dict get $data sender] [dict get $data serial] $msg
    return -level [info level] -async 1
}

# Make sure a new interface on a path has all the necessary parts so it
# doesn't need to be checked every time.
#
proc dbus::dbif::create {bus path intf} {
    variable dbif
    if {![info exists dbif($bus,$path,$intf)]} {
	set dbif($bus,$path,$intf) \
	  [dict create methods {} signals {} properties {}]
    }
}

# Parse a DBus method or signal argument specification list
#
proc dbus::dbif::args {list {thing Argument}} {
    set signature {}
    set args {}
    foreach n $list {
	lassign [split $n :] arg sig
	namecheck $arg $thing
	if {$sig eq ""} {set sig s}
	lappend args $arg $sig
	append signature $sig
    }
    return [dict create signature $signature args $args]
}

# Define a method that can be called over the DBus
#
proc dbus::dbif::define {bus path intf name cmd int {in {}} {out {}} {meta {}} {async 0}} {
    variable dbif
    create $bus $path $intf
    set args [args $in]
    dict update args signature sig args inargs {}
    set args [args $out]
    dict update args signature ret args outargs {}
    set dict [dict create command $cmd interp $int signature $ret \
      in $inargs out $outargs meta $meta async $async]
    dict set dbif($bus,$path,$intf) methods $name,$sig $dict
}

# Release the information stored for a message
#
proc dbus::dbif::expire {id} {
    variable info
    if {[info exists info($id)]} {
	after cancel [dict get $info($id) afterid]
	unset info($id)
    }
}

# Parse a dbif command line with options, required, and optional arguments
#
proc dbus::dbif::cmdline {optvar argvar argspec arglist body} {
    upvar 1 $optvar option $argvar value
    foreach {opt cmd} $body {
	switch -glob -- $opt {
	    -*: {set arg([string range $opt 0 end-1]) $opt}
	    -* {set arg($opt) $opt}
	}
    }
    while {[llength $arglist]} {
	set rest [lassign $arglist opt]
	if {$opt eq "-" || [string index $opt 0] ne "-"} break
	if {$opt eq "--"} {set arglist $rest; break}
	if {[info exists arg($opt)]} {
	    set option $opt
	} elseif {[llength [set match [array names arg $opt*]]] == 1} {
	    set option [lindex $match 0]
       	} else {
   	    # Unknown or ambiguous option
	    error "Unknown or ambiguous option: \"$opt\""
	}
	if {$arg($option) ne $option} {
	    if {[llength $rest]} {
		set rest [lassign $rest value]
	    } else {
		error "Option requires argument: \"$opt\""
	    }
	}
	uplevel 1 [list switch -- $arg($option) $body]
	set arglist $rest
    }
    if {[lindex $argspec end] eq "args"} {
    	set len [expr {[llength $argspec] - 1}]
	uplevel 1 [list set args [lrange $arglist $len end]]
	incr len -1
	set argspec [lrange $argspec 0 $len]
	set arglist [lrange $arglist 0 $len]
    }
    set miss [expr {[llength $argspec] - [llength $arglist]}]
    set opt 0
    if {$miss > 0} {
	foreach n $argspec {if {[llength $n] == 2} {incr opt}}
    }
    if {$miss > $opt || $miss < 0} {
	set cmdline [dict get [info frame -2] cmd]
	set cmd [lrange $cmdline \
	  0 [expr {[llength $cmdline] - [llength [info level -1]]}]]
	append cmd " ?options?"
	foreach n $argspec {
	    if {[llength $n] == 2} {
		append cmd " ?[lindex $n 0]?"
	    } else {
		append cmd " $n"
	    }
	}
	error [format {wrong # args: should be "%s"} $cmd]
    }
    foreach a $argspec {
	upvar 1 [lindex $a 0] var
	if {[llength $a] == 2} {
	    if {$miss > 0 && $opt <= $miss} {
		set var [lindex $a 1]
		continue
	    }
	    incr opt -1
	}
	set arglist [lassign $arglist var]
    }
}

# Get the namespace of the caller
#
proc dbus::dbif::getns {interp} {
    if {$interp eq ""} {
	# This is a helper procedure. So 1 level up is the actual procedure
	# We need to go 2 levels up for the caller of the actual procedure
	return [uplevel 2 [list namespace current]]
    } else {
	# If the command is in another interpreter, we probably arived here
	# through an interp alias. In that case the calling context of that
	# interp is accessible via interp eval
	return [interp eval $interp [list namespace current]]
    }
}

# Access the miscellaneous information of a message
#
proc dbus::dbif::get {id name} {
    variable info
    if {![info exists info($id)]} {
	error "MessageID does not exist: \"$id\""
    }
    if {![dict exists $info($id) $name]} {
	set list [lsort [dict keys $info($id)]]
	lset list end "or [lindex $list end]"
	error "Unknown property: \"$name\". Must be [join $list ", "]"
    }
    return [dict get $info($id) $name]
}

proc dbus::dbif::namecheck {name {thing Name}} {
    if {[string is wordchar -strict $name]} {return name}
    error "$thing contains invalid characters: \"$name\""
}

proc dbus::dbif::buscheck {name} {
    if {$name in {session system starter}} {return $name}
    if {[regexp {^[a-z]+:([0-9A-Za-z_/.\\,=-]|%[0-9a-fA-F]{2})+$} $name]} {
	set spec [lassign [split $name :,] transport]
	if {[lsearch -not $spec *=*] < 0 && [lsearch $spec *=*=*] < 0} {
	    return $name
	}
    }
    error "Invalid bus: \"$name\"."
}

proc dbus::dbif::pathcheck {name} {
    if {[dbus validate path $name]} {return $name}
    error "Invalid path name: \"$name\"."
}

proc dbus::dbif::intfcheck {name} {
    if {[dbus validate interface $name]} {return $name}
    error "Invalid interface name: \"$name\"."
}

proc dbus::dbif::accesscheck {name} {
    if {$name in {read write readwrite}} {return $name}
    error "Invalid access mode: \"$name\". Must be: read, write, or readwrite"
}

proc dbus::dbif::metacheck {data} {
    if {[string is list $data] && ([llength $data] % 2) == 0} {
	# Convert to a dict, removing duplicates (or should they be allowed?)
	return [dict merge {} $data]
    }
    error "Invalid attribute specification. Must be a dict"
}

proc dbus::dbif::async {opts} {
    return [expr {[dict exists $opts -async] && \
      [string is true -strict [dict get $opts -async]]}]
}

proc dbus::dbif::vartrace {op bus path intf name} {
    variable dbif; variable trace
    dict with dbif($bus,$path,$intf) properties $name {
	if {[dict exists $meta Property.EmitsChangedSignal]} {
	    set ecs [dict get $meta Property.EmitsChangedSignal]
	} else {
	    set ecs true
	}
	if {$op eq "add"} {
	    if {!$trace} return
	    if {$access ni {read readwrite}} return
	    if {$ecs ni {true invalidates}} return
	}
	set inv [expr {$ecs eq "invalidates"}]
	set trc [list dbus::dbif::propchg $bus $path $intf $name $inv]
	set cmd [list trace $op variable $variable {write unset} $trc]
	interp eval $interp [list uplevel #0 $cmd]
    }
    return
}

# Needs to be exposed via the regular API?
proc dbus::dbif::changedsignal {state} {
    variable trace
    if {!$state == !$trace} return
    set trace [expr {!!$state}]
    set op [lindex {remove add} $trace]
    variable dbif
    foreach n [array names dbif] {
	lassign [split $n ,] bus path intf
	foreach name [dict keys [dict get $dbif($n) properties]] {
	    vartrace $op $bus $path $intf $name
	}
    }
}

########################################################################
# Ensemble subcommands
########################################################################

# Select which DBus to use (session or system)
#
proc dbus::dbif::default {args} {
    variable defaults
    set opts $defaults
    cmdline opt arg {} $args {
	-bus: {dict set opts bus [buscheck $arg]}
	-interface: {dict set opts intf [intfcheck $arg]}
    }
    set defaults $opts
    # Return the current values
    return [dict create \
      -bus [dict get $opts bus] -interface [dict get $opts intf]]
}

# Connect to the DBus, optionally requesting one or more names to be assigned
# to the current application
#
proc dbus::dbif::connect {args} {
    variable defaults
    set bus [dict get $defaults bus]; set opts {}
    cmdline opt arg args $args {
	-bus: {set bus [buscheck $arg]}
	-yield - -replace - -noqueue {lappend opts $opt}
    }
    dbus connect $bus
    set rc {}; foreach name $args {
    	if {![catch {dbus name $bus {*}$opts $name}]} {
	    lappend rc $name
	}
    }
    if {[dict get $defaults intf] eq "com.tclcode.default" && [llength $args]} {
	dict set defaults intf [lindex $args 0]
	# Path of least surprise. If no defaults have been set up, users will
	# probably expect the bus used for connecting will be the default
	dict set defaults bus $bus
    }
    dbus method $bus {} org.freedesktop.DBus.Peer.Ping dbus::dbif::ping
    dbus method $bus {} org.freedesktop.DBus.Peer.GetMachineId \
      [list dbus::dbif::machineid $bus]
    dbus method $bus {} org.freedesktop.DBus.Introspectable.Introspect \
      [list dbus::dbif::introspect $bus]
    dbus method $bus -details {} org.freedesktop.DBus.Properties.Set \
      [list dbus::dbif::propset $bus]
    dbus method $bus {} org.freedesktop.DBus.Properties.Get \
      [list dbus::dbif::propget $bus]
    dbus method $bus {} org.freedesktop.DBus.Properties.GetAll \
      [list dbus::dbif::propdump $bus]
    # Add the standard interfaces to the API specification
    standard $bus
    return $rc
}

# Define a signal that the application may send
#
proc dbus::dbif::signal {args} {
    variable defaults; variable dbif; variable signal; variable sigid
    dict with defaults {}; set meta {}
    set id ""
    cmdline opt arg {path name {in {}} {opt {}} {arglist {}} {body {}}} $args {
	-id: {set id $arg}
	-bus: {set bus [buscheck $arg]}
	-interface: {set intf [intfcheck $arg]}
	-attributes: {set meta [metacheck $arg]}
    }
    if {$body eq ""} {
	set body $arglist
	set arglist $opt
	set interp ""
    } else {
	set interp $opt
    }
    namecheck $name
    # Signals without a predefined path need a body to provide the path
    if {$path ne "" || $body eq ""} {pathcheck $path}
    create $bus $path $intf
    if {$id eq ""} {set id signal[incr sigid]}
    set dict [dict create \
      bus $bus path $path interface $intf name $name command "" interp $interp]
    if {$body ne ""} {
	set ns [getns $interp]
	dict set dict command [list apply [list $arglist $body $ns]]
    }
    if {[info exists signal($id)]} {
	# Clean up the old signal
	dict update signal($id) bus obus path opath interface ointf {}
	if {$obus eq ""} {
	    # Internal signal present on all buses
	    if {$id eq "PropertiesChanged"} {
		# Stop automatic signalling of changed properties
		changedsignal 0
		# The code may have messed with the path
		set opath ""
	    }
	    set old [array names dbif *,$opath,$ointf]
	} else {
	    set old [list $obus,$opath,$ointf]
	}
	foreach o $old {
	    set sigs [dict get $dbif($o) signals]
    	    dict set dbif($o) signals \
	      [lsearch -all -inline -exact -not $sigs $id]
	}
    }
    set signal($id) [dict merge $dict [args $in] [dict create meta $meta]]
    dict lappend dbif($bus,$path,$intf) signals $id
    return $id
}

# Define a property that may be accessed through the DBus
#
proc dbus::dbif::property {args} {
    variable defaults; variable dbif
    dict with defaults {}; set op readwrite; set meta {}
    cmdline opt arg {path name var args} $args {
	-bus: {set bus [buscheck $arg]}
	-interface: {set intf [intfcheck $arg]}
	-access: {set op [accesscheck $arg]}
	-attributes: {set meta [metacheck $arg]}
    }
    if {[llength $args] <= 2} {
	lassign [lreverse $args] body interp
    } else {
	set cmd {dbif property ?options? path name var ?interp ?body??}
	error [format {wrong # args: should be "%s"} $cmd]
    }
    set args [args [list $name] Property]
    set name [lindex [dict get $args args] 0]
    set sig [lindex [dict get $args signature] 0]
    create $bus $path $intf

    # Remove any old trace
    if {[dict exists $dbif($bus,$path,$intf) properties $name]} {
	vartrace remove $bus $path $intf $name
    }

    if {$body ne ""} {
	set ns [getns $interp]
	set cmd [list apply [list $name $body $ns]]
    } else {
	set cmd ""
    }
    set dict [dict create variable $var access $op signature $sig \
      command $cmd interp $interp meta $meta]
    dict set dbif($bus,$path,$intf) properties $name $dict

    # Setup a variable trace for readable properties
    vartrace add $bus $path $intf $name
    if {$interp ne {}} {
	interp alias $interp ::dbus::dbif::propchg {} ::dbus::dbif::propchg
    }
}

# Define how to handle a method call
#
proc dbus::dbif::method {args} {
    variable defaults
    dict with defaults {}; set meta {}; set async 0
    cmdline opt arg {path cmd {in ""} {out ""} {interp ""} body} $args {
        -bus: {set bus [buscheck $arg]}
        -interface: {set intf [intfcheck $arg]}
	-attributes: {set meta [metacheck $arg]}
	-async {set async 1}
    }
    namecheck $cmd
    set args {}
    set info {{}}
    foreach n $in {
	if {[llength $n] == 2 || [llength $info] > 1} {
	    lassign $n arg default
	    lassign [split $arg :] name sig
	    lappend args [list $name $default]
	    lappend info [linsert [lindex $info end] end $arg]
	} else {
	    lassign [split $n :] name sig
	    lappend args $name
	    lset info 0 [linsert [lindex $info 0] end $n]
	}
    }
    set ns [getns $interp]
    set code [list apply [list [linsert $args 0 msgid] $body $ns]]
    foreach n $info {
	define $bus $path $intf $cmd $code $interp $n $out $meta $async
    }
    dbus method $bus $path $intf.$cmd [list dbus::dbif::methods $bus]
}

# Generate a signal according to an earlier specification
#
proc dbus::dbif::generate {id args} {
    variable signal
    if {![info exists signal($id)]} {
	error "Signal '$id' has not been defined"
    }
    set cmd [dict get $signal($id) command]
    set int [dict get $signal($id) interp]
    if {$cmd eq ""} {
    	set argv $args
	dict with signal($id) {}
    } else {
	# Need to use catch to get the additional return options
	if {[catch {interp eval $int [list uplevel #0 $cmd $args]} argv opts]} {
	    # Rethrow any exceptions
	    return -options $opts $argv
	}
	dict with signal($id) {}
	if {$path eq ""} {
	    # Standard signal, body code must have provided the path
	    if {[dict exists $opts -path]} {
		set path [pathcheck [dict get $opts -path]]
	    } else {
		error "No path specified for the signal"
	    }
	}
	# Don't expect the body to provide a list for single arg signals
	# Check for a length of 2 because args contains name/signature pairs
	if {[llength $args] == 2} {
	    dbus signal $bus -signature $signature \
	      $path $interface $name $argv
	    return
	}
    }
    dbus signal $bus -signature $signature \
      $path $interface $name {*}$argv
}

# Setup a signal handler for a specific signal
#
proc dbus::dbif::listen {args} {
    variable defaults; variable hear
    dict with defaults {}
    cmdline opt arg {path name {arglist ""} {interp ""} body} $args {
        -bus: {set bus [buscheck $arg]}
        -interface: {set intf [intfcheck $arg]}
    }
    dbus filter $bus add \
      -type signal -path $path -interface $intf -member $name
    set args {}
    set info {{}}
    foreach n $arglist {
	if {[llength $n] == 2 || [llength $info] > 1} {
	    lassign $n arg default
	    lassign [split $arg :] var sig
	    if {$sig eq ""} {set sig s}
	    lappend args [list $var $default]
	    lappend info [lindex $info end]$sig
	} else {
	    lassign [split $n :] var sig
	    if {$sig eq ""} {set sig s}
	    lappend args $var
	    lset info 0 [lindex $info 0]$sig
	}
    }
    set ns [getns $interp]
    set code [list apply [list [linsert $args 0 msgid] $body $ns]]
    foreach n $info {
    	set dict [dict create command $code interp $interp]
    	dict set hear($bus,$path,$intf) $name,$n $dict
    }
    dbus listen $bus $path $intf.$name [list dbus::dbif::signals $bus]
}

# Send a response to a DBus message
#
proc dbus::dbif::respond {response id result {name ""}} {
    variable info; variable dbif
    if {![info exists info($id)]} {
	error "Message ID $id does not exist"
    }
    dict with info($id) {}
    expire $id
    if {$noreply} return
    set dict [dict get $dbif($bus,$path,$interface) methods $member,$signature]
    dict with dict {
	if {$response eq "error"} {
	    if {$name eq ""} {
		dbus error $bus $sender $serial $result
	    } else {
		dbus error $bus -name $name $sender $serial $result
	    }
	} elseif {[llength $out] == 2} {
    	    # The returned result was a single value, not a list
	    dbus return $bus -signature $signature $sender $serial $result
	} else {
	    if {[llength $out] == 0} {set result ""}
	    dbus return $bus -signature $signature $sender $serial {*}$result
	}
    }
}

# Remove a path from the published DBus interface
#
proc dbus::dbif::delete {args} {
    variable defaults; variable dbif; variable signal
    dict with defaults {}
    cmdline opt arg {path} $args {
	-bus: {set bus [buscheck $arg]}
	-interface: {set intf [intfcheck $arg]}
    }
    pathcheck $path
    if {$path eq "/"} {set pat /*} else {set pat $path/*}
    set paths [array names dbif($bus,$pat,$intf)]
    if {[info exists dbif($bus,$path,$intf)]} {lappend paths $bus,$path,$intf}
    foreach n $paths {
	foreach sig [dict get $dbif($n) signals] {
	    unset -nocomplain signal($sig)
	}
	unset dbif($n)
    }
}

########################################################################
# Property access
########################################################################

# Handle a property set request
#
proc dbus::dbif::propset {bus data intf name arg} {
    variable dbif; variable info
    set path [dict get $data path]
    if {![info exists dbif($bus,$path,$intf)]} {
    	dbuserr interface $bus $path $intf
    }
    if {![dict exists $dbif($bus,$path,$intf) properties $name]} {
    	dbuserr property $bus $path $intf $name
    }
    set dict [dict get $dbif($bus,$path,$intf) properties $name]
    dict with dict {
	if {$access ni {write readwrite}} {
    	    dbuserr access $bus $path $intf $name write
	}
	# Strip off the two string arguments for interface and name
	set sig [dict get $data signature]
	set sig [string range $sig 2 end]
       	if {$sig eq "v"} {
	    lassign $arg sig arg
	}
	if {$sig ne "v" && $sig ne $signature} {
	    dbuserr signature $bus $path $intf $name $sig $signature
    	}
	if {$command ne ""} {
	    # Failures will automatically be reported back to the caller
  	    interp eval $interp [list uplevel #0 [linsert $command end $arg]]
	}
	interp eval $interp [list uplevel #0 [list set $variable $arg]]
    }
    dict with data {
    	dbus return $bus $sender $serial
    }
    return -async 1
}

# Handle a property get request
#
proc dbus::dbif::propget {bus data intf name} {
    variable dbif; variable info
    set path [dict get $data path]
    if {![info exists dbif($bus,$path,$intf)]} {
	dbuserr interface $bus $path $intf
    }
    if {![dict exists $dbif($bus,$path,$intf) properties $name]} {
	dbuserr property $bus $path $intf $name
    }
    set op [dict get $dbif($bus,$path,$intf) properties $name access]
    if {$op ni {read readwrite}} {dbuserr access $bus $path $intf $name read}
    set interp [dict get $dbif($bus,$path,$intf) properties $name interp]
    set var [dict get $dbif($bus,$path,$intf) properties $name variable]
    if {[interp eval $interp [list uplevel #0 [list info exists $var]]]} {
	set sig [dict get $dbif($bus,$path,$intf) properties $name signature]
	set dest [dict get $data sender]
	set serial [dict get $data serial]
	set value [interp eval $interp [list uplevel #0 [list set $var]]]
	dbus return $bus -signature $sig $dest $serial $value
    } else {
	dbuserr propunset $bus $path $intf $name
    }
    return -async 1
}

# Handle a property getall request
#
proc dbus::dbif::propdump {bus data {intf ""} args} {
    variable dbif; variable info
    set path [dict get $data path]
    if {![info exists dbif($bus,$path,$intf)]} {
	dbuserr interface $bus $path $intf
    }
    if {![dict exists $dbif($bus,$path,$intf) properties]} {return {}}
    set rc {}
    dict for {n v} [dict get $dbif($bus,$path,$intf) properties] {
	set interp [dict get $v interp]
	set var [dict get $v variable]
	if {[interp eval $interp [list uplevel #0 [list info exists $var]]]} {
	    set sig [dict get $v signature]
	    set value [interp eval $interp [list uplevel #0 [list set $var]]]
	    lappend rc $n [list $sig $value]
	}
    }
    dict with data {
 	dbus return $bus -signature a{sv} $sender $serial $rc
    }
    return -async 1
}

# Track property changes
proc dbus::dbif::propchg {bus path intf prop inv name1 name2 op} {
    variable propchg
    if {$op eq "unset"} {
	# After an unset trace fires, the trace is removed
	vartrace add $bus $path $intf $prop
    }

    if {$inv} {set op invalid}
    dict set propchg $bus $path $intf $prop $op

    after cancel [namespace code propchgsignal]
    after idle [namespace code propchgsignal]
}

proc dbus::dbif::propchanged {path {intf ""} {bus ""}} {
    variable propchg
    if {$bus eq ""} {
	variable defaults
	set bus [dict get $defaults bus]
	if {$intf eq ""} {set intf [dict get $defaults intf]}
    }
    if {![dict exists $propchg $bus $path $intf]} {
	# Don't generate the signal
	return -code return
    }
    variable dbif
    set change {}
    set invalid {}
    dict for {key op} [dict get $propchg $bus $path $intf] {
	if {$op eq "write"} {
	    set info [dict get $dbif($bus,$path,$intf) properties $key]
	    dict with info {}
	    set value [interp eval $interp \
	      [list uplevel #0 [list set $variable]]]
	    dict set change $key [list $signature $value]
	} else {
	    lappend invalid $key
	}
    }
    dict unset propchg $bus $path $intf
    variable signal
    # Put the details into the signal (not the interface!)
    dict set signal(PropertiesChanged) bus $bus
    dict set signal(PropertiesChanged) path $path
    return [list $intf $change $invalid]
}

# Report changed properties
#
proc dbus::dbif::propchgsignal {} {
    variable propchg
    dict for {bus data} $propchg {
	dict for {path dict} $data {
	    dict for {intf chg} $dict {
		if {[dict size $chg] > 0} {
		    generate PropertiesChanged $path $intf $bus
		}
	    }
	}
    }
    # All changes have been reported
    set propchg {}
}

########################################################################
# Introspection procedures
########################################################################

proc dbus::dbif::node {bus path} {
    variable dbif
    set list [array names dbif $bus,$path,*]
    if {[llength $list] == 0} return
    set rc {
	{<!DOCTYPE node PUBLIC\
	  "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN"}
	{"http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">}
    }
    lappend rc {<node>}
    foreach n $list {
	set i [lindex [split $n ,] 2]
	set dict $dbif($n)
	if {[info exists dbif($bus,,$i)]} {
	    dict with dict {
		set std $dbif($bus,,$i)
		set methods [dict merge [dict get $std methods] $methods]
		set properties \
		  [dict merge [dict get $std properties] $properties]
		foreach n [dict get $std signals] {
		    if {$n ni $signals} {lappend signals $n}
		}
	    }
	}
	lappend rc [interface $i $dict "  "]
	lappend ilist $i
    }
    foreach n [array names dbif $bus,,*] {
	set i [lindex [split $n ,] 2]
	if {$i ni $ilist} {
	    lappend rc [interface $i $dbif($n) "  "]
	}
    }
    set parent(/) {}
    foreach n [array names dbif $bus,$path*] {
	set p [lindex [split $n ,] 1]
	if {$p eq "/"} continue
	set dir /
	foreach d [lrange [split $p /] 1 end] {
	    lappend parent($dir) $d
	    if {$dir eq "/"} {set dir ""}
	    append dir / $d
	    lappend parent($dir)
	}
    }
    foreach n [lsort -unique $parent($path)] {
	lappend rc [format {  <node name="%s"/>} $n]
    }
    lappend rc {</node>} {}
    join $rc \n
}

proc dbus::dbif::interface {intf dict tab} {
    variable signal
    set rc [list [format {%s<interface name="%s">} $tab $intf]]
    if {[dict exists $dict methods]} {
	dict for {n v} [dict get $dict methods] {
	    lassign [split $n ,] name sig
	    lappend rc [format {%s  <method name="%s">} $tab $name]
	    foreach {arg sig} [dict get $dict methods $n in] {
    		lappend rc [format {%s    <arg name="%s" type="%s"\
		  direction="%s"/>} $tab $arg $sig in]
	    }
	    foreach {arg sig} [dict get $dict methods $n out] {
    		lappend rc [format {%s    <arg name="%s" type="%s"\
		  direction="%s"/>} $tab $arg $sig out]
	    }
	    foreach {key value} [dict get $dict methods $n meta] {
		lappend rc [format {%s    <annotation name="%s" value="%s"/>} \
		  $tab org.freedesktop.DBus.$key $value]
	    }
	    lappend rc [format {%s  </method>} $tab]
	}
    }
    if {[dict exists $dict signals]} {
	foreach n [dict get $dict signals] {
	    set name [dict get $signal($n) name]
	    lappend rc [format {%s  <signal name="%s">} $tab $name]
	    foreach {arg sig} [dict get $signal($n) args] {
    		lappend rc [format {%s    <arg name="%s" type="%s"/>} \
		  $tab $arg $sig]
	    }
	    foreach {key value} [dict get $signal($n) meta] {
		lappend rc [format {%s    <annotation name="%s" value="%s"/>} \
		  $tab org.freedesktop.DBus.$key $value]
	    }
	    lappend rc [format {%s  </signal>} $tab]
	}
    }
    if {[dict exists $dict properties]} {
	dict for {name v} [dict get $dict properties] {
	    dict with v {}
	    if {[dict size $meta] == 0} {
		lappend rc [format {%s  <property name="%s" type="%s"\
		  access="%s"/>} $tab $name $signature $access]
		continue
	    }
	    lappend rc [format {%s  <property name="%s" type="%s"\
	      access="%s">} $tab $name $signature $access]
	    foreach {key value} $meta {
		lappend rc [format {%s    <annotation name="%s" value="%s"/>} \
		  $tab org.freedesktop.DBus.$key $value]
	    }
	    lappend rc [format {%s  </property>} $tab]
	}
    }
    lappend rc [format {%s</interface>} $tab]
    return [join $rc \n]
}

proc dbus::dbif::standard {bus} {
    variable dbif
    variable trace
    set arg1 [dict create in {interface_name s property_name s} out {value v} meta {}]
    set arg2 [dict create in {interface_name s property_name s value v} out {} meta {}]
    set arg3 [dict create in {interface_name s} out {values a{sv}} meta {}]
    create $bus "" org.freedesktop.DBus.Properties
    dict set dbif($bus,,org.freedesktop.DBus.Properties) methods \
      [dict create Get,ss $arg1 Set,ssv $arg2 GetAll,sa{sv} $arg3]
    if {$trace} {
	dict set dbif($bus,,org.freedesktop.DBus.Properties) signals \
	  [list PropertiesChanged]
    }
    create $bus "" org.freedesktop.DBus.Introspectable
    dict set dbif($bus,,org.freedesktop.DBus.Introspectable) methods \
      [dict create Introspect, [dict create in {} out {xml_data s} meta {}]]
}

########################################################################
# DBus message handlers
########################################################################

# Handlers for processing received messages. This will automatically handle
# calls to methods of the supported standard interfaces. Calls to defined
# methods will be handed off to the associated code.
#
proc dbus::dbif::ping {data args} {
    return
}

proc dbus::dbif::machineid {bus data args} {
    return [dbus info $bus machineid]
}

proc dbus::dbif::introspect {bus data args} {
    return [node $bus [dict get $data path]]
}

proc dbus::dbif::methods {bus data args} {
    variable timeout; variable msgid; variable info; variable dbif
    dict with data {}
    if {![info exists dbif($bus,$path,$interface)]} {
	dbuserr interface $bus $path $interface
    }
    if {![dict exists $dbif($bus,$path,$interface) \
      methods $member,$signature]} {
	dbuserr member $bus $path $interface $member $signature
    }
    set dict [dict get $dbif($bus,$path,$interface) methods $member,$signature]

    set id message[incr msgid]
    # Allow 25 seconds for the application to provide a response
    set afterid [after $timeout [list dbus::dbif::expire $id]]
    set info($id) [dict merge $data [dict create bus $bus afterid $afterid]]
    dict with dict {
    	if {[catch {interp eval $interp \
	  [list uplevel #0 $command [linsert $args 0 $id]]} result opts]} {
	    respond error $id $result
	} elseif {$async || [async $opts]} {
    	    # Keep the message information around for a bit more
	} elseif {$noreply} {
	    expire $id
	} elseif {[info exists info($id)]} {
	    respond return $id $result
	}
    }
    return -async 1
}

proc dbus::dbif::signals {bus data args} {
    variable msgid; variable info; variable hear
    dict with data {}
    # Check that a handler was defined for the member/signature combination
    if {![dict exists $hear($bus,$path,$interface) $member,$signature]} return

    set id message[incr msgid]
    set info($id) [dict merge $data [dict create bus $bus afterid $id]]
    set dict [dict get $hear($bus,$path,$interface) $member,$signature]
    catch {
	dict with dict {
	    interp eval $interp [list uplevel #0 $command [linsert $args 0 $id]]
	}
    }
    # Clean up
    expire $id
}
