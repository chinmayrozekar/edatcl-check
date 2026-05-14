# edatcl-check

A TCL verification toolkit for EDA flows — mock testing, runtime observability, and static analysis. Catches silently broken constraints that today escape to STA and beyond.

## Problem

Every EDA engineer has lived this:

```tcl
set_false_path -from [get_pins u_core/gen_clk_reg/Q] -to [get_pins u_core/sync_reg/D]
```

The pin was renamed by synthesis to `gen_clk_reg_reg/Q`. `get_pins` matches zero objects, returns an empty collection, and `set_false_path` with an empty collection is a silent no-op. The run completes. Timing looks clean. You tape out. Silicon comes back broken.

## Components

### v0.1 — Mock EDA Framework (current)

Unit-test flow procs without a $200k license.

```tcl
package require mock::eda

mock::create_hierarchy {
    cell u_core {
        pin gen_clk_reg_reg/Q
        pin sync_reg/D
    }
}

# Test that a bad pin name is caught
set result [get_pins u_core/gen_clk_reg/Q]  ;# returns 0 matches
if {[get_collection_size $result] == 0} {
    error "No pins matched!"
}
```

### v0.2 — Runtime Tracer (planned)

Observability for real EDA runs. Captures constraint coverage into JSONL for post-hoc query.

### v0.3 — Static Linter (planned)

Parses TCL/SDC without execution, flags guaranteed-noop patterns before you run.

## Quick Start

```bash
tclsh tests/run_all.tcl
```

```bash
tclsh examples/simple_flow/run_demo.tcl
```

## Design

See [AGENTS.md](AGENTS.md) for the full design spec and rationale. Architecture decisions are documented in [docs/decisions/](docs/decisions/).

## License

MIT
