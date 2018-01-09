# Internet Explorer:
# Import client.pfx in Personal
# Import CA.crt in Trusted root certificate authorities
#
# Firefox:
# Import client.pfx in Your Certificates
# Import CA.crt in Authorities (This certificate can identify web sites)

# Repeat the basic starkit initialization
package require starkit
set argv0 [file normalize [info script]]
starkit::startup
if {$starkit::mode in {unwrapped sourced}} {
    tcl::tm::add {*}[glob -nocomplain [file join $starkit::topdir lib tcl? *]]
}

package require Tk
wm withdraw .
tk appname otmonwiz
wm protocol . WM_DELETE_WINDOW {thread::release}

source [file join [file dirname [info script]] themes.tcl]
themeinit

namespace eval sslwizard {
    variable passphrase "" capassphrase "" pfxpasswd ""

    variable cfg
    array set cfg {
	certdays	365
	cacertdays	3652
    }
    variable access rw

    variable filetypes {
	.key	"License Key Files"
	.csr	"Certificate Signing Request Files"
	.crt	"Security Certificate Files"
	.pfx	"PKCS #12 Certificate Files"
    }

    variable ssldir [file join [file dirname $starkit::topdir] auth]
    file mkdir $ssldir

    ttk::style map TEntry -foreground {invalid red} -background {invalid yellow}

    # Try to locate the openssl binary for additional functionality
    variable openssl
    if {[set openssl [auto_execok openssl]] ne ""} {
        # Binary found on the system
    } elseif {[info exists env(OPENSSL)]} {
	# Specified via the environment
	set openssl [file normalize $env(OPENSSL)]
    } elseif {[info exists env(OPENSSL_CONF)]} {
	# Next to the config file
	set openssl [file join [file dirname $env(OPENSSL_CONF)] openssl.exe]
    } elseif {$tcl_platform(platform) eq "windows"} {
        # Default path on windows
        set openssl "C:/OpenSSL-Win32/bin/openssl.exe"
    } else {
        # Wild guess
        set openssl /usr/sbin/openssl
    }
    if {![file executable $openssl]} {set openssl ""}
}

proc sslwizard::openssl {args} {
    variable openssl
    return [exec $openssl {*}$args]
}

proc sslwizard::sslfile {name} {
    variable ssldir
    return [file join $ssldir $name]
}

proc sslwizard::geolocation {} {
    variable wiz
    package require http
    package require tdom

    set url http://freegeoip.net/xml/
    if {[catch {http::geturl $url -timeout 10000} tok]} {
	puts $tok
	return
    }
    set status [::http::status $tok]
    set data [http::data $tok]
    http::cleanup $tok
    if {$status ne "ok"} {
	puts $data
	return
    }

    set rc {}
    catch {
	dom parse $data doc
	$doc documentElement root
	foreach n [$root childNodes] {
	    dict set rc [$n nodeName] [$n text]
	}
    }
    return $rc
}

proc sslwizard::store {name data {permissions 0o600}} {
    set file [sslfile $name]
    set fd [open $file w $permissions]
    puts $fd $data
    close $fd
    return $file
}

proc sslwizard::sslcfg {data {file openssl.cnf}} {
    set cfgfile [sslfile $file]
    set fmt {%-32s= %s}
    set f [open $cfgfile w]
    dict for {sect list} $data {
	puts $f [format {[ %s ]} $sect]
	foreach {attr val} $list {
	    puts $f [format $fmt $attr $val]
	}
	puts $f ""
    }
    close $f
    return $cfgfile
}

proc sslwizard::cakey {{password ""}} {
    # Read and decode the CA key file
    set fd [open [sslfile CA.key]]
    set rc [pki::pkcs::parse_key [read $fd] $password]
    close $fd
    # Get the subject from the certificate
    set fd [open [sslfile CA.crt]]
    set info [pki::x509::parse_cert [read $fd]]
    close $fd
    dict set rc subject [dict get $info subject]

    return $rc
}

proc sslwizard::distname {init {ua server}} {
    global tcl_platform
    variable hostnames {}
    if {[dict exists $init L] && [dict get $init L] ne ""} {
	set city [dict remove $init CN OU]
    } else {
    	set data [geolocation]
	set city [dict create]
	foreach {n1 n2} {CountryCode C RegionName ST City L} {
	    if {[dict exists $data $n1]} {
		dict set city $n2 [dict get $data $n1]
	    }
	}
    }
    if {[catch {socket -server dummy -myaddr [info hostname] 0} sock]} {
	set ip {}
	set host {}
    } else {
    	lassign [fconfigure $sock -sockname] ip host
	close $sock
    }
    set user $tcl_platform(user)
    if {$ua eq "CA"} {
	set str [string totitle [lindex [split [info hostname] .] 0]]
	set name "$str Root CA"
	set unit "Certificate Authority"
    } elseif {$ua eq "server"} {
	# Try to determine the external host name
	set url http://hv.tclcode.com/cgi-bin/hostname.cgi?all
	if {[catch {http::geturl $url} tok] || [http::ncode $tok] != 200} {
	    if {$host ne $ip} {
                lappend hostnames $host
            }
            lappend hostnames localhost
	} else {
	    set dict [split [string trim [http::data $tok] \n] \n\t]
	    if {[llength $dict] & 1} {set dict {}}
	    if {[dict exists $dict fqdn]} {
		lappend hostnames [dict get $dict fqdn]
	    }
	    if {$host ne $ip} {
    		lappend hostnames $host
	    }
	    lappend hostnames localhost
	    if {[dict exists $dict ip]} {
		lappend hostnames [dict get $dict ip]
	    }
	}
	http::cleanup $tok
	if {$ip ne ""} {lappend hostnames $ip}
	lappend hostnames 127.0.0.1
	set name [lindex $hostnames 0]
	set unit OTMonitor
    } elseif {$tcl_platform(platform) ne "windows"} {
	set name $user
	set f [open /etc/passwd]
	while {[gets $f line] != -1} {
	    set rec [split $line :]
	    if {[lindex $rec 0] eq $user} {
		set name [lindex $rec 4]
		break
	    }
	}
	close $f
	set unit Users
    } else {
	set name $user
	if {![catch {open "|wmic useraccount get fullname,name /value"} f]} {
	    fconfigure $f -translation crlf
	    set data [string map [list \r ""] [read $f]]
	    close $f
	    set lines [split $data \n]
	    set x [lsearch -exact $lines "Name=$user"]
	    if {$x > 0} {
		set line [lindex $lines [expr {$x - 1}]]
		if {[string match {FullName=?*} $line]} {
		    set name [string range $line 9 end]
		}
	    }
	}
	set unit Users
    }
    set rc [dict create C "" ST "" L "" O "Opentherm Gateway" \
      OU $unit CN $name EMAIL [string map [list " " .] $user@$host]]
    return [dict merge $rc $city]
}

proc sslwizard::certificate {name {sign 0}} {
    variable wiz
    set dn [array get wiz]
    if {$name eq "server"} {
	# Allow multiple domains
	set cn [dict get $dn CN]
	dict unset dn CN
	set seq 0
	foreach n $cn {
    	    lappend dn $seq.CN $n
	    incr seq
	}
	# Don't put a password on the server key
	set passwd ""
    } else {
	variable passphrase
	set name [getclientname $wiz(CN)]
	set passwd $passphrase
    }
    dict set dict req default_bits 1024
    dict set dict req distinguished_name req_distinguished_name
    dict set dict req prompt no
    dict set dict req_distinguished_name $dn

    # Generate an RSA key
    set key [pki::rsa::generate 1024]
    store $name.key [pki::key $key $passwd]

    # Create a certificate signing request
    set csr [pki::pkcs::create_csr $key [array get wiz] 1]
    
    if {$sign} {
	sign $csr $name
	message action "Successfully generated the server certificate"
    } else {
	store $name.csr $csr
	set msg "Successfully generated the certificate signing request"
	append msg \n \n "Output file: [file nativename $name.csr]"
	append msg \n "Key file: [file nativename $name.key]"
	message action $msg
    }
}

proc sslwizard::sign {csrdata name {serial ""}} {
    global mainthread
    variable cfg
    variable capassphrase
    if {$serial eq ""} {
	set serial [clock format [clock seconds] -format %Y%m%d%H%M%S]
    }

    set csr [pki::pkcs::parse_csr $csrdata]
    set issue [clock seconds]
    set expire [clock add $issue $cfg(certdays) days]
    set cakey [cakey $capassphrase]

    set crt [pki::x509::create_cert $csr $cakey $serial $issue $expire 0 {} 1]
    return [store $name.crt $crt]
}

proc sslwizard::clear {} {
    variable f
    lassign [grid size $f] cols rows
    for {set i 0} {$i < $cols} {incr i} {
	grid columnconfigure $f $i -weight 0
    }
    for {set i 0} {$i < $rows} {incr i} {
	grid rowconfigure $f $i -weight 0
    }
    destroy {*}[winfo children $f]
    return $f
}

proc sslwizard::message {cmd str} {
    variable f
    destroy {*}[winfo children $f]
    set w [expr {[winfo reqwidth $f] - 4}]
    ttk::label $f.msg -text $str -wraplength $w
    grid $f.msg -sticky new
    grid columnconfigure $f $f.msg -weight 1
    grid rowconfigure $f $f.msg -weight 1
    next -command $cmd -state !disabled
    finish -state disabled
}

proc sslwizard::busy {body} {
    variable f
    set top [winfo toplevel $f]
    message {} "Collecting information - Please wait ..."
    $top configure -cursor watch
    grab $f.msg
    set rc [uplevel 1 $body]
    $top configure -cursor {}
    grab release $f.msg
    return $rc
}

proc sslwizard::button {w args} {
    if {[dict exists $args -command]} {
	dict set args -command [namespace code [dict get $args -command]]
    }
    $w configure {*}[dict remove $args -state]
    if {[dict exists $args -state]} {
	$w state [dict get $args -state]
    }
}

proc sslwizard::next {args} {
    button .wiz.b1 {*}$args
}

proc sslwizard::finish {args} {
    button .wiz.b2 {*}$args
}

proc sslwizard::cancel {args} {
    button .wiz.b3 {*}$args
}

proc sslwizard::quit {} {
    destroy .wiz
    thread::release
}

proc sslwizard::finally {} {
    # Perform the Next action and then terminate
    .wiz.b1 invoke
    quit
}

proc sslwizard::runaction {} {
    variable step
    $step
}

proc sslwizard::getfile {win args} {
    variable filetypes
    if {$win eq "-save"} {
	set cmd tk_getSaveFile
	set args [lassign $args win]
    } else {
	set cmd tk_getOpenFile
    }
    set var [$win cget -textvariable]
    upvar 1 $var name
    set dir [file dirname $name]
    set file [file tail $name]
    foreach n $args {
	if {[dict exists $filetypes $n]} {
	    lappend types [list [dict get $filetypes $n] $n]
	}
    }
    lappend types [list "All Files" *]
    set file [$cmd -parent .wiz -filetypes $types \
      -initialfile $file -initialdir $dir]
    if {$file ne ""} {
	set name $file
	$win validate
    }
}

proc sslwizard::getclientname {name} {
    # Remove troublesome characters from the string
    regsub -all {["/\\*?<>|:]} $name _ str
    set path [sslfile $str]
    set exist [glob -nocomplain -tails -path $path .csr ??.csr]
    set file $str
    set seq ""
    while {"$file.csr" in $exist} {
	set seq [expr {$seq eq "" ? 0 : $seq + 1}]
	set file [format %s%02d $str $seq]
    }
    return $file
}

proc sslwizard::getlatest {{pattern *}} {
    variable ssldir
    set name ""
    set ts 0
    foreach file [glob -nocomplain -directory $ssldir $pattern] {
	set mtime [file mtime $file]
	if {$mtime > $ts} {
	    set name $file
	    set ts $mtime
	}
    }
    return $name
}

proc sslwizard::validate {win cond value {min 1} {max 64}} {
    set parent [winfo parent $win]
    set len [string length $value]
    set rc [expr {$len >= $min && $len <= $max}]
    after idle [list $win state [lindex {invalid !invalid} $rc]]
    # We're using a shadow ttk::entry widget for ttk::comboxen
    if {[winfo class $win] eq "TCombobox"} {append win s}
    if {$cond ne "forced"} {
    	foreach w [winfo children $parent] {
	    if {$w ne $win && [winfo class $w] in {TEntry}} {
		$w instate disabled continue
		if {![$w validate]} {set rc 0}
    	    }
	}
	set state [lindex {disabled !disabled} $rc]
	next -state $state
	finish -state $state
	return 1
    } else {
	return $rc
    }
}

proc sslwizard::validatefile {str} {
    set ok [file exists $str]
    set state [lindex {disabled !disabled} $ok]
    next -state $state
    return 1
}

proc sslwizard::certificateform {{ua ""}} {
    variable hostnames {}
    if {$ua ne ""} {
	variable wiz
	array set wiz [busy {distname [array get wiz] $ua}]
    }
    set f [clear]
    ttk::label $f.l6 -text "Common Name:"
    if {$ua eq "server"} {
	ttk::combobox $f.e6 -width 28 -textvariable sslwizard::wiz(CN) \
	  -validate all -validatecommand [namespace code {validate %W %V %P}] \
	  -values $hostnames
	ttk::entry $f.e6s -textvariable sslwizard::wiz(CN) \
	  -validatecommand [namespace code {validate %W %V %P}]
    } else {
    	ttk::entry $f.e6 -width 36 -textvariable sslwizard::wiz(CN) \
	  -validate all -validatecommand [namespace code {validate %W %V %P}]
    }
    ttk::label $f.l7 -text "Email address:"
    ttk::entry $f.e7 -width 36 -textvariable sslwizard::wiz(EMAIL) \
      -validate all -validatecommand [namespace code {validate %W %V %P}]
    ttk::label $f.l4 -text Organization:
    ttk::entry $f.e4 -width 36 -textvariable sslwizard::wiz(O) \
      -validate all -validatecommand [namespace code {validate %W %V %P}]
    ttk::label $f.l5 -text Unit:
    ttk::entry $f.e5 -width 36 -textvariable sslwizard::wiz(OU) \
      -validate all -validatecommand [namespace code {validate %W %V %P}]
    ttk::label $f.l3 -text Location:
    ttk::entry $f.e3 -width 36 -textvariable sslwizard::wiz(L) \
      -validate all -validatecommand [namespace code {validate %W %V %P}]
    ttk::label $f.l2 -text State:
    ttk::entry $f.e2 -width 36 -textvariable sslwizard::wiz(ST) \
      -validate all -validatecommand [namespace code {validate %W %V %P}]
    ttk::label $f.l1 -text Country:
    ttk::entry $f.e1 -width 4 -textvariable sslwizard::wiz(C) \
      -validate all -validatecommand [namespace code {validate %W %V %P 2 2}]
    ttk::checkbutton $f.c1 -text Read-only -variable sslwizard::access \
      -onvalue ro -offvalue rw
    ttk::label $f.l8 -text "CA Passphrase:"
    ttk::entry $f.e8 -width 36 -textvariable sslwizard::capassphrase -show # \
      -validate all -validatecommand [namespace code {validate %W %V %P 4 20}]
    grid $f.l6 $f.e6 - -sticky ew -padx 2 -pady 2
    grid $f.l7 $f.e7 - -sticky ew -padx 2 -pady 2
    grid $f.l4 $f.e4 - -sticky ew -padx 2 -pady 2
    grid $f.l5 $f.e5 - -sticky ew -padx 2 -pady 2
    grid $f.l3 $f.e3 - -sticky ew -padx 2 -pady 2
    grid $f.l2 $f.e2 - -sticky ew -padx 2 -pady 2
    grid $f.l1 $f.e1 $f.c1 -sticky ew -padx 2 -pady 2
    grid $f.l8 $f.e8 - -sticky ew -padx 2 -pady 2
    grid columnconfigure $f $f.e1 -weight 1
    grid remove $f.c1
    $f.e8 validate
    $f.e6 selection range 0 end
    $f.e6 icursor end
    after idle [list focus $f.e6]
    return $f
}

proc sslwizard::init {} {
    global tcl_platform

    package require http
    package require pki

    variable imgdir [file join $starkit::topdir images]
    for {set retries 1} {$retries < 10} {incr retries} {
	if {[catch {image create photo icon \
	  -file [file join $imgdir cert.png]}]} {
	    lappend ::errorLog $::errorInfo
	} else {
	    break
	}
    }
    image create photo icon48 -file [file join $imgdir cert48.png]

    toplevel .wiz
    if {$tcl_platform(platform) eq "unix"} {
	# ttk::setTheme plastik
	array set col [ttk::style configure .]
	option add *background $col(-background) userDefault
	option add *Menu.activeBackground #668aac userDefault
	option add *Menu.activeForeground #ffffff userDefault
	option add *Menu.activeBorderWidth 0 userDefault
	option add *Menu.borderWidth 1 userDefault
	option add *Menu.relief solid userDefault
    } else {
	array set col [ttk::style configure .]
    }
    place [ttk::frame .wiz.bg] -relwidth 1 -relheight 1
    wm withdraw .wiz
    wm title .wiz "Certificate wizard"
    wm iconphoto .wiz -default icon48 icon
    variable f [ttk::frame .wiz.f]
    ttk::separator .wiz.sep
    ttk::button .wiz.b1 -width 6 -text Next
    ttk::button .wiz.b2 -width 6 -text Finish
    ttk::button .wiz.b3 -width 6 -text Cancel
    grid .wiz.f -columnspan 3 -sticky news -padx 8 -pady 8
    grid .wiz.sep -columnspan 3 -padx 2 -sticky ew
    grid .wiz.b1 .wiz.b2 .wiz.b3 -sticky e -padx 4 -pady 6
    grid columnconfigure .wiz .wiz.b1 -weight 1
    grid rowconfigure .wiz .wiz.f -weight 1
    grid anchor $f center
    certificateform
    update
    grid propagate $f 0
    tk::PlaceWindow .wiz
    wm deiconify .wiz
    action
}

proc sslwizard::action {} {
    variable step; variable openssl
    set f [clear]
    ttk::labelframe $f.f1 -text "Server side"
    ttk::labelframe $f.f2 -text "Client side"
    ttk::radiobutton $f.r1 -variable sslwizard::step -value createcacheck \
      -text "Setup certification authority"
    ttk::radiobutton $f.r2 -variable sslwizard::step -value servercertform \
      -text "Create server certificate"
    ttk::radiobutton $f.r4 -variable sslwizard::step -value signcsrform \
      -text "Digitally sign a client's CSR"
    ttk::radiobutton $f.r6 -variable sslwizard::step -value revokecertform \
      -text "Revoke a client certificate"
    ttk::radiobutton $f.r3 -variable sslwizard::step -value clientcertform \
      -text "Create signing request"
    ttk::radiobutton $f.r5 -variable sslwizard::step -value clientpkcsform \
      -text "Bundle files in PKCS#12 format"
    if {$openssl eq ""} {$f.r5 state disabled}
    grid $f.f1 -sticky ew -pady 4
    grid $f.f2 -sticky ew -pady 4
    grid $f.r1 -sticky ew -in $f.f1 -padx 4
    grid $f.r2 -sticky ew -in $f.f1 -padx 4
    grid $f.r4 -sticky ew -in $f.f1 -padx 4
    grid $f.r6 -sticky ew -in $f.f1 -padx 4
    grid $f.r3 -sticky ew -in $f.f2 -padx 4
    grid $f.r5 -sticky ew -in $f.f2 -padx 4

    if {![file exists [sslfile CA.crt]] || ![file exists [sslfile CA.key]]} {
	$f.r2 state disabled
	$f.r4 state disabled
	if {![file exists [sslfile CA.crt]]} {
	    $f.r6 state disabled
	    set step createcacheck
	} else {
	    set step revokecertform
	}
    } elseif {![info exists step] || $step eq "servercertform"} {
	set step signcsrform
    } elseif {$step eq "createcacheck"} {
	set step servercertform
    }

    next -command runaction -state !disabled
    cancel -command quit -state !disabled
    finish -state disabled
}

proc sslwizard::createcacheck {} {
    if {[file exists [sslfile CA.crt]]} {
	message createcaform "A Certification Authority has already been set\
	  up. Continuing to set up a new Certification Authority will make\
	  all client certificates signed by the old Certification Authority\
	  completely useless.\n\nClick 'Next' to continue, or 'Cancel' to\
	  return to the previous page."
	cancel -command action -state !disabled
    } else {
	createcaform
    }
}

proc sslwizard::createcaform {} {
    certificateform CA
    next -command createca
    cancel -command action -state !disabled
    finish -command finally
}

proc sslwizard::createca {} {
    variable cfg
    variable capassphrase; variable wiz
    dict set dict req default_bits 1024
    dict set dict req distinguished_name req_distinguished_name
    dict set dict req prompt no
    dict set dict req_distinguished_name [array get wiz]

    set key [pki::rsa::generate 1024]
    store CA.key [pki::key $key $capassphrase]
    # Keep a standard order to make the certificate easier to read by humans
    foreach n {CN O OU C ST L EMAIL} {
	if {$wiz($n) ne ""} {
	    lappend subject $n=$wiz($n)
	}
    }
    dict set key subject [join $subject ,]
    set issue [clock seconds]
    set expire [clock add $issue $cfg(cacertdays) days]
    set crt [pki::x509::create_cert $key $key 1 $issue $expire 1 {} 1]
    store CA.crt $crt

    set msg "Certification Authority has been setup successfully."

    # Delete all client certificates, which are now obsolete

    message action $msg
    cancel -command quit -state !disabled
}

proc sslwizard::servercertform {} {
    certificateform server
    next -command {certificate server 1}
    cancel -command action -state !disabled
    finish -command finally
}

proc sslwizard::clientcertform {} {
    set f [certificateform client]
    $f.l8 configure -text Passphrase:
    $f.e8 configure -textvariable sslwizard::passphrase
    # $f.l8 state disabled
    # $f.e8 state disabled
    next -command {certificate client} -state !disabled
    cancel -command action -state !disabled
    finish -command finally -state !disabled
}

proc sslwizard::signcsrform {} {
    variable csrfile [getlatest *.csr]
    set f [clear]
    ttk::label $f.l1 -text "Location of the client signing request file:"
    ttk::entry $f.e1 -textvariable sslwizard::csrfile -validate all \
      -validatecommand [namespace code {validatefile %P}]
    ttk::button $f.b1 -text ... -width 0 \
      -command [namespace code [list getfile $f.e1 .csr]]
    grid $f.l1 - -sticky w -padx 2
    grid $f.e1 $f.b1 -sticky ew -padx 2
    grid columnconfigure $f $f.e1 -weight 1
    next -command getcsrdata
    cancel -command action -state !disabled
    finish -state disabled
}

proc sslwizard::getcsrdata {} {
    variable csrfile
    # openssl req -noout -subject -in testclient.csr
    # subject=/C=NL/L=Hilversum/O=Tcl Code, Inc/OU=HomeVisionXL/CN=Schelte Bron/EMAIL=hvxl@tclcode.com
    try {
	set fd [open $csrfile]
	set csr [::pki::pkcs::parse_csr [read $fd]]
	close $fd
    } trap {POSIX ENOENT} err {
	message signcsrform "Could not process certificate signing\
	  request:\nFile does not exist: $crsfile"
	cancel -command action -state !disabled
	return
    } on error err {
	message signcsrform "Could not process certificate signing\
	  request:\n$err"
	cancel -command action -state !disabled
	close $fd
	return
    }

    variable wiz
    set f [certificateform]
    for {set i 1} {$i < 8} {incr i} {
	$f.e$i state readonly
    }
    # grid $f.c1
    $f.e3 configure -style TEntry
    foreach n [split [dict get $csr subject] ,] {
	set x [string first = $n]
	set var [string trim [string range $n 0 [expr {$x - 1}]]]
	set val [string trim [string range $n [expr {$x + 1}] end]]
	set wiz($var) $val
    }
    next -command signrequest
    cancel -command action -state !disabled
    finish -command finally
}

proc sslwizard::signrequest {} {
    global mainthread
    variable cfg
    variable csrfile
    variable access
    set serial [clock format [clock seconds] -format %Y%m%d%H%M%S]
    set name [file rootname [file tail $csrfile]]
    try {
	set fd [open $csrfile]
	set csr [read $fd]
	close $fd
	set out [sign $csr $name $serial]
    	# Tell the main thread to register the certificate
	thread::send -async $mainthread [list security addcert $out $access]
	message action "Successfully generated the client certificate"
	cancel -command quit -state !disabled
    } on error result {
	message getcsrdata "Failed to sign the certificate:\n$result"
	cancel -command action -state !disabled
    }
}

proc sslwizard::revokecertform {} {
    global mainthread
    set f [clear]
    set width [expr {[font measure TkDefaultFont {0000/00/00 00:00:00}] + 8}]
    ttk::label $f.l1 -text "Select the certificates to revoke:"
    ttk::treeview $f.tv -show headings \
      -columns {name serial expire access} -displaycolumns {name serial}
    $f.tv column name -stretch 1 -width 100
    $f.tv heading name -text Name
    $f.tv column serial -stretch 0 -width $width
    $f.tv heading serial -text Issued
    # Get the data from the main thread
    set sql {select name,serial,expires,access from certificates where revoked=0}
    set data [thread::send $mainthread [list security::db eval $sql]]
    foreach {name serial expire access} $data {
	scan $serial {%4s%2s%2s%2s%2s%2s} y mon d h m s
	set serial "$y/$mon/$d $h:$m:$s"
	set expire [clock format $expire -format {%Y/%m/%d %T}]
	$f.tv insert {} end -values [list $name $serial $expire $access]
    }
    pack propagate $f 0
    pack $f.l1 -side top -fill x -pady {0 2}
    pack $f.tv -fill both -expand 1

    bind $f.tv <<TreeviewSelect>> {
	apply {
	    w {
		if {[llength [$w selection]] > 0} {
		    next -state !disabled
		    finish -state !disabled
		} else {
		    next -state disabled
		    finish -state disabled
		}
	    }
	sslwizard} %W
    }

    next -command [list revokecert $f.tv] -state disabled
    cancel -command action -state !disabled
    finish -command finally -state disabled
}

proc sslwizard::revokecert {w} {
    global mainthread
    foreach n [$w selection] {
	set serial [string map {: "" / "" " " ""} [$w set $n serial]]
    }
    thread::send -async $mainthread [list security delcert $serial]
    tailcall action
}

proc sslwizard::clientpkcsform {} {
    set f [clear]
    set root [file rootname [getlatest *.crt]]
    if {$root eq "" || [file tail $root] in {CA server}} {
    	set root [sslfile client]
    }
    variable crtfile [file nativename $root.crt]
    variable keyfile [file nativename $root.key]
    variable pfxfile [file rootname $crtfile].pfx

    ttk::label $f.l2 -text "Private key file"
    ttk::entry $f.e2 -textvariable sslwizard::keyfile
    ttk::button $f.b2 -text ... -width 0 \
      -command [namespace code [list getfile $f.e2 .key]]
    ttk::label $f.l3 -text Passphrase: -width 0
    ttk::entry $f.e3 -textvariable sslwizard::passphrase -show #

    ttk::label $f.l1 -text "Signed certificate:"
    ttk::entry $f.e1 -textvariable sslwizard::crtfile
    ttk::button $f.b1 -text ... -width 0 \
      -command [namespace code [list getfile $f.e1 .crt]]

    ttk::label $f.l4 -text "Output file:"
    ttk::entry $f.e4 -textvariable sslwizard::pfxfile
    ttk::button $f.b4 -text ... -width 0 \
      -command [namespace code [list getfile -save $f.e4 .pfx]]
    ttk::label $f.l5 -text Passphrase: -width 0
    ttk::entry $f.e5 -textvariable sslwizard::pfxpasswd -show #

    grid $f.l2 - - -sticky sew -padx 2 -pady 0
    grid $f.e2 - $f.b2 -sticky ew -padx 2 -pady {0 4}
    grid $f.l3 $f.e3 - -sticky ew -padx 2 -pady 0

    grid $f.l1 - - -sticky sew -padx 2 -pady 0
    grid $f.e1 - $f.b1 -sticky ew -padx 2 -pady 0

    grid $f.l4 - - -sticky sew -padx 2 -pady 0
    grid $f.e4 - $f.b4 -sticky ew -padx 2 -pady {0 4}
    grid $f.l5 $f.e5 - -sticky ew -padx 2 -pady 0

    grid columnconfigure $f 1 -weight 1
    grid rowconfigure $f [list $f.l1 $f.l4] -weight 1 -uniform space
    next -command createpkcs12 -state !disabled
    cancel -command action -state !disabled
    finish -command finally -state !disabled
}

proc sslwizard::createpkcs12 {} {
    global tcl_platform
    variable crtfile; variable keyfile; variable pfxfile
    variable passphrase; variable pfxpasswd
    try {
	# Need the \n after $pfxpasswd in case it is left empty
	# Can't send both passwords via stdin on windows
	openssl pkcs12 -inkey $keyfile -passin pass:$passphrase -in $crtfile \
	  -export -out $pfxfile -passout pass:$pfxpasswd
	# Keep the file private
	if {$tcl_platform(platform) eq "unix"} {
	    file attributes $pfxfile -permissions go-rwx
	}
    } on ok out {
	set msg "Successfully generated PKCS#12 file."
	append msg \n \n "Output file: [file nativename $pfxfile]"
    } trap NONE out {
	# Some output was sent to stderr, on windows probably:
	# Loading 'screen' into random state - done
	set msg "Successfully generated PKCS#12 file."
	append msg \n \n "Output file: [file nativename $pfxfile]"
    } on error {out info} {
	set msg "Failed to create PKCS#12 file."
	append msg \n\n $out
    }
    message action $msg
    cancel -command quit -state !disabled
}

sslwizard::init

# Start the event loop
thread::wait
