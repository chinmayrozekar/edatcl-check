package require tcltest
namespace import ::tcltest::*

# ---- Fixture: simple hierarchy ----

proc setup_simple_hierarchy {} {
    ::mock::create_hierarchy {
        cell top {
            cell u_core {
                pin clk
                pin d
                pin q
            }
            cell u_io {
                pin pad_in
                pin pad_out
            }
        }
        clock clk 10.0
    }
}

# ---- test: create_hierarchy populates cells ----

test create_hierarchy-cells-1 {
    Verify that cells are created with correct names.
} -setup {
    setup_simple_hierarchy
} -body {
    set cells [::mock::_internal::get_objects_by_type cell]
    return [lmap c $cells { dict get $c name }]
} -match exact -result {top top/u_core top/u_io}

test create_hierarchy-pins-1 {
    Verify pins are created with correct hierarchical names.
} -setup {
    setup_simple_hierarchy
} -body {
    set pins [::mock::_internal::get_objects_by_type pin]
    return [lsort [lmap p $pins { dict get $p name }]]
} -match exact -result {top/u_core/clk top/u_core/d top/u_core/q top/u_io/pad_in top/u_io/pad_out}

test create_hierarchy-clocks-1 {
    Verify clocks are created.
} -setup {
    setup_simple_hierarchy
} -body {
    set clocks [::mock::_internal::get_objects_by_type clock]
    set c [lindex $clocks 0]
    return [list [dict get $c name] [format %.1f [dict get $c period]]]
} -match exact -result {clk 10.0}

# ---- test: get_pins ----

test get_pins-basic-1 {
    get_pins top-level pins matches nothing at wrong scope.
} -setup {
    setup_simple_hierarchy
} -body {
    set result [::mock::get_pins clk]
    return [llength $result]
} -match exact -result 0

test get_pins-basic-2 {
    get_pins with wildcard matches flat pins.
} -setup {
    setup_simple_hierarchy
} -body {
    # top has no direct pins, only cells
    set result [::mock::get_pins {*}]
    return [llength $result]
} -match exact -result 0

test get_pins-basic-3 {
    get_pins one-level-down matches correctly.
} -setup {
    setup_simple_hierarchy
} -body {
    set result [::mock::get_pins {top/u_core/*}]
    return [lsort [lmap p $result { dict get $p name }]]
} -match exact -result {top/u_core/clk top/u_core/d top/u_core/q}

test get_pins-basic-4 {
    get_pins with non-matching pattern returns empty.
} -setup {
    setup_simple_hierarchy
} -body {
    set result [::mock::get_pins {nonexistent/*}]
    return [llength $result]
} -match exact -result 0

# ---- test: get_cells ----

test get_cells-basic-1 {
    get_cells matches by wildcard.
} -setup {
    setup_simple_hierarchy
} -body {
    set result [::mock::get_cells {top/*}]
    return [lsort [lmap c $result { dict get $c name }]]
} -match exact -result {top/u_core top/u_io}

test get_cells-basic-2 {
    get_cells with no match returns empty.
} -setup {
    setup_simple_hierarchy
} -body {
    set result [::mock::get_cells {nonexistent}]
    return [llength $result]
} -match exact -result 0

# ---- test: get_clocks ----

test get_clocks-basic-1 {
    get_clocks matches by name.
} -setup {
    setup_simple_hierarchy
} -body {
    set result [::mock::get_clocks {clk}]
    return [llength $result]
} -match exact -result 1

test get_clocks-basic-2 {
    get_clocks with no match returns empty.
} -setup {
    setup_simple_hierarchy
} -body {
    set result [::mock::get_clocks {nonexistent}]
    return [llength $result]
} -match exact -result 0

# ---- test: get_collection_size ----

test collection_size-1 {
    get_collection_size returns correct count.
} -setup {
    setup_simple_hierarchy
} -body {
    set pins [::mock::get_pins {top/u_core/*}]
    return [::mock::get_collection_size $pins]
} -match exact -result 3

test collection_size-2 {
    get_collection_size returns 0 for empty collection.
} -setup {
    setup_simple_hierarchy
} -body {
    set pins [::mock::get_pins {nonexistent/*}]
    return [::mock::get_collection_size $pins]
} -match exact -result 0

# ---- test: object structure ----

test object-structure-1 {
    Returned objects have correct keys (id, name, type).
} -setup {
    setup_simple_hierarchy
} -body {
    set result [::mock::get_pins {top/u_core/clk}]
    set obj [lindex $result 0]
    return [dict exists $obj id]
} -match exact -result 1

test object-structure-2 {
    Object contains name field.
} -setup {
    setup_simple_hierarchy
} -body {
    set result [::mock::get_pins {top/u_core/clk}]
    set obj [lindex $result 0]
    return [dict get $obj name]
} -match exact -result top/u_core/clk
