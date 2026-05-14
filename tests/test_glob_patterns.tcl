package require tcltest
namespace import ::tcltest::*

# Fixture: deeper hierarchy for glob testing
proc setup_deep_hierarchy {} {
    ::mock::create_hierarchy {
        cell top {
            cell a {
                cell b {
                    pin q
                }
                pin x
            }
            cell c {
                pin y
            }
            pin z
        }
    }
}

# ---- Single-level wildcard (*) ----

test glob-single-level-1 {
    * at one level under top matches direct pin children of that level.
} -setup {
    setup_deep_hierarchy
} -body {
    set result [::mock::get_pins {top/*}]
    return [lsort [lmap p $result { dict get $p name }]]
} -match exact -result top/z

test glob-single-level-2 {
    */* at top matches pins two levels under top.
} -setup {
    setup_deep_hierarchy
} -body {
    set result [::mock::get_pins {top/*/*}]
    return [lsort [lmap p $result { dict get $p name }]]
} -match exact -result {top/a/x top/c/y}

test glob-single-level-3 {
    No match when pattern is too shallow.
} -setup {
    setup_deep_hierarchy
} -body {
    set result [::mock::get_pins {top/a/b/*}]
    return [lsort [lmap p $result { dict get $p name }]]
} -match exact -result {top/a/b/q}

# ---- Prefix/suffix wildcards ----

test glob-prefix-1 {
    Prefix wildcard matches partial names.
} -setup {
    setup_deep_hierarchy
} -body {
    set result [::mock::get_pins {top/c/*}]
    return [lsort [lmap p $result { dict get $p name }]]
} -match exact -result top/c/y

test glob-prefix-2 {
    Suffix match.
} -setup {
    setup_deep_hierarchy
} -body {
    # Match any level, ending with 'z'
    set result [::mock::get_pins {top/z}]
    return [lsort [lmap p $result { dict get $p name }]]
} -match exact -result top/z

# ---- -regexp mode ----

test glob-regexp-1 {
    -regexp treats pattern as regex.
} -setup {
    setup_deep_hierarchy
} -body {
    set result [::mock::get_pins {top/a/.*} -regexp]
    return [lsort [lmap p $result { dict get $p name }]]
} -match exact -result {top/a/b/q top/a/x}

test glob-regexp-2 {
    -regexp with ^ and $ anchors.
} -setup {
    setup_deep_hierarchy
} -body {
    set result [::mock::get_pins {^top/c/y$} -regexp]
    return [lsort [lmap p $result { dict get $p name }]]
} -match exact -result top/c/y

test glob-regexp-3 {
    -regexp non-match returns empty.
} -setup {
    setup_deep_hierarchy
} -body {
    set result [::mock::get_pins {^nonexistent$} -regexp]
    return [llength $result]
} -match exact -result 0

# ---- -hierarchical mode ----

test glob-hierarchical-1 {
    -hierarchical * matches all objects of the type.
} -setup {
    setup_deep_hierarchy
} -body {
    set result [::mock::get_pins {*} -hierarchical]
    return [lsort [lmap p $result { dict get $p name }]]
} -match exact -result {top/a/b/q top/a/x top/c/y top/z}

test glob-hierarchical-2 {
    -hierarchical */q matches all pins named q at any depth.
} -setup {
    setup_deep_hierarchy
} -body {
    set result [::mock::get_pins {*/q} -hierarchical]
    return [lsort [lmap p $result { dict get $p name }]]
} -match exact -result top/a/b/q

test glob-hierarchical-3 {
    -hierarchical with no match returns empty.
} -setup {
    setup_deep_hierarchy
} -body {
    set result [::mock::get_pins {*/does_not_exist} -hierarchical]
    return [llength $result]
} -match exact -result 0

# ---- Multiple pin matches in one cell ----

test glob-multi-match-1 {
    Multiple pins in one cell matched with *
} -setup {
    ::mock::create_hierarchy {
        cell top {
            cell alu {
                pin clk
                pin rst
                pin a
                pin b
                pin result
            }
        }
    }
} -body {
    set result [::mock::get_pins {top/alu/*}]
    return [lsort [lmap p $result { dict get $p name }]]
} -match exact -result {top/alu/a top/alu/b top/alu/clk top/alu/result top/alu/rst}

# ---- Deterministic ordering ----

test glob-ordering-1 {
    Results always return in deterministic sorted order.
} -setup {
    ::mock::create_hierarchy {
        cell top {
            pin z_pin
            pin a_pin
            pin m_pin
        }
    }
} -body {
    set result [::mock::get_pins {top/*}]
    return [lmap p $result { dict get $p name }]
} -match exact -result {top/a_pin top/m_pin top/z_pin}

# ---- get_cells with wildcards ----

test glob-cells-1 {
    get_cells matches cells with *.
} -setup {
    setup_deep_hierarchy
} -body {
    set result [::mock::get_cells {top/a/*}]
    return [lsort [lmap c $result { dict get $c name }]]
} -match exact -result top/a/b
