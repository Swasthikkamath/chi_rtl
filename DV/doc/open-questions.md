# CHI Interconnect DV - Open Questions and Assumptions Log

This file is the single register of everything the testbench could not read from
its two permitted inputs. Every entry has a number, the reason it matters, the
default the testbench will take if the question is not answered, and a status.

Permitted inputs (INPUT ISOLATION):

1. `chi_rtl/rtl/top/chi_interconnect_top.sv` - port list, parameters, the
   `chi_cfg_pkg::chi_cfg_t` type and only those `chi_cfg_t` fields the top
   module itself references.
2. The AMBA 5 CHI Architecture Specification, ARM IHI 0050. See Q19 for the
   issue actually available to this run.

Nothing else in the DUT repository has been opened. `rtl/if/`, `rtl/pkg/`,
`rtl/link/`, `rtl/noc/`, `rtl/sam/`, `rtl/hnf/`, `rtl/hni/`, `rtl/mn/`,
`rtl/sva/`, the other files under `rtl/top/`, `filelist.f`, `DV/`, `tb/`,
`doc-src/` and `docs/` are unread. `filelist.f` is referenced by path only.

Status values: `OPEN` (blocking, default in use), `CONFIRMED` (answered, now an
`[ASSUMPTION:n]` tag in source), `CLOSED` (answered and no longer an
assumption, replaced by a `[TOP:...]` or `[SPEC:...]` tag).

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

**What this run has.** No copy of ARM IHI 0050, of any issue, is present in the
environment, and `developer.arm.com/documentation/ihi0050` serves only a
JavaScript shell with no retrievable text, so the document cannot be fetched.
The DUT's own top-module comments cite Issue H in the part-prefixed form
`B3.3.1`, `B2.10.2.1`, `B13.9`, which fixes the citation style but supplies no
tables.

**Default.** Work from my trained knowledge of IHI 0050 Issue H, and:

- cite as `[SPEC:IHI0050H <section> <section title>]` so a reader can find the
  clause even if my section number is off by a subsection;
- put every numeric encoding in exactly one place, a table in `chiGlobalsPkg`,
  with one `traceability.md` row per constant;
- mark any constant I am not fully confident of with `See OPEN QUESTIONS Q19`
  and list it in the Q19 encoding annex, rather than silently asserting it.

**Preferred answer.** Either confirm that citation from knowledge is acceptable,
or drop the Issue H PDF (or just the REQ/RSP/SNP/DAT opcode tables, the
`RespErr` and `Resp[2:0]` encodings, and the flit field-order tables) into the
workspace. Status: **OPEN**.

### Q20. There is no simulator in this environment. What counts as "must elaborate" and "must pass"?

**Why it matters.** Stage 1 is required to elaborate and Stage 5 is required to
pass `chiLinkBringUpTest` and `chiCoherentTrafficTest`.

**What this run has.** No `xrun`, `xmvlog`, `xmelab`, `vcs`, `vlog`,
`verilator` or `iverilog` on `PATH`, no `/opt/cadence` or equivalent tool tree,
and no licence server. Xcelium cannot be installed here.

**Default.** Deliver complete, review-clean source plus the exact commands, and
substitute the strongest static checking obtainable without a licence:

- install the prebuilt `slang` SystemVerilog front end and run a parse and
  elaborate pass over `chiGlobalsPkg` and the whole HDL side (`chiClkRstBfm`,
  `chiLinkLayerBfm`, both driver BFMs, `chiMonitorBfm`, `hdlTop`) against a
  minimal local stand-in for `chi_cfg_pkg` and `chi_if` that is built solely
  from the identifiers the top module references, is kept outside the compile
  order used for Xcelium, and is never used to infer DUT behaviour;
- hand-check the HVL side against the same front end where the UVM class
  library is not required, and by inspection where it is.

Each stage will state plainly which checks were run and that the Xcelium
elaboration and the two passing tests are pending on a licensed machine.
Status: **OPEN**.

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
per channel so that the orientation is a single edit, not a rewrite. Status:
**OPEN**.

### Q2. Does `chi_if` carry `CLK`/`RESETn`, and who drives them?

**Why it matters.** Two drivers on a clock is an X; no driver is no clock.

**What the top module gives.** `clk` and `resetn` are scalar module inputs and
are passed to `chi_link_port` separately from `.chiPort`, so the DUT does not
need a clock from inside `chi_if`.

**Default.** `chi_if` may contain `CLK` and `RESETn` members but the DUT does
not drive them. `chiClkRstBfm` is the only clock and reset source: it drives the
DUT's `clk`/`resetn` ports, and if the interface has `CLK`/`RESETn` members
`hdlTop` drives them from the same source. All BFMs sample and drive on the same
`clk`. Status: **OPEN**.

### Q3. `TXSACTIVE` / `RXSACTIVE` ownership per port class

**Default.** Node-perspective naming as in Q1: the testbench drives `TXSACTIVE`
on every port it owns and observes `RXSACTIVE`. `TXSACTIVE` is raised before
requesting link activation and lowered only after both directions reach STOP.
If the DUT does not drive `RXSACTIVE` at all, the link reference model records
the fact and downgrades the SACTIVE check to "not observable" rather than
failing. Status: **OPEN**.

### Q4. `SYSCOREQ` / `SYSCOACK` presence and ownership per port class

**Default.** Present on all `chi_if` instances. The node side drives
`SYSCOREQ`, the interconnect drives `SYSCOACK`. The testbench runs the system
coherency handshake only on RN-F ports (`chiRequesterAgentConfig.syscoPresent`
is derived from the node class), holds `SYSCOREQ` low on RN-D, RN-I, SN-F and
SN-I ports, and treats a `SYSCOACK` assertion on a port where the testbench
never raised `SYSCOREQ` as a finding. Status: **OPEN**.

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
Illegal-NodeID stimulus is out of scope. Status: **OPEN** only on whether
`defaultNodeId` is guaranteed to produce a legal, collision-free table for a
swept configuration.

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
**CONFIRMED** from `[TOP:reqToNoc, requester_sam]`; no assumption needed.

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

**Preferred answer.** The `B13.9` field order for REQ, RSP, SNP and DAT, and
which end of the flit is bit 0. Status: **OPEN** and the highest-risk item in
this log.

### Q8. Data flit granularity, `DataID`, `BE` width, and cache line size

**Default.** The cache line is 64 bytes for all configurations. A line transfer
is `512 / CFG.dataW` DAT flits, `BE` is `CFG.dataW / 8` bits, and `DataID`
identifies the flit's 16-byte offset, so it steps by `CFG.dataW / 128`: values
0, 1, 2, 3 at `dataW = 128`, 0 and 2 at 256, and 0 only at 512. Partial and
non-line-size accesses use `Size` plus `Addr` and set `BE` accordingly. Status:
**OPEN**.

### Q9. `CFG.lcrdDepth` semantics

**Default.** `lcrdDepth` is the per-channel receive buffer depth on one side of
one link, it is the same on every channel and in both directions, and the
receiver may advertise up to `lcrdDepth` L-Credits. The testbench's link layer
advertises exactly `lcrdDepth` credits per channel it receives on, once the
direction reaches RUN. The link reference model checks that neither side ever
has more flits in flight on a channel than credits it was given, and that the
DUT never advertises more than `lcrdDepth`. The elaboration check
`CFG.lcrdDepth < 2` confirms at least two credits per channel. Status: **OPEN**.

### Q17. Can a link parity error or credit error be provoked, or only observed?

**Why it matters.** `linkParityError` and `linkCreditError` are outputs the
monitor must observe `[TOP:ports]`, and the feature matrix may not call them
Verified without a test that reaches them.

**Default.** Assume `chi_if` has no separate parity or check pins the testbench
can corrupt independently of the flit payload, so neither error is injectable
black-box. Both are observed and asserted quiet in every functional test, the
link reference model fails a test that raises either unexpectedly, and the
feature matrix records them as `Partial` with the reason. If the interface does
carry a parity or `*CHECK` pin, or if a flit-payload parity field exists that
the testbench can miscompute deliberately, a directed injection test is added
and the status becomes Verified. Status: **OPEN**.

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

**Default.** `REGION_TARGET` is a NodeID zero-extended to `CHI_NODEID_SLOT_W`,
and `CHI_NODEID_SLOT_W >= CHI_MAX_NODEID_W >= CFG.nodeIdW`. Bit 0 is the region
valid bit and bit 1 is a secure or non-secure qualifier that pairs with the
`nonSecure` input the top module feeds the SAM from `pasNonSecure`. The
testbench builds its region table with exactly the three bit patterns the top
module itself writes, so no new encoding is invented, and it leaves bit 1 at 0.
Status: **OPEN** on the meaning of bits 1 and 0 only.

### Q11. Unused regions, and the fourth region slot

**What the top module gives.** `NUM_REGIONS` defaults to 4 but
`USE_DEFAULT_REGIONS` fills only regions 0, 1 and 2: region 0 is the lower half
of the address space hashed across the HN-Fs, region 1 is the upper half below
`CFG_MMIO_BASE` direct to HN-I ordinal 0, region 2 is the 4 KiB `CFG_MMIO_BASE`
window to the same HN-I. Region 3 is left `'0`.

**Default.** `attributes == 4'h0` means an invalid region and an address that
matches no valid region raises the SAM's `unmappedError`. The testbench mirrors
the three-region default explicitly with `USE_DEFAULT_REGIONS = 1'b0`, keeps
region 3 invalid, and uses region 3 as the target of the runtime region
programming test if Q18a says APB programming is in scope. Status: **OPEN**.

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
Status: **OPEN**, non-blocking.

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
`rtl/if` and `rtl/pkg` or whether `chiFileList.f` must add them. Status:
**OPEN**.

---

## Protocol scope per node class

### Q13. Do RN-D and RN-I ports receive snoops?

**What the top module gives.** All three requester classes are instantiated with
`IS_REQUESTER = 1'b1`, so `portSnpTxValid`/`portSnpTxFlit` are wired from
`snpOutValid`/`snpOutFlit` on RN-D and RN-I ports too, not tied off.

**Default.** The RN-F agent answers coherent snoops and DVM snoops. The RN-D
agent advertises SNP credits and answers `SnpDVMOp` only. The RN-I agent
advertises SNP credits so that a misdirected snoop cannot deadlock the fabric,
but records any snoop it receives as a finding in the lifecycle reference model.
Status: **OPEN**.

### Q14. Which nodes are in the DVM node set?

**What the top module gives.** `makeDvmIds` fills `DVM_NODE_IDS` with the first
`NUM_REQ` NodeIDs, that is every RN-F, RN-D **and** RN-I, and passes them to
`chi_mn_dvm` as `NUM_DVM_NODES`/`DVM_NODE_IDS`.

**Default.** The testbench expects that a DVM operation may be snooped to any
requester port including RN-I. Each requester agent therefore answers `SnpDVMOp`
with a DVM snoop response regardless of class, and the lifecycle model records a
DVM snoop delivered to an RN-I as a finding to be adjudicated rather than an
immediate error. Status: **OPEN**.

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

**Default.** Treat CMOs, write-zero, `Order`/`ReadReceipt`, QoS, and the error
and poison and `DataCheck` paths as unconditionally present per the spec, and
give each a test, a check and coverage. Mark memory tagging (MTE) and PBHA
`N/A: no enable field referenced by the top module` and exclude their
coverpoints rather than leaving holes. Status: **OPEN**.

### Q16. Reset and bring-up requirements

**Default.** `resetn` is asserted low for at least 10 `clk` cycles from time 0
and de-asserted synchronously on a clock edge. No `chi_if` activity, including
`TXSACTIVE`, starts before `resetn` is high. Link activation then runs
STOP to ACTIVATE to RUN per direction, and no flit is sent before both the
direction is RUN and a credit has been received. Status: **OPEN**.

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
change. Status: **OPEN**.

### Q18a. Is configuration-port stimulus in scope?

The architecture rules say the unused APB port is tied off, but `CFG.cfgAccess`
can select `CFG_APB` or `CFG_CHI_MMIO`, and both change the DUT's address map at
run time through `regionUpdate`.

**Default.** Tie the APB port off (`PSEL = 0`, `PENABLE = 0`, `PWRITE = 0`, all
data and control inputs zero) in the default configuration, observe `PREADY` and
`PSLVERR`, and mark APB and CHI-MMIO region programming `Not verified` in the
feature matrix with the reason recorded. An APB region-programming test is added
only if asked, since driving it means the APB is no longer an unused port.
Status: **OPEN**.

---

## Confirmed assumptions

None yet. Entries move here as `[ASSUMPTION:n]` once answered, and the number is
the question number so that a source tag and this log never drift apart.

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
