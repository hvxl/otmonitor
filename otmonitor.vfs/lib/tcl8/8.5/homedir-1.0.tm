# Determine the user's home directory. This can be more complicated than it
# should be. On linux $env(HOME) may not exist when the process is auto-started
# by dbus. On Windows a user may also have changed $env(USERNAME), leading to
# a fake user in $tcl_platform(user).

proc homedir {} {
    global env tcl_platform
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
