namespace eval security {
    package require sqlite3
    variable cache {}
    variable authdb
    if {[info exists dbfile] && [file writable [file dirname $dbfile]]} {
        set authdb $dbfile
    } else {
        set authdb [file join [file dirname $starkit::topdir] auth auth.db]
        if {![file writable $authdb]} {
            set authdb [file join [settings appdata] auth.db]
        }
    }
    namespace ensemble create -subcommands {
	getusers adduser deluser chguser vfyuser addcert delcert vfycert
    }
}

proc security::authdb {script} {
    variable authdb
    sqlite3 [namespace current]::dbrw $authdb
    try {
        uplevel 1 [list dbrw eval $script]
    } finally {
	dbrw close
    }
}

proc security::permissions {file str} {
    global tcl_platform
    if {$tcl_platform(platform) eq "unix"} {
	file attributes $file -permissions $str
    }
}

proc security::createdb {} {
    global dbfile
    variable authdb
    if {![info exists dbfile]} {
        set authdir [file dirname $authdb]
        file mkdir $authdir
        permissions $authdir go-rwx
    }
    authdb {
	create table if not exists users (
	  name text unique,
	  password text,
	  access text check (access in ("rw", "ro"))
	);
	create table if not exists certificates (
	  name text,
	  serial int unique,
	  access text check (access in ("rw", "ro")),
	  expires int,
	  revoked int
        );
    }
    permissions $authdb go-rw
}

proc security::hash {str} {
    package require sha1
    return [sha1::sha1 $str]
}

proc security::getusers {} {
    return [db eval {select name from users}]
}

proc security::adduser {user password access} {
    set hash [hash $password]
    authdb {
	insert into users 
	  (name, password, access) 
	  values ($user, $hash, $access)
    }
}

proc security::deluser {user} {
    authdb {delete from users where name = $user}
}

proc security::chguser {user password} {
    set hash [hash $password]
    authdb {update users set password = $hash where name = $user}
}

proc security::vfyuser {str} {
    variable cache
    if {[dict exists $cache $str]} {
	return [dict get $cache $str]
    }
    set password [join [lassign [split [binary decode base64 $str] :] user] :]
    set hash [hash $password]
    db eval {select password,access from users where name = $user} {
	if {$password eq $hash} {
	    # Put the entry into the cache for faster access
	    set rc [dict create user $user access $access]
	    dict set cache $str $rc
	    return $rc
	}
    }
    # Don't grant access to the user
    return {}
}

proc security::addcert {file access} {
    package require pki
    set fd [open $file]
    try {
	set cert [::pki::x509::parse_cert [read $fd]]
    } finally {
	close $fd
    }
    dict update cert serial_number serial notAfter expires subject subject {}
    set rec [split $subject ,]
    set match [lsearch -inline -regexp $rec {^\s*CN=}]
    if {$match ne ""} {
	regsub {^\s*CN=} $match {} name
    }

    authdb {
	insert into certificates
	  (name, serial, access, expires, revoked)
	  values ($name, $serial, $access, $expires, 0)
    }
}

proc security::delcert {serial} {
    authdb {update certificates set revoked = 1 where serial = $serial}
}

proc security::vfycert {sernum} {
    db eval {select * from certificates where serial = $sernum} {
	if {!$revoked && $expires >= [clock seconds]} {
	    return [dict create user $name access $access]
	}
    }
    return {}
}

namespace eval security {} {
    variable available 0
    if {![file exists $authdb]} {if {[catch {createdb}]} return}
    sqlite3 [namespace current]::db $authdb -readonly 1
    set available 1
}
