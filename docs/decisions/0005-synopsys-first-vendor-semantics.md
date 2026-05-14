# 0005 — Synopsys-First Vendor Semantics for Pattern Matching

Date: 2025-05-14
Status: Accepted

## Context

EDA pattern matching (`get_pins`, `get_cells`, etc.) has vendor-specific
behavior for glob patterns, hierarchy traversal, bus bit escaping, and
regex flags. Supporting all vendors from day one is impractical and
would delay v0.1 significantly.

The market reality: Synopsys tools (Design Compiler, PrimeTime, IC
Compiler) dominate the EDA flow TCL ecosystem. Most users' constraints
are Synopsys-flavored SDC.

## Decision

v0.1 targets Synopsys `get_*` semantics as the default and only vendor.

Specific semantics (as implemented):
- `*` matches one hierarchy level by default (not recursive)
- `-hierarchical` flag makes `*` traverse all levels
- `-regexp` flag switches from glob to EDA-specific regex
- Bus bits: `foo[3]` is literal syntax; `foo\[3\]` escapes to literal
  bracket
- Objects returned in stable lexicographic order (diverges from real
  tools — documented)

A `mock::eda_config -vendor cadence` switch is reserved for v0.2+.

## Consequences

- v0.1 ships faster by targeting one vendor's semantics.
- Users on Innovus/Genus get partial value (basic patterns work; edge
  cases may be wrong) until v0.2.
- Vendor dialect layer is designed as a pluggable component from the
  start, even though only one implementation exists.
- Pattern matching engine must be structured to swap semantics without
  rewriting the core.
