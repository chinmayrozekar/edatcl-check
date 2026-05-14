# 0003 — JSONL Files for v0.2 Trace Transport, SQLite Deferred

Date: 2025-05-14
Status: Accepted

## Context

The runtime tracer needs to get trace events from the TCL process
(inside the EDA tool) to the Rust analysis CLI. Three options exist:

- **Option A:** TCL writes directly to SQLite via `tclsqlite3`.
  Pro: simple. Con: TCL shim is no longer thin; adds SQLite dep to
  the user's flow environment.
- **Option B:** TCL writes newline-delimited JSON to a file; Rust
  ingests and queries post-hoc. Pro: clean separation, TCL shim stays
  thin. Con: async flush means data loss on crash; large files for
  long runs.
- **Option C:** TCL talks to a Rust daemon over Unix socket.
  Pro: real-time. Con: another process in the user's flow — EDA users
  hate this.

## Decision

Use Option B (JSONL with periodic flush) for v0.2.

Rust queries JSONL directly with serde streaming iterators — no SQLite
yet. SQLite for multi-run regression comparison is deferred to v0.3.
Unix-socket daemon for real-time use is v0.4+.

## Consequences

- TCL shim writes JSONL every 1000 events or at script exit.
- Data loss on crash is accepted for v0.2 (mitigated by periodic flush).
- Rust CLI is simpler — no SQLite dependency in v0.2.
- At ~100K events for a typical flow, JSONL query via serde iterators
  is sub-second. SQLite only justified when users want cross-run
  queries (regression comparison on ~10M+ events).
