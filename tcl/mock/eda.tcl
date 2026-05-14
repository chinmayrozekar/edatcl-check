if {![package vsatisfies [info tclversion] 8.6-]} {
    error "edatcl-check requires Tcl 8.6 or later (have [info tclversion])"
}

namespace eval ::mock {
    namespace export create_hierarchy install_eda_shims get_pins get_cells \
        get_nets get_clocks get_collection_size query_constraints \
        reset_constraint_log set_false_path set_multicycle_path \
        set_clock_groups
}

# ---- DSL: create_hierarchy ----

proc ::mock::create_hierarchy {body} {
    ::mock::_internal::init
    set tokens [::mock::_internal::tokenize $body]
    ::mock::_internal::parse_hierarchy_block $tokens ""
}

# ---- EDA command shims (installed into global namespace) ----

proc ::mock::get_pins {pattern args} {
    set opts [parse_get_args $args]
    set result [::mock::_internal::match_objects pin $pattern {*}$opts]
    ::mock::_internal::log_constraint get_pins [dict create \
        command get_pins \
        pattern $pattern \
        match_count [llength $result] \
        match_names [lmap obj $result { dict get $obj name }] \
    ]
    return $result
}

proc ::mock::get_cells {pattern args} {
    set opts [parse_get_args $args]
    set result [::mock::_internal::match_objects cell $pattern {*}$opts]
    ::mock::_internal::log_constraint get_cells [dict create \
        command get_cells \
        pattern $pattern \
        match_count [llength $result] \
        match_names [lmap obj $result { dict get $obj name }] \
    ]
    return $result
}

proc ::mock::get_nets {pattern args} {
    set opts [parse_get_args $args]
    set result [::mock::_internal::match_objects net $pattern {*}$opts]
    ::mock::_internal::log_constraint get_nets [dict create \
        command get_nets \
        pattern $pattern \
        match_count [llength $result] \
        match_names [lmap obj $result { dict get $obj name }] \
    ]
    return $result
}

proc ::mock::get_clocks {pattern args} {
    set opts [parse_get_args $args]
    set result [::mock::_internal::match_objects clock $pattern {*}$opts]
    ::mock::_internal::log_constraint get_clocks [dict create \
        command get_clocks \
        pattern $pattern \
        match_count [llength $result] \
        match_names [lmap obj $result { dict get $obj name }] \
    ]
    return $result
}

# ---- Helper for get_* argument parsing ----

proc ::mock::parse_get_args {arglist} {
    set opts [list]
    foreach arg $arglist {
        switch -exact -- $arg {
            -hierarchical { lappend opts -hierarchical 1 }
            -regexp       { lappend opts -regexp 1 }
            default {
                lappend opts -$arg 1
            }
        }
    }
    return $opts
}

# ---- Collection utilities ----

proc ::mock::get_collection_size {collection} {
    return [llength $collection]
}

# ---- Constraint log queries ----

proc ::mock::query_constraints {args} {
    return [::mock::_internal::query_constraints {*}$args]
}

proc ::mock::reset_constraint_log {} {
    ::mock::_internal::reset_constraint_log
}

# ---- Install shims into global namespace ----

proc ::mock::install_eda_shims {} {
    namespace eval :: {
        namespace import -force ::mock::get_pins
        namespace import -force ::mock::get_cells
        namespace import -force ::mock::get_nets
        namespace import -force ::mock::get_clocks
        namespace import -force ::mock::get_collection_size
        namespace import -force ::mock::set_false_path
        namespace import -force ::mock::set_multicycle_path
        namespace import -force ::mock::set_clock_groups
    }
}

# ---- Tokenizer and parser for the create_hierarchy DSL ----

namespace eval ::mock::_internal {

    proc tokenize {text} {
        set tokens [list]
        set len [string length $text]
        set i 0
        set current ""

        while {$i < $len} {
            set c [string index $text $i]

            if {[string is space $c]} {
                if {$current ne ""} {
                    lappend tokens $current
                    set current ""
                }
                incr i
                continue
            }

            if {$c eq "\{"} {
                if {$current ne ""} {
                    lappend tokens $current
                    set current ""
                }
                set depth 1
                set j [expr {$i + 1}]
                while {$j < $len && $depth > 0} {
                    set c2 [string index $text $j]
                    if {$c2 eq "\{"} { incr depth }
                    if {$c2 eq "\}"} { incr depth -1 }
                    incr j
                }
                set block [string range $text [expr {$i + 1}] [expr {$j - 2}]]
                lappend tokens [list BLOCK $block]
                set i $j
                continue
            }

            if {$c eq "\\"} {
                append current $c
                incr i
                if {$i < $len} {
                    append current [string index $text $i]
                    incr i
                }
                continue
            }

            append current $c
            incr i
        }

        if {$current ne ""} {
            lappend tokens $current
        }

        return $tokens
    }

    proc parse_hierarchy_block {tokens {parent_cell ""}} {
        set i 0
        set n [llength $tokens]

        while {$i < $n} {
            set token [lindex $tokens $i]
            set keyword [string tolower $token]

            if {$keyword eq "cell"} {
                incr i
                if {$i >= $n} {
                    error "create_hierarchy: expected cell name after 'cell'"
                }
                set cell_name [lindex $tokens $i]
                incr i

                set qualified [qualify_name $cell_name $parent_cell]
                add_cell $qualified

                if {$i < $n} {
                    set next [lindex $tokens $i]
                    if {[llength $next] == 2 && [lindex $next 0] eq "BLOCK"} {
                        set block_tokens [tokenize [lindex $next 1]]
                        parse_hierarchy_block $block_tokens $qualified
                        incr i
                    }
                }
                continue
            }

            if {$keyword eq "pin"} {
                incr i
                if {$i >= $n} {
                    error "create_hierarchy: expected pin name after 'pin'"
                }
                set pin_name [lindex $tokens $i]
                incr i
                set qualified [qualify_name $pin_name $parent_cell]
                add_pin $qualified
                continue
            }

            if {$keyword eq "net"} {
                incr i
                if {$i >= $n} {
                    error "create_hierarchy: expected net name after 'net'"
                }
                set net_name [lindex $tokens $i]
                incr i
                set qualified [qualify_name $net_name $parent_cell]
                add_net $qualified
                continue
            }

            if {$keyword eq "clock"} {
                incr i
                if {$i >= $n} {
                    error "create_hierarchy: expected clock name after 'clock'"
                }
                set clock_name [lindex $tokens $i]
                incr i
                set period ""
                if {$i < $n} {
                    set next [lindex $tokens $i]
                    if {[llength $next] != 2} {
                        set period $next
                        incr i
                    }
                }
                add_clock $clock_name $period
                continue
            }

            incr i
        }
    }

    proc qualify_name {name parent} {
        if {$parent eq ""} {
            return $name
        }
        return "${parent}/${name}"
    }
}
