---
date: 2025-05-14
tool: opencode (deepseek-v4-flash-free) + claude.ai
outcome: full design spec in AGENTS.md; 5 ADRs; v0.1 TCL mock framework scaffolded
---

## Origin

Every EDA engineer has a graveyard of tape-out post-mortems caused by
constraints that silently did nothing. This project started with a simple
observation: the TCL scripts we trust to govern multi-million dollar
silicon have less safety tooling than a weekend JavaScript project. The
design space exploration that followed is recorded below.

## Key Inflection Points

1. **Silent failure detector idea** — First EDA-specific concept. A TCL
   package that wraps core commands and logs every suppressed error,
   unreadable file, unmatched wildcard. Newcomers' #1 complaint.

2. **Senior architect framing** — "Think and act like a very senior
   architect level senior engineer at Synopsys/Cadence/Mentor." This
   reframing produced the three specific pains: zero static analysis,
   no unit test framework for EDA flows, constraint debugging black hole.

3. **The `edatcl-check` concept** — Three-component design (lint + mock +
   trace) emerged from pushing back on AI/ML teams at EDA companies
   "already fixing it." The anti-incentive argument crystallized here.

4. **First review feedback** — Sharp critique that led to: reordering
   phases (mock first), implementation language (TCL only where forced,
   Rust for everything else), realistic timelines, Non-Goals section.

5. **Second review feedback** — Addressed 7 technical gaps: TCL/Rust
   boundary (JSONL), glob→regex complexity, Nagelfar vs tree-sitter,
   rename mechanism, mock adoption blocker, trace add execution caveats.

6. **Third review feedback** — Fixed Nagelfar subprocess approach,
   capture_from_tool redefinition, SQLite deferral, softened OpenROAD
   demo target, added testing strategy + versioning.

## Key Decisions (all formalized as ADRs)

- ADR-0001: Three-component architecture (mock + tracer + linter)
- ADR-0002: Rust + TCL split, TCL only where forced
- ADR-0003: JSONL for v0.2 trace transport, SQLite deferred to v0.3
- ADR-0004: Nagelfar subprocess for v0.3 lint, not native Rust port
- ADR-0005: Synopsys-first vendor semantics for pattern matching

## Source Files Created

- AGENTS.md — full design spec (iterated 4 versions)
- CLAUDE.md — operational instructions for AI assistants
- docs/decisions/0001-0005 — architecture decision records
- Prompts/2025-05-seed-conversation.md — this file
- tcl/mock/eda.tcl — mock framework entry point
- tcl/mock/hierarchy.tcl — cell/pin/net storage
- tcl/mock/sdc.tcl — constraint log + set_* commands
- tests/run_all.tcl — test runner
- tests/test_mock_basic.tcl — basic mock tests
- tests/test_glob_patterns.tcl — glob matching tests
- tests/test_constraint_log.tcl — constraint log tests
- examples/simple_flow/ — end-to-end demo
