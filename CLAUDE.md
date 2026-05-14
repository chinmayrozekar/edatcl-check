# Claude Code Working Notes — edatcl-check

## Project Status
v0.0.0 — pre-MVP. Working toward v0.1 (mock framework).

## Read First
- **AGENTS.md** — full design spec, rationale, and Non-Goals. This is the source of truth for *what* and *why*. Read it before suggesting any architectural change.
- **Non-Goals section in AGENTS.md** — hard scope boundary. Do not exceed. If a request would cross a Non-Goal, push back and ask before proceeding.

## Current Focus
v0.1 — Declarative Mock EDA Framework. Pure TCL. Target: 6–8 weeks.

In-scope for v0.1:
- `mock::create_hierarchy` DSL for declaring cells/pins/nets/ports/clocks
- `get_pins`, `get_cells`, `get_nets`, `get_clocks` with Synopsys glob semantics
- `set_false_path`, `set_multicycle_path`, `set_clock_groups` with constraint log
- `mock::query_constraints` for assertion in `tcltest` cases
- `mock::reset_constraint_log` for test isolation
- Deterministic ordering on all collection returns

Explicitly NOT in v0.1:
- Liberty parsing
- Verilog parsing
- Runtime tracer (v0.2)
- Static linter (v0.3)
- Non-Synopsys vendor semantics
- GUI / LSP / IDE integration

## Conventions

**Language.** TCL 8.6+ syntax. Use `{*}$args` for arg expansion, not `eval`. Use `dict` not legacy arrays where possible. Namespaces required for all public commands.

**Namespacing.**
- Public mock commands live in `::mock::` namespace
- Internal helpers live in `::mock::_internal::` (underscore prefix signals private)
- Mocked EDA commands (`get_pins`, etc.) are installed into global namespace via `mock::install_eda_shims`

**Constraint log.** All `set_*` mocks call `mock::_internal::log_constraint <type> <args_dict>`. Schema:
```
{type set_false_path
 args {-from {u_core/clk} -to {u_core/d}}
 resolved {-from {1 pin} -to {1 pin}}
 line 42 file constraints.sdc}
```

**Pattern semantics (Synopsys).**
- `*` matches one hierarchy level by default
- `-hierarchical` traverses all levels
- `-regexp` switches glob → regex
- Bus bits `foo[3]` need escaping; `foo\[3\]` is literal
- When ambiguous, ASK before implementing

**Determinism.** All `get_*` results return objects in stable lexicographic order. This differs from real tools. Document the divergence in the public API doc, not silently.

## Repo Layout

```
edatcl-check/
├── AGENTS.md              # Design spec (read-only context)
├── CLAUDE.md              # This file (operational notes; update as we go)
├── tcl/
│   └── mock/
│       ├── eda.tcl        # Public mock command surface
│       ├── hierarchy.tcl  # Internal cell/pin/net storage
│       └── sdc.tcl        # set_* mock implementations + log
├── tests/
│   ├── run_all.tcl        # Entry point; exits non-zero on failure
│   ├── fixtures/          # Test TCL/SDC files
│   ├── test_mock_basic.tcl
│   ├── test_glob_patterns.tcl
│   └── test_constraint_log.tcl
└── examples/
    └── simple_flow/       # Minimal end-to-end demo
```

Rust workspace (`Cargo.toml`, `src/`) is deferred to v0.2 — no need to scaffold yet.

## How To Test

```bash
tclsh tests/run_all.tcl
```

Should exit 0 on success, non-zero on any failed test case. Use `tcltest::cleanupTests` to count failures and exit accordingly.

## Commit Authorship

All commits in this repository are authored by Chinmay Rozekar. LLM-generated code is committed under the user's identity. Never add LLM signatures, co-authors, or credits in commit messages or author fields.

## Working Style

- **Ask before assuming.** Synopsys edge cases, OpenROAD specifics, ambiguous SDC behavior — ask first, don't guess. Wrong assumptions silently embedded in the mock are the exact failure mode the project exists to prevent.
- **Small commits.** Each commit should leave `tests/run_all.tcl` passing. If a refactor requires temporarily breaking tests, say so explicitly and stage the fix in the next commit.
- **No yak-shaving.** If a tangent emerges (e.g., "we should write our own TCL parser"), surface it and defer to AGENTS.md Non-Goals. Stay on the v0.1 path.
- **Empirical over theoretical.** When unsure about Synopsys behavior, write a probe script, suggest the user run it in a real tool if available, and proceed from observed behavior — not from documentation alone.
- **Commit authorship.** All commits are authored by Chinmay Rozekar. No LLM co-authors or signatures.

## Session Log

### 2025-05-14 — v0.1 Core Implementation
- Wrote 5 retroactive ADRs (`docs/decisions/0001-0005`)
- Saved seed conversation to `Prompts/2025-05-seed-conversation.md`
- Implemented `tcl/mock/hierarchy.tcl` — dict-keyed object storage, glob→regex pattern
  matching with Synopsys semantics (`*` = one level, `-hierarchical` = recursive,
  `-regexp` = literal regex)
- Implemented `tcl/mock/eda.tcl` — `create_hierarchy` DSL parser, `get_pins`/`get_cells`/
  `get_nets`/`get_clocks`, `install_eda_shims`, `query_constraints`, `reset_constraint_log`
- Implemented `tcl/mock/sdc.tcl` — `set_false_path`, `set_multicycle_path`,
  `set_clock_groups` with constraint log and resolved-count tracking
- All commands auto-log to constraint log; `query_constraints` filters by key=value
- 41 tcltest cases across 3 test files: basic mock, glob patterns, constraint log
- `examples/simple_flow/run_demo.tcl` — end-to-end demo catching the AGENTS.md bug
- Fixed: Tcl 9.0 compat (version check), list-of-dicts sorting, multi-arg return bug,
  namespace export for SDC commands
- **Status:** All 41 tests pass. Demo correctly catches `get_pins gen_clk_reg/Q → 0 matches`.

## Open Questions (Ask Before Assuming)

- Exact Synopsys glob semantics for `*` across hierarchy boundaries (default behavior vs `-hierarchical`)
- Which OpenROAD reference flow to target for v0.1 demo (gcd? aes? riscv32i?) — needs verification by running mock against the real script
- Should `mock::query_constraints` support negative assertions (e.g., "no `set_clock_groups` was applied")? Likely yes — confirm before implementing.

## Session End Protocol

At the end of every session, update this file with:

1. **What we just did** — bullet list of files changed and why
2. **What's next** — single sentence describing the next logical step
3. **Anything I'm uncertain about** — questions for the user to answer before next session

Treat CLAUDE.md as a living log, not a fixed primer. The goal is that the next session starts with full context in under 60 seconds of reading.

## Out-of-Scope Triggers (Push Back)

If the user asks for any of these mid-session, pause and confirm before proceeding:

- "Let's also start the Rust CLI" → v0.2; finish v0.1 first
- "Can we parse a Liberty file?" → v0.2+; not in v0.1 scope
- "Add Cadence Innovus support" → v0.2+
- "Let's build a GUI for the trace viewer" → Non-Goal, full stop
- "Port this to Python instead" → Major scope change; revisit design doc

Polite pushback, not refusal. The user can override; the job is to surface the scope cost first.
