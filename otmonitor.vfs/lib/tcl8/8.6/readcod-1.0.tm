# Library to read Byte Craft's .cod formatted symbol files.

oo::class create codfile {
    constructor {filename} {
	variable fd ""
	set fd [open $filename rb]
	my Parse
    }

    destructor {
	my variable fd
	if {$fd ne ""} {close $fd}
    }

    method DictScan {data spec {offs 0}} {
	set rc $spec
	set texts {}
	set fmt [lmap {k v} $spec {
	    if {[regexp {^T(\d+)$} $v -> cnt]} {
		lappend texts $k
		format {a%d} [incr cnt]
	    } else {
		set v
	    }
	}]
	if {$offs} {set fmt [linsert $fmt 0 @$offs]}
	dict with rc {
	    if {[binary scan $data $fmt {*}[dict keys $spec]] != [dict size $spec]} {
		return
	    }
	}
	foreach key $texts {
	    if {[scan [dict get $rc $key] %c l] == 1} {
		dict set rc $key [string range [dict get $rc $key] 1 $l]
	    }
	}
	return $rc
    }

    method ReadBlock {block} {
	my variable fd
	seek $fd [expr {$block * 512}]
	return [read $fd 512]
    }

    method Parse {} {
	my variable fd blocks info
	set spec {
	    indices su128
	    name T63
	    date T7
	    time su
	    version T19
	    compiler T11
	    notice T63
	    symtab su2
	    namtab su2
	    lsttab su2
	    addrsize cu
	    highaddr su
	    nextdir su
	    memmap su2
	    localvar su2
	    codtype su
	    processor T8
	    lsymtab su2
	    messtab su2
	}
	set next 0
	while {1} {
	    set block [my DictScan [my ReadBlock $next] $spec]
	    if {$next == 0} {set info $block}
	    set indices \
	      [lsearch -all -inline -integer -not [dict get $block indices] 0]
	    set base [expr {[dict get $block highaddr] << 16}]
	    set ranges {}
	    for {lassign [dict get $block memmap] i j} {$i && $i <= $j} {incr i} {
		binary scan [my ReadBlock $i] su* list
		foreach {start end} $list {
		    if {$end == 0 && [llength $ranges]} break
		    lappend ranges [expr {$base + $start}]
		    lappend ranges [expr {$base + $end}]
		}
	    }
	    set page -1
	    foreach {addr1 addr2} $ranges {
		set start $addr1
		while {$start <= $addr2} {
		    set addr [expr {$start & ~0x1ff}]
		    if {$addr != $page} {
			set indices [lassign $indices blknum]
			set page $addr
		    }
		    set end [expr {min($addr2, $start | 0x1ff)}]
		    dict lappend blocks $blknum $start $end
		    set start [expr {$end + 1}]
		}
	    }
	    set next [dict get $block nextdir]
	    if {$next == 0} return
	}
    }

    method processor {} {
	my variable info
	return [dict get $info processor]
    }

    method code {} {
	my variable blocks
	set addr 0
	set end 0
	dict for {blknum ranges} $blocks {
	    binary scan [my ReadBlock $blknum] su* words
	    lassign $ranges start
	    if {$start != $end + 1} {set addr [expr {$start >> 1}]}
	    set x2 0
	    foreach {start end} $ranges {
		set page [expr {$start & ~0x1ff}]
		set x1 [expr {($start - $page) >> 1}]
		if {$x2 && $x1 > $x2 + 1} {
		    set cnt [expr {$x1 - $x2 - 1}]
		    dict lappend code $addr {*}[lrepeat $cnt {}]
		}
		set x2 [expr {($end - $page) >> 1}]
		dict lappend code $addr {*}[lrange $words $x1 $x2]
	    }
	}
	return $code
    }

    method symbols {} {
	my variable info
	set rc {}
	lassign [dict get $info lsymtab] start end
	if {!$start} return
	for {set blknum $start} {$blknum <= $end} {incr blknum} {
	    set block [my ReadBlock $blknum]
	    set x 0
	    while {1} {
		if {[binary scan $block "@$x cu" len] < 1} break
		if {$len == 0} break
		incr x
		if {[binary scan $block "@$x a$len su Iu" name type value] < 3} {
		    break
		}
		incr x [expr {$len + 6}]
		switch $type {
		    2 {
			set type short
		    }
		    46 {
			set type address
		    }
		    default {
			set type constant
		    }
		}
		dict set rc $name [dict create type $type value $value]
	    }
	}
	return $rc
    }

    method files {} {
	my variable info
	set rc {}
	lassign [dict get $info namtab] start end
	set spec {
	    file1 T255
	    file2 T255
	}
	for {set blknum $start} {$blknum <= $end} {incr blknum} {
	    set dict [my DictScan [my ReadBlock $blknum] $spec]
	    dict for {key val} $dict {
		if {$val ne ""} {lappend rc $val}
	    }
	}
	return $rc
    }

    method list {} {
	my variable info
	lassign [dict get $info lsttab] start end
	set spec {
	    file cu
	    flags cu
	    linenum su
	    address su
	}
	for {set blknum $start} {$blknum <= $end} {incr blknum} {
	    set x 0
	    while {$x < 504} {
		set block [my ReadBlock $blknum]
		set dict [my DictScan $block $spec $x]
		if {[dict get $dict flags]} {
		    puts $dict
		}
		incr x 6
	    }
	}
    }
}
