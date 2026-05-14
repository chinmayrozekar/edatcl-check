# edatcl-check

## Elevator Pitch
Unit-test your EDA flow procs in 2 seconds on a laptop — no $200k license, no 6-hour elaboration. Catch silently broken constraints in CI before they hit STA.

## The Problem

Every EDA engineer has lived one of these:

**Zero match.** The pin was renamed by synthesis. `get_pins` returns an empty collection. `set_false_path` applies to nothing. No error, no warning.

```tcl
set_false_path -from [get_pins u_core/gen_clk_reg/Q] -to [get_pins u_core/sync_reg/D]
# gen_clk_reg was renamed to gen_clk_reg_reg — this does nothing, silently
```

**Partial match.** A netlist change drops one of ten wildcard matches. The constraint still applies — just incompletely. `check_timing` won't flag it.

```tcl
set_false_path -from [get_pins *clk*]  ;# matched 11 pins yesterday, 10 today
```

Both bugs currently require a licensed tool and hours of elaboration to detect. Most aren't caught until STA, and some escape to silicon.

EDA vendors' safety nets (`check_timing`, `check_design`, warning messages) are better than nothing, but:
- They require a $200k license and hours of netlist elaboration — impossible in CI
- Warnings in 100k-line logs are routinely suppressed or buried
- Partial matches are structurally invisible to them

## What the Industry Currently Has

| Pain Point | Current Mitigation | Why It's Insufficient |
|---|---|---|
| `get_pins` matches zero objects | Manual `sizeof_collection` checks | Nobody does this consistently; no linter enforces it |
| Uninitialized variable becomes literal string | TCL discipline | Easy to miss; no static analysis |
| Undefined proc called at runtime | Only caught when that code path executes | Can slip through for hours |
| SDC constraint applies to nothing | No tool warns you | Zero objects is a valid collection in TCL |
| Flow procs untestable offline | Need $200k license + 6hr elaboration | Nobody tests; bugs found at tape-out |

## The Solution (3 Components)

### Component 1 — Mock EDA Framework (`package require mock::eda`) [v0.1]

Enables unit-testing flow procs **without licensing any EDA tool**.

```tcl
package require mock::eda
package require tcltest

mock::create_hierarchy {
    cell u_core {
        pin gen_clk_reg_reg/Q
        pin sync_reg/D
    }
}

proc apply_my_false_path {from to} {
    set from_pins [get_pins $from]
    if {[get_collection_size $from_pins] == 0} {
        error "No pins matched: $from"
    }
    set_false_path -from $from_pins -to [get_pins $to]
}

tcltest::test apply_my_false_path-nonexistent {
    -body { apply_my_false_path "bad_pin" "u_core/sync_reg/D" }
    -returnCodes error
    -match glob
    -result "*No pins matched*"
}
```

**Mock commands record all invocations for assertion:**

```tcl
tcltest::test apply_constraints-applies-false-paths {
    -setup { mock::reset_constraint_log }
    -body {
        apply_constraints
        mock::query_constraints type=set_false_path
    }
    -result {2 false paths applied}
}
```

**EDA Pattern Matching Semantics.** Glob→regex is less trivial than it sounds. EDA tools have vendor-specific behaviors:

- Synopsys `*` matches across hierarchy boundaries in some contexts
- `-hierarchical` flag changes traversal scope
- Bus bits use `[` `]` with tool-specific escaping rules
- `-regexp` flag switches from glob to a tool-specific regex flavor

v0.1 targets Synopsys `get_*` semantics as the default. A `mock::eda_config -vendor cadence` switch is reserved for v0.2+. Glob patterns are compiled to regex via a custom matcher that handles Synopsys hierarchy rules, not a naive `*` → `.*` translation.

**Mock API:**
- `mock::create_hierarchy { ... }` — declare cells, pins, nets, ports, clocks
- `mock::capture_from_tool` — TCL helper that runs inside a live EDA tool and emits a `mock::create_hierarchy` block. Does **not** parse Liberty or Verilog.
- `mock::load_netlist /path/to/verilog` — parse **structural/gate-level Verilog** (no behavioral). **v0.2+ only**; v0.1 uses TCL-declared hierarchies exclusively.
- `mock::query_constraints [filters...]` — assert what `set_*` commands were called with
- All real `get_*` / `set_*` commands proxied through deterministic mock DB
- **Deterministic ordering** — mock returns objects in stable order; users must not rely on ordering in constraints

### Component 2 — Runtime Constraint Coverage Tracer [v0.2]

An overlay wrapping every `get_*`, `set_*`, `source`, `read_*` call at runtime using the **rename-and-wrap pattern**:

```tcl
rename get_pins __real_get_pins
proc get_pins {args} {
    set result [__real_get_pins {*}$args]
    edatcl::trace::log get_pins $args $result
    return $result
}
```

Note: `{*}$args` expands the captured args list back into individual arguments; without it, the renamed command receives a single list argument.

The TCL shim writes **newline-delimited JSON (JSONL)** to a temp file with periodic flush. A Rust CLI ingests it post-run:

```tcl
package require edatcl::trace
edatcl::trace::enable
source constraints.sdc
```

```bash
edatcl-check trace report unmatched trace.jsonl
edatcl-check trace explain "u_core/sync_reg/D" trace.jsonl
```

Output:
```
constraint.sdc:142 matched 0 pins
  pattern: u_core/gen_clk_reg/Q
  existing pins:
    - u_core/gen_clk_reg_reg/Q
    - u_core/gen_clk_reg_reg/C
  severity: CRITICAL (empty -from → set_false_path is no-op)
```

**Mock/tracer interoperability.** Mock and tracer emit a compatible constraint-log format. A test written against the mock can be re-validated against a traced real-tool run, surfacing mock/reality divergence. This is the closed loop that gives the framework long-term value: tests don't drift from production behavior because they're checked against actual tool traces.

**Why JSONL?** Two-phase architecture keeps the TCL shim thin. The Rust CLI queries JSONL directly with serde + streaming iterators — no SQLite in v0.2. If multi-run cross-analysis is needed (regression comparison), SQLite ingestion is added in v0.3. If real-time needs grow, Unix-socket daemon is v0.4+.

**Why not just `info commands` interception inside the real tool?** That requires the $200k license you're trying to avoid. The mock framework is the license-free sandbox; the tracer works alongside the real tool but adds observability after the fact.

**Rename limitations.** `rename` may not work on all EDA tools — some register C-implemented commands with hooks that prevent renaming. `trace add execution` is an *untested* fallback with caveats: it fires before/after command execution but cannot easily modify args or return values, and some tools bypass trace entirely. The real answer is empirical: each tool's interception strategy will be tested and documented during v0.2 development. Tools that resist both rename and trace will require per-tool compatibility shims.

### Component 3 — SDC-Aware Static Linter [v0.3]

Parses TCL/SDC without executing. Detects:
- `get_*` patterns guaranteed to match nothing (cross-refs against elaborated DB)
- `set_false_path` / `set_multicycle_path` / `set_clock_groups` applied to empty collections
- Uninitialized variable reads
- Undefined proc calls
- Unused variable assignments
- File reads / `source` of nonexistent paths
- Proc called with wrong arity

**Scoping:** We analyze TCL at the proc/channel level. Dynamic dispatch via `eval`, `uplevel`, `subst` — we flag and punt.

**Parser strategy (Nagelfar).** Nagelfar is a BSD-licensed TCL static analysis engine with a mature AST parser. Rather than porting thousands of lines of TCL pattern-matching to Rust (a multi-month effort), v0.3 shells out to Nagelfar as a subprocess and parses its structured output. This adds a TCL runtime dependency to the lint command only — the mock and trace CLIs remain single-binary Rust. A native Rust port is a potential performance optimization, post-1.0. No tree-sitter — the community TCL grammars aren't mature enough for production.

## Implementation Language — Rust

| Component | Language | Why |
|---|---|---|
| Mock framework (TCL shim) | TCL | Must be loadable by user's flow; no choice |
| Runtime tracer (TCL shim) | TCL | Intercepts calls in-process |
| **Everything else** | **Rust** | One static binary, no runtime dep |

Rust wins because:
- `cargo install edatcl-check`, no Python env management
- Streaming JSONL ingest with serde
- Custom glob→regex matcher without GC pauses
- Parallel test runner
- Single binary for CI integration

## Phase Scope & Realistic Timelines

### v0.1 — Declarative Mock Framework (6–8 weeks)
- `package require mock::eda` with `create_hierarchy`
- `get_pins`, `get_cells`, `get_nets`, `get_clocks` with Synopsys glob semantics
- `set_false_path`, `set_multicycle_path`, `set_clock_groups` with constraint log
- `mock::query_constraints` for test assertions
- **No Liberty parsing. No Verilog parsing.** Mock hierarchies are declared in TCL only.
- Deterministic ordering guaranteed; documented as distinct from real tool behavior
- **Demo:** Find silently-dead `set_false_path` / `set_multicycle_path` patterns in publicly available reference flows (OpenROAD-flow-scripts, Sky130 examples). Specific target design TBD pending v0.1 testing of actual flow scripts.

### v0.2 — Runtime Tracer (additional 8 weeks)
- Rename-and-wrap interception for `get_*` / `set_*`
- JSONL trace output with periodic flush (every 1000 events, or at script exit)
- `edatcl-check trace report|explain` CLI
- Fallback strategies for `rename`-resistant tools (`trace add execution`, per-tool shims) — empirically tested per tool
- Documentation: per-tool compatibility matrix

### v0.3 — Static Linter (additional 12 weeks)
- Nagelfar subprocess integration + structured output parsing
- SDC command definitions for all standard constraints
- Design DB cross-reference (structural Verilog reader, limited Liberty subset)
- `edatcl-check lint` with CI-ready exit codes

**Total realistic: 6–8 months of side-project effort.** v0.1 alone is ship-worthy. The mock framework is the unique value.

## Non-Goals (Explicitly Out of Scope)

- Full TCL language semantics (no eval/uplevel/subst analysis)
- Behavioral Verilog parsing
- Liberty timing models or timing analysis
- GUI of any kind
- IDE integration / LSP
- Vendor-specific extensions beyond Synopsys-style `get_*`
- Real-time tracing daemon (v0.2 uses JSONL files; socket daemon is v0.4+)
- Support for EDA tools that forbid `rename` on built-in commands

## Risks

| Risk | Mitigation |
|---|---|
| Nagelfar-dependent lint (TCL dep) | Acceptable — lint runs in dev, not in flow; mock/trace remain pure Rust |
| `rename`/`trace` bypass by tool internals | Per-tool empirical testing in v0.2; documented compatibility matrix; per-tool shims where neither rename nor trace works |
| Liberty parsing is unbounded | Punted to v0.3+; v0.1 uses declarative mock only |
| Users silently rely on non-deterministic ordering | Mock guarantees stable order; documented difference from real tools |
| Adoption requires internal champions | Target open silicon community first for proof |

## Why Nobody Has Built This

| Who | Why They Haven't |
|---|---|
| **Synopsys / Cadence / Siemens** | Anti-incentive. A static analyzer exposing the tool's silent behavior is a support liability, not a product. Their AI teams chase PPA optimization — not TCL tooling. |
| **Open-source community** | EDA TCL is too niche. Nobody outside the industry knows what `get_pins` does or why silently failing matters. |
| **Academia** | Not publishable. Studies algorithms, not tool scripting ergonomics. |
| **Individual engineers** | Too burned out from tape-outs to build it. |

## Why Now

**AI-generated TCL makes this worse, not better.** LLMs hallucinate pin names, generate `get_*` calls with typos, and write constraints that look correct but do nothing. The industry is adopting AI for flow generation at speed, with zero verification tooling for the output. `edatcl-check` is the missing verification layer.

## Target Audience

- EDA application engineers writing flow scripts
- Methodology/automation teams maintaining re-usable TCL libraries
- New hires learning constraints — catch mistakes instantly instead of at tape-out
- Anyone running regression flows who's ever said "I swear nothing changed but QoR moved"

## How It Gets Adopted

**Phase 1 — Open silicon community.** Target OpenROAD GitHub and Skywater PDK Slack. v0.1 demo shows a real bug in the public reference flow. Community gets tooling for free; tool gets real-world testing and testimonials.

**Phase 2 — Internal champions.** EDA engineers inside companies see the OpenROAD case study and adopt internally. No telemetry upstream — tool must work in air-gapped environments. Champions advocate to their methodology teams.

**Phase 3 — Vendor-neutral standard.** If adoption grows, propose SDC test patterns as a community convention. This is aspirational and not a v0.x goal.

## Success Metrics (Hard, Falsifiable)

- **N≥1** silently-dead constraint patterns identified in publicly available reference flows (OpenROAD-flow-scripts, Sky130, OpenLane, or similar); fix PRs submitted upstream where applicable
- **N≥5** silently dead constraints found across publicly available SDC corpora
- **Adoption:** 10+ EDA engineers using the mock framework in CI within 6 months
- **Testimonial:** "Reduced bring-up time of new flow procs from days to hours"

## Prior Art (What Exists, Why It's Not Enough)

| Tool | What It Does | Gap |
|---|---|---|
| `tclcheck` / `nagelfar` | Generic TCL lint | Knows nothing about `get_*`, SDC, or EDA semantics |
| Synopsys `check_timing` | Checks timing constraints structurally | Proprietary; only checks what applied; can't catch zero-match |
| Cadence `report_analysis_coverage` | Reports constraint coverage | Proprietary; post-hoc only; no lint or mock |
| `tcltest` | Unit test framework | No EDA mock layer — needs real tool |
| Custom shell wrappers | Manual `sizeof_collection` checks | Inconsistent, not enforced |

## Testing Strategy (for edatcl-check itself)

| Layer | How | What It Covers |
|---|---|---|
| Rust unit tests | Cargo's built-in test runner | Pattern matching, hierarchy DB, glob→regex, trace query logic |
| TCL integration tests | `tcltest` suites run via `cargo test` (spawns TCL) | Mock framework end-to-end, constraint log assertions |
| CLI golden tests | Run `edatcl-check` against fixture TCL/SDC files, diff against golden output | Lint, trace report, explain commands |
| Real-flow smoke tests | Run mock against actual OpenROAD-flow-scripts TCL files | Demo target validation, regression detection |

CI runs all four tiers. Failures block merge.

## Versioning

Pre-1.0: `0.x.y` SemVer. APIs may change between minor versions with changelogs. Mock and trace command surfaces get deprecation warnings for one minor version before removal.

Post-1.0: Standard SemVer with stability guarantees for mock, trace, and lint CLI.

## Architecture

```
edatcl-check/
├── Cargo.toml               # Rust workspace
├── src/
│   ├── main.rs              # CLI entry point
│   ├── cli/                 # `edatcl-check mock|trace|lint` commands
│   ├── lint/                # Nagelfar-based static analysis
│   │   ├── parser.rs        # Nagelfar subprocess runner + AST parser
│   │   ├── checks/
│   │   │   ├── mod.rs
│   │   │   ├── empty_get.rs
│   │   │   ├── noop_constraint.rs
│   │   │   ├── uninit_var.rs
│   │   │   ├── undefined_proc.rs
│   │   │   └── unused_var.rs
│   │   └── sdc.rs           # SDC command definitions
│   ├── mock/                # Rust-side pattern engine
│   │   ├── hierarchy.rs     # Cell/pin/net DB (Synopsys semantics)
│   │   ├── pattern.rs       # Custom glob→regex (Synopsys rules)
│   │   └── gen.rs           # TCL mock stub codegen
│   └── trace/               # Trace ingestion + analysis
│       ├── ingest.rs        # JSONL streaming reader (serde)
│       ├── query.rs         # `explain`, `report unmatched` over in-memory
│       └── store.rs         # (v0.3+) SQLite for multi-run regression query
├── tcl/
│   ├── mock/
│   │   ├── eda.tcl          # Mock command surface (thin shim)
│   │   ├── hierarchy.tcl    # Cell/pin/net DB (proxy to Rust)
│   │   └── sdc.tcl          # SDC command implementations + constraint log
│   └── trace/
│       ├── core.tcl         # Rename-and-wrap shim
│       └── write.tcl        # JSONL flush logic
├── tests/
│   ├── fixtures/            # Test TCL/SDC files
│   ├── mock_integration/    # End-to-end mock tests
│   └── lint_cases/          # Per-check test cases
├── examples/
│   ├── openroad/            # OpenROAD gcd flow demo
│   └── simple_flow/         # Minimal working example
└── AGENTS.md
```

## Call to Action

Build this. TCL only where forced. Rust for everything else.

The mock framework alone (v0.1, 6–8 weeks) is a publishable, demo-able, resume-grade project that brings software-engineering testing discipline to an industry that's been waiting 20 years for it.

The EDA industry has normalized silent corruption of design intent for 25 years. Nobody else is going to fix it.

## Commit Authorship

All commits in this repository are authored by Chinmay Rozekar. LLM-generated code is committed under the user's identity — no LLM is credited as a commit author or co-author.
