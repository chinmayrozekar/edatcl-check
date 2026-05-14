#!/usr/bin/env tclsh

# edatcl-check v0.1 — Simple Flow Demo
#
# Demonstrates the core mock framework workflow:
#   1. Declare a design hierarchy
#   2. Write constraint procedures
#   3. Unit-test them with tcltest
#   4. Catch the zero-match bug from AGENTS.md

if {![package vsatisfies [info tclversion] 8.6-]} {
    puts stderr "edatcl-check requires Tcl 8.6 or later (have [info tclversion])"
    exit 1
}

set mock_dir [file join [file dirname [info script]] ../.. tcl mock]
source [file join $mock_dir hierarchy.tcl]
source [file join $mock_dir sdc.tcl]
source [file join $mock_dir eda.tcl]

# ============================================================
# Step 1: Declare a design hierarchy
# ============================================================

mock::create_hierarchy {
    cell top {
        cell u_core {
            pin gen_clk_reg_reg/Q
            pin sync_reg/D
            pin alu_out_ff/Q
            pin alu_out_ff/D
            pin ctrl_ff/Q
            pin ctrl_ff/D
        }
        cell u_mem {
            pin addr
            pin data_in
            pin data_out
            pin clk
        }
    }
    clock sys_clk 10.0
    clock mem_clk  5.0
}

puts "=== Design Hierarchy ==="
puts "Cells:  [llength [::mock::_internal::get_objects_by_type cell]]"
puts "Pins:   [llength [::mock::_internal::get_objects_by_type pin]]"
puts "Clocks: [llength [::mock::_internal::get_objects_by_type clock]]"

# ============================================================
# Step 2: Write constraint procedures (like a real flow)
# ============================================================

proc apply_false_path {from_pin to_pin} {
    set from_collection [get_pins $from_pin]
    set to_collection   [get_pins $to_pin]

    if {[get_collection_size $from_collection] == 0} {
        error "No pins matched for -from: $from_pin"
    }
    if {[get_collection_size $to_collection] == 0} {
        error "No pins matched for -to: $to_pin"
    }

    set_false_path -from $from_collection -to $to_collection
}

proc apply_all_constraints {} {
    # Known good constraints
    apply_false_path "top/u_core/ctrl_ff/Q" "top/u_core/ctrl_ff/D"

    # THE BUG: get_pins uses the wrong name!
    # In RTL this was gen_clk_reg, but synthesis renamed it gen_clk_reg_reg
    # Without the mock framework, this silently does nothing:
    apply_false_path "top/u_core/gen_clk_reg/Q" "top/u_core/sync_reg/D"
}

puts "\n=== Running Constraints ==="

# Install mock shims so our procs work without a real EDA tool
mock::install_eda_shims

# Apply constraints (this will fail on the bad pin because our proc checks!)
if {[catch { apply_all_constraints } err]} {
    puts "ERROR: $err"
    puts "\n--> The mock framework caught the bug!"
    puts "    The pin 'top/u_core/gen_clk_reg/Q' does not exist."
    puts "    (It was renamed to 'gen_clk_reg_reg/Q' by synthesis.)"
}

# ============================================================
# Step 3: Inspect the constraint log
# ============================================================

puts "\n=== Constraint Log ==="
set all_constraints [mock::query_constraints]
puts "Total constraint entries: [llength $all_constraints]"

puts "\n=== False Paths Applied ==="
set fps [mock::query_constraints type set_false_path]
foreach fp $fps {
    puts "  type=[dict get $fp type]  resolved=[dict get $fp resolved]"
}

puts "\n=== get_pins Calls with Zero Matches ==="
set all_gets [mock::query_constraints command get_pins]
foreach g $all_gets {
    set count [dict get $g match_count]
    if {$count == 0} {
        puts "  WARNING: [dict get $g command] [dict get $g pattern] matched 0 objects!"
    }
}

puts "\n=== Demo Complete ==="
