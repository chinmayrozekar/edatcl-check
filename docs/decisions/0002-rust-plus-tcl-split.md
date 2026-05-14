# 0002 — Rust + TCL Split, TCL Only Where Forced

Date: 2025-05-14
Status: Accepted

## Context

Implementation language for the project. Options considered:
- Pure TCL (minimal deps, runs anywhere a tool runs)
- Rust (single static binary, modern tooling)
- Python (rich ecosystem, easy prototyping)
- Go (easy cross-compile, good CLI)

Key constraints:
- The mock framework MUST be loadable into the user's EDA tool via
  `package require` — this forces TCL for the mock shim
- The tracer must intercept TCL calls in-process — also forces TCL
- The linter and CLI tooling do NOT need to run inside the tool —
  Rust is optimal

## Decision

| Component | Language | Why |
|---|---|---|
| Mock framework (TCL shim) | TCL | Must be loadable by user's flow |
| Runtime tracer (TCL shim) | TCL | Must intercept calls in-process |
| Everything else | Rust | Single binary, no runtime dep |

Rust-specific wins: serde for streaming JSONL, custom glob→regex
without GC pauses, parallel test runner, `cargo install` distribution.

## Consequences

- TCL code must be kept as thin shims; all heavy logic (pattern
  matching, storage, query) lives in Rust.
- v0.1 ships TCL-only. Rust workspace is scaffolded in v0.2 when the
  tracer CLI is built.
- No Python/Go dependency at any point. CI stays simple.
- TCL/Rust boundary design (JSONL files, TCL→Rust IPC) must be
  explicitly designed, not hand-waved.
