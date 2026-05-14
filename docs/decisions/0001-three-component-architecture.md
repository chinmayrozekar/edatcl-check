# 0001 — Three-Component Architecture (Mock + Tracer + Linter)

Date: 2025-05-14
Status: Accepted

## Context

The project goal is to catch silently broken TCL constraints in EDA flows.
Initial proposals included a single monolithic static analyzer (symbolic
execution approach). Review identified three distinct user needs that
don't overlap completely:

- **Pre-run:** Catch bugs before execution (static analysis, CI gate)
- **Offline testing:** Unit-test flow procs without a $200k license
- **Post-hoc:** Debug what happened during a 4-hour run

Each maps to a different technique and a different insertion point in
the user's workflow. Trying to solve all three with one tool would
produce a worse experience for each.

## Decision

Split into three independently ship-able components:

1. **Mock EDA Framework (v0.1)** — pure TCL, loadable into any flow.
   Replaces real `get_*` / `set_*` with deterministic test doubles.
2. **Runtime Tracer (v0.2)** — TCL shim + Rust CLI. Intercepts real
   EDA commands during a run, emits JSONL, post-hoc query.
3. **Static Linter (v0.3)** — Rust CLI with Nagelfar backend. Parses
   TCL/SDC without execution, flags guaranteed-noop patterns.

## Consequences

- v0.1 (mock) is the unique value and the foundation for the other two.
  The later components build on its hierarchy DB and pattern engine.
- Users get value at each phase independently; they don't wait for all
  three.
- Shared infrastructure (hierarchy DB, pattern matching, constraint log
  schema) must be designed for reuse across components from the start.
- Risk: mock's semantics may drift from real tool behavior. Mitigated
  by tracer (v0.2) which validates mocks against reality.
