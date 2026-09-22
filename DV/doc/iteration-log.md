# CHI Interconnect DV — Iteration Log and Findings Register

Bring-up failures, each classified **TB bug** or **DUT bug**, with the fix applied.
Pre-simulation entries are findings by inspection (spec text vs. user-supplied RTL facts);
each is demonstrated (or refuted) by a simulation before the DV spec is finalized.

## DUT findings register

| ID | Finding | Spec basis | Evidence | TB strategy | Status |
|----|---------|------------|----------|-------------|--------|
| F-1 | Interface parity is **even** per byte; spec requires **odd** parity (check bit makes an odd number of 1s in the group). DataCheck is likewise specified as odd byte parity. | IHI0050H B9.3.1, B9.6 | User RTL reading (Q1): check bit = XOR of the byte; spec text quoted in Stage 0 closure | TB implements spec-odd parity. Default config runs `parityEn=0`. Directed parity test (a) drives spec-odd and expects `linkParityError` pulses — demonstrating F-1 at the boundary; (b) drives DUT-convention even parity with injected single-bit flips to prove the detection path works | Open — demonstrate in Stage 6 |
| F-2 | `TXSACTIVE` is driven by the fabric (to `resetn`) on every port; spec makes TXSACTIVE a node-side output indicating node protocol activity. | IHI0050H B14.7.2 | User RTL reading (Q7) | TB never drives `TXSACTIVE`; link reference model checks only `RXSACTIVE` (also DUT-driven = `resetn`) as a static out-of-reset indication. SACTIVE functional checking is reduced to "no X, constant high out of reset" | Open — waive ownership, log |
| F-3 | `linkUp[i]` reflects only the node→fabric (DUT receive) direction reaching RUN, not both directions. | IHI0050H B14.5/B14.6 (link activation is bidirectional; a "link up" indication conventionally covers both) | User RTL reading (Q8) | Scoreboard link model checks `linkUp[i]` against the TB's TX-link RUN state only; the fabric→node direction is checked separately via observed flit flow | Open — adjusted check |
| F-4 | `multiReqEn` is declared in `chi_cfg_t` but no logic references it: MultiReq is neither implemented nor rejected. | IHI0050H B13.9.1 (MultiReq/NumReq/CacheLineID) | User RTL reading (Q9) | TB always drives MultiReq=0; chiMultiReqTest stays feature-gated and reports SKIP; matrix row "Not verified — DUT ignores enable" | Open — documented limitation |
| F-5 | MN sends `SnpDVMOp` to **every** Requester including RN-I; RN-I has no SNP channel in the spec. Sending to the originator is legal (permitted, not required). | IHI0050H B13.6.1.3, B8.2.1 step 4 | User RTL reading (Q11); spec B8.2.1 step 4: "broadcasts to the remaining RN-F and RN-D nodes" | TB keeps the SNP link active on RN-I ports and answers `SnpDVMOp` there under a documented, counted waiver (`chiRequesterAgentConfig.allowRniDvmSnoop`, default 1 with UVM_WARNING per occurrence) so DVM tests run; a strict mode (0) reports UVM_ERROR | Open — waived, counted |
| F-6 | MN omits the DVMOp DBIDResp + 8-byte NonCopyBackWriteData phase (IDLE→snoop→Comp). Spec flow is Req → DBIDResp → NCBWrData → snoops → Comp. | IHI0050H B8.2.1 steps 2–3, B8.2.2 steps 2–3 | User RTL reading (Q11); spec text verified Stage 0 closure | TB Requester DVM flow has `expectDvmDbidResp` knob (default 0 = tolerate missing DBIDResp/data phase, counted warning); strict mode reports UVM_ERROR. TB still sends NCBWrData only after DBIDResp in strict mode; in tolerant mode it waits for Comp directly | Open — waived, counted |

## Environment log

| ID | Entry | Resolution |
|----|-------|------------|
| E-0 | No commercial simulator in this environment (`xrun`, VCS, Questa all absent); the mandated flow is Xcelium. | Xcelium Makefile/filelist/probe remain the authoritative deliverables (`DV/sim/xcelium/`). For local verification, `slang` 11.0.0 was built from source in-environment (g++ 13; the default `c++` is Clang 18 with a broken GCC-14 toolchain path, so the build uses `-DCMAKE_CXX_COMPILER=g++`). Validated 2026-09-22: `slang --relax-enum-conversions --top chi_interconnect_top -F chi_rtl/filelist.f` compiles and elaborates the whole DUT; `-F` resolves paths relative to the filelist's own directory (same semantics as xrun `-F`, confirms Q21). Two tool-compat notes, neither a DUT bug: slang is LRM-strict about `'{default:'0}` on a struct with an enum member (xrun accepts; waived locally by `--relax-enum-conversions`), and slang errors on the DUT's unconnected interface ports when elaborated without a testbench (resolved by `hdlTop` in Stage 1). HVL parse-checks use Accellera UVM sources. Local pass/fail evidence comes from slang elaboration; Xcelium runs remain the sign-off flow. Recorded in the DV spec §10. |

## Bring-up log (populated from Stage 1 onward)

| Date | Stage | Symptom | Classification | Root cause | Fix |
|------|-------|---------|----------------|------------|-----|
| — | — | — (no failures yet) | — | — | — |
