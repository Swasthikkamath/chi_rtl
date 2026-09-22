# CHI Interconnect DV - Open Questions and Assumptions Log

This file is the single register of everything the testbench could not read from
its two permitted inputs. Every entry has a number, the reason it matters, the
default the testbench will take if the question is not answered, and a status.

Permitted inputs (INPUT ISOLATION), as widened by the user on 2026-09-22:

1. `chi_rtl/rtl/top/chi_interconnect_top.sv` — port list, parameters and body.
2. The `chi_cfg_pkg::chi_cfg_t` declaration and `CHI_CFG_DEFAULT`. Widened per
   the Q15 recommendation: these are types and values, not behaviour, and four
   of the fields the top module never references (`dataCheckEn`, `poisonEn`,
   `parityEn`, `mteEn`) change the DAT flit width, so the flit model cannot be
   built without them.
3. The AMBA 5 CHI Architecture Specification, ARM IHI 0050. See Q19 for the
   issue actually available to this run.
4. **Compiling** the real RTL through its own `filelist.f`, per the Q20
   decision. Compiling is not reading: an elaboration error, a bus width or a
   configuration constraint reported by the compiler is boundary information,
   and it is how several entries below were answered.

Nothing else in the DUT repository has been opened. `rtl/if/`, `rtl/pkg/`
beyond the two items named above, `rtl/link/`, `rtl/noc/`, `rtl/sam/`,
`rtl/hnf/`, `rtl/hni/`, `rtl/mn/`, `rtl/sva/`, the other files under
`rtl/top/`, `DV/`, `tb/`, `doc-src/` and `docs/` are unread. `filelist.f` is
read only as a list of file names, by the Makefile, never by a person.

Status values: `OPEN` (blocking, default in use), `CONFIRMED` (answered, now an
`[ASSUMPTION:n]` tag in source), `CLOSED` (answered and no longer an
assumption, replaced by a `[TOP:...]` or `[SPEC:...]` tag).

**2026-09-22 — second RTL answer round.** The user re-read the RTL on `main`
and confirmed most of the first round. Four entries moved: **Q5** (the DUT's
default NodeID table is legal only up to 14 nodes, and only under geometry
constraints), **Q11** (`unmappedError` is unconnected → finding **F-7**),
**Q15** (isolation widened to the `chi_cfg_t` declaration and
`CHI_CFG_DEFAULT`, with the full default table now recorded under Q12) and
**Q21** (the design's `filelist.f` needs sanitising before `xrun` reads it).
Q18, Q18a, Q19 and Q20 were decisions rather than facts and are recorded with
the choice made. Compiling the RTL at swept configurations, which Q20 allows,
added findings **F-8** (`numMn = 0` indexes out of range), **F-9** (`mpamW`
sizes nothing) and **F-10** (18 flit bits the model could not name).

**2026-09-22 — the specification is now a file, not a memory.** Acting on the
Q19 recommendation, ARM IHI 0050 Issue H was fetched into `DV/doc/spec/` (by
a committed script; the Arm-copyright PDF itself is not committed). Reading
the real tables settled three things that were being carried on recollection:
**F-10 is closed** — all eighteen bits were fields the testbench had missed,
not bits the DUT adds, and every channel's field list now sums exactly to its
measured bus width; **F-1 is confirmed**, B9.3.1 requires odd parity where the
DUT generates even; and **F-6 is confirmed**, B8.2.1 and B8.2.2 both require
the DBIDResp and write-data phase the MN skips, so a specification-compliant
Requester really does stall and the tolerant mode is mandatory rather than
lenient. One new deviation came out of the same reading: **F-11**, the DUT
drives the node-side single-bit `*CHK` companions that Table B9.18 assigns to
the node.

**2026-09-22 — Stage 0 closure update.** All 21 items are resolved: the user
supplied answers read from the RTL for the twelve-question Stage 0 register
this run originally posted (mapping table at the bottom), and the
register-specific items are resolved from the Issue H specification text
obtained by this run (Q19) or adopted as stated (marked ADOPTED). DUT-side
problems uncovered by the answers are tracked as findings F-1…F-6 in
`iteration-log.md`. Per-question `Status` lines were updated in place.

---

## Process blockers

These two decide whether the deliverable can be demonstrated rather than only
reviewed, and what a protocol citation is allowed to look like. They are listed
first because every later stage inherits the answer.

### Q19. Which CHI specification issue is actually available, and is citation from knowledge acceptable?

**Why it matters.** Every flit field order, opcode encoding, response encoding
and cache-state encoding in `chiGlobalsPkg` is a numeric constant that must be
bit-exact with the DUT for any traffic at all to flow. The rules require a
`[SPEC:IHI0050H <section>]` tag on each one.

**Resolution (2026-09-22).** A full text rendering of the official document is
in hand: **ARM IHI 0050, Issue H, date of issue 17 Sep 2025** (eleventh public
release, non-confidential), including the B13.9 flit tables, the B13.10 field
definitions, the B9 error/parity sections, the B8 DVM flows and the B14 link
handshake. All `[SPEC:IHI0050H …]` citations are from the document, not from
trained knowledge. The original default's precautions are still adopted: every
numeric encoding lives exactly once in `chiGlobalsPkg` with one
`traceability.md` row per constant, and citations use the part-prefixed form
(`B13.9.1`) matching the DUT's own comment style. Status: **CLOSED**.

**Second round (2026-09-22): the PDF is in the workspace.** The user's first
preference was to drop the Issue H PDF in if possible, because citing
encodings from recollection is riskiest exactly where it matters. It was
possible: Arm's documentation service serves IHI 0050 Issue H as a free
non-confidential download, and `DV/doc/spec/fetchSpec.sh` retrieves it and
renders it to text. The PDF itself is not committed — it is Arm copyright and
free to download but not ours to redistribute — so the script is committed
instead and the artefacts are ignored, which keeps the input reproducible
without republishing it.

This is not a formality. Reading the real B13.6 to B13.9 tables closed
finding F-10 outright (Q7), confirmed the parity polarity behind F-1 (Q17),
and confirmed the DVM DBIDResp requirement behind F-6 (Q14) — three things
that were being carried on recollection. The fallback plan still applies to
what has not been diffed yet: every numeric encoding lives once in
`chiGlobalsPkg`, flagged `Q19`, and the opcode and Resp tables get a line-by-
line diff against B13.8 and B13.10 before Stage 5.

### Q20. There is no simulator in this environment. What counts as "must elaborate" and "must pass"?

**Why it matters.** Stage 1 is required to elaborate and Stage 5 is required to
pass `chiLinkBringUpTest` and `chiCoherentTrafficTest`.

**What this run has.** No `xrun`, `xmvlog`, `xmelab`, `vcs`, `vlog`,
`verilator` or `iverilog` on `PATH`, no `/opt/cadence` or equivalent tool tree,
and no licence server. Xcelium cannot be installed here.

**Resolution (2026-09-22).** No simulator is installed and Xcelium cannot be
installed here, so the Xcelium flow in `DV/sim/xcelium/` remains the sign-off
flow, with its results pending a licensed machine. Local checking uses `slang`,
built from source in this environment (cmake/g++ available), in two passes that
never read the DUT sources: (a) full elaboration of `hdlTop` + the DUT,
compiled exactly as the Xcelium flow compiles it — by referencing the
repository's `filelist.f` from `chiFileList.f` (Q21); (b) parse/compile of the
HVL side against the Accellera UVM sources fetched from their public
repository. No stand-in packages are built: the real `chi_cfg_pkg` and `chi_if`
are compiled from the DUT filelist without being opened. Each stage states
which checks ran and which are pending Xcelium. Status: **CLOSED** (process
adopted; Xcelium sign-off pending).

**Second round (2026-09-22): confirmed, and this is where most of the round's
findings came from.** The decision not to build stand-in `chi_cfg_pkg` and
`chi_if` files is the right one for the reason given — a wrong stand-in hides
the mismatches the exercise is meant to find — and no stand-in exists.
Verilator is not installed in this image, so slang is the local elaborator;
the RTL's Verilator-cleanliness carries over, with one waiver
(`--relax-enum-conversions`, a tool strictness difference rather than a DUT
defect) recorded in `iteration-log.md`.

Compiling rather than reading turned out to be the most productive input of
the round. Sweeping configurations and reading the resulting bus widths gave
every flit-width coefficient (Q7); sweeping node counts found F-8; sweeping
`mpamW` found F-9. None of that is visible in the port list, and none of it
required opening a DUT source file.

---

## Node interface and link layer

### Q1. `chi_if` member names, parameterization, and TX/RX orientation on each port class

**Why it matters.** Every BFM task references these signals directly. Nothing
in the testbench can be written without them.

**What the top module gives.** The ports are declared `chi_if rnf [...]`,
`chi_if rnd [...]`, `chi_if rni [...]`, `chi_if snf [...]`, `chi_if sni [...]`,
so all five classes use the same interface type. Each element is handed whole to
`chi_link_port` as `.chiPort(PORT[i])`, and `chi_link_port` is parameterized
`#(.CFG(CFG), .REQUESTER_PORT(IS_REQUESTER))` with `IS_REQUESTER` set to 1 for
`rnf`, `rnd`, `rni` and 0 for `snf`, `sni`. On a requester port the DUT consumes
REQ and produces SNP, RSP and DAT; on a subordinate port the DUT produces REQ
and consumes RSP and DAT, and the SNP direction is unused
(`snpOutReady = 1'b1`, `snpInValid = 1'b0`). The DUT never accepts an SNP flit
from any external port. The interface declaration itself is in `rtl/if/`, which
is unread.

**Default.** `chi_if` is parameterized `#(parameter chi_cfg_pkg::chi_cfg_t CFG =
chi_cfg_pkg::CHI_CFG_DEFAULT)` and `hdlTop` instantiates every array with the
same `CHI_CFG` it passes to the DUT. Members carry the IHI 0050 pin names from
the **node's** point of view on every port class, so `TX*` is node-to-
interconnect and `RX*` is interconnect-to-node on subordinate ports as well as
requester ports, and the port class only changes which bundles are in use:

| bundle | requester port | subordinate port |
| --- | --- | --- |
| `TXREQFLITPEND`, `TXREQFLITV`, `TXREQFLIT`, `TXREQLCRDV` | node sends REQ | unused |
| `RXREQFLITPEND`, `RXREQFLITV`, `RXREQFLIT`, `RXREQLCRDV` | unused | node receives REQ |
| `TXRSPFLITPEND`, `TXRSPFLITV`, `TXRSPFLIT`, `TXRSPLCRDV` | node sends RSP | node sends RSP |
| `RXRSPFLITPEND`, `RXRSPFLITV`, `RXRSPFLIT`, `RXRSPLCRDV` | node receives RSP | node receives RSP |
| `TXDATFLITPEND`, `TXDATFLITV`, `TXDATFLIT`, `TXDATLCRDV` | node sends DAT | node sends DAT |
| `RXDATFLITPEND`, `RXDATFLITV`, `RXDATFLIT`, `RXDATLCRDV` | node receives DAT | node receives DAT |
| `RXSNPFLITPEND`, `RXSNPFLITV`, `RXSNPFLIT`, `RXSNPLCRDV` | node receives SNP | unused |
| `TXSNPFLITPEND`, `TXSNPFLITV`, `TXSNPFLIT`, `TXSNPLCRDV` | unused | unused |

In each bundle `*LCRDV` is driven by the receiver of that bundle, so the
testbench drives `RXREQLCRDV` on a subordinate port and `RXRSPLCRDV`,
`RXDATLCRDV`, `RXSNPLCRDV` on a requester port, and observes `TX*LCRDV`.
Activation uses `TXLINKACTIVEREQ`, `TXLINKACTIVEACK`, `RXLINKACTIVEREQ`,
`RXLINKACTIVEACK`.

**Fallback if wrong.** The alternative encoding is that the names are fixed from
the interconnect's point of view, which swaps every `TX`/`RX` prefix on the two
subordinate arrays. The BFMs therefore reach the interface through one macro pair
per channel so that the orientation is a single edit, not a rewrite.

**Resolution (2026-09-22, user from `rtl/if/chi_if.sv` and `chi_link_port.sv`).**
The default held, with additions. Every listed signal exists under its spec
name; `CLK`/`RESETn` are also members (Q2); **every signal has a `*CHK`
companion** — `TX/RX<x>FLITCHK` is `ceil(FLIT_W/8)` bits, one per byte — and
there are no `*SHAREDCRD`/`*LCRDSHV` pins. The TB drives only
`TX<x>FLITPEND/FLITV/FLIT`, `TX<x>FLITCHK` (only when `parityEn=1`),
`TXLINKACTIVEREQ`, `RXLINKACTIVEACK`, `RX<x>LCRDV` and `SYSCOREQ`; the DUT
drives every single-bit `*CHK` pin to 0, so the TB must not drive those (double
driver). `TXSNPFLIT*` is unread on every port and is tied to 0; `TXSNPLCRDV` is
driven to 0 by the DUT. Orientation is the node's perspective on all five port
classes: on requester ports the DUT receives REQ/RSP/DAT on `TX*` and transmits
RSP/SNP/DAT on `RX*` with `RXREQ*` tied off; on subordinate ports the DUT
receives RSP/DAT on `TX*` and transmits REQ/RSP/DAT on `RX*`, with the TB
holding `TXREQFLITV=0` and `RXSNP*` tied off. The DUT's parity is **even** per
byte; IHI 0050H B9.3.1 requires **odd** → finding **F-1**. The
macro-pair-per-channel fallback is kept anyway so any residual naming surprise
is a single edit. Status: **CONFIRMED** → `[ASSUMPTION:1]`.

### Q2. Does `chi_if` carry `CLK`/`RESETn`, and who drives them?

**Why it matters.** Two drivers on a clock is an X; no driver is no clock.

**What the top module gives.** `clk` and `resetn` are scalar module inputs and
are passed to `chi_link_port` separately from `.chiPort`, so the DUT does not
need a clock from inside `chi_if`.

**Default.** `chi_if` may contain `CLK` and `RESETn` members but the DUT does
not drive them. `chiClkRstBfm` is the only clock and reset source: it drives the
DUT's `clk`/`resetn` ports, and if the interface has `CLK`/`RESETn` members
`hdlTop` drives them from the same source. All BFMs sample and drive on the same
`clk`.

**Resolution (2026-09-22, user from `chi_link_port.sv`).** The default is
corrected: `chi_if` **does** contain `CLK` and `RESETn`, and the **DUT drives
both** from the top-level `clk`/`resetn`. `chiClkRstBfm` still owns only the
top-level `clk`/`resetn` ports; the TB never drives the interface members, and
every BFM samples `chiPort.CLK` / qualifies on `chiPort.RESETn`. Status:
**CONFIRMED** → `[ASSUMPTION:2]`.

### Q3. `TXSACTIVE` / `RXSACTIVE` ownership per port class

**Resolution (2026-09-22, user from `chi_link_port.sv`).** The default is
corrected: the **DUT drives both `TXSACTIVE` and `RXSACTIVE` to `resetn`** on
every port, so the TB must not drive `TXSACTIVE` at all. IHI 0050H B14.7.2 makes
TXSACTIVE a node output indicating node protocol activity, so the DUT driving
the node-side signal is a deviation — logged as finding **F-2** and waived: the
link reference model checks `RXSACTIVE` only as a static out-of-reset
indication and never waits on SACTIVE for progress. Status: **CONFIRMED** →
`[ASSUMPTION:3]`.

### Q4. `SYSCOREQ` / `SYSCOACK` presence and ownership per port class

**Resolution (2026-09-22, user from `chi_link_port.sv`).** `SYSCOACK` is a
**combinational copy of `SYSCOREQ` on every port class**. The TB drives
`SYSCOREQ` on RN-F ports (RN-D optional, config-controlled) and ties it to 0 on
RN-I, SN-F and SN-I. Because the ACK is a pure copy, the planned "ACK without
REQ" finding cannot fire and is dropped; the coherency check that remains is
the spec one — a snoop arriving at an RN-F before it asserted `SYSCOREQ` (or
after deassertion) is a DUT error. Status: **CONFIRMED** → `[ASSUMPTION:4]`.

### Q5. Which NodeID values are legal, and how is a NodeID constructed?

**Why it matters.** `SrcID` on every testbench-driven flit, and `TgtID` on the
exceptional cases in Q6, must be a legal NodeID under the DUT's encoding.

**What the top module gives.** `NODE_IDS` is
`logic [chi_cfg_pkg::CHI_MAX_NODEID_W-1:0] [NUM_NODES-1:0]` with an all-ones
sentinel that means "use `defaultNodeId(CFG, ordinal)`". The elaboration check
requires, for every ordinal: a valid placement,
`placement.nodeClass == nodeClassForOrdinal(CFG, i)`,
`int'(placement.nodeIndex) == nodeIndexForOrdinal(CFG, i)`,
`meshX`/`meshY`/`devicePort` inside `CFG.meshX`/`CFG.meshY`/
`CFG.numDevPortsPerXp`, agreement between the placement coordinates and
`nodeIdMeshX/nodeIdMeshY/nodeIdDevicePort(CFG, NODE_IDS[i])`, globally unique
NodeIDs, and no two nodes on the same `(meshX, meshY, devicePort)`. So a NodeID
embeds its routing coordinates, and `defaultNodeId` is the only constructor the
top module names.

**Default.** The testbench never invents a NodeID. `chiGlobalsPkg` materialises
`NODE_IDS[i] = defaultNodeId(CHI_CFG, i)` for all ordinals and derives each
placement from the NodeID it just built:

```
placement.valid      = 1'b1
placement.nodeClass  = nodeClassForOrdinal(CHI_CFG, i)
placement.nodeIndex  = nodeIndexForOrdinal(CHI_CFG, i)
placement.meshX      = nodeIdMeshX(CHI_CFG, NODE_IDS[i])
placement.meshY      = nodeIdMeshY(CHI_CFG, NODE_IDS[i])
placement.devicePort = nodeIdDevicePort(CHI_CFG, NODE_IDS[i])
```

with `USE_DEFAULT_PLACEMENTS = 1'b0` so the explicit array is the one used. This
satisfies every check by construction for any configuration, not only the
14-node default, and it makes the whole NodeID table a testbench-side constant.
Illegal-NodeID stimulus is out of scope.

**Resolution (2026-09-22, user from `chi_pkg.sv` / `chi_cfg_pkg.sv`).** The
helpers are split across two packages: `chi_cfg_pkg` holds
`defaultMeshPlacement`, `nodeClassForOrdinal`, `nodeIndexForOrdinal` and the
placement/region types; `chi_pkg` holds `defaultNodeId`, `encodeNodeId`,
`deviceIdWidth`, `clog2Min1` and `nodeIdMeshX/Y/DevicePort/DeviceId`. The NodeID
layout is LSB-first **`{meshY, meshX, devicePort, deviceId}`** with
`xW = clog2Min1(meshX)`, `yW = clog2Min1(meshY)`,
`portW = clog2Min1(numDevPortsPerXp)` (each at least 1) and
`deviceIdWidth = nodeIdW − yW − xW − portW` (6 bits in the DUT default
11-2-2-1); `defaultNodeId` sets `deviceId` to the node ordinal.
`chi_mesh_placement_t.nodeClass` is `chi_node_class_e` with `NODE_RNF`=0 …
`NODE_MN`=7, and the elaboration checks run for **every** topology, not only
MESH_2D. **TB decision:** rather than importing `chi_pkg` (the DUT's protocol
package — the TB protocol model must stay independent of it), `chiGlobalsPkg`
implements its own `tbEncodeNodeId()` from this confirmed formula with
`deviceId = ordinal`, and builds placements from
`chi_cfg_pkg::chi_mesh_placement_t` and `chi_node_class_e` literals. The DUT's
own elaboration checks then independently verify the TB table (routing fields
vs placement, uniqueness, no collisions) — if the TB encoder ever drifted from
`defaultNodeId`, elaboration fails loudly. `USE_DEFAULT_PLACEMENTS=0` with
explicit `PLACEMENTS` for any node count. Status: **CONFIRMED** →
`[ASSUMPTION:5]`.

**Second round (2026-09-22).** The layout is re-confirmed, and the caution
about the DUT's default table is noted but does not apply here.
`defaultMeshPlacement` is defined only for ordinals 0 to 13; ordinal 14 and
above returns `'0` with `valid = 0`, so any configuration over 14 nodes that
derived its placements from `defaultNodeId` would collide at (0,0,0). It also
needs `meshX >= 3`, `meshY >= 3`, `numDevPortsPerXp >= 2` and
`deviceIdWidth >= 4` for the 14-node case, in every topology including
CROSSBAR and RING.

The testbench never reads that table. `chiGlobalsPkg` computes its own
placement for every ordinal — device port varying fastest, then mesh X, then
mesh Y — and encodes the matching NodeID with the confirmed LSB-first layout,
so the assignment is a bijection at any node count the geometry can hold and
the 14-node ceiling is not inherited. Two differences from `defaultNodeId` are
deliberate: device IDs start at 1, so that NodeID 0 stays reserved and an
unmapped request routed to target 0 is distinguishable from a delivery to a
real node (finding F-7); and placements are built directly rather than decoded
back out of the NodeID. `hdlTop` checks the geometry capacity and the device
field width at elaboration, and the NodeID and placement tables for collisions
at time 0, on top of the DUT's own checks.

### Q6. How is `TgtID` on a Requester REQ flit interpreted?

**What the top module gives.** This one is readable. Per requester port the top
module unpacks the incoming REQ, and `reqToNoc` **overwrites** `request.tgtId`
with the routing target before the flit enters the NoC. The routing target is
the address-mapper output, except that `DVMOp` goes to the MN, `PrefetchTgt`
goes to the prefetch mapper's SN-F, and `PCrdReturn` or any request with
`allowRetry == 0` uses the `tgtId` the Requester supplied.

**Default.** The requester driver drives `tgtId = '0` on an ordinary
`allowRetry == 1` request, drives the `srcId` captured from the `RetryAck` on a
replay with `allowRetry == 0`, and drives the granting Home's NodeID on
`PCrdReturn`. The lifecycle reference model never checks `TgtID` on a request
and never predicts which Home or Subordinate a request reaches. Status:
**CLOSED** — re-confirmed 2026-09-22 by the user from
`chi_interconnect_top.sv:188, 511-529`: the SAM overwrites TgtID except
DVMOp→MN and PrefetchTgt→prefetch mapper, and PCrdReturn / `AllowRetry==0`
honor the driven TgtID, overriding the other two exceptions. No assumption
needed; cited as `[TOP:reqToNoc, requester_sam]`.

### Q7. Flit field order and optional-field placement

**Why it matters.** The testbench owns its flit model, so a packing mismatch
stops all traffic. The configurable widths make the optional-field positions the
risky part, not the field list.

**What the top module gives.** Field widths and presence follow `CFG.addrW`,
`dataW`, `nodeIdW`, `txnIdW`, `lpidW`, `ccidW`, `groupIdW`, `rsvdcW`, `mpamW`,
`mpamEn`, `mecEn`, `cdaEn`, and the width functions `reqFlitWidth`,
`rspFlitWidth`, `snpFlitWidth`, `datFlitWidth`. The elaboration check bounds
them: REQ within `[93 + addrW, 120 + addrW + CHI_MAX_RSVDC_W + CHI_MPAM_W +
CHI_PBHA_W + 1 + CHI_STREAMID_W]`, RSP within `[71, 89]`, SNP within
`[53 + addrW - 3, 71 + addrW - 3 + CHI_MPAM_W + CHI_MECID_W]`, DAT at least
`240 + ((dataW - 128) * 149) / 128`, and the comment ties the field list to
`B13.9`. `MECID` and `StreamID` share one REQ field of width `max(E, R)`, which
is why `mecEn && cdaEn` is illegal. SNP carries `addrW - 3` address bits and no
`TgtID`.

**Default.** Pack each flit LSB-first in the order the Issue H `B13.9` field
table lists, omitting any field whose configured width is zero, keeping the
shared `MECID`/`StreamID` field at a single position sized `max(CHI_MECID_W,
CHI_STREAMID_W)`, and leaving optional fields at the position the table gives
rather than appending them. `chiGlobalsPkg` asserts its own computed widths
against `reqFlitWidth(CHI_CFG)` and friends at elaboration, so a field-list
drift is caught before any test runs rather than appearing as random data
corruption.

**Resolution (2026-09-22, user from `chi_pkg.sv`, cross-checked against the
B13.9 tables obtained in Q19).** Optional-field presence is now known:
`CHI_CFG_DEFAULT` has `dataCheckEn=1` (DW/8 bits) and `poisonEn=1` (DW/64 bits);
DAT Tag (DW/32) and TU (DW/128) are **always present** whatever `mteEn` is; PBHA
is a 4-bit REQ field when `pbhaEn=1` and shares the FwdNID/HomeNID slots in
SNP/DAT; MECID/StreamID share one REQ field (`mecEn && cdaEn` is an elaboration
fatal) and MECID also appears in SNP and DAT when `mecEn=1`. Fixed slots: TxnID
12, ReturnTxnID 12, GroupID/LPID shared 8-bit slot, CCID 2, DataID 2, REQ
Size/NumReq 6-bit slot, RSP DBID 12, DAT DBID 16. **Independent check (the TB
side of the black-box split):** the TB flit model is derived from the B13.9
tables, not from the DUT's pack order. The B13.9.1 total-width formula forces
exactly 72 fixed REQ bits + 3·NodeID + RAW (both anchors give 72: N=7 →
93+RAW, N=16 → 120+RAW), which admits exactly one 8-bit slot between SnpAttr
and Excl — the slot shared by DoDWT / PGroupID / StashGroupID / TagGroupID /
LPID — matching the DUT's stated "GroupID/LPID shared 8-bit slot". RSP sums to
T=71 at N=7 and 89 at N=16; SNP to S=53+SAW; DAT to the 240/389/687 minima at
DW=128/256/512 — all consistent with B13.9.2/3/4. No flit-layout finding. Bit 0
is the LSB and fields pack LSB-first in table order. The elaboration self-check
of TB-computed widths against the DUT's `reqFlitWidth(CHI_CFG)` and friends is
kept (called by explicit scope if visible; otherwise against the absolute B13.9
formulas). Status: **CONFIRMED** → `[ASSUMPTION:7]`.

**Second round (2026-09-22): the widths are now measured, not derived.** The
user's warning that the default configuration would fail the width check
unless DAT included DataCheck and Poison was the prompt to stop deriving flit
widths from the B13.9 formulas and start measuring them at the boundary, which
is what the Q20 decision allows. Sweeping one configuration field at a time
and reading the resulting bus width gives every coefficient directly:

| field | REQ | RSP | SNP | DAT | note |
|---|---|---|---|---|---|
| `nodeIdW` | +3 | +2 | +2 | +3 | per bit; the NodeID count per channel |
| `addrW` | +1 | — | +1 | — | per bit; SNP carries `addrW − 3` |
| `dataW` | — | — | — | +334 per 256 | data + BE + DataCheck + Poison + Tag + TU |
| `rsvdcW` | +1 | — | — | +1 | per bit |
| `mpamEn` | +15 | — | +15 | — | fixed slot, see F-9 |
| `mecEn` | +16 | — | +16 | +16 | |
| `cdaEn` | +17 | — | — | — | StreamID 16 + SecSID1 1 |
| `pbhaEn` | +4 | — | — | — | |

with constant terms REQ 72, RSP 57, SNP 39, DAT 70, giving 153 / 79 / 106 /
437 at the default. Three results were not predictable from the spec text:
`txnIdW`, `lpidW`, `ccidW`, `groupIdW` and `mpamW` move no bus bit at all, so
those fields sit in slots fixed at their architectural maximum (finding F-9
for `mpamW`); `mteEn` moves nothing, confirming Tag and TU are always carried;
and `mecEn` with `cdaEn` add 17 to REQ rather than 33, because MECID and
StreamID share one slot. Every coefficient is confirmed over 41 random
configurations, and `make check` re-checks the formulas against the real buses
on every build.

**Third round (2026-09-22): the field list is now the specification's, and
there is nothing left unnamed.** With the Issue H PDF in the workspace (Q19)
the B13.6 to B13.9 tables were diffed against the model, and the eighteen
"unnamed" bits turned out to be testbench omissions rather than DUT bits, so
finding **F-10 is closed, not waived**:

| channel | what the model was missing |
|---|---|
| REQ | MultiReq, and PAS at two bits instead of three |
| RSP | the FwdState slot modelled eight bits wide instead of three, the GroupIDs put in it rather than in the twelve-bit DBID slot they actually share, and CacheLineID absent |
| SNP | a StashLPIDValid bit of its own, when it lives inside the FwdTxnID slot, offset by PAS again being one bit short |
| DAT | the DataSource slot four bits instead of eight, and DataPull, CacheLineID, CAH, NumDat and Replicate all absent |

PAS was the common thread on three of the four: Issue H replaced the NS and
NSE bits of earlier issues with a three-bit field naming one of six Physical
Address Spaces [SPEC:IHI0050H B13.10.68]. The other recurring trap is the
merged width cell: several rows of each table share one slot, and reading them
as separate fields inflates the model.

Two checks now hold this in place. Each channel's field list sums exactly to
the width measured at the boundary, at every configuration in the sweep, and
`hdlTop` fails elaboration if one ever stops matching — verified by
temporarily narrowing a field and watching it fire. The value of that check is
that the two sides are independent: the field list comes off the
specification, the width off the DUT's bus, and neither was fitted to the
other. The field ORDER within each channel is still the specification's order
rather than a measured one, so it remains the residual risk, but every field
is now present and every bit accounted for.

NumDat is the field with consequences beyond the width: the DUT honours it
(Q8), so a receiver may not assume a DAT message carries a full transfer.

### Q8. Data flit granularity, `DataID`, `BE` width, and cache line size

**Default.** The cache line is 64 bytes for all configurations. A line transfer
is `512 / CFG.dataW` DAT flits, `BE` is `CFG.dataW / 8` bits, and `DataID`
identifies the flit's 16-byte offset, so it steps by `CFG.dataW / 128`: values
0, 1, 2, 3 at `dataW = 128`, 0 and 2 at 256, and 0 only at 512. Partial and
non-line-size accesses use `Size` plus `Addr` and set `BE` accordingly.

**Resolution (2026-09-22, spec IHI0050H B2.9.4 "Data packetization" and
B13.9.4).** ADOPTED as stated; the DAT flit table confirms BE = DW/8 and the
flit-count rule, and B13.9.4's DataID is the 16-byte chunk index. Re-verified
numerically in Stage 1 when the DAT pack functions are written. Status:
**CONFIRMED** → `[ASSUMPTION:8]`.

**Second round (2026-09-22): one correction on the receive side.** A transfer
is only the packets covering the bytes named by `Addr` and `Size`, not a whole
line, so a 16-byte or smaller transfer is a single packet whatever `dataW` is.
The DUT also honours `NumDat`, so a sender may elide later packets and a
receiver must accept a DAT message shorter than `512/dataW` packets. Nothing
in the testbench may count on a fixed packet count:
`chiGlobalsPkg::datPacketCount()` derives it from `Size`, and
`datDataId()` derives DataID from the address offset within the line.

### Q9. `CFG.lcrdDepth` semantics

**Default.** `lcrdDepth` is the per-channel receive buffer depth on one side of
one link, it is the same on every channel and in both directions, and the
receiver may advertise up to `lcrdDepth` L-Credits. The testbench's link layer
advertises exactly `lcrdDepth` credits per channel it receives on, once the
direction reaches RUN. The link reference model checks that neither side ever
has more flits in flight on a channel than credits it was given, and that the
DUT never advertises more than `lcrdDepth`. The elaboration check
`CFG.lcrdDepth < 2` confirms at least two credits per channel.

**Resolution (2026-09-22).** ADOPTED: `lcrdDepth` is the per-channel receive
buffer depth on one side of one link; the TB link layer advertises exactly
`lcrdDepth` L-Credits per channel it receives on once that direction reaches
RUN, and the link reference model enforces the credit ceiling in both
directions. Status: **CONFIRMED** → `[ASSUMPTION:9]`.

**Second round (2026-09-22).** The DUT advertises `max(lcrdDepth, 2)` credits
per receive channel, and raises `linkCreditError` from the credit manager's
overflow path if it is ever handed more than its transmitter depth. So the
ceiling is a protocol requirement the testbench must respect, not a
politeness, and `chiGlobalsPkg::LCRD_DEPTH` is `max(lcrdDepth, 2)` to match.
Over-advertising is still reachable deliberately, through
`injectExtraCredits()`, which is how the directed credit-error test works.

### Q17. Can a link parity error or credit error be provoked, or only observed?

**Why it matters.** `linkParityError` and `linkCreditError` are outputs the
monitor must observe `[TOP:ports]`, and the feature matrix may not call them
Verified without a test that reaches them.

**Resolution (2026-09-22, user answers to Stage 0 register items 1 and 8).**
Both errors **are** injectable, so the `Partial` default is upgraded. Parity:
`*FLITCHK` pins exist and the TB drives `TX<x>FLITCHK` when `parityEn=1`, so a
directed test miscomputes one check byte and observes `linkParityError` — a
registered one-cycle pulse per mismatching flit, only when `parityEn=1`. Credit:
`linkCreditError` is a combinational pulse on credit overflow/underflow,
reachable by a negative test that deliberately over-sends beyond granted
credits. Neither output is sticky, so the monitor latches both. The parity test
runs two sub-tests: spec-odd parity (every TB flit is flagged → demonstrates
finding **F-1** at the boundary) and DUT-convention even parity with single-bit
injection (proves the detection path end to end). The same answer fixed
`linkUp[i]` semantics: it is the OR of the DUT's **receive**-direction channel
states being RUN — the node→fabric direction only — level, and zero on the
HN-F/HN-I/MN ordinals (finding **F-3**); the link reference model checks it
against the TB's TX-link RUN state and checks the fabric→node direction
separately via observed flit flow. Status: **CONFIRMED** → `[ASSUMPTION:17]`.

**Second round (2026-09-22): the parity polarity is verified, and F-1
stands.** The user asked for the spec side to be checked before the DUT's even
parity is called a bug. B9.3.1 is unambiguous: "Odd parity is used. Odd parity
means that check signals are added to groups of signals on the interface and
driven such that there is always an odd number of bits set to 1 in that
group." Table B9.18 gives `REQFLITCHK` a width of `ceil(R/8)` with a check
granularity of 1 to 8 and a check enable of `REQFLITV == 1`, matching the
per-byte checking the DUT does. So the DUT's byte width and enable are right
and only its polarity is inverted, which is exactly the shape finding **F-1**
describes, and the two-part parity test — spec-odd to demonstrate the
deviation, DUT-even with a single-bit flip to prove the detection path — is
the right pair.

Two details for the test to respect. Parity needs `parityEn = 1`, which is not
the default (Q12), so the test carries its own configuration. And both error
outputs are pulses rather than sticky bits, so the monitor latches them; the
credit error is reachable either by returning more than `lcrdDepth` credits or
by sending a flit with no credit at all, and the credit manager's overflow
path is what raises it (Q9).

One more deviation of the same family, found while reading B9.3.1: Table B9.18
assigns the single-bit check companions to whichever side drives the signal
they cover, so `TXLINKACTIVEREQCHK`, `SYSCOREQCHK` and the `TX<x>FLITPEND` and
`FLITV` check bits are node outputs. The DUT drives all of them itself, which
is why the testbench must leave them alone or create a second driver. Logged
as finding **F-11**, and waived on the same grounds as F-2: it removes a check
the testbench could otherwise make, but it does not block traffic.

---

## Configuration, address map, and node table

### Q10. `REGION_TARGET` slot semantics and the `REGION_ATTRIBUTES[3:0]` bit layout

**What the top module gives.** `REGION_TARGET` is
`logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0]`, and `makeRegionTarget` assigns
`EFFECTIVE_NODE_IDS[OFF_HNI]` into it, so the slot holds a literal NodeID rather
than an index into a node table. The same width appears on
`requesterSamTarget`, on `chi_noc_flit_t.targetNodeId`, and on the `tgtId` field
that `reqToNoc` writes. Attributes are built as
`{SAM_REGION_HNF_HASH, 1'b0, 1'b1}`, `{SAM_REGION_DIRECT, 1'b0, 1'b1}` and
`{SAM_REGION_MMIO, 1'b0, 1'b1}`, so `SAM_REGION_*` occupies bits 3:2 and two
single-bit fields follow.

**Resolution (2026-09-22, user from `chi_sam.sv`).** Confirmed with one
correction: the attribute layout is `{kind[3:2], secureOnly[1], valid[0]}` —
bit 1 is **secure-only**, not a generic qualifier, and bit 0 is valid. Kinds:
HNF_HASH=00, DIRECT=01, MMIO=10. `CHI_NODEID_SLOT_W == CHI_MAX_NODEID_W == 16`;
the slot holds the Home Node's NodeID zero-extended to 16 bits and is ignored
for HNF_HASH regions. The limit is **inclusive** (`addr <= limit`) and the first
matching region in ascending order wins; a secure-only match from a Non-secure
request returns unmapped with **no fall-through** to later regions. The TB
region table sets `secureOnly` per test intent, and a directed test covers the
secure-only/NS-mismatch unmapped path. Status: **CONFIRMED** →
`[ASSUMPTION:10]`.

### Q11. Unused regions, and the fourth region slot

**What the top module gives.** `NUM_REGIONS` defaults to 4 but
`USE_DEFAULT_REGIONS` fills only regions 0, 1 and 2: region 0 is the lower half
of the address space hashed across the HN-Fs, region 1 is the upper half below
`CFG_MMIO_BASE` direct to HN-I ordinal 0, region 2 is the 4 KiB `CFG_MMIO_BASE`
window to the same HN-I. Region 3 is left `'0`.

**Resolution (2026-09-22, user from `chi_sam.sv`).** Corrected mechanism:
region 3 is inert because its attributes default to `'0` (`valid=0`), not
because base ≥ limit — with `valid=1`, `base == limit` matches exactly one
address, since the limit is inclusive. The TB mirrors the three-region default
explicitly with `USE_DEFAULT_REGIONS=0`, keeps region 3 invalid in the default
map, and exercises single-address (`base == limit`) regions in the
region-boundary directed test. Runtime region programming is out of scope
(Q18a). Status: **CONFIRMED** → `[ASSUMPTION:11]`.

**Second round (2026-09-22): the unmapped path is broken, finding F-7.** The
mapper's `unmappedError` output (`requesterSamError`) is wired to nothing in
the top module. An unmapped address, or a Non-secure access to a secure-only
region, therefore gets no error response at all: the request is routed to
target NodeID 0, which is not a valid node, and the result is a hang or a
misdelivery rather than a DERR.

Two consequences, both now in the code. No test may generate an undeliverable
address, so `chiGlobalsPkg::chiSamLookup()` models the mapper from its region
semantics and `chiAddrIsDeliverable()` gates every generated address;
`hdlTop` checks both stimulus windows against it at time 0. And the
"unmapped → DERR" directed test is written but gated as an expected failure,
so the gap stays visible in the report instead of being quietly dropped from
the plan. The secure-only / Non-secure mismatch test is gated the same way,
since it reaches the same unconnected output.

### Q12. What is in `CHI_CFG_DEFAULT`?

**Why it matters.** The Stage 0 report cannot print a numeric NodeID and region
table without it, and `USE_DEFAULT_PLACEMENTS` is only legal when
`NUM_NODES == 14`, with `DEFAULT_PLACEMENTS` enumerated for ordinals 0 to 13.

**Default.** Nothing numeric is hardcoded in the testbench. `chiGlobalsPkg`
starts from `CHI_CFG_DEFAULT`, applies the `+define+CHI_TB_*` overrides, and
exports the resolved values; `hdlTop` prints the fully resolved configuration,
NodeID table, placement table and region table in an `initial` block at time 0,
and Stage 1 pastes that printout into `traceability.md`. The testbench never
depends on `NUM_NODES == 14` because it supplies its own placements (Q5).

**Resolution (2026-09-22).** Partially revealed by the Q5/Q7 answers: the DUT
default has `nodeIdW=11` on a 4×4 mesh with a 6-bit deviceId field, and
`dataCheckEn=1`, `poisonEn=1`; the answers also confirm `chi_cfg_t` contains
`pbhaEn`, `mteEn`, `multiReqEn` and `parityEn` even though the top module never
references them. Everything the TB depends on is overridden through
`+define+CHI_TB_*`, and the time-0 printout mechanism above is adopted to
capture the rest. Status: **CLOSED** (non-blocking; printout adopted).

**Second round (2026-09-22): the table in full, now a permitted input.** With
the Q15 widening, `CHI_CFG_DEFAULT` is read directly rather than inferred, and
`chiGlobalsPkg` starts from it. Recorded here so the register stands on its own:

| group | values |
|---|---|
| node counts | `numRnf` 4, `numRnd` **0**, `numRni` 1, `numSnf` 2, `numSni` 1, `numHnf` 4, `numHni` 1, `numMn` 1 — 14 nodes |
| widths | `dataW` 256, `addrW` 48, `nodeIdW` 11, `txnIdW` 12, `lpidW` 5, `rsvdcW` 0, `ccidW` 2, `groupIdW` 8, `mpamW` 0 |
| topology | `numIfPerNode` 1, `replChannels` 1, MESH_2D 3×3, 2 device ports per crosspoint |
| home node | snoop filter 1024 entries / 4 ways, `posEntries` 32, `retryRecords` 16, `lcrdDepth` 8, `exclMonitors` 32, `interleaveGranule` 64, `hnHashShift` 6 |
| enabled | `dataCheckEn`, `poisonEn`, `dctEn`, `dmtEn`, `dwtEn`, `atomicEn`, `dvmEn`, `stashEn`, `exclEn` |
| disabled | `parityEn`, `mpamEn`, `mteEn`, `mecEn`, `pbhaEn`, `cdaEn`, `multiReqEn` |
| config access | `CFG_PARAM_ONLY` |

Two of these change the testbench rather than just documenting it. The mesh is
3×3 with 2 ports, not 4×4: 18 positions for 14 nodes, which is what the
`hdlTop` geometry-capacity check now enforces before the DUT's own check can
fail more obscurely. And `numRnd` is 0, so `rnd[0]` is a sentinel port with no
node behind it — no agent, no driver, no monitor, and every node-side signal
tied to zero in `hdlTop` so the absent port cannot push X into the DUT.
`retryRecords` and `hnHashShift` are internal sizing the boundary never sees;
they are recorded only so that a POS-full or hash-distribution test knows the
scale it is aiming at.

### Q21. How does `chiFileList.f` pull in the repository's `filelist.f` without opening it?

**Default.** `chiFileList.f` references it as `-F $(CHI_RTL_ROOT)/filelist.f`,
using the `xrun` form that resolves paths inside an argument file relative to
**that file's own directory** rather than the launch directory, so the
repository's internal relative paths resolve against the repository root whatever
directory `make` was run from. `CHI_RTL_ROOT` is a Makefile variable defaulting
to `../../../chi_rtl`, matching a clone placed beside the `DV/` tree. If `-F`
turns out not to have that semantics in the installed Xcelium version, the
Makefile's fallback target runs `cd $(CHI_RTL_ROOT) && xrun ... -f filelist.f`
with all testbench paths made absolute. Confirm which form the installed version
needs, and whether `filelist.f` already supplies its own `-incdir` lines for
`rtl/if` and `rtl/pkg` or whether `chiFileList.f` must add them.

**Resolution (2026-09-22).** ADOPTED: `chiFileList.f` references the repository
as `-F $(CHI_RTL_ROOT)/filelist.f` (xrun `-F` resolves paths inside an argument
file relative to that file's own directory), with `CHI_RTL_ROOT` defaulting to
the sibling clone and the CWD-based fallback target documented in the Makefile.
For the local slang pass, the equivalent (`slang -F`) is verified against the
built binary before use and recorded in `iteration-log.md`. Status:
**CONFIRMED** → `[ASSUMPTION:21]`.

**Second round (2026-09-22): the design's list is now sanitised rather than
read raw.** Four points from the user, and what each one changed.

No `-incdir` lines are needed, because the RTL uses no `` `include ``, and the
relative paths resolve correctly under `-F`. Confirmed locally — the earlier
slang run already relied on it.

The `#` comment on the first line is the risk the user flagged and is the
reason the raw list is no longer handed to the compiler. Argument files are
not standardised on a comment character, so rather than find out on a
licensed machine whether `xrun` accepts `#`, the Makefile derives a clean copy
each build: `#` rewritten to `//`, paths made absolute so the list can be read
from any directory, and the result written to `gen/` and named by
`CHI_DUT_FILELIST`. `make dutlist` regenerates it alone;
`CHI_DUT_FILELIST=<path>` on the command line bypasses the whole mechanism
and supplies an explicit list.

The `rtl/top/*_compile.sv` lint harnesses are dropped unconditionally. They
are extra elaboration roots that `-top hdlTop` makes dead weight.

The `rtl/sva/*` binds are **kept by default**, dropped by `SVA=0`. A firing
internal assertion is worth knowing about even though it is reported against a
hierarchy this testbench may not reason about; the black-box answer is to
treat it as a pointer for the DUT owner rather than as a testbench failure,
and `+chiSvaOff` switches them off at run time for the DUT instance only when
they get in the way of a debug session. Keeping them cost nothing so far: the
current elaboration reports only two of them as trivially unmatchable, because
`parityEn` is 0 in the default configuration.

---

## Protocol scope per node class

### Q13. Do RN-D and RN-I ports receive snoops?

**What the top module gives.** All three requester classes are instantiated with
`IS_REQUESTER = 1'b1`, so `portSnpTxValid`/`portSnpTxFlit` are wired from
`snpOutValid`/`snpOutFlit` on RN-D and RN-I ports too, not tied off.

**Resolution (2026-09-22, user from `chi_mn_dvm.sv`).** The MN sends `SnpDVMOp`
sequentially to **every** Requester — RN-F, RN-D **and RN-I** — including the
originator itself, two flits per target, waiting for each response. Sending to
the originator is legal (IHI0050H B8.2.1 step 4: permitted, not required);
sending to RN-I violates B13.6.1.3 (the RN-I interface has no SNP channel) →
finding **F-5**, waived and counted so DVM tests can run
(`chiRequesterAgentConfig.allowRniDvmSnoop`, default 1 with a UVM_WARNING per
occurrence; 0 = strict, UVM_ERROR). All three requester agent classes advertise
SNP credits and answer `SnpDVMOp`; coherent (non-DVM) snoops to RN-D/RN-I
remain hard errors. Status: **CONFIRMED** → `[ASSUMPTION:13]`.

**Second round (2026-09-22): answering `SnpDVMOp` is mandatory, not polite.**
The MN sends the two snoop parts to each Requester in sequence and waits for
a SnpResp from each before it moves on, so a single agent that treats an
unexpected snoop as a finding and stays silent hangs every DVMOp in the test.
"RN-I records any snoop as a finding" is therefore not a usable rule: all
three requester agent classes keep their SNP link credited and answer
`SnpDVMOp`, and the RN-I case is counted as finding F-5 rather than refused.
Coherent snoops to RN-D or RN-I remain hard errors, because the Home is only
ever given the RN-F NodeIDs and so cannot legitimately produce one.

### Q14. Which nodes are in the DVM node set?

**What the top module gives.** `makeDvmIds` fills `DVM_NODE_IDS` with the first
`NUM_REQ` NodeIDs, that is every RN-F, RN-D **and** RN-I, and passes them to
`chi_mn_dvm` as `NUM_DVM_NODES`/`DVM_NODE_IDS`.

**Resolution (2026-09-22, user from `chi_mn_dvm.sv`).** Confirmed: the DVM node
set is every Requester including RN-I and the originator (the RN-I part is
finding **F-5**, waived per Q13). The same answer exposed two more MN
deviations: the MN has **no DBIDResp / NonCopyBackWriteData phase** (it goes
IDLE → snoop → Comp), although IHI0050H B8.2.1 steps 2–3 and B8.2.2 steps 2–3
require a DBIDResp followed by an 8-byte NonCopyBackWriteData — finding **F-6**,
waived by `chiRequesterAgentConfig.expectDvmDbidResp` (default 0 = tolerate and
count a warning; 1 = strict, expect the spec flow and error on its absence);
and the MN returns NDERR for DVM types above Sync, which the TB expects and
checks. The MN's SnpDVMOp payload bit layout is a local choice, so the TB
checks only spec-mandated SnpDVMOp properties (two parts, same TxnID on both —
B8.2.3.2) and never the payload encoding. Status: **CONFIRMED** →
`[ASSUMPTION:14]`.

**Second round (2026-09-22): F-6 verified against the document, and it does
block a compliant Requester.** The user asked for the B8 flow to be confirmed
before the DVM Sync test is built. It now is, from the PDF rather than from
recollection. Both flows require the same first three steps: the Requester
sends the DVMOp, *the MN returns a DBIDResp*, and the Requester sends an
eight-byte NonCopyBackWriteData — B8.2.1 steps 1 to 3 for Non-sync, B8.2.2
steps 1 to 3 for Sync, and both figures show all three. The MN's IDLE → snoop
→ Comp path omits steps 2 and 3 entirely.

So the user's concern is right: a Requester written to the specification waits
for a DBIDResp that never arrives and stalls before it ever sends its write
data. That makes `expectDvmDbidResp = 0` the only setting under which a DVM
test can run at all against this DUT, rather than a tolerance. In that mode
the Requester sends no NonCopyBackWriteData either — the MN has no write data
phase to receive it, so sending one would be an unsolicited DAT flit to a node
with no matching credit reservation. Strict mode (1) is kept so the deviation
can be demonstrated on demand, and it is expected to time out.

The specification also settles two smaller points the same way. Sending the
snoop to the originating Requester is explicitly "permitted, but not required"
(B8.2.1 step 4), so it is not a finding. The same sentence says the MN
broadcasts "to the remaining RN-F and RN-D nodes", which is the text RN-I is
absent from, confirming F-5.

### Q15. Features with no `chi_cfg_t` enable field among those the top module references

**Why it matters.** The feature matrix may not mark a feature `N/A: disabled`
without an enable field, nor `Verified` without a test, a check and covered
bins. The referenced enable fields are `atomicEn`, `dctEn`, `dmtEn`, `dwtEn`,
`stashEn`, `dvmEn`, `exclEn`, `mpamEn`, `mecEn`, `cdaEn`, plus `cfgAccess`,
`topology`, `interleaveGranule`, `posEntries`, `lcrdDepth`, `exclMonitors`,
`snpFilterEntries`, `snpFilterWays`, `rsvdcW`, `mpamW`. There is no field for
CMOs, write-zero, `Order`/`ReadReceipt`, error and poison and `DataCheck`,
memory tagging, or PBHA, yet `CHI_PBHA_W` and a lone `+ 1` appear in the REQ
width bound, which suggests PBHA and at least one tag-related field are sized by
`chi_cfg_t` members the top module does not reference and that I am therefore
not allowed to use.

**Resolution (2026-09-22, user answers to Stage 0 register items 5 and 9).**
The enable fields exist in `chi_cfg_t` even though the top module never
references them: `pbhaEn`, `mteEn`, `dataCheckEn`, `poisonEn`, `multiReqEn`,
`parityEn`. Consequences: CMOs, Write+CMO (`Write*CleanSh/CleanInv/PerSep/PoPA`
— supported), WriteZero (`WriteUniqueZero`/`WriteNoSnpZero` — supported in
HN-F), Order/ReadReceipt, QoS and the error/poison/DataCheck paths are all
testable and each gets a test, a check and coverage; MTE is testable for tag
propagation because DAT Tag/TU bits are always present; PBHA is testable with
`pbhaEn=1`. **MultiReq is inert**: `multiReqEn` is declared but no logic
references it, so the DUT neither implements nor rejects multi-request
transactions → finding **F-4**; the TB always drives MultiReq=0 and
chiMultiReqTest stays gated and reports SKIP. Status: **CONFIRMED** →
`[ASSUMPTION:15]`.

**Second round (2026-09-22): isolation widened, which is what unblocked the
flit model.** The recommendation to allow the `chi_cfg_t` declaration and
`CHI_CFG_DEFAULT` is adopted and recorded at the top of this file. They are
types and values rather than behaviour, and without them the four fields the
top module never references but that change the DAT width — `dataCheckEn` and
`poisonEn`, both on by default, plus `parityEn` and `mteEn` — would have to be
guessed. The full default table is now under Q12.

Two corrections to the entry above. The lone `+ 1` in the REQ width bound is
SecSID1, from `cdaEn`, not a tag field; the model sizes it that way and the
measured `cdaEn` coefficient of 17 (StreamID 16 plus SecSID1 1) confirms it.
And `mteEn` moves no bus bit, because Tag and TU are carried unconditionally —
so the model packs them always, as zero when MTE is unused, and an `mteEn`
sweep is a behaviour sweep rather than a width sweep. `multiReqEn` stays
inert (F-4), but MultiReq itself is now modelled as a REQ field, because a
flit the DUT sends still has to unpack; it is simply never driven to 1.

### Q16. Reset and bring-up requirements

**Default.** `resetn` is asserted low for at least 10 `clk` cycles from time 0
and de-asserted synchronously on a clock edge. No `chi_if` activity, including
`TXSACTIVE`, starts before `resetn` is high. Link activation then runs
STOP to ACTIVATE to RUN per direction, and no flit is sent before both the
direction is RUN and a credit has been received.

**Resolution (2026-09-22).** ADOPTED. With Q2 resolved, BFMs additionally
qualify on `chiPort.RESETn` (DUT-driven copy of the same reset); with Q3
resolved, "no `TXSACTIVE` before reset" becomes a DUT observation, not a TB
action, since the DUT owns both SACTIVE pins (F-2). Status: **CONFIRMED** →
`[ASSUMPTION:16]`.

---

## Testbench structure questions for approval

### Q18. Four reference-model files inside `topEnv/`

The checking section requires four reference models with no shared state. Coding
them as one class in `topScoreboard.sv` would make one very large file whose
four halves cannot be reviewed or reused independently.

**Default.** Keep `topScoreboard.sv` as the `uvm_scoreboard` that owns the
analysis exports, the flit queues and the end-of-test checks, and add four files
in the same directory, named by the integration-layer scheme without the `chi`
prefix: `topEnv/topLinkRefModel.sv`, `topEnv/topLifecycleRefModel.sv`,
`topEnv/topDirectoryRefModel.sv`, `topEnv/topMemoryRefModel.sv`, each a
`uvm_component` fed only from boundary traffic, all four listed in
`chiFileList.f` and in the DV spec component inventory. If a single file is
preferred, they collapse into `topScoreboard.sv` as nested classes with no other
change.

**Resolution (2026-09-22).** ADOPTED with one naming adjustment to naming rule
3 (the approved suffix list has `Model`, not `RefModel`):
`topEnv/topLinkModel.sv`, `topEnv/topLifecycleModel.sv`,
`topEnv/topDirectoryModel.sv`, `topEnv/topMemoryModel.sv` — four
`uvm_component`s fed only from boundary traffic, with no shared state between
them or with any driver, each added to `chiFileList.f` and to the DV spec
component inventory. Status: **CONFIRMED** → `[ASSUMPTION:18]`.

### Q18a. Is configuration-port stimulus in scope?

The architecture rules say the unused APB port is tied off, but `CFG.cfgAccess`
can select `CFG_APB` or `CFG_CHI_MMIO`, and both change the DUT's address map at
run time through `regionUpdate`.

**Resolution (2026-09-22, user answer to Stage 0 register item 10).** Tie-off
confirmed benign: with APB unselected the DUT drives `PRDATA=0`, `PREADY=1`,
`PSLVERR=PSEL&PENABLE`, so `PSEL=0` (all other inputs 0) is safe. APB and
CHI-MMIO runtime region programming are **Not verified — out of scope**; no APB
stimulus test is built. Status: **CONFIRMED** → `[ASSUMPTION:18a]`.

---

## Confirmed assumptions

All entries resolved 2026-09-22. The number is the question number so that a
source tag and this log never drift apart. `[ASSUMPTION:n]` in TB source refers
to this register; each is also marked `See OPEN QUESTIONS`.

- `[ASSUMPTION:1]` chi_if carries all spec-named signals plus `CLK`/`RESETn`
  plus per-byte `*CHK` parity companions; no shared-credit pins; TB drives only
  `TX<x>FLITPEND/FLITV/FLIT[/FLITCHK]`, `TXLINKACTIVEREQ`, `RXLINKACTIVEACK`,
  `RX<x>LCRDV`, `SYSCOREQ`; `TXSNPFLIT*` tied 0. (Q1)
- `[ASSUMPTION:2]` `chi_if.CLK/RESETn` are driven by the DUT; BFMs sample
  `chiPort.CLK`; TB never drives them. (Q2)
- `[ASSUMPTION:3]` DUT drives both SACTIVE pins to `resetn`; TB never drives
  `TXSACTIVE`; SACTIVE checking reduced accordingly. Finding F-2. (Q3)
- `[ASSUMPTION:4]` `SYSCOACK` is a combinational copy of `SYSCOREQ` on every
  port class; TB drives `SYSCOREQ` on RN-F (RN-D optional), ties 0 elsewhere. (Q4)
- `[ASSUMPTION:5]` NodeID = `{meshY, meshX, devicePort, deviceId}` LSB-first
  with `xW/yW/portW = clog2Min1(meshX/meshY/numDevPortsPerXp)` (≥1) and
  `deviceIdWidth = nodeIdW − yW − xW − portW`; TB-owned `tbEncodeNodeId` with
  `deviceId = ordinal`; placements built from `chi_cfg_pkg` types and
  `chi_node_class_e` literals; DUT elaboration checks verify the table. (Q5)
- `[ASSUMPTION:7]` Flit field list and order per the IHI0050H B13.6–B13.9
  tables, read from the PDF in `DV/doc/spec/`; PAS is 3 bits; the merged-cell
  rows are single shared slots; DataCheck/Poison present by default; Tag/TU
  always present in DAT; PBHA when `pbhaEn`; MECID in REQ/SNP/DAT when
  `mecEn`; StreamID+SecSID1 when `cdaEn`. Each channel's field sum equals its
  measured bus width and `hdlTop` enforces that at elaboration. Only the
  order within a channel remains unverified against the DUT. (Q7)
- `[ASSUMPTION:8]` 64-byte line; `BE = dataW/8`; `DataID` steps by
  `dataW/128`; a transfer is only the packets covering `Addr`/`Size`, and a
  receiver must accept a message shortened by `NumDat`. (Q8)
- `[ASSUMPTION:9]` `lcrdDepth` = per-channel RX buffer depth; the DUT
  advertises `max(lcrdDepth, 2)`; over-advertising raises `linkCreditError`,
  so the ceiling is a requirement and the TB respects it except in the
  directed credit-error test. (Q9)
- `[ASSUMPTION:10]` Region attributes `{kind[3:2], secureOnly[1], valid[0]}`,
  kinds HNF_HASH=00/DIRECT=01/MMIO=10; `REGION_TARGET` = Home NodeID (16-bit
  slot); inclusive limit; first match wins; secure-only + NS → unmapped. (Q10)
- `[ASSUMPTION:11]` A region with `valid=0` never matches; `base == limit`
  with `valid=1` matches exactly one address. (Q11)
- `[ASSUMPTION:13]` MN snoops DVM to every Requester incl. RN-I (F-5, waived
  and counted) and the originator (legal); all requester agents answer
  `SnpDVMOp`. (Q13)
- `[ASSUMPTION:14]` MN has no DVM DBIDResp/NCBWrData phase (F-6, waived via
  `expectDvmDbidResp=0`); MN returns NDERR for DVM types above Sync; TB checks
  only spec-mandated SnpDVMOp properties. (Q14)
- `[ASSUMPTION:15]` `pbhaEn`/`mteEn`/`dataCheckEn`/`poisonEn`/`multiReqEn`/
  `parityEn` exist in `chi_cfg_t`; MultiReq is inert in the DUT (F-4) and the
  TB always drives MultiReq=0. (Q15)
- `[ASSUMPTION:16]` Reset held ≥10 cycles, synchronous deassert; no link
  activity before `resetn` high. (Q16)
- `[ASSUMPTION:17]` Parity and credit errors are injectable black-box;
  `linkParityError`/`linkCreditError` are single-cycle pulses latched by the
  monitor; `linkUp[i]` = DUT receive-direction RUN, level (F-3); spec parity
  is odd per B9.3.1 against the DUT's even (F-1), and the DUT drives the
  node-side single-bit `*CHK` companions (F-11). (Q17)
- `[ASSUMPTION:18]` Four reference models live in separate files
  `topEnv/topLinkModel.sv`, `topLifecycleModel.sv`, `topDirectoryModel.sv`,
  `topMemoryModel.sv`. (Q18)
- `[ASSUMPTION:18a]` APB tied off; runtime region programming out of scope. (Q18a)
- `[ASSUMPTION:21]` `chiFileList.f` pulls in the DUT through a sanitised copy
  of the design's own `filelist.f`, regenerated each build: `#` comments
  rewritten, paths absolute, lint harnesses dropped, SVA binds kept unless
  `SVA=0`. (Q21)

Q6 (TgtID) and Q12 (`CHI_CFG_DEFAULT` contents) are **CLOSED** — facts, not
assumptions. Q19 (spec issue) and Q20 (simulator process) are **CLOSED**.

### Mapping from the 2026-09-22 Stage 0 twelve-question register

The user's RTL answers were keyed to this run's original twelve-question
register. Mapping to this 21-item register (several originals split):

| Stage 0 register | This register | Answer headline |
|---|---|---|
| 1 chi_if inventory | Q1 (+Q17) | Corrected: parity `*CHK` pins exist; no shared-credit pins; even parity → F-1 |
| 2 orientation | Q1 | Confirmed: node perspective on all classes |
| 3 NodeID encoding | Q5 | Corrected: `{meshY,meshX,devicePort,deviceId}`, deviceId=ordinal |
| 4 TgtID | Q6 | Confirmed (already readable from the top module) |
| 5 flit layout | Q7 | Corrected: DataCheck/Poison default-on, Tag/TU always, PBHA via `pbhaEn` |
| 6 REGION_TARGET | Q10 | Confirmed + secureOnly bit and inclusive limit |
| 7 CLK/SACTIVE/SYSCO | Q2, Q3, Q4 | Corrected: DUT drives CLK/RESETn and both SACTIVE (F-2); SYSCOACK is a comb copy |
| 8 linkUp/errors | Q17 | Corrected: RX-direction-only linkUp (F-3), pulsed error outputs |
| 9 Issue-H support | Q15 | Corrected: Write+CMO/WriteZero supported; MultiReq inert (F-4) |
| 10 APB | Q18a | Confirmed: tie-off benign |
| 11 RN-I/RN-D snoops | Q13, Q14 | Confirmed + MN deviations (F-5, F-6) |
| 12 region 3 | Q11 | Corrected: inert via `valid=0`; inclusive limit |

---

## Annex: what Stage 0 read from `chi_interconnect_top.sv`

Recorded here so that later stages can be reviewed without reopening the DUT
file, and so that every `[TOP:...]` tag has a written source.

**Parameters.** `CFG` (`chi_cfg_pkg::chi_cfg_t`, default `CHI_CFG_DEFAULT`),
`AGE_LIMIT` (16), `NUM_REGIONS` (4), `NUM_NODES` (sum of the eight node counts),
`NODE_IDS[NUM_NODES-1:0]` (`CHI_MAX_NODEID_W` wide, all-ones sentinel),
`USE_DEFAULT_PLACEMENTS` (1), `PLACEMENTS[NUM_NODES-1:0]`
(`chi_mesh_placement_t`), `CFG_MMIO_BASE` (`addrW` wide, top 4 KiB),
`USE_DEFAULT_REGIONS` (1), `REGION_BASE`, `REGION_LIMIT` (`addrW` wide),
`REGION_TARGET` (`CHI_NODEID_SLOT_W` wide), `REGION_ATTRIBUTES` (4 bits), the
last four dimensioned `[NUM_REGIONS-1:0]`.

**Ports.** `clk`, `resetn`; `chi_if` arrays `rnf`, `rnd`, `rni`, `snf`, `sni`,
each sized `(count > 0 ? count : 1) - 1 : 0`; APB `PADDR[11:0]`, `PSEL`,
`PENABLE`, `PWRITE`, `PWDATA[31:0]`, `PSTRB[3:0]`, `PPROT[2:0]`,
`PRDATA[31:0]`, `PREADY`, `PSLVERR`; and `linkUp`, `linkParityError`,
`linkCreditError`, each `[NUM_NODES-1:0]` and indexed by node ordinal, with the
HN-F, HN-I and MN bits reading zero because those endpoints have no external
link.

**Node ordinal order.** RN-F, RN-D, RN-I, SN-F, SN-I, HN-F, HN-I, MN, from
`OFF_RNF = 0`, `OFF_RND`, `OFF_RNI`, `OFF_SNF`, `OFF_SNI`, `OFF_HNF`,
`OFF_HNI`, `OFF_MN`.

**`chi_cfg_t` fields the top module references, and nothing else is available to
the testbench.** `numRnf`, `numRnd`, `numRni`, `numSnf`, `numSni`, `numHnf`,
`numHni`, `numMn`, `addrW`, `dataW`, `nodeIdW`, `txnIdW`, `lpidW`, `ccidW`,
`groupIdW`, `rsvdcW`, `numIfPerNode`, `replChannels`, `mpamW`, `mpamEn`,
`mecEn`, `cdaEn`, `posEntries`, `lcrdDepth`, `exclMonitors`,
`interleaveGranule`, `snpFilterEntries`, `snpFilterWays`, `atomicEn`, `dctEn`,
`dmtEn`, `dwtEn`, `stashEn`, `dvmEn`, `exclEn`, `topology`, `meshX`, `meshY`,
`numDevPortsPerXp`, `cfgAccess`.

**Configuration legality, from the top module's own elaboration checks.**
`dataW` in {128, 256, 512}; `addrW`, `nodeIdW`, `txnIdW`, `lpidW`, `ccidW`,
`groupIdW` inside their `CHI_MIN_*`/`CHI_MAX_*` bounds; `rsvdcW` in {0, 4, 8,
12, 16, 24, 32}; `numIfPerNode == 1` and `replChannels == 1`; `mpamW` in {0, 12,
15} and `mpamEn` requires a non-zero `mpamW`; `mecEn` and `cdaEn` mutually
exclusive; the four flit widths inside their Issue H ranges; `posEntries`,
`exclMonitors`, `interleaveGranule`, `NUM_REGIONS`, `AGE_LIMIT` all non-zero and
`lcrdDepth >= 2`; snoop-filter geometry non-zero with `snpFilterWays <=
snpFilterEntries` and `snpFilterEntries % snpFilterWays == 0`;
`interleaveGranule` a power of two at least 64; `numHnf > 0` requires
`numSnf > 0`; `numHni > 0` requires `numSni > 0`; `atomicEn` requires a Home;
`dctEn` requires RN-F and HN-F; `dmtEn` or `dwtEn` requires a Home and SN-F;
`stashEn` requires RN-F and HN-F; `dvmEn` requires an MN and a Request Node;
`exclEn` requires a Home and monitors; `topology` in {`CROSSBAR`, `RING`,
`MESH_2D`}; `NUM_NODES` equal to the sum of the counts; `USE_DEFAULT_PLACEMENTS`
only when `NUM_NODES == 14`; `MESH_2D` needs non-zero `meshX`, `meshY`,
`numDevPortsPerXp`, a positive `deviceIdWidth(CFG)` and
`meshX * meshY * numDevPortsPerXp >= NUM_NODES`; `cfgAccess` in
{`CFG_PARAM_ONLY`, `CFG_APB`, `CFG_CHI_MMIO`}; `CFG_CHI_MMIO` requires
`numHni > 0` and a 4 KiB-aligned `CFG_MMIO_BASE`; `CFG_APB` requires
`NUM_REGIONS > 0`.

**Boundary-visible routing rules.** A requester's REQ has its `TgtID` replaced
by the address mapper's target; `DVMOp` is redirected to the MN when one exists;
`PrefetchTgt` is redirected to an SN-F chosen by a separate prefetch mapper;
`PCrdReturn` and any request with `allowRetry == 0` keep the `TgtID` the
requester supplied. REQ egress toward a requester port and SNP ingress from any
external port are unused.

**Default region table when `USE_DEFAULT_REGIONS` is 1.** Region 0 covers
`0` to `2**(addrW-1) - 1` with `{SAM_REGION_HNF_HASH, 1'b0, 1'b1}`; region 1
covers `2**(addrW-1)` to `CFG_MMIO_BASE - 1` targeting HN-I ordinal 0 with
`{SAM_REGION_DIRECT, 1'b0, 1'b1}`; region 2 covers `CFG_MMIO_BASE` to all-ones
targeting the same HN-I with `{SAM_REGION_MMIO, 1'b0, 1'b1}`; region 3 is zero.

**Internal endpoint pairing, visible only as parameters.** HN-F ordinal `i` is
given `SN_NODE_ID = EFFECTIVE_NODE_IDS[OFF_SNF + (i % numSnf)]` and HN-I ordinal
`i` targets `EFFECTIVE_NODE_IDS[OFF_SNI + (i % numSni)]`. The scoreboard does
**not** use this: it never predicts which Home or Subordinate a request reaches.
It is recorded only to explain why the memory reference model must track data by
address across all Subordinates rather than per port.
