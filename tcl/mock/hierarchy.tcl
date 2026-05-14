if {![package vsatisfies [info tclversion] 8.6-]} {
    error "edatcl-check requires Tcl 8.6 or later (have [info tclversion])"
}

namespace eval ::mock::_internal {
    variable next_id 0
    variable objects [dict create]
    variable name_index [dict create]

    proc init {} {
        variable next_id 0
        variable objects [dict create]
        variable name_index [dict create]
        variable ::mock::_internal::constraint_log [list]
    }

    proc _next_id {} {
        variable next_id
        return [expr {[incr next_id] - 1}]
    }

    proc _index_name {name id} {
        variable name_index
        dict set name_index $name $id
    }

    proc _name_to_id {name} {
        variable name_index
        if {[dict exists $name_index $name]} {
            return [dict get $name_index $name]
        }
        return ""
    }

    proc add_object {name type attr_dict} {
        variable objects
        set id [_next_id]
        dict set objects $id [dict create \
            id $id \
            name $name \
            type $type \
            {*}$attr_dict \
        ]
        _index_name $name $id
        return $id
    }

    proc get_object {id} {
        variable objects
        if {[dict exists $objects $id]} {
            return [dict get $objects $id]
        }
        return {}
    }

    proc get_object_by_name {name} {
        set id [_name_to_id $name]
        if {$id ne ""} {
            return [get_object $id]
        }
        return {}
    }

proc _sort_by_name {a b} {
    return [string compare [dict get $a name] [dict get $b name]]
}

proc get_objects_by_type {type} {
    variable objects
    set result [list]
    dict for {id obj} $objects {
        if {[dict get $obj type] eq $type} {
            lappend result $obj
        }
    }
    return [lsort -command _sort_by_name $result]
}

    proc add_cell {name} {
        return [add_object $name cell {}]
    }

    proc add_pin {name} {
        return [add_object $name pin {}]
    }

    proc add_net {name} {
        return [add_object $name net {}]
    }

    proc add_clock {name {period ""}} {
        set attrs [dict create]
        if {$period ne ""} {
            dict set attrs period $period
        }
        return [add_object $name clock $attrs]
    }

    # ---- Pattern matching ----

    proc segment_to_regex {segment} {
        set result ""
        set i 0
        set len [string length $segment]
        while {$i < $len} {
            set c [string index $segment $i]
            switch -exact -- $c {
                * {
                    append result {[^/]*}
                }
                ? {
                    append result {[^/]}
                }
                [ {
                    append_result_char_class result segment i len
                }
                default {
                    if {[string match {[.^$|+(){}]} $c]} {
                        append result \\
                    }
                    append result $c
                }
            }
            incr i
        }
        return $result
    }

    proc append_result_char_class {resultVar segmentVar iVar len} {
        upvar 1 $resultVar result $segmentVar segment $iVar i
        append result {[}
        incr i
        while {$i < $len} {
            set c [string index $segment $i]
            if {$c eq {]}} {
                append result ]
                return
            }
            if {$c eq "\\"} {
                append result $c
                incr i
                if {$i < $len} {
                    append result [string index $segment $i]
                }
            } else {
                append result $c
            }
            incr i
        }
        append result {]}
    }

    # Build regex from a glob pattern, handling hierarchical scope
    proc glob_to_regex {pattern {hierarchical 0}} {
        set segments [split $pattern /]
        set regex_segments [list]
        foreach seg $segments {
            lappend regex_segments [segment_to_regex $seg]
        }

        if {$hierarchical} {
            set first [lindex $segments 0]
            if {$first eq "*" && [llength $segments] == 1} {
                return {^.*$}
            }
            set joined [join $regex_segments /]
            return "^(.*/)?${joined}$"
        } else {
            set joined [join $regex_segments /]
            return "^${joined}$"
        }
    }

    proc match_objects {type pattern args} {
        variable objects
        set opts [dict merge {-hierarchical 0 -regexp 0} $args]
        set hierarchical [dict get $opts -hierarchical]
        set is_regexp [dict get $opts -regexp]

        if {$is_regexp} {
            set regex_str "^${pattern}$"
        } else {
            set regex_str [glob_to_regex $pattern $hierarchical]
        }

        set matched [list]
        dict for {id obj} $objects {
            if {[dict get $obj type] ne $type} { continue }
            set name [dict get $obj name]
            if {[regexp -- $regex_str $name]} {
                lappend matched $obj
            }
        }

        return [lsort -command _sort_by_name $matched]
    }

    proc match_objects_count {type pattern args} {
        set matched [match_objects $type $pattern {*}$args]
        return [llength $matched]
    }

    # ---- Constraint log ----

    proc log_constraint {type entry_dict} {
        variable ::mock::_internal::constraint_log
        set entry [dict merge [list \
            type $type \
            timestamp [clock milliseconds] \
        ] $entry_dict]
        lappend ::mock::_internal::constraint_log $entry
        return [llength $::mock::_internal::constraint_log]
    }

    proc query_constraints {args} {
        variable ::mock::_internal::constraint_log
        set results $::mock::_internal::constraint_log
        foreach {key val} $args {
            set filtered [list]
            foreach entry $results {
                if {[dict exists $entry $key] && [dict get $entry $key] eq $val} {
                    lappend filtered $entry
                }
            }
            set results $filtered
        }
        return $results
    }

    proc reset_constraint_log {} {
        variable ::mock::_internal::constraint_log
        set ::mock::_internal::constraint_log [list]
    }
}
