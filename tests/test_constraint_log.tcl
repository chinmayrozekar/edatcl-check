package require tcltest
namespace import ::tcltest::*

# Fixture: simple design for constraint testing
proc setup_design {} {
    ::mock::create_hierarchy {
        cell top {
            cell core {
                pin clk
                pin data_in
                pin data_out
                pin rst
            }
            cell io {
                pin pad_in
                pin pad_out
            }
        }
        clock sys_clk 10.0
    }
}

# ---- set_false_path ----

test constraint-false-path-1 {
    set_false_path with matching pins logs correctly.
} -setup {
    setup_design
    ::mock::reset_constraint_log
} -body {
    set pins [::mock::get_pins {top/core/*}]
    ::mock::set_false_path -from $pins -to [::mock::get_pins {top/io/*}]
    set log [::mock::query_constraints type set_false_path]
    set entry [lindex $log 0]
    return [dict get $entry resolved]
} -match exact -result {-from 4 -to 2}

test constraint-false-path-2 {
    set_false_path with non-matching pattern logs zero resolution.
} -setup {
    setup_design
    ::mock::reset_constraint_log
} -body {
    ::mock::set_false_path -from "nonexistent/*" -to "also_bad/*"
    set log [::mock::query_constraints type set_false_path]
    set entry [lindex $log 0]
    return [dict get $entry resolved]
} -match exact -result {-from 0 -to 0}

test constraint-false-path-3 {
    set_false_path with -setup flag logs entry with setup in opts.
} -setup {
    setup_design
    ::mock::reset_constraint_log
} -body {
    ::mock::set_false_path -setup -from {top/core/clk} -to {top/core/data_out}
    set log [::mock::query_constraints type set_false_path]
    return [llength $log]
} -match exact -result 1

# ---- set_multicycle_path ----

test constraint-multicycle-path-1 {
    set_multicycle_path with path multiplier logs correctly.
} -setup {
    setup_design
    ::mock::reset_constraint_log
} -body {
    ::mock::set_multicycle_path 2 -from {top/core/clk} -to {top/core/data_out}
    set log [::mock::query_constraints type set_multicycle_path]
    set entry [lindex $log 0]
    return [dict get $entry path_mult]
} -match exact -result 2

test constraint-multicycle-path-2 {
    set_multicycle_path with -hold flag logs entry.
} -setup {
    setup_design
    ::mock::reset_constraint_log
} -body {
    ::mock::set_multicycle_path 2 -hold -from {top/core/clk} -to {top/core/data_out}
    set log [::mock::query_constraints type set_multicycle_path]
    return [llength $log]
} -match exact -result 1

# ---- set_clock_groups ----

test constraint-clock-groups-1 {
    set_clock_groups logs clock groups with match counts.
} -setup {
    setup_design
    ::mock::reset_constraint_log
} -body {
    ::mock::set_clock_groups -name my_group \
        -logically_exclusive \
        -group sys_clk \
        -group sys_clk
    set log [::mock::query_constraints type set_clock_groups]
    set entry [lindex $log 0]
    set groups [dict get $entry groups]
    return [llength [dict get $entry groups]]
} -match exact -result 2

test constraint-clock-groups-2 {
    set_clock_groups with non-matching clock logs zero match count.
} -setup {
    setup_design
    ::mock::reset_constraint_log
} -body {
    ::mock::set_clock_groups -name bad_group \
        -logically_exclusive \
        -group nonexistent_clk
    set log [::mock::query_constraints type set_clock_groups]
    set entry [lindex $log 0]
    set groups [dict get $entry groups]
    return [dict get [lindex $groups 0] match_count]
} -match exact -result 0

# ---- mock::reset_constraint_log ----

test constraint-reset-1 {
    reset_constraint_log clears all entries.
} -setup {
    setup_design
    ::mock::reset_constraint_log
} -body {
    ::mock::set_false_path -from {top/core/*} -to {top/io/*}
    ::mock::reset_constraint_log
    set log [::mock::query_constraints type set_false_path]
    return [llength $log]
} -match exact -result 0

# ---- query_constraints filtering ----

test constraint-query-filter-1 {
    query_constraints filters by type correctly.
} -setup {
    setup_design
    ::mock::reset_constraint_log
} -body {
    ::mock::set_false_path -from {top/core/*} -to {top/io/*}
    ::mock::set_multicycle_path 2 -from {top/core/clk} -to {top/core/data_out}
    set false_paths [::mock::query_constraints type set_false_path]
    set mcp_paths [::mock::query_constraints type set_multicycle_path]
    return [list [llength $false_paths] [llength $mcp_paths]]
} -match exact -result {1 1}

# ---- get_pins automatically logs ----

test constraint-get-pins-log-1 {
    get_pins calls are automatically logged.
} -setup {
    setup_design
    ::mock::reset_constraint_log
} -body {
    ::mock::get_pins {top/core/*}
    set log [::mock::query_constraints command get_pins]
    set entry [lindex $log 0]
    return [dict get $entry match_count]
} -match exact -result 4

test constraint-get-pins-log-2 {
    get_pins with zero match is logged as 0 count.
} -setup {
    setup_design
    ::mock::reset_constraint_log
} -body {
    ::mock::get_pins {nonexistent/*}
    set log [::mock::query_constraints command get_pins]
    set entry [lindex $log 0]
    return [dict get $entry match_count]
} -match exact -result 0

# ---- Demo from AGENTS.md: catching the zero-match bug ----

test constraint-demo-zero-match-1 {
    set_false_path with dead pin pattern logs zero resolution.
    This is EXACTLY the scenario from the Problem section of AGENTS.md.
} -setup {
    ::mock::create_hierarchy {
        cell u_core {
            pin gen_clk_reg_reg/Q
            pin sync_reg/D
        }
    }
    ::mock::reset_constraint_log
} -body {
    # This is the broken constraint from AGENTS.md
    ::mock::set_false_path \
        -from [::mock::get_pins {u_core/gen_clk_reg/Q}] \
        -to   [::mock::get_pins {u_core/sync_reg/D}]

    set log [::mock::query_constraints type set_false_path]
    set entry [lindex $log 0]
    set resolved [dict get $entry resolved]

    # -from matched 0 because the pin doesn't exist!
    set from_count [dict get $resolved -from]
    return $from_count
} -match exact -result 0
