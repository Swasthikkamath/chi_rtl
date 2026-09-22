# Open questions

Stage 0 questions, with the answers that Stage 1 codes against.
Tags in the testbench use these numbers: `[ASSUMPTION:n]`.

## 1. `chi_if` members and orientation — CONFIRMED, corrected

`chi_if` carries the Issue H pin names, including a `*CHK` for every signal.
`TX/RX<channel>FLITCHK` is `ceil(width/8)` bits. The DUT drives every
single-bit `*CHK` to 0, including the node-side copies, so the testbench
does not drive those.

TX/RX names are from the external node's point of view. `*LCRDV` is driven
by the receiver of that channel: the DUT drives `TX*LCRDV`, and the node
drives `RX*LCRDV`.

Requester testbench drives: `TXREQ/RSP/DAT` `FLITPEND`, `FLITV`, `FLIT`,
`FLITCHK`; `RXRSP/DAT/SNP LCRDV`; `TXLINKACTIVEREQ`; `RXLINKACTIVEACK`;
`SYSCOREQ`.

Requester DUT drives: `RXRSP/DAT/SNP FLIT*`; `TXREQ/RSP/DAT LCRDV`;
`TXLINKACTIVEACK`; `RXLINKACTIVEREQ`; `SYSCOACK`; `TXSACTIVE`; `RXSACTIVE`;
`CLK`; `RESETn`; `TXSNPLCRDV` (held at 0); every 1-bit `*CHK`.

Subordinate testbench drives: `TXRSP/DAT FLIT*`; `RXREQ/RSP/DAT LCRDV`;
`TXLINKACTIVEREQ`; `RXLINKACTIVEACK`.

Subordinate DUT drives: `RXREQ/RSP/DAT FLIT*`; `TXRSP/DAT LCRDV`; the same
link, SACTIVE, `CLK`/`RESETn`, and 1-bit `*CHK` signals as on a requester port.

`TXSNP*` is tied to 0 on every port. `TXREQ*` is tied to 0 on subordinate
ports. `SYSCOACK` is a combinational copy of `SYSCOREQ` on every port class.
Subordinate `SYSCOREQ` is tied to 0.

## 2. CLK, RESETn, and SACTIVE — CONFIRMED, corrected

`chi_if` contains `CLK` and `RESETn`. `chi_link_port` drives them from the
top-level `clk` and `resetn`. The DUT also drives `TXSACTIVE` and
`RXSACTIVE`, each equal to `resetn`. The testbench drives none of these.
`chiClkRstBfm` drives only the module ports. BFMs sample `chiPort.CLK`.

This is a spec deviation: IHI 0050H B14.7.2 makes `TXSACTIVE` a node output.
The monitor records the values and does not try to drive them.

## 3. NodeID encoding — CONFIRMED, corrected

LSB-first field order is `{deviceId, devicePort, meshX, meshY}`
(MSB-first that reads `{meshY, meshX, devicePort, deviceId}`).

Each coordinate field is `clog2Min1(dim)` bits, minimum 1.
`deviceIdWidth = nodeIdW - yW - xW - portW`. The fields fill `nodeIdW`;
the identifier is not zero-extended inside `nodeIdW`.
`defaultNodeId` puts the node ordinal in `deviceId`. The testbench does
the same when it builds `NODE_IDS`.

For the default configuration the split is 11 = 2 + 2 + 1 + 6.

`nodeClass` 0..7 is RN-F, RN-D, RN-I, SN-F, SN-I, HN-F, HN-I, MN.
`nodeIndex` is the index inside that class.

`CHI_NODEID_SLOT_W` is 16, equal to `CHI_MAX_NODEID_W`. NodeIDs are
zero-extended into that slot. On a REQ flit, `tgtId` is packed at
`nodeIdW` bits.

## 4. Requester TgtID — CONFIRMED

`reqToNoc` writes the full NodeID into `tgtId`. DVMOp is redirected to the
MN and PrefetchTgt to the prefetch mapper; both are overwritten as well.
`PCrdReturn`, and any request with `AllowRetry == 0`, keeps the TgtID the
requester drove.

## 5. Flit layout — CONFIRMED, corrected

Pack order follows IHI 0050H B13.9.1 (REQ), B13.9.2 (RSP), B13.9.3 (SNP),
and B13.9.4 (DAT), from bit 0.

REQ inserts a 6-bit slot after `MultiReq`: `{3'b0, Size[2:0]}` when
`MultiReq` is 0, and `NumReq[5:0]` when it is 1. `Addr` follows that slot.

`dataCheckEn` and `poisonEn` default to 1. DAT then carries `dataW/8`
DataCheck bits and `dataW/64` Poison bits. Tag (`dataW/32`) and TU
(`dataW/128`) are always present, whatever `mteEn` is. PBHA is off by
default and is omitted.

On-wire widths stay fixed when `txnIdW`, `lpidW`, `ccidW`, or `groupIdW`
change. Those parameters size internal structures only. TxnID is 12,
the group/LPID slot is 8, CCID is 2, ReturnTxnID is 12, RSP DBID is 12,
DAT DBID is 16, DataSource is 8, and CacheLineID is 6 on RSP and DAT.
Opcode widths are REQ 7, RSP 5, SNP 5, DAT 4. `PAS` Non-secure is `3'b001`.

The 8-bit group slot is opaque. The DUT does not interpret LPID inside it,
and the exclusive monitor matches line address and requester NodeID only.
Two LPIDs on the same node collide in that monitor. That is a DUT finding.
The testbench does not expect them to stay separate, and it does not place
LPID in the low 5 bits.

## 6. Region attributes — CONFIRMED, with the bit-1 correction

`REGION_ATTRIBUTES` is `{kind[1:0], secureOnly, valid}`.

- `2'b00` hashes across HN-F and ignores `REGION_TARGET`.
- `2'b01` is a direct target.
- `2'b10` is MMIO, also direct.

`secureOnly` 1 rejects a PAS that `pasNonSecure()` treats as non-secure:
Non-secure, Realm, and Non-secure Protected. `secureOnly` 0 applies to
every PAS. Limits are inclusive. The first valid region in ascending index
order wins. An unmapped or rejected address produces no error response,
because `unmappedError` is not connected. Stimulus must not use those
addresses.

The default windows match the formulas in `chi_interconnect_top`: lower
half hashed to HN-F, the span up to `CFG_MMIO_BASE` direct to the first
HN-I, and the top window MMIO to that same HN-I. The testbench passes
those values with `USE_DEFAULT_REGIONS` 0 so it knows them by construction.

## 7. `CHI_CFG_DEFAULT` — CONFIRMED

Counts sum to 14: RN-F 4, RN-D 0, RN-I 1, SN-F 2, SN-I 1, HN-F 4, HN-I 1,
MN 1. The testbench reads the counts from the elaborated struct and does
not hard-code them. `+define+CHI_TB_*` can override individual fields.

## 8. Sentinel ports and L-Credits — CONFIRMED, with additions

An idle sentinel, such as `rnd[0]`, is driven only on the node-owned
signals from item 1, held inactive. No agent is bound to it.

The DUT advertises `max(lcrdDepth, 2)` credits per channel. The top
rejects `lcrdDepth` below 2, so a legal configuration advertises
`lcrdDepth`. Granting more than that fires `linkCreditError`. The
testbench treats `lcrdDepth` as a hard outstanding-credit cap.

The DUT raises its TX link (the node's `RXLINKACTIVEREQ`) as soon as reset
is released. The testbench acknowledges on the following clock.

The per-agent outstanding cap of 16 is independent of `posEntries`.

## 9. `filelist.f` — CONFIRMED, corrected

`filelist.f` is an xrun argument file. `chiFileList.f` references it with
`-F`, so paths inside it resolve from the `chi_rtl` directory regardless
of the launch directory. It is not a SystemVerilog `` `include ``.

Line 1 is a `#` comment. The file also compiles `rtl/top/*_compile.sv`
(harmless with an explicit `-top`) and the `rtl/sva/*` bind files, which
are active on every run. No `-incdir` is required for the DUT list.
The testbench adds one `-incdir` for `chiLinkLayerBfm.svh`.
