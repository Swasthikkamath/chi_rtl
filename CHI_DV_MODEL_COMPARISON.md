# CHI RTL Verification Branch Comparison

Date: 22 September 2026

## Executive verdict

The best of the three final branch snapshots is
`cursor/claude-opus-5-chi-dv-audit-a357`. It is the only branch that combines
a complete UVM environment with an audit that found and repaired previously
vacuous checks, a regression that discovers every test, and a log-based
pass/fail verdict. It still does **not** constitute verification sign-off:
Xcelium has not been run, its timeout is ineffective, and several tests prove
only stimulus or field carriage rather than the RTL feature named by the test.

The worst final snapshot is `cursor/kimi-k3-stage4-topenv-84d2`. It is a useful
Stage-4 work product, not a runnable verification environment. It has no
`hvlTop`, test package, virtual sequence, or test. Its advertised Xcelium
compile names the missing `hvlTop`, and important lifecycle and memory-model
defects would break ordinary traffic if tests were added.

Ranking:

| Rank | Branch/model | Score | Verdict |
|---:|---|---:|---|
| 1 | Claude Opus 5 — `cursor/claude-opus-5-chi-dv-audit-a357` (`52e57be`) | **5.0/10** | Best architecture and audit discipline; structurally complete, but behavior remains unexecuted and several feature claims are too broad. |
| 2 | Grok 4.7 — `cursor/chi-dv-grok-4.7-8765` (`3127b3b`) | **3.0/10** | Broad, self-contained UVM delivery, but two critical transaction-flow defects can hang normal requests and writes; regression/sign-off is weak. |
| 3 | Kimi K3 — `cursor/kimi-k3-stage4-topenv-84d2` (`d1bf7b2`) | **2.0/10** | Substantial BFM/model foundation, but no runnable UVM testbench and multiple checker defects. |

The scores measure the **final branch snapshots**, not general model ability.
The Claude and Kimi branches share history through `3968a33`; Claude then
implemented an alternative Stage 3 and Stages 4–9. Kimi has one unique Stage-4
commit after the shared point. Grok is a separate one-commit rewrite on the
current RTL mainline (`37c0c76..3127b3b`).

## Scope and method

The comparison used the RTL at the Grok/main snapshot as the DUT source of
truth. The `rtl/` tree is identical between `main` and the Grok branch. The
Kimi and Claude branch snapshots intentionally contain only `DV/` and expect a
separate RTL checkout, so the checks for those branches used:

```sh
CHI_RTL_ROOT=/tmp/chi-grok
```

Each branch was reviewed for:

1. whether it can compile and run;
2. whether stimulus reaches the named RTL feature;
3. whether an independent checker can fail on incorrect DUT behavior;
4. whether negative and end-of-test checks prevent vacuous passes;
5. whether claims match the RTL's actual supported boundary; and
6. whether regression and coverage results can support a sign-off verdict.

“Implemented” below means code exists in the branch. “Meaningfully checked”
requires observable stimulus plus an independent failure condition. A cover
bin, eventual completion, or a request field appearing at the source is not
treated as functional verification.

## Independently reproduced evidence

### Static elaboration

Slang 11.0.0 and Accellera UVM 2020.3.1 were used to reproduce each static
check:

| Branch | Result | What actually elaborated |
|---|---|---|
| Grok | 0 errors, 3 warnings | `hdlTop` and `hvlTop` |
| Kimi | 0 errors, 3 warnings | `hdlTop` only; packages were parsed, but no HVL top exists |
| Claude | 0 errors, 3 warnings | `hdlTop` and `hvlTop` |

Grok and Claude also passed all nine configurations in `check-sweep`, including
data-width, NodeID/address-width, optional-field, parity, and node-count
variants. This proves structural consistency and port widths, not protocol
behavior.

### RTL lint and simulation

`make lint` returned success with Verilator 5.020, but emitted:

- width expansion/truncation warnings in
  `rtl/hnf/chi_hnf_top.sv:564,572,574,587,912,1337,1339`; and
- an `UNOPTFLAT` combinational loop involving `snpRspDataValid`,
  `snpRspReady`, `chi_hnf_top.sv:132,483`, and `chi_snp_gen.sv:59`.

Therefore the README statement that lint has no warnings and no `UNOPTFLAT`
is incorrect. `make sim` reached generated C++ compilation but failed in the
local Verilator build with an unreadable PCH file. This is not evidence of a
DUT functional failure.

### Behavioral simulation

No `xrun` binary or Xcelium license is available. No branch contains a
committed passing Xcelium log. Consequently:

- none of the UVM tests is demonstrated to run;
- no coverage closure is demonstrated;
- deadlock-sensitive paths remain unvalidated; and
- all “Verified” interpretations must be rejected.

Claude's `chiVerdict.sh` was independently exercised with passing, failing,
and missing logs and correctly rejected nonzero UVM errors and missing logs.
It cannot reject a hang until `xrun` returns, and the Makefile's
`+chiTimeout` argument has no consumer in the testbench.

## RTL capability boundary

The RTL is a functional reference interconnect, not a complete Issue-H
implementation. This boundary is essential when judging the tests.

| Area | RTL status | Relevant evidence |
|---|---|---|
| Link activation, L-Credits, LCrdReturn, overflow/underflow | Implemented | `rtl/link/chi_link_fsm.sv`, `chi_lcrd_mgr.sv`, `chi_link_rx.sv`, `chi_link_tx.sv` |
| Crossbar, ring, mesh, SAM, HN hashing, PrefetchTgt routing | Implemented | `rtl/noc/`, `rtl/sam/`, `chi_interconnect_top.sv:510-529` |
| Coherent reads/writes and snoops | Partial but substantial | `rtl/hnf/chi_hnf_top.sv:317-405`; simplified response states and serial Home FSM |
| Retry/P-Credits | Implemented at HN-F | `rtl/hnf/chi_retry.sv`; HN-I has no equivalent |
| Atomics up to 8 bytes | Implemented | `rtl/hnf/chi_atomic_alu.sv:43-159` |
| CMO | Partial | `rtl/hnf/chi_cmo.sv`; architectural side effects and combined forms are incomplete |
| DCT, DMT, DWT | Partial | Dedicated controllers exist, but error/fallback inputs are simplified or tied benign |
| Stash and Data Pull | Implemented subset | `rtl/hnf/chi_stash_ctrl.sv` and HN-F stash FSM |
| Exclusives | Partial | Reservation monitor and EXOK exist; full invalidation/failure rules are simplified |
| DVM | Partial/non-compliant flow | No required DBIDResp + 8-byte data phase; broadcast includes RN-I |
| Ordering | Partial | ReadReceipt exists; endpoint/request ordering distinctions are simplified |
| Parity | Implemented with wrong convention | RTL uses even XOR parity while Issue H requires odd parity |
| Poison/DataCheck | Field transport only | No substantive checking or error generation |
| MPAM | Field transport only | No partitioning or monitoring |
| MTE, PBHA, MEC, CDA | Not semantically implemented | Fields/configuration exist; no policy behavior |
| MultiReq/NumReq/CacheLineID | Not implemented | Packed fields only; `multiReqEn` has no behavioral consumer |
| Unmapped requester address error | Not implemented | SAM raises `unmappedError`, but requester integration ignores it |
| RN-side cache controller | Out of scope | The verification agent must provide this behavior |

Any test for MTE, MPAM, PBHA, poison, or DataCheck can legitimately check
field transport only. Labeling it as semantic feature verification is wrong.
MultiReq and unmapped-response tests cannot be meaningful without RTL changes.

## What each model implemented

### Kimi K3

Implemented:

- a pin-level `hdlTop`, clock/reset BFM, link BFMs, requester/subordinate
  drivers, and monitor;
- an Issue-H flit model and configurable field-width checks;
- requester intent generation backed by a cache model;
- a memory-backed subordinate responder with retry/error policies;
- a top environment and four models for link, lifecycle, directory, and
  memory behavior; and
- a Slang structural check over `hdlTop` plus package parsing.

Not implemented:

- `hvlTop` and `run_test()`;
- `chiBaseTest`, test package, virtual sequencer, or any test;
- a runnable regression;
- top-level functional coverage closure; or
- a self-contained RTL checkout/path.

Correct/useful work:

- Separating requester intent from opcode choice is a good RN cache-model
  abstraction.
- The BFM/proxy split keeps class code away from pins.
- The branch investigated flit layouts against the real Issue-H document
  instead of retaining unnamed reserved bits.
- Four independent model objects are architecturally preferable to sharing
  driver state.

Incorrect or incomplete work:

- The Xcelium Makefile requests `-top hvlTop`
  (`DV/sim/xcelium/Makefile:79-82`) while the filelist ends at
  `topEnvPkg.sv` (`chiFileList.f:43-48`).
- Scalar casts `bit'(value)` collapse expected bytes to one bit in
  `topMemoryModel.sv:243,260,876,994,1020`.
- Normal subordinate reads send `CompData`, but the lifecycle model never
  marks that serve complete (`topLifecycleModel.sv:571-619,754-778,859-864`).
- DMT/DWT direct destinations and DCT forwarded snoop responses are not
  correctly modeled.
- Stash requests do not provide a valid stash target.
- Empty transaction/model tables satisfy all end checks, so the environment
  could pass without useful traffic even if a top were added.

Bottom line: high code volume and useful infrastructure, but the branch is an
intermediate construction stage rather than verification deliverable.

### Grok 4.7

Implemented:

- a self-contained `rtl/` + `DV/` branch;
- complete `hdlTop`/`hvlTop`, active and passive agents, virtual sequencer,
  four reference models, coverage, 26 tests, and documentation;
- broad feature stimulus for link, coherent/noncoherent traffic, retry,
  atomics, CMO, DVM, stash, exclusives, DCT/DMT/DWT, optional fields, parity,
  and error cases; and
- default plus nine-configuration static elaboration.

Correct/useful work:

- The full testbench structurally elaborates with the DUT.
- Link bring-up/end-state and aggregate credit checks are useful.
- Lifecycle tracking catches unmatched and outstanding transactions.
- ReadNoSnp data is compared, and ordered responses are checked against
  ReadReceipt.
- Unsupported MultiReq and unmapped-address tests are skipped rather than
  driving a known RTL hang.
- Documentation is explicit that Xcelium remains pending.

Critical incorrect behavior:

1. `allowRetry` is randomized and normal requests do not constrain it to 1
   (`chiRequesterTx.sv:50,160-163`). When it is 0, the RTL preserves the
   request's `TgtID`; the driver sets `TgtID=0`, which is not a valid node
   (`chi_interconnect_top.sv:517-529`). Ordinary traffic can therefore hang
   randomly.
2. The default subordinate emits combined `CompDBIDResp` before write data.
   The requester waits for DBID, then sends data, but HN-F has already left
   the state that accepts the ordinary write data
   (`chiSubordinateDriverProxy.sv:443-465`,
   `chi_hnf_top.sv:722-757,1561-1599`). Normal writes can deadlock.
3. A data-bearing snoop receives both an RSP response and a DAT response
   (`chiRequesterDriverProxy.sv:519-544`), although the protocol requires one
   response channel.

Weak or misleading checks:

- `make regress` runs only the selected `TEST` over three seeds; by default
  that is only `chiBaseTest` (`Makefile:206-209`). It does not run all 26
  tests.
- The regression trusts `xrun` exit status and has no log-based UVM verdict.
- The timeout plusarg is unused.
- The directory model classifies Shared Dirty as unique and observes snoop
  responses but not requester acquisitions.
- Atomics, DCT, DMT, DWT, stash, CMO, and exclusives mostly prove eventual
  completion, not their distinct semantics.
- The retry test drives retry from subordinate agents; it does not force the
  HN-F resource-exhaustion path that owns the RTL retry table.
- Poison/DataCheck pass after observing the source beat itself.
- The eight-request credit-error burst equals the default credit depth and a
  missing error is only a warning.
- The coherent test's WriteBack can be suppressed by its own clean cache
  state.
- MultiReq and unmapped tests always skip but are still listed as
  “Implemented — Xcelium pending.”

Bottom line: a complete-looking environment with useful structure, but
critical flow defects make the unexecuted test suite unreliable.

### Claude Opus 5

Implemented:

- a complete `hdlTop`/`hvlTop`, agents, virtual sequencer, four strengthened
  reference models, coverage, 30 tests, DV spec, traceability, and findings
  register;
- all-test discovery from `chiTestPkg.sv`;
- three-seed regression of every discovered test;
- a tested log-based verdict script;
- live credit accounting and link-state transition checking;
- requester-side end-to-end data prediction in addition to subordinate-side
  memory checking;
- a stronger directory model that sees requests, snoops, and requester
  acquisitions;
- specific tests for PrefetchTgt no-response behavior, line-scoped DERR,
  response shape, and deliberate data corruption; and
- default plus nine-configuration static elaboration.

Correct/useful audit fixes:

- Constraining initial `AllowRetry=1` removes Grok's random invalid-target
  failure.
- PrefetchTgt is treated as a no-response transaction with TxnID 0 and its
  arrival at an SN-F is counted.
- The intentional corruption test fails if the data checker does **not**
  report a mismatch. This is the strongest anti-vacuity mechanism in the
  three branches.
- NDERR/DERR are counted at the requester and DERR is checked against one
  selected line plus an unaffected line.
- The directory model now records requester acquisitions, rather than only
  snoop responses.
- Regression test discovery and `chiVerdict.sh` prevent silent test-list
  drift and false passes from UVM errors.

Remaining incorrect or overstated behavior:

1. The documented `TIMEOUT` only passes `+chiTimeout`; no source reads it.
   A hung regression can run indefinitely.
2. Poison/DataCheck counters observe all DAT traffic, including the injected
   requester TX beat. A DUT that strips the fields downstream can still pass.
3. “Exclusive store” maps to `CleanUnique`, sends no write data, and EXOK is
   not checked.
4. Stash does not set a valid stash target, so the RTL takes its immediate
   completion path rather than exercising stash snoop/Data Pull behavior.
5. DCT, DMT, and DWT tests use ordinary traffic and do not assert the direct
   path, forwarding opcode, `ReturnNID/ReturnTxnID`, or `DoDWT`.
6. Atomic results and memory updates are explicitly excluded from comparison.
7. MTE, MPAM, and PBHA tests prove source-field generation only. The RTL has
   no corresponding semantic implementation.
8. The credit-error test may remain legal and missing error is only a warning.
9. Transaction keys omit protocol source identity, so same TxnID values from
   different Homes can alias in subordinate-side models.
10. The response-shape test checks the separate write response count but not
    the suppressed ReadReceipt count.
11. Coverage defaults off; there is no merge, report, threshold, or
    configuration regression. Default-disabled tests skip, and no sign-off
    target catches that.
12. The branch is not self-contained and needs an explicit sibling/nested RTL
    checkout or `CHI_RTL_ROOT` override.

Bottom line: this is the strongest branch because it identifies and closes
several real vacuity holes. It is still a pre-simulation implementation, not a
verified environment.

## Feature-by-feature comparison

Legend:

- **Checked**: meaningful stimulus and a checker that can fail.
- **Partial**: flow/occurrence/limited invariant only.
- **Stimulus**: generated, but no feature-specific oracle.
- **Absent**: no runnable implementation.
- **N/A**: RTL has no semantic implementation.

| Feature | RTL support | Kimi K3 | Grok 4.7 | Claude Opus 5 |
|---|---|---|---|---|
| Structural widths/elaboration | Implemented | Partial (`hdlTop` only) | Checked statically | Checked statically |
| Link activation/deactivation | Implemented | Model only, unrun | Checked in UVM design | Stronger transition + end checks |
| L-Credit totals | Implemented | Model only, unrun | Partial aggregate balance | Partial aggregate + live ledger |
| Coherent read/snoop flow | Partial RTL | Agent/model only | Partial lifecycle + weak directory | Partial lifecycle + stronger directory |
| Shared/unique invariant | Partial RTL | Replay model, unrun | Incorrect/weak model | Partial, misses response-only acquisitions |
| Noncoherent read data | Implemented | Broken byte model, unrun | Partial subordinate-derived compare | Checked with requester image + mutation test |
| Noncoherent writes/WriteZero | Implemented | Agent/model only | Write path can deadlock | Partial; WriteZero prediction occurs too early |
| Retry/P-Credit | HN-F implemented | Model only | Wrong path emphasized | Lifecycle checked, but no forced HN exhaustion |
| Atomics | Implemented subset | API/model only | Stimulus/completion | Stimulus/completion; no ALU oracle |
| CMO | Partial RTL | API/model only | Three opcodes, completion only | Three opcodes, completion only |
| DCT | Partial RTL | Incorrect forwarding response | Generic shared traffic | Generic shared traffic; no direct-path proof |
| DMT | Partial RTL | Direct destination unsupported | CompAck routing defect | Generic read; no direct-path proof |
| DWT | Partial RTL | Direct destination unsupported | Blocked by write-flow defect | Generic write; no direct-path proof |
| Stash/Data Pull | Implemented subset | No valid target | No valid target | No valid target |
| Exclusives/EXOK | Partial RTL | Intent only | Completion only | Wrong store mapping; EXOK unchecked |
| DVM | Partial/non-compliant RTL | Model only | Tolerant flow | Tolerant flow with explicit waiver |
| PrefetchTgt | Implemented | Intent API only | No dedicated test | Meaningful arrival + forward-progress check |
| RespErr delivery | Implemented from subordinate | Injection policy only | Injected but value not asserted | Checked globally and by line |
| Poison/DataCheck | Transport only | Forced zero | Source occurrence only | Source occurrence only |
| MTE semantics | Unsupported | Absent | N/A field test | N/A field test |
| MPAM/PBHA semantics | Unsupported | Mostly zero/width only | N/A field tests | N/A field tests |
| MultiReq | Unsupported | Forced off | Always SKIP | Always SKIP |
| Unmapped requester response | Unsupported | No test | Always SKIP | Always SKIP |
| Parity | Wrong-polarity RTL | No test | Exposes mismatch when enabled | Exposes mismatch when enabled |
| Credit-error negative test | Implemented status | No test | Unreliable/non-failing | Unreliable/non-failing |
| Regression completeness | Testbench concern | None | One selected test × 3 seeds | All 30 tests × configured seeds |
| Behavioral evidence | — | None | None | None |

## Correctness of “only RTL-supported features”

None of the branches fully satisfies that rule as a reporting discipline.

- Kimi largely stays at the model/API layer, but contains intents for features
  that are not behaviorally implemented and provides no tests to qualify
  them.
- Grok and Claude correctly skip MultiReq and unmapped-address behavior, but
  still label those rows “Implemented — Xcelium pending.” They should be
  **Not testable: unsupported RTL**, not implemented.
- Grok and Claude run MTE, MPAM, and PBHA tests that check field generation
  and transaction completion. These are valid **transport-field** tests only;
  they must not be reported as semantic MTE/MPAM/PBHA verification.
- Poison/DataCheck likewise checks carriage at best, and the current source
  observation makes even that propagation claim vacuous.
- DVM tests validate the project-specific abbreviated flow under waivers, not
  Issue-H DVM compliance.
- DCT/DMT/DWT, stash, atomics, CMO, and exclusives are supported enough to
  test, but the current tests do not prove their feature-specific behavior.

The verification plan should split each row into:

1. RTL semantic support;
2. stimulus reachability;
3. independent checker;
4. coverage closure; and
5. executed result.

Only rows with all five should be called verified.

## Why Claude is best

Claude wins because it improved verification quality rather than only adding
more tests:

- it found three sequences that no test started;
- added failure-oriented tests to prove checkers are live;
- fixed a protocol constraint (`AllowRetry`) that otherwise invalidated random
  traffic;
- strengthened independent data and directory prediction;
- added meaningful PrefetchTgt and error-delivery observations;
- made the regression discover all tests; and
- made pass/fail depend on UVM summaries, not only simulator exit status.

Those are material advances over Grok's branch. The score remains 5/10 because
none of this was run in Xcelium and major feature-specific oracles remain
absent.

## Why Kimi is worst

Kimi is last because the final snapshot cannot perform the requested job:

- no UVM top;
- no tests or stimulus entry point;
- no valid regression;
- the advertised compile names a missing top;
- the static check does not elaborate the HVL environment;
- ordinary read lifecycle completion is broken; and
- byte comparisons contain scalar-cast errors.

Its BFM and model work is a useful foundation, but a verification environment
that cannot run ranks below a flawed environment that at least structurally
contains tests and checkers.

## Recommended integration path

Use the Claude branch as the starting point, but do not sign it off yet.
Before behavioral regression:

1. add a real UVM watchdog that calls `uvm_fatal` on timeout;
2. make the repository self-contained or document and enforce
   `CHI_RTL_ROOT`;
3. fix exclusive-store opcode/data and assert EXOK plus memory effect;
4. provide valid stash target fields and check the stash snoop/Data Pull path;
5. add path-specific DCT/DMT/DWT observations and assertions;
6. add an atomic reference calculation and compare returned/or final data;
7. count Poison/DataCheck only at the destination and relabel them as
   transport tests;
8. force a genuine credit overdraft and make a missing error fatal;
9. include source identity in transaction keys;
10. gate semantic tests to actual RTL support and relabel unsupported rows;
11. add legal configuration runs for parity, RN-D, MPAM field width, and other
    default-disabled transport options;
12. enforce coverage merge and thresholds; and
13. run the complete Xcelium regression, archive logs, and update matrix
    statuses only from those results.

Until those actions are complete, the accurate project status is:

> UVM environment implemented and statically elaborated; behavioral
> verification and coverage sign-off pending.
