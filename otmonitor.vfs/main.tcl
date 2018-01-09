#!/usr/bin/env otmonkit

package require starkit
starkit::startup
if {$starkit::mode in {unwrapped sourced}} {
    tcl::tm::add {*}[glob -nocomplain [file join $starkit::topdir lib tcl? *]]
}

proc include {file} [format {
    uplevel #0 [list source [file join %s $file]]
} [list $starkit::topdir]]

include otmonitor.tcl

