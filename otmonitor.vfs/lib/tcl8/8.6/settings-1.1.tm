# -*- tcl -*-

package require Tcl 8.6; # Due to the use of tailcall

namespace eval settings {
    variable mtime "" settings {} storage file author Unknown homedir ""
    namespace ensemble create -map {
	set define unset undefine get obtain flush write
	file configfile homedir homedir appdata appdata
    }
}

proc settings::init {} {
    global argv0
    variable storage
    variable author
    if {![catch {package require registry}]} {
	set storage registry
	if {[info exists starkit::topdir]} {
	    # Extract the author from the tclkit.inf file.
	    if {![catch {open [file join $starkit::topdir tclkit.inf]} fd]} {
		catch {set author [dict get [read $fd] CompanyName]}
		close $fd
	    }
	}
    }

    if {[info exists starkit::mode] && $starkit::mode eq "starpack"} {
	# Only for starpacks take the name of the executable
	set app [info nameofexecutable]
    } elseif {[string match *.vfs/main.tcl [file normalize $argv0]]} {
	# Running unwrapped starpack
	set app [file dirname [file normalize $argv0]]
    } else {
	# Otherwise take the name of the main script/kit
	set app $argv0
    }
    variable appname [file rootname [file tail $app]]

    if {$storage eq "file"} {
	# Old convention
	variable configfile [file join [homedir] [format .%src $appname]]
	if {![file exists $configfile]} {
	    if {[file isdirectory [file join [homedir] .config]]} {
		file mkdir [file join [homedir] .config $appname]
		set configfile \
		  [file join [homedir] .config $appname $appname.conf]
	    } else {
		set configfile [file join [homedir] $appname $appname.conf]
	    }
	}
    } elseif {$storage eq "registry"} {
	# Old convention
	variable registrykey \
	  [format {HKEY_LOCAL_MACHINE\Software\%s\%s} Unknown $appname]
	# Possible errors: absence of the key, insufficient permissions
	if {[catch {registry keys $registrykey} old] || [llength $old] == 0} {
	    set registrykey \
	      [format {HKEY_CURRENT_USER\Software\%s\%s} $author $appname]
	}
    }
}

proc settings::define {section name value} {
    variable settings
    dict set settings $section $name $value
}

proc settings::undefine {section name} {
    variable settings
    dict unset settings $section $name
}

proc settings::obtain {section name {default ""}} {
    variable settings
    load
    if {[dict exists $settings $section $name]} {
	return [dict get $settings $section $name]
    } else {
	return $default
    }
}

proc settings::write {} {
    variable storage
    if {$storage eq "registry"} {
        tailcall writereg
    } else {
        tailcall writefile
    }
}

proc settings::writefile {} {
    variable settings
    variable configfile
    set fd [open $configfile w]
    dict for {section data} $settings {
	puts $fd [format {%s %c} $section 123]
	dict for {var val} $data {
	    if {[string match *list $var]} {
		puts $fd [format {  %s %c} $var 123]
		foreach n $val {puts $fd "    [list $n]"}
		puts $fd [format {  %c} 125]
	    } else {
		puts $fd "  [list $var $val]"
	    }
	}
	puts $fd [format %c 125]
    }
    close $fd
}

proc settings::writereg {} {
    variable registrykey
    variable settings
    dict for {section data} $settings {
	set key $registrykey\\$section
	dict for {var val} $data {
	    if {[string match *list $var]} {
		registry set $key $var $val multi_sz
	    } else {
		registry set $key $var $val
	    }
	}
    }
}

proc settings::load {} {
    variable storage
    if {$storage eq "registry"} {
	tailcall loadreg
    } else {
	tailcall loadfile
    }
}

proc settings::loadfile {} {
    variable settings
    variable mtime
    variable configfile
    try {
	set file $configfile
	if {[file mtime $file] <= $mtime} return
	set fd [open $file]
	set settings [read $fd]
	# Check that the data can be parsed as a two-level dict
	dict for {section data} $settings {
	    dict size $data
	}
	set mtime [clock seconds]
    } on error err {
	set settings {}
    } finally {
	if {[info exists fd]} {close $fd}
    }
}

proc settings::loadreg {} {
    variable registrykey
    variable settings {}
    if {[catch {registry keys $registrykey} sections]} return
    foreach section $sections {
	set key $registrykey\\$section
	foreach var [registry values $key] {
	    dict set settings $section $var [registry get $key $var]
	}
    }
}

proc settings::configfile {name} {
    variable configfile $name storage file
}

proc settings::appdata {} {
    # Find a directory for storing data files
    global tcl_platform
    variable author
    variable appname
    if {$tcl_platform(platform) eq "windows"} {
	set appdata [file join [homedir] AppData Local $author $appname]
    } else {
	set appdata [file join [homedir] .config $appname]
    }
}

proc settings::homedir {} {
    # Determine the user's home directory. This can be more complicated
    # than it should be. On linux $env(HOME) may not exist when the process
    # is auto-started by dbus. On Windows a user may also have changed
    # $env(USERNAME), leading to a fake user in $tcl_platform(user).
    global env tcl_platform
    variable homedir
    if {$homedir ne ""} {return $homedir}
    if {[info exists env(HOME)]} {
	# Simple situation, should provide a result in 99% of the cases
	return [file normalize $env(HOME)]
    } elseif {![catch {file normalize ~$tcl_platform(user)} dir]} {
	# The home directory of the current user
	return $dir
    } elseif {$tcl_platform(platform) ne "windows"} {
	# Create a file and get its owner
	set fd [file tempfile fn]
	set user [file attributes $fn -owner]
	close $fd
	file delete -force $fn
    } elseif {![catch {exec \
      tasklist /FI {IMAGENAME eq explorer.exe} /FO list /V} ret]} {
	# Fake user, try to determine the real user
	set line [lsearch -inline [split $ret \n] {User Name: *}]
	regexp {^User Name: *(.*)\\(.*)} $line - domain user
    } else {
	# All other avenues failed, return some standard location
	return C:/users/default
    }
    # Return the home directory of the real user
    return [file normalize ~$user]
}

namespace eval settings init

# blob		binary
# integer	dword
# string	sz
# list		multi_sz
