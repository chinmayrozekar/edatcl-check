if {![package vsatisfies [info tclversion] 8.6-]} {
    error "edatcl-check requires Tcl 8.6 or later (have [info tclversion])"
}

# Helper: given a value that may be a glob pattern string or a
# pre-resolved collection (list of object dicts), return the list
# of matching object names.
proc ::mock::_internal::resolve_to_names {type value} {
    if {[llength $value] > 0} {
        set first [lindex $value 0]
        if {[catch {dict get $first name}] == 0} {
            return [lmap obj $value { dict get $obj name }]
        }
    }
    set matched [::mock::_internal::match_objects $type $value]
    return [lmap obj $matched { dict get $obj name }]
}

proc ::mock::_internal::resolve_to_count {type value} {
    return [llength [::mock::_internal::resolve_to_names $type $value]]
}

# ---- set_false_path ----
# Usage: set_false_path ?-setup|-hold? ?-from pins? ?-to pins? ?-through pins?

proc ::mock::set_false_path {args} {
    set opts [dict create]
    set i 0
    set n [llength $args]

    while {$i < $n} {
        set flag [lindex $args $i]
        switch -exact -- $flag {
            -from - -to - -through - -rise_from - -rise_to - -fall_from - -fall_to {
                incr i
                if {$i >= $n} { error "set_false_path: missing value after $flag" }
                dict set opts $flag [lindex $args $i]
                incr i
            }
            -setup - -hold {
                dict set opts $flag true
                incr i
            }
            default {
                error "set_false_path: unknown option $flag"
            }
        }
    }

    # Resolve to counts (for logging / assertion)
    set resolved [dict create]
    dict for {key val} $opts {
        switch -exact -- $key {
            -from - -to - -through - -rise_from - -rise_to - -fall_from - -fall_to {
                dict set resolved $key [::mock::_internal::resolve_to_count pin $val]
            }
        }
    }

    ::mock::_internal::log_constraint set_false_path [dict create \
        opts $opts \
        resolved $resolved \
    ]
}

# ---- set_multicycle_path ----
# Usage: set_multicycle_path path_mult ?-setup|-hold? ?-from pins? ?-to pins?

proc ::mock::set_multicycle_path {args} {
    set opts [dict create]
    set path_mult 1
    set i 0
    set n [llength $args]

    while {$i < $n} {
        set token [lindex $args $i]
        switch -exact -- $token {
            -setup - -hold {
                dict set opts $token true
                incr i
            }
            -from - -to - -through - -rise_from - -rise_to - -fall_from - -fall_to {
                incr i
                if {$i >= $n} { error "set_multicycle_path: missing value after $token" }
                dict set opts $token [lindex $args $i]
                incr i
            }
            default {
                if {[string is entier -strict $token]} {
                    set path_mult $token
                    incr i
                } else {
                    error "set_multicycle_path: unknown option or non-integer: $token"
                }
            }
        }
    }

    set resolved [dict create]
    dict for {key val} $opts {
        switch -exact -- $key {
            -from - -to - -through - -rise_from - -rise_to - -fall_from - -fall_to {
                dict set resolved $key [::mock::_internal::resolve_to_count pin $val]
            }
        }
    }

    ::mock::_internal::log_constraint set_multicycle_path [dict create \
        path_mult $path_mult \
        opts $opts \
        resolved $resolved \
    ]
}

# ---- set_clock_groups ----
# Usage: set_clock_groups -name name ?-logically_exclusive|-physically_exclusive
#                               |-asynchronous? -group clks -group clks ...

proc ::mock::set_clock_groups {args} {
    set opts [dict create]
    set groups [list]
    set i 0
    set n [llength $args]

    while {$i < $n} {
        set token [lindex $args $i]
        switch -exact -- $token {
            -name {
                incr i
                if {$i >= $n} { error "set_clock_groups: missing value after -name" }
                dict set opts -name [lindex $args $i]
                incr i
            }
            -group {
                incr i
                if {$i >= $n} { error "set_clock_groups: missing value after -group" }
                set clk_pattern [lindex $args $i]
                incr i
                set matched [::mock::_internal::resolve_to_names clock $clk_pattern]
                lappend groups [dict create \
                    pattern $clk_pattern \
                    match_count [llength $matched] \
                    match_names $matched \
                ]
            }
            -logically_exclusive - -physically_exclusive - -asynchronous {
                dict set opts $token true
                incr i
            }
            default {
                error "set_clock_groups: unknown option $token"
            }
        }
    }

    ::mock::_internal::log_constraint set_clock_groups [dict create \
        opts $opts \
        groups $groups \
    ]
}
