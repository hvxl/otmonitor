# Support for MathWorks' ThingSpeak
# api_key=MYQL01QU749XE0XR

package require http
package require tls

http::register https 443 tls::socket

namespace eval tspeak {
    variable uri https://api.thingspeak.com/update
}

proc tspeak::run {{init 0}} {
    global cfg
    set cmd [namespace code run]
    after cancel $cmd
    if {$cfg(tspeak,enable)} {
	set ms [expr {1000 * $cfg(tspeak,interval)}]
	if {$cfg(tspeak,sync)} {
	    set ms [expr {$ms - ([clock milliseconds] % $ms)}]
	}
	if {$init} {
	    if {$cfg(tspeak,sync) && $ms < 30000} {
		# Allow some time at startup to collect data
		set ms [expr {$ms + $cfg(tspeak,interval) * 1000}]
	    }
	} else {
	    post
	}
	after $ms $cmd
    }
}

proc tspeak::post {} {
    global gui cfg
    variable uri
    set query [dict create api_key $cfg(tspeak,key)]
    foreach n [array names cfg tspeak,field*] {
	if {[info exists gui($cfg($n))]} {
	    set fld [lindex [split $n ,] 1]
	    dict set query $fld $gui($cfg($n))
	}
    }
    dict set query created_at \
      [clock format [clock seconds] -format {%Y-%m-%d %T%z}]

    if {[catch {http::geturl $uri -query [http::formatQuery {*}$query] \
      -command [namespace code response]} err]} {
	set ts [clock format [clock seconds] -format {%Y-%m-%d %T}]
	variable status "$ts - HTTP request failed: $err"
    }
}

proc tspeak::response {tok} {
    variable status
    set ts [clock format [clock seconds] -format {%Y-%m-%d %T}]
    if {[http::status $tok] ne "ok"} {
	set status "$ts - HTTP transaction failed: [http::status $tok]"
    } elseif {[http::ncode $tok] != 200} {
	set str [http::code $tok]
	set str [string replace $str 0 [string first " " $str]]
	set status "$ts - Request rejected: $str"
    } else {
	set entry [http::data $tok]
	if {$entry == 0} {
	    set status "$ts - Update rejected by the server"
	} else {
	    set status "$ts - Successfully created entry $entry"
	}
    }
    http::cleanup $tok
}

tspeak::run [expr {[clock seconds] - $start < 30}]
