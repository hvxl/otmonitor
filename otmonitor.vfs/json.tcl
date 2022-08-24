namespace eval json {
    package require tdom 0.9.3-

    namespace ensemble create -subcommands {attribute build layout object}

    namespace eval layout {
	namespace path [list [namespace parent]]
    }

    namespace eval cmds {
	namespace unknown [namespace parent]::unknown
	# namespace path [list [namespace parent]]
	dom createNodeCmd -jsonType OBJECT elementNode object
	dom createNodeCmd -jsonType ARRAY elementNode array
	dom createNodeCmd -jsonType NUMBER textNode number
	dom createNodeCmd -jsonType STRING textNode string
	dom createNodeCmd -jsonType TRUE textNode true
	dom createNodeCmd -jsonType FALSE textNode false
	dom createNodeCmd -jsonType NULL textNode null

	dom createNodeCmd -jsonType NUMBER textNode byte
	dom createNodeCmd -jsonType NUMBER textNode integer
	dom createNodeCmd -jsonType NUMBER textNode unsigned

	proc float {arg} {
	    tailcall number [format %0.2f $arg]
	}

	proc boolean {arg} {
	    if {$arg} {
		tailcall true true
	    } else {
		tailcall false false
	    }
	}

	proc milliseconds {} {
	    tailcall number [clock milliseconds]
	}
    }

    proc unknown {cmd args} {
	if {[regexp {^([a-z]+)::(.*)} $cmd -> type name]} {
	    if {$type in {object array}} {
		# Generate an appropriate elementNode
		namespace eval cmds [list tdom::fsnewNode \
		  -jsonType [string toupper $type] $name {*}$args]
	    } else {
		# Generate an appropriate elementNode
		namespace eval cmds [list tdom::fsnewNode \
		  -jsonType NONE $name [linsert $args 0 $type]]
	    }
	}
    }
}

proc json::script {dict} {
    set rc {}
    dict for {cmd args} $dict {
	lappend rc [list $cmd $args]
    }
    return [join $rc {;}]
}

proc json::layout {name args body} {
    namespace eval layout [list proc $name $args $body]
}

proc json::build {type layout args} {
    set script [script [namespace eval layout [list $layout {*}$args]]]
    dom createDocumentNode doc
    # Should be either "OBJECT" or "ARRAY"
    $doc jsonType [string toupper $type]
    # set cmds::data $data
    namespace eval cmds [list $doc appendFromScript $script]
    return [$doc asJSON]
}

proc json::object {name {tag ""}} {
    if {$tag eq ""} {set tag $name}
    namespace eval cmds \
      [list dom createNodeCmd -jsonType OBJECT -tagName $tag elementNode $name]
}

proc json::attribute {name {tag ""}} {
    if {$tag eq ""} {set tag $name}
    namespace eval cmds \
      [list dom createNodeCmd -jsonType NONE -tagName $tag elementNode $name]
}

json layout test {} {
    return {
	attribute {value float 1.2}
    }
}
