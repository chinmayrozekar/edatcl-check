#!/usr/bin/env tclsh

if {![package vsatisfies [info tclversion] 8.6-]} {
    puts stderr "edatcl-check requires Tcl 8.6 or later (have [info tclversion])"
    exit 1
}
package require tcltest

namespace import ::tcltest::*

# Source the mock framework
set mock_dir [file join [file dirname [info script]] .. tcl mock]
source [file join $mock_dir hierarchy.tcl]
source [file join $mock_dir sdc.tcl]
source [file join $mock_dir eda.tcl]

# Configure tcltest
tcltest::configure -testdir [file dirname [info script]] -verbose {body error}

# Run all test files
source [file join [file dirname [info script]] test_mock_basic.tcl]
source [file join [file dirname [info script]] test_glob_patterns.tcl]
source [file join [file dirname [info script]] test_constraint_log.tcl]

# Cleanup and exit with proper code
::tcltest::cleanupTests
return
