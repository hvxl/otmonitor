namespace eval htpasswd {
    variable apr 
    set apr ./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz
}

proc htpasswd::bitstochar {bits} {
    variable apr
    set rc ""
    while {$bits ne ""} {
	scan [string range $bits end-5 end] %b x
	append rc [string index $apr $x]
	set bits [string range $bits 0 end-6]
    }
    return $rc
}

proc htpasswd::salt {} {
    return [bitstochar [format %024b%024b \
      [expr {int(rand() * 16777216)}] [expr {int(rand() * 16777216)}]]]
}

proc htpasswd::pwmd5 {pw str} {
    package require md5

    set magic {$apr1$}
    set parts [split $str $]
    if {[lindex $parts 0] eq "" && "$[lindex $parts 1]$" eq $magic} {
	set parts [lrange $parts 2 end]
    }

    lassign $parts salt hash

    set sum [::md5::md5 $pw$salt$pw]

    set str $pw$magic$salt
    append str [string range $sum 0 [expr {[string length $pw] - 1}]]
    for {set i [string length $pw]} {$i != 0} {set i [expr {$i >> 1}]} {
	if {$i & 1} {
	    append str \0
	} else {
	    append str [string index $pw 0]
	}
    }
    set sum [::md5::md5 $str]

    for {set i 0} {$i < 1000} {incr i} {
	if {$i & 1} {set str $pw} else {set str $sum}
	if {$i % 3} {append str $salt}
	if {$i % 7} {append str $pw}
	if {$i & 1} {append str $sum} else {append str $pw}
	set sum [::md5::md5 $str]
    }

    binary scan $sum cu* bytes

    foreach n {0 6 12 1 7 13 2 8 14 3 9 15 4 10 5 11} {
	append bits [format %08b [lindex $bytes $n]]
	if {[string length $bits] >= 24} {
	    append result [bitstochar $bits]
	    set bits ""
	}
    }

    append result [bitstochar $bits]

    return $magic$salt$$result
}

proc htpasswd::pwsha1 {pw hash} {
    package require sha1
    return "{SHA}[binary encode base64 [sha1::sha1 -bin $pw]]"
}

proc htpasswd::validate {str hash} {
    switch -glob $hash {
	{$2a$*} - {$2y$*} {
	    # Blowfish
	}
	{$apr1$*} {
	    # MD5
	    set try [pwmd5 $str $hash]
	    return [expr {[pwmd5 $str $hash] eq $hash}]
	}
	{{SHA}*} {
	    # SHA1
	    set try [pwsha1 $str]
	    return [expr {[pwsha1 $str] eq $hash}]
	}
	default {
	    # Crypt?
	}
    }
    return 0
}
