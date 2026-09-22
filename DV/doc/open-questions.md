# CHI Interconnect DV — Open Questions and Assumptions Log

Status: **Stage 0 CLOSED — all 12 questions answered** (answers supplied by the user, read from the
RTL, 2026-09-22). Spec: ARM IHI 0050, **Issue H** (17 Sep 2025).

Permitted inputs (INPUT ISOLATION): `chi_rtl/rtl/top/chi_interconnect_top.sv` and the
AMBA CHI Architecture Specification only. No other repository file is read, listed, or
inferred from by the TB author. The answers below were provided by the user from the RTL
and are treated as confirmed `[ASSUMPTION:n]` resolutions.

Every resolved assumption is cited in TB source as `[ASSUMPTION:<n>]` with `See OPEN QUESTIONS`.
DUT-side problems uncovered by the answers are tracked in `iteration-log.md` (findings F-1…F-6).

## Resolution table

| # | Question (short form) | Resolution | Status |
|---|------------------------|------------|--------|
| 1 | chi_if signal inventory and names | All spec-named signals present, plus `CLK`/`RESETn`, plus per-byte parity: every signal has a `*CHK` companion; `TX/RX<x>FLITCHK` is `ceil(FLIT_W/8)` bits. No `*SHAREDCRD`/`*LCRDSHV` pins. TB drives only: `TX<x>FLITPEND/FLITV/FLIT`, `TX<x>FLITCHK` (only when `parityEn=1`), `TXLINKACTIVEREQ`, `RXLINKACTIVEACK`, `RX<x>LCRDV`, `SYSCOREQ`. DUT drives all single-bit `*CHK` pins to 0 — TB must not drive them (double-driver). `TXSNPFLIT*` unread on every port → TB ties it to 0. **DUT parity is EVEN per byte; spec B9.3.1 requires ODD → finding F-1.** | RESOLVED (default was wrong: parity pins exist) |
| 2 | TX/RX orientation on Subordinate ports | Confirmed: names are from the external node's perspective on every port. Requester ports: DUT receives REQ/RSP/DAT on `TX*`, transmits RSP/SNP/DAT on `RX*`; `RXREQ*` tied off. Subordinate ports: DUT receives RSP/DAT on `TX*`, transmits REQ/RSP/DAT on `RX*`; `TXREQ*` ignored (TB holds `TXREQFLITV=0`); `RXSNP*` tied off. `TXSNPLCRDV` driven to 0 on every port. | RESOLVED (default held) |
| 3 | NodeID encoding and helpers | Helpers are split: `chi_cfg_pkg` has `defaultMeshPlacement`, `nodeClassForOrdinal`, `nodeIndexForOrdinal`, placement/region types; `chi_pkg` has `defaultNodeId`, `encodeNodeId`, `deviceIdWidth`, `clog2Min1`, `nodeIdMeshX/Y/DevicePort/DeviceId`. Layout LSB-first `{meshY, meshX, devicePort, deviceId}`; `xW=clog2Min1(meshX)`, `yW=clog2Min1(meshY)`, `portW=clog2Min1(numDevPortsPerXp)` (each ≥1), `deviceIdWidth = nodeIdW − yW − xW − portW` (=6 for the DUT default 11-2-2-1). `defaultNodeId` sets `deviceId`=ordinal. `chi_node_class_e`: `NODE_RNF`=0 … `NODE_MN`=7. Elaboration checks run for every topology. `USE_DEFAULT_PLACEMENTS=1` only with 14 nodes. **TB decision: implement its own encoder from this confirmed formula (no `chi_pkg` import); use `chi_cfg_pkg` types + `chi_node_class_e` literals for placements; pass explicit `NODE_IDS`/`PLACEMENTS` with `USE_DEFAULT_PLACEMENTS=0`.** | RESOLVED (default was incomplete: deviceId field was missing) |
| 4 | TgtID interpretation | Confirmed: SAM overwrites TgtID except DVMOp→MN, PrefetchTgt→prefetch mapper; PCrdReturn and `AllowRetry==0` honor the driven TgtID and override the first two. Replays/PCrdReturn use the SrcID from RetryAck/PCrdGrant; driving 0 for mapped `AllowRetry==1` requests is fine. | RESOLVED (default held) |
| 5 | Flit layout options | `dataCheckEn=1` (DW/8) and `poisonEn=1` (DW/64) in `CHI_CFG_DEFAULT` — present by default. Tag (DW/32) and TU (DW/128) always present in DAT regardless of `mteEn`. PBHA: 4-bit REQ field when `pbhaEn=1`; in SNP/DAT it shares the FwdNID/HomeNID slots. MECID/StreamID share one REQ field (`mecEn && cdaEn` → fatal); MECID also in SNP/DAT when `mecEn=1`. Fixed slots: TxnID 12, ReturnTxnID 12, GroupID/LPID shared 8-bit slot, CCID 2, DataID 2, REQ Size/NumReq 6-bit slot, RSP DBID 12, DAT DBID 16. DUT pack order supplied by the user; **TB flit model is derived independently from B13.9/B13.10 and diffed (see below).** | RESOLVED (default was wrong: DataCheck/Poison/Tag/TU present) |
| 6 | REGION_TARGET semantics | Confirmed with one correction: attribute layout is `{kind[3:2], secureOnly[1], valid[0]}` — bit 1 is secure-only, not reserved. Kinds: HNF_HASH=00, DIRECT=01, MMIO=10. `CHI_NODEID_SLOT_W == CHI_MAX_NODEID_W == 16`. Target = Home Node's NodeID, ignored for HNF_HASH. Limit is **inclusive**; first matching region in ascending order wins; a secure-only match from an NS request returns unmapped (no fall-through). | RESOLVED (default held, secureOnly added) |
| 7 | CLK/RESETn, SACTIVE, SYSCO ownership | `chi_if` has `CLK`/`RESETn`, both driven by the DUT from the top-level `clk`/`resetn`; BFMs sample `chiPort.CLK`. **DUT drives both `TXSACTIVE` and `RXSACTIVE` to `resetn` — TB must not drive `TXSACTIVE` (spec makes it a node output → finding F-2).** `SYSCOACK` is a combinational copy of `SYSCOREQ` on every port class; TB drives `SYSCOREQ` on RN-F (optionally RN-D), ties 0 elsewhere. Fabric raises its own TX link (`txActivate = resetn`) and never deactivates while out of reset. | RESOLVED (default was wrong: CLK/RESETn exist and are DUT-driven; TXSACTIVE not TB-driven) |
| 8 | linkUp / error outputs | `linkUp[i]` = OR of the DUT's **receive**-channel states being RUN (node→fabric direction only), level; HN-F/HN-I/MN bits read 0 (**direction asymmetry → finding F-3**). `linkParityError` = registered one-cycle pulse per mismatching flit, only when `parityEn=1`. `linkCreditError` = combinational pulse on credit overflow/underflow. Neither is sticky → the monitor latches them. | RESOLVED (default was wrong: single direction, pulsed) |
| 9 | Issue-H transaction support | PrefetchTgt: supported. Write+CMO (`Write*CleanSh/CleanInv/PerSep/PoPA`): supported. WriteZero: `WriteUniqueZero`/`WriteNoSnpZero` handled in HN-F. **MultiReq: `multiReqEn` exists in `chi_cfg_t` but no logic references it — silently ignored (finding F-4); MultiReq test stays gated to SKIP and TB always drives MultiReq=0.** | RESOLVED (corrected: Write+CMO/WriteZero supported; MultiReq inert) |
| 10 | APB tie-off | Confirmed: with APB not selected, `PRDATA=0`, `PREADY=1`, `PSLVERR=PSEL&PENABLE`; tying PSEL=0 is benign. | RESOLVED (default held) |
| 11 | Snoops to RN-I/RN-D, DVM flow | MN sends `SnpDVMOp` sequentially to **every** Requester including RN-I and the originator, two flits each, waiting per response. Sending to the originator is legal (B8.2.1 step 4: permitted, not required). **Sending to RN-I violates B13.6.1.3 (RN-I has no SNP channel) → finding F-5; TB waives with a counted warning so DVM tests can run.** MN has **no DBIDResp/NCBWrData phase** (IDLE→snoop→Comp); B8.2.1/B8.2.2 steps 2–3 require DBIDResp + 8-byte NonCopyBackWriteData → **finding F-6**; TB Requester tolerates (config knob, documented). MN payload bit layout is a local choice → TB does not over-check SnpDVMOp payload fields. MN returns NDERR for DVM types above Sync → TB expects NDERR there. | RESOLVED (default held with major extra detail) |
| 12 | Region 3 inert | Corrected: region 3 is inert because its attributes default to `'0` (`valid=0`), not because base ≥ limit. With `valid=1`, `base == limit` matches exactly one address (inclusive limit). Default map: R0 HNF_HASH `[0, 2^(addrW−1)−1]`; R1 DIRECT→HN-I `[2^(addrW−1), MMIO_BASE−1]`; R2 MMIO→HN-I top 4 KiB. | RESOLVED (corrected mechanism) |

## Independent flit-layout diff (Q5 follow-up, TB side of the independent check)

The TB flit model is derived from the IHI 0050H B13.9 tables and cross-checked against the
spec's own total-width formulas, not from the DUT's pack order:

- **REQ**: the B13.9.1 total `(93+RAW+…) … (120+RAW+…)` forces exactly 72 fixed bits + 3·NodeID
  + RAW (both anchors, N=7 and N=16, give 72). That admits exactly **one** 8-bit slot between
  SnpAttr and Excl — the slot shared by DoDWT / PGroupID / StashGroupID / TagGroupID / LPID.
  This matches the DUT's stated "GroupID/LPID shared 8-bit slot". Per-opcode interpretation of
  the slot is taken from B13.10 field definitions in Stage 1. No flit-layout finding.
- **RSP**: field order and widths sum to T=71 at N=7 and T=89 at N=16 — matches B13.9.2.
- **SNP**: sums to S=53+SAW at N=7 — matches B13.9.3 (FwdNID shares PBHA; FwdTxnID shares
  StashLPID/VMIDExt).
- **DAT**: the DUT's field list sums to exactly D=240 at DW=128/N=7 and 267 at N=16, 389/416 at
  DW=256, 687/714 at DW=512 — matches B13.9.4, with Tag/TU unconditional and DataCheck/Poison
  appended per `dataCheckEn`/`poisonEn`. HomeNID shares {MismatchedMECID, PBHA[3:0]}; DataSource
  byte shares FwdState for DCT.

## Confirmed facts read from `chi_interconnect_top.sv` (Stage 0, unchanged)

- Node ordinal map: RN-F, RN-D, RN-I, SN-F, SN-I, HN-F, HN-I, MN (`OFF_*` localparams). `[TOP:OFF_*]`
- `chi_if` arrays sized `max(count,1)`; no link layer for a zero-count class. `[TOP:ports]`
- REQ routing: SAM(address, PAS.NS), overridden by DVM→MN, PrefetchTgt→prefetch mapper,
  PCrdReturn or `AllowRetry==0` → TgtID; `reqToNoc` rewrites `tgtId`. `[TOP:reqToNoc]`
- HN-F *i* ↔ SN-F (*i* mod numSnf); HN-I *i* ↔ SN-I (*i* mod numSni). `[TOP:hnf_nodes/hni_nodes]`
- Default regions and attribute layout. `[TOP:makeRegion*]` (attribute bit 1 = secureOnly per Q6)
- `USE_DEFAULT_PLACEMENTS=1` requires `NUM_NODES==14`; placement/NodeID checks for all topologies. `[TOP:cfg_check]`
- Legal ranges: dataW ∈ {128,256,512}; rsvdcW ∈ {0,4,8,12,16,24,32}; mpamW ∈ {0,12,15};
  mecEn⊕cdaEn; lcrdDepth ≥ 2; interleaveGranule ≥ 64 pow2; numIfPerNode == replChannels == 1. `[TOP:cfg_check]`
- Flit totals inside Issue H ranges. `[TOP:cfg_check]`
