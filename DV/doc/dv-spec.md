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
| `topLifecycleModel` | Every requester TX request and subordinate RX request is outstanding until Comp, the expected data beats, and CompAck when `expCompAck` is set. An ordered read that completes or returns data before ReadReceipt is an error. The maps are empty at the end. |
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
| RespErr NDERR | `chiRespErrTest` | lifecycle still retires | — | Implemented — Xcelium pending |
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

## 5. Sign-off

`make -C DV/sim/xcelium compile` is the Xcelium elaboration. `make run
TEST=<name>` runs one test. Neither `xrun` nor any other simulator is
installed here. The local check is:

```
make -C DV/sim/xcelium check SLANG=/path/to/slang UVM_HOME=/path/to/uvm-core-2020.3.1
```

`check` elaborates `hdlTop` and `hvlTop` with slang. It does not execute
a test. A resized port connection fails the check.

## 6. Open items

No new assumption was added for stages 4–7. The citation index remains
`DV/doc/open-questions.md`.

Still open for an Xcelium run: NumDat is not decoded (Q8); the credit
equality check may be off by a pipeline beat and would then be loosened
to a warning; F-1 is demonstrated only when `parityEn` is 1.
