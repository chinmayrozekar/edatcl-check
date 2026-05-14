# 0004 — Nagelfar Subprocess, Not Native Rust Port

Date: 2025-05-14
Status: Accepted

## Context

Component 3 (static linter) needs a TCL AST parser. Options:

- **Port Nagelfar to Rust:** Nagelfar is BSD-licensed, battle-tested,
  and handles TCL's quoting/substitution correctly. But it's thousands
  of lines of TCL pattern-matching — a 2-3 month port.
- **Tree-sitter:** Modern, generates parsers from grammar files. But
  the community tree-sitter-tcl grammars are immature and get TCL's
  contextual parsing rules wrong.
- **Shell out to Nagelfar:** Spawn as subprocess, parse its structured
  output. Adds TCL runtime dep to lint command only.
- **Write our own parser:** TCL grammar is simple but full of quirks.
  6-8 weeks to get wrong.

## Decision

Shell out to Nagelfar as a subprocess and parse its AST output (v0.3).

This adds a TCL runtime dependency to the `edatcl-check lint` CLI only.
The mock and trace CLIs remain single-binary Rust. A native Rust port
is reserved for post-1.0 if performance demands it.

## Consequences

- Lint command requires `tclsh` + Nagelfar on PATH. Documented in
  installation instructions.
- No TCL dependency for `edatcl-check mock` or `edatcl-check trace`.
- Shell-out latency is acceptable because lint is run interactively
  (pre-commit / CI), not embedded in flows.
- Nagelfar's structured output format becomes an implicit API contract.
