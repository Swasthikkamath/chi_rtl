# CHI interconnect DV specification

Black-box UVM testbench for `chi_interconnect_top`. The protocol model is
`chiGlobalsPkg`. It is checked against AMBA CHI Architecture Specification
ARM IHI 0050 Issue H (17 September 2025). Citations in the source use
`[SPEC:IHI0050H <section>]`. Nothing in this tree is a quotation of that
document.

The DUT checkout is compiled through its own filelist. This specification
does not describe DUT internals.

## 1. Architecture

Two tops. `hdlTop` instantiates the DUT, `chiClkRstBfm`, and one flat-port
driver BFM and monitor BFM per configured port. It publishes the virtual
BFM handles with `uvm_config_db` under path `*`. No class lives in `hdlTop`.

`hvlTop` imports `uvm_pkg` and `chiTestPkg` and calls `run_test()`. slang
does not make `export uvm_pkg::*` visible to a module, so the UVM import
is repeated there. A class never touches a pin. Proxies call BFM tasks
through virtual interfaces.

One requester agent covers RN-F, RN-D, and RN-I. One subordinate agent
covers SN-F and SN-I. The node class is a field of the agent config.
`holdQuiet` builds the driver, drives the pins to STOP, and does not
activate or accept sequences, so a passive port is not X.

`topEnv` builds `chiEnv`, `topScoreboard`, `topCoverage`, and
`chiVirtualSequencer`. Sequences state intent. The requester driver picks
the opcode from its cache model at issue time. The subordinate answers
whatever REQ arrives. No sequence predicts which home or subordinate a
request is routed to.

## 2. Reference models

Four models, each with its own state. None of them shares a map with a
driver. [ASSUMPTION:18]

| Model | What it checks |
| --- | --- |
| `topLinkModel` | Active ports reach TX and RX RUN. `linkUp` is compared with TX RUN only. At the end every TX link is STOP. Credit grants equal protocol flits plus L-Credit returns on active ports. Parity and credit pulses match the test's expect flags. A missing credit pulse is a warning. |
| `topLifecycleModel` | Every requester TX request and subordinate RX request is outstanding until Comp, the expected data beats, and CompAck when `expCompAck` is set. An ordered read that completes or returns data before ReadReceipt is an error. PrefetchTgt is counted, not tracked: it has no response, and its TxnID must be 0 and need not be unique. Error completions arriving at a requester are counted in total and by line. The maps are empty at the end. |
| `topDirectoryModel` | A snoop response without a remembered snoop is an error. A response of UC/UD, SD, UC-PD, or SD-PD claims unique for that line. A second owner is an error. UC and UD share one encoding. |
| `topMemoryModel` | Bytes are stored by address. A byte never written reads as `chiMemInitData`. The image changes only from subordinate RX write data, committed on Comp, and from WriteZero completions. WriteDataCancel does not commit. ReadNoSnp and ReadNoSnpSep data are compared. Coherent data and atomics are not. |

End-of-test checks run in `check_phase`. Deactivation L-Credit returns are
still in the monitor queues then, because the monitor proxy has stopped.
`tryGetFlitSample` and `tryGetLinkSample` pop them without waiting.
`check_phase` is a function and cannot call the blocking getters.

## 3. Tests

`chiBaseTest` raises an objection, calls `chiRun`, and drops it. The
default `chiRun` waits 1 us so link activation finishes before shutdown.
Traffic tests start `chiVirtualSeq` on `env.virtualSequencer`.

A gated test prints `` `uvm_info("SKIP", ..., UVM_NONE) `` and returns
when its enable is clear. It does not pass silently. `chiMultiReqTest`
always skips (F-4): the DUT ignores `multiReqEn` and the driver keeps
MultiReq at 0. `chiUnmappedTest` always skips (F-7) and does not drive
an undeliverable address.

Addresses stay inside the coherent window (`coherentLineAddr`). The
default node counts are numRnf 4, numRnd 0, numRni 1, numSnf 2, numSni 1,
numHnf 4, numHni 1, numMn 1.

| Test | Gate | Stimulus |
| --- | --- | --- |
| `chiLinkBringUpTest` | always | no flits; links activate and deactivate |
| `chiCoherentTrafficTest` | always | RN-F 0 ReadShared, ReadUnique, WriteBack |
| `chiSharedLineTest` | `NUM_RNF >= 2` | two RN-F ReadShared, then ReadUnique |
| `chiRetryStressTest` | always | subordinates retry once, then ReadNoSnp |
| `chiPassiveAgentTest` | `NUM_RNF >= 2` | RN-F 1 quiet; RN-F 0 ReadNoSnp |
| `chiRndReadTest` | `NUM_RND > 0` | RN-D 0 ReadNoSnp |
| `chiAtomicTest` | `atomicEn` | one atomic load |
| `chiDvmTest` | `dvmEn` | one DVMOp; `expectDvmDbidResp` stays 0 |
| `chiStashTest` | `stashEn` | StashOnceShared |
| `chiExclusiveTest` | `exclEn` | exclusive load then exclusive store |
| `chiCmoTest` | always | CleanShared, CleanInvalid, MakeInvalid |
| `chiWriteZeroTest` | always | WriteNoSnpZero then ReadNoSnp |
| `chiOrderTest` | always | ReadNoSnp with Order set |
| `chiRespErrTest` | always | subordinates answer NDERR |
| `chiPoisonTest` | `poisonEn` | WriteNoSnp with Poison set, then ReadNoSnp |
| `chiMteTest` | `mteEn` | ReadNoSnp with TagOp set |
| `chiPbhaTest` | `pbhaEn` | ReadNoSnp with PBHA set |
| `chiMpamTest` | `mpamEn` | ReadNoSnp with MPAM set |
| `chiMultiReqTest` | always SKIP (F-4) | no flits |
| `chiParityTest` | `parityEn` | odd parity on RN-F 0; expect `linkParityError` |
| `chiCreditErrorTest` | always | send without credit; missing pulse is a warning |
| `chiUnmappedTest` | always SKIP (F-7) | no flits |
| `chiDctTest` | `dctEn` and two RN-F | shared-line traffic |
| `chiDmtTest` | `dmtEn` | ReadNoSnp |
| `chiDwtTest` | `dwtEn` | WriteNoSnp |
| `chiRespShapeTest` | always | subordinates send DBIDResp + Comp and withhold ReadReceipt |
| `chiDataErrTest` | always | DERR on one line; reads that line and an untouched one |
| `chiPrefetchTest` | `NUM_SNF >= 1` | PrefetchTgt, then ReadNoSnp of the same line |
| `chiDataCorruptTest` | always | corrupt read data with RespErr OK; expects the checker to object |

Four of those exist because a check the testbench already made had never
been reached. `chiDataCorruptTest` is the only test whose pass condition
is that a model reported an error: the mismatch reports are demoted and
counted, and seeing none is the failure. It is what makes a clean run of
every other test mean something, because it is the only evidence that the
data comparison runs at all.

## 4. Feature matrix

A row is Verified only after a passing Xcelium run, a check that can
fail, and a covered bin. Xcelium has not been run in this environment
(Q20). Every row below is therefore **Implemented — Xcelium pending**.

| Feature | Test | Check | Coverage | Status |
| --- | --- | --- | --- | --- |
| Link bring-up | `chiLinkBringUpTest` | `topLinkModel` | link samples | Implemented — Xcelium pending |
| Coherent read / write-back | `chiCoherentTrafficTest` | lifecycle, directory | `topIssueCg` | Implemented — Xcelium pending |
| Shared line | `chiSharedLineTest` | directory unique owner | `topIssueCg` | Implemented — Xcelium pending |
| Retry | `chiRetryStressTest` | lifecycle empties after PCrdReturn | `topIssueCg` pcrdReturn | Implemented — Xcelium pending |
| Passive agent | `chiPassiveAgentTest` | quiet TX request count is 0 | — | Implemented — Xcelium pending |
| RN-D | `chiRndReadTest` | lifecycle | `topIssueCg` class RN-D | Implemented — Xcelium pending (SKIP at numRnd 0) |
| Atomics | `chiAtomicTest` | lifecycle; memory skips the compare | `topAtomicCg` when `atomicEn` | Implemented — Xcelium pending |
| DVM | `chiDvmTest` | lifecycle, F-6 tolerant | `topDvmCg` when `dvmEn` | Implemented — Xcelium pending |
| Stash | `chiStashTest` | lifecycle | `topStashCg` when `stashEn` | Implemented — Xcelium pending |
| Exclusive | `chiExclusiveTest` | lifecycle | `topExclCg` when `exclEn` | Implemented — Xcelium pending |
| CMO | `chiCmoTest` | lifecycle | `topIssueCg` | Implemented — Xcelium pending |
| WriteZero | `chiWriteZeroTest` | memory zeros then compares the read | `topIssueCg` | Implemented — Xcelium pending |
| Ordering | `chiOrderTest` | ReadReceipt before data and Comp | `topIssueCg` | Implemented — Xcelium pending |
| RespErr NDERR | `chiRespErrTest` | lifecycle still retires and the NDERR arrives at a Requester | `topCompletionCg`, `topReadDataCg` | Implemented — Xcelium pending |
| RespErr DERR, one line | `chiDataErrTest` | the error reaches that line's read and no other | `topCompletionCg`, `topReadDataCg` | Implemented — Xcelium pending |
| Subordinate response shapes | `chiRespShapeTest` | the separate pair was driven at least once | `chiSubordinateRespCg` shapeCx | Implemented — Xcelium pending |
| PrefetchTgt (F-13) | `chiPrefetchTest` | the hint reached an SN-F; the read after it completes | `topIssueCg` prefetch | Implemented — Xcelium pending |
| Data comparison is live | `chiDataCorruptTest` | fails when the corruption is *not* reported | — | Implemented — Xcelium pending |
| Snoops the DUT chose | all coherent tests | directory invariant | `topSnoopCg` | Implemented — Xcelium pending |
| Poison / DataCheck | `chiPoisonTest` | `expectPoison` / `expectDataCheck` | — | Implemented — Xcelium pending |
| MTE | `chiMteTest` | request completes with TagOp | `topMteCg` when `mteEn` | Implemented — Xcelium pending |
| PBHA | `chiPbhaTest` | request completes with PBHA | `topPbhaCg` when `pbhaEn` | Implemented — Xcelium pending |
| MPAM | `chiMpamTest` | request completes with MPAM | `topMpamCg` when `mpamEn` | Implemented — Xcelium pending |
| MultiReq | `chiMultiReqTest` | no stimulus (F-4) | absent | Implemented — Xcelium pending; SKIP, DUT ignores the enable |
| Parity (F-1) | `chiParityTest` | `expectParityError` | — | Implemented — Xcelium pending; needs `parityEn=1` |
| Credit error | `chiCreditErrorTest` | warning if no pulse | — | Implemented — Xcelium pending |
| Unmapped (F-7) | `chiUnmappedTest` | no stimulus | absent | Implemented — Xcelium pending; SKIP, would hang |
| DCT / DMT / DWT | `chiDctTest`, `chiDmtTest`, `chiDwtTest` | lifecycle | `topIssueCg` | Implemented — Xcelium pending |

Disabled-feature covergroups are package-scope types constructed in
`build_phase` only when the enable is set. `option.auto_bin_max = 0`
because slang rejects `ignore_bins = default`.

Coverage is split by who decided the thing being measured. `topIssueCg`
and the feature groups record what the testbench asked of the
interconnect, which is predictable and therefore weak evidence.
`topSnoopCg`, `topCompletionCg`, `topReadDataCg` and the subordinate
groups record what the interconnect chose to do about it: which snoops
it sent, how it ended each transaction, and what it forwarded
downstream. Those are the bins worth reading, because no sequence can
ask for them directly.

## 5. Sign-off

`make -C DV/sim/xcelium compile` is the Xcelium elaboration and `make run
TEST=<name>` runs one test. `make regress` runs every test over `SEEDS`,
which defaults to 1 2 3.

The regression does not keep its own list of tests. It derives one from
`chiTestPkg.sv`, which has to name every test anyway, so a test that
compiles is a test the regression runs and the two cannot drift.
`make testlist` prints it.

The verdict comes from `chiVerdict.sh` rather than from xrun's exit
status, which reports whether the simulator ran and not whether the test
passed. A log fails on a non-zero UVM_ERROR or UVM_FATAL count, on an
xrun error line, or on having no UVM report summary at all. The last one
matters most: a test that hung until the timeout, or died before
`run_test`, leaves a log with no errors in it, and treating that as a
pass would make the quietest failure the easiest to miss.

Neither `xrun` nor any other simulator is installed here. The local
check is:

```
make -C DV/sim/xcelium check SLANG=/path/to/slang UVM_HOME=/path/to/uvm-core-2020.3.1
```

`check` elaborates `hdlTop` and `hvlTop` with slang. It does not execute
a test. A resized port connection fails the check.

## 6. Open items

No new assumption was added for stages 4–9. The citation index remains
`DV/doc/open-questions.md`. F-13 to F-15, all testbench defects found by
the stage 9 audit, are in `DV/doc/iteration-log.md`.

Still open for an Xcelium run: NumDat is not decoded (Q8); the credit
equality check may be off by a pipeline beat and would then be loosened
to a warning; F-1 is demonstrated only when `parityEn` is 1.

One result of the audit is worth carrying forward as a rule. Three
sequences existed that no test ever started, and each of them was the
only thing that would have reached a check the testbench had already
been written to make. A checker nothing arms is indistinguishable from
a checker that works. Every check added from here should land with the
stimulus that reaches it, and where the check is the deliverable, with
a test that fails when it does not fire.
