---
title: "Configurable AMBA 5 CHI Interconnect"
subtitle: "Design Specification"
author: "CHI RTL project"
---

# Document status

This document describes the RTL in this repository against Arm IHI 0050H. It
is a reference implementation, not a compliance claim. Every statement about
behaviour below was checked against the source, and the feature matrix in
Section 1.3 states exactly where each function stops.

The document is generated from a single Markdown source in `doc-src/` so that
the Word file in `docs/` and the RTL never drift apart. See Section 12.7 for
the regeneration command.

# 1 Scope, Issue H baseline, and feature status

## 1.1 Baseline and exclusions

The architectural reference is Arm IHI 0050H, *AMBA CHI Architecture
Specification*, Issue H, 17 September 2025:
<https://developer.arm.com/documentation/ihi0050/h/>. Section references
identify relevant Issue H material without reproducing Arm prose or tables.

The project implements an on-chip CHI interconnect among RN-F, RN-D, RN-I,
SN-F, SN-I, HN-F, HN-I and MN functions. The following are outside the
project scope and are not present in any form:

- CHI Chip-to-Chip (IHI 0098), CXS, CCIX, die-to-die framing, C2C containers
  and link services.
- Device Assignment and Coherent Device Assignment protocol behaviour. The
  RME-CDA `StreamID` and `SecSID1` flit fields are carried, but no assignment
  or ownership checking exists.
- GDI.
- An RN-side cache controller. This repository is the interconnect; the RN-F
  line-state model in Section 10 is the contract an RN must meet, not RTL
  that is shipped here.

The Issue H errata have not been assessed against this RTL. An item marked
Implemented below means the named block exists in synthesizable RTL and
performs the described function; it is not an interoperability statement.

## 1.2 Status definitions

**Implemented** --- the function exists in synthesizable RTL and performs the
described protocol behaviour over its stated contract.

**Partial** --- useful logic exists, but protocol cases, integration, or
end-to-end behaviour are incomplete. The boundary column says which.

**Not implemented** --- no semantic implementation exists. An enum value or a
packed flit field by itself is carriage, not implementation.

## 1.3 Feature matrix

| Feature | Issue H reference | Status | Actual RTL boundary |
|---|---|---|---|
| REQ/RSP/SNP/DAT records and pack/unpack | B13.9, B13.10 | Implemented | Configurable packed records match the Issue H field lists and slot widths, including every documented field overlay. Opcode-dependent field legality is not policed. |
| Fixed flit slot widths and overlays | B13.9.1--B13.9.4 | Implemented | `TxnID` 12, `ReturnTxnID`/`StashLPID` 12, `NumReq`/`Size` 6, `GroupID` 8, RSP `DBID` 12, DAT `DBID` 16, `DataSource` 8, `CCID` 2, `DataID` 2, `CacheLineID` 6, `PAS` 3 are slot widths independent of the node-side field widths. |
| `PAS[2:0]` replacing `NS`/`NSE` | B2.9, B13.10 | Implemented | REQ and SNP carry the three-bit Physical Address Space selector and the SAM decodes its non-secure sense. |
| One node-facing interface type | B13 | Implemented | `if/chi_if.sv` is the only interface declaration in the repository and is a superset used by all five external node-class arrays. |
| Top-level interface count and replicated channels | B13.7 | Not implemented | Elaboration requires `numIfPerNode == 1` and `replChannels == 1`. No top-level replication exists. |
| L-Credit manager, link TX and link RX | B13.11, B14.2 | Implemented | `chi_lcrd_mgr`, `chi_link_tx` and `chi_link_rx` implement finite credit accounting, receive buffering and credit return. |
| Link layer integrated at every node port | B13.11, B14.2 | Implemented | `chi_link_port` instantiates three receivers and three or four transmitters per port, and `chi_interconnect_top` instantiates one per RN-F, RN-D, RN-I, SN-F and SN-I interface. `*LCRDV` are real credit pulses, not ready echoes. |
| Link activation and deactivation FSM | B14.5--B14.6 | Implemented | `chi_link_fsm` implements STOP, ACTIVATE, RUN and DEACTIVATE with credit-drain conditions, and is instantiated per channel per direction inside every port. |
| System coherency interface | B14.4 | Partial | `TXSACTIVE` and `RXSACTIVE` follow reset and `SYSCOACK` echoes `SYSCOREQ`. There is no power-domain or coherency-entry sequencing. |
| Flit parity | B9.3 | Implemented | `chi_link_tx` generates per-byte flit parity and `chi_link_rx` checks it. `parityEn` is accepted at the top and a mismatch raises `linkParityError` for that node. |
| Control and credit signal checks | B9.3 | Not implemented | The `*CHK` scalars beside control, valid and credit signals are declared in the interface and driven to zero. Only the flit parity vectors are live. |
| Link error reporting | B9 | Implemented | `linkUp`, `linkParityError` and `linkCreditError` are per-node-ordinal top-level outputs. Credit error covers receive-buffer overflow and L-Credit overflow or underflow. |
| Four physically separated internal channels | B2.1, B13 | Implemented | REQ, RSP, SNP and DAT have separate ready/valid arrays, arbitration and topology storage throughout. |
| Crossbar | B1.2 | Implemented | Per-output, per-channel QoS, age and round-robin arbitration. |
| Bidirectional ring | B1.2 | Implemented | Shortest-direction routing, clockwise tie-break, directional registers, local and transit alternation, and ejection round-robin. |
| 2D mesh with deterministic XY routing | B1.2, B3 | Implemented | Per-channel routers, one output register per crosspoint output, and placement-driven device ports. |
| Per-hop L-Credits inside the fabric | B13.11 | Not implemented | Internal topology links use ready/valid with registered crosspoint outputs. CHI L-Credits terminate at the node ports. |
| Requester SAM, HN striping and HN-I SAM | B3.1--B3.3 | Implemented | Ordered region table, security rejection, XOR-fold hash and runtime update ports. |
| `PrefetchTgt` routing | B3.3.1, B4.2.6.2 | Implemented | `chi_prefetch_map` maps the address to an SN-F independently of the HN hash, the request bypasses the Home, and both the HN-F and HN-I accept and discard it without a response and without a RetryAck. |
| Coherent read family | B4, B5.1 | Partial | `ReadShared`, `ReadClean`, `ReadNotSharedDirty`, `ReadUnique`, `ReadOnce`, `ReadPreferUnique`, `ReadOnceCleanInvalid` and `ReadOnceMakeInvalid` are classified, snooped when required, forwarded, and completed. Response-state selection is simplified and not every legal state combination is produced. |
| Write family | B5.3 | Partial | Fourteen writes including the stash forms are classified and relayed with `CompDBIDResp` combining. Partial-write byte-enable rules, write cancellation and every combined form are incomplete. |
| CMO and combined write-CMO | B7 | Partial | Opcode classification plus completion and persist tracking. Architectural completion points and the snoop and data side effects of each CMO are incomplete. |
| DCT | B2.5.1.3, B4.8 | Partial | Eligibility, forwarding-snoop generation and `SnpRespFwded` collection exist. The fallback path when the forwarding peer cannot supply data is not implemented. |
| DMT, including `ReadNoSnpSep` | B2.5.1.1--B2.5.1.2 | Implemented | `chi_dmt_ctrl` selects direct memory transfer, the downstream read names the Requester in `ReturnNID` and `ReturnTxnID`, the Subordinate sends `CompData` straight to the Requester, and the Home issues only the response it still owes. |
| DWT | B2.3.2.1, B13.10.24 | Implemented | `chi_dwt_ctrl` sets `DoDWT` on the downstream write, the Subordinate returns `DBIDResp` directly to the Requester, and the Home forwards only the completion. |
| Atomics | B2.3.3, B4.2.5, B5.4 | Implemented | `chi_atomic_alu` implements the `AtomicStore`, `AtomicLoad`, `AtomicSwap` and `AtomicCompare` operations. The Home serializes the operand, reads the initial value, applies the operation, writes it back and returns the original value. Little-endian and big-endian operands are both handled. The datapath is 64 bits, so operands wider than 8 bytes are not supported. |
| Far atomics | B4.2.5 | Partial | Operations are executed at the Home. There is no negotiation that pushes the operation to the Subordinate. |
| DVM and MN | B2.3.7, B8 | Partial | The MN serially unicasts `SnpDVMOp` to configured Requesters and collects responses. The two-part DVM message payload is not decoded, so operation-specific ordering is absent. |
| Sequential coherent snoops | B4.3--B4.4, B4.8 | Partial | The Home walks a precise sharer vector one RN-F at a time and collects responses including forwarded and dirty-data cases. One snoop is outstanding at a time. |
| Cache stashing | B4.9, B7 | Implemented | `chi_stash_ctrl` decodes `WriteUniqueFullStash`, `WriteUniquePtlStash`, `StashOnceShared`, `StashOnceUnique`, `StashOnceSepShared` and `StashOnceSepUnique`, resolves `StashNID`, `StashNIDValid`, `StashLPID` and `StashLPIDValid`, issues the matching stash snoop, honours a `DataPull` in the snoop response by issuing the implied read, and returns `Comp`, `StashDone` or the combined `CompStashDone`. |
| RN cache states and transitions | B4.1, B4.6--B4.8 | Not implemented | Out of project scope. State encodings exist in `chi_pkg` and the required model is documented in Section 10, but there is no RN cache controller here. |
| POS and same-line hazards | B1.5, B2.7, B4.11 | Partial | POS storage, allocation and same-line plus ordered hazard logic exist, but the Home FSM admits one transaction at a time, so configured POS depth does not create concurrency. |
| Inclusive precise snoop filter | B4.4, B4.11 | Partial | Set-associative sharer and owner storage with rotating replacement and sequential back-invalidation. State updates are simplified and are not a complete Issue H directory model. |
| Request Retry, `RetryAck` and `PCrdGrant` | B2.5.5, B2.10 | Implemented | `chi_retry` records the `SrcID`, QoS and credit class behind every `RetryAck`, allocates one of four P-Credit types, and issues `PCrdGrant` naming the recorded Requester with no `TxnID` and no `DBID`. QoS selects which record is granted and age breaks ties. |
| P-Credit return | B2.5.6, B2.10.1 | Implemented | A granted credit leaves the accounting either when a request arrives with `AllowRetry` deasserted or when the Requester returns it with `PCrdReturn`, which the Home accepts and discards. |
| Exclusives | B6 | Partial | Line and requester reservation monitors produce `EXOK`. Request classification and the full set of invalidation and failure rules are simplified. |
| Ordering and `ReadReceipt` | B2.7 | Partial | Ordered requests are globally serialized and a `ReadReceipt` is returned for a request that asks for one. Endpoint order and request order are not distinguished. |
| `DataCheck` and poison carriage | B9, B13.10 | Partial | Optional DAT bits pack and unpack end to end. There is no error-response generation from a data check failure. |
| MultiReq, `NumReq` and `CacheLineID` | B2.8, B13.10 | Not implemented | The fields and the `Size`/`NumReq` slot overlay are carried, but no multi-request expansion or per-line tracking exists. `multiReqEn` is checked metadata. |
| PBHA | B13.10 | Not implemented | The four-bit field and its REQ, SNP and DAT slot overlays are carried. No page-based hardware attribute behaviour exists. |
| MTE tag semantics | B12, B13.10 | Not implemented | `Tag`, `TU` and `TagOp` are carried. There is no allocation-tag storage, matching or tag-operation behaviour. |
| MEC | B10.6, B13.10 | Not implemented | The 16-bit `MECID` and its DAT slot overlay are carried. No MEC access control, translation or consistency checking exists. |
| MPAM | B11.4 | Partial | The 12-bit or 15-bit bus is carried in REQ and SNP. There is no resource partitioning or monitoring. |
| APB configuration | Project-defined | Implemented | Secure-write staged region editor with a quiescent commit. Limitations are in Section 7. |
| CHI MMIO configuration | Project-defined | Partial | The HN-I recognizes a 4 KiB window and simple read and write offsets. Security, validation and quiescent commit are incomplete. |
| SVA | Sections above | Partial | Bound local safety, stability and protocol-field properties with functional covers. There is no full protocol checker and no proof closure. |

# 2 Architecture and hierarchy

## 2.1 Block diagram

```
  RN-F / RN-D / RN-I arrays              SN-F / SN-I arrays
        one chi_if each                     one chi_if each
               |                                   |
        chi_link_port                       chi_link_port
   L-Credits, parity, activation      L-Credits, parity, activation
               |                                   |
      requester SAM + PrefetchTgt map              |
               |                                   |
      +------------------ chi_noc_top -------------------+
      |  CROSSBAR          RING            MESH_2D       |
      |  separate REQ / RSP / SNP / DAT ready-valid      |
      +--------------------------+-----------------------+
                                 |
            +--------------------+--------------------+
            |                    |                    |
       chi_hnf_top          chi_hni_top           chi_mn_dvm
      coherent Home       noncoherent Home       DVM sequencer
      + CFG-MMIO endpoint
            |                    |
          SN-F                 SN-I

  APB4 --> chi_cfg_slave --> shared SAM region-update broadcast
```

HN-F, HN-I and MN are internal endpoints on the fabric, not external
`chi_if` ports, so they have no link layer.

## 2.2 RTL hierarchy

```
chi_interconnect_top
├── chi_cfg_check                            (elaboration assertions)
├── rnf_ports[*] / rnd_ports[*] / rni_ports[*] : chi_link_port
│   ├── chi_link_rx  x3   (REQ, RSP, DAT from the node)
│   ├── chi_link_tx  x3   (RSP, SNP, DAT to the node)
│   └── chi_link_fsm x6   (one per channel per direction)
├── snf_ports[*] / sni_ports[*] : chi_link_port
│   ├── chi_link_rx  x2   (RSP, DAT from the node)
│   └── chi_link_tx  x3   (REQ, RSP, DAT to the node)
├── requester_sam[*]
│   ├── chi_sam  ── chi_hn_hash
│   └── chi_prefetch_map
├── apb_cfg : chi_cfg_slave                          [CFG_APB]
├── hnf_nodes[*] : chi_hnf_top
│   ├── chi_pos
│   ├── chi_hazard
│   ├── chi_snoop_filter
│   ├── chi_snp_gen
│   ├── chi_retry
│   ├── chi_dct_ctrl
│   ├── chi_dmt_ctrl
│   ├── chi_dwt_ctrl
│   ├── chi_stash_ctrl
│   ├── chi_atomic_alu
│   ├── chi_cmo
│   └── chi_excl_mon
├── hni_nodes[*] : chi_hni_top
│   └── chi_sam
├── mn_nodes[*] : chi_mn_dvm
└── chi_noc_top
    ├── chi_xbar ── chi_vc_arb[*]                   [CROSSBAR]
    ├── chi_ring                                    [RING]
    └── chi_mesh                                    [MESH_2D]
        └── chi_mesh_xp[*]
            └── chi_router[REQ/RSP/SNP/DAT]
                ├── chi_route_compute[*]
                └── chi_vc_arb[*]
```

`chi_lcrd_mgr` is used by `chi_link_tx`. Every link block is now inside the
product hierarchy; none of them is harness-only.

## 2.3 Handshake discipline

Every ready/valid channel in the design obeys two rules, and the RTL is
structured so that a linter can see both:

1. A valid and its flit never depend combinationally on the ready they are
   paired with. The Home Node decides a `RetryAck`, a `PCrdGrant` and every
   transaction response without looking at `rspOutReady`.
2. A module that drives both directions of a handshake writes the forward and
   the backward direction in separate `always_comb` blocks. `chi_mesh` uses
   four blocks --- ingress forward, egress forward, egress ready, ingress
   ready --- because a single block would make every crosspoint ready appear
   to depend on every crosspoint valid.

The consequence is that the whole fabric elaborates with no circular
combinational logic, which Section 12.6 records as a passing lint result.

# 3 Parameters and elaboration constraints

## 3.1 `chi_cfg_t`

All count fields are unsigned. "No explicit maximum" means the elaboration
checker has no direct bound; array size, NodeID capacity and tool resources
still apply.

| Field | Default | Accepted by `chi_cfg_check` | Effect |
|---|---:|---|---|
| `numRnf` | 4 | 0 or greater | External RN-F interfaces and Home sharer-vector width. |
| `numRnd` | 0 | 0 or greater | External RN-D interfaces. |
| `numRni` | 1 | 0 or greater | External RN-I interfaces. |
| `numSnf` | 2 | required when `numHnf>0` | External SN-F interfaces and `PrefetchTgt` targets. |
| `numSni` | 1 | required when `numHni>0` | External SN-I interfaces. |
| `numHnf` | 4 | 0 or greater | Internal HN-F endpoints and hash targets. |
| `numHni` | 1 | 0 or greater | Internal HN-I endpoints. |
| `numMn` | 1 | 0 or greater | Internal MN endpoints. |
| `dataW` | 256 | 128, 256 or 512 | DAT data and derived BE, tag, TU and check widths. |
| `addrW` | 48 | 44 through 52 | REQ address and line and tag widths. |
| `nodeIdW` | 11 | 7 through 16 | Active NodeID bits. Internal buses are always 16 bits wide. |
| `txnIdW` | 12 | 8 through 12 | Node-side TxnID width. The flit slot is always 12 bits. |
| `lpidW` | 5 | 1 through 5 | LPID and `StashLPID` overlay width. |
| `rsvdcW` | 0 | 0, 4, 8, 12, 16, 24 or 32 | REQ and DAT RSVDC width. |
| `ccidW` | 2 | 1 or 2 | Node-side CCID width. The flit slot is 2 bits. |
| `groupIdW` | 8 | 1 through 8 | Group-ID overlay width within the 8-bit slot. |
| `mpamW` | 0 | 0, 12 or 15; must be non-zero when `mpamEn` | MPAM bus width. |
| `numIfPerNode` | 1 | exactly 1 | Metadata only; multiple interfaces are rejected. |
| `replChannels` | 1 | exactly 1 | Metadata only; channel replication is rejected. |
| `topology` | `MESH_2D` | `CROSSBAR`, `RING`, `MESH_2D` | Selects the generated NoC. |
| `meshX`, `meshY` | 3, 3 | positive for mesh | Mesh coordinates and NodeID fields. |
| `numDevPortsPerXp` | 2 | positive for mesh | Local ports per crosspoint and NodeID field. |
| `snpFilterEntries` | 1024 | positive, divisible by ways | Total Home directory entries. |
| `snpFilterWays` | 4 | 1 through entries, exact divisor | Directory associativity. |
| `posEntries` | 32 | positive | POS array depth. The Home is still globally serial. |
| `retryRecords` | 16 | positive | Retry record table depth, that is, the number of outstanding `RetryAck` records the Home can hold. |
| `lcrdDepth` | 8 | 2 or greater | L-Credits advertised per channel and receive-buffer depth. |
| `exclMonitors` | 32 | positive | Exclusive monitor entries. |
| `interleaveGranule` | 64 | power of two, at least 64 | HN hash stripe bytes. |
| `hnHashShift` | 6 | no range check | XOR fold distance. A shift at or above `addrW` collapses the folded term to zero. |
| `dataCheckEn` | 1 | 0 or 1 | Adds `dataW/8` DAT DataCheck bits. |
| `poisonEn` | 1 | 0 or 1 | Adds `dataW/64` DAT poison bits. |
| `parityEn` | 0 | 0 or 1 | Enables flit parity generation and checking in every link. |
| `mpamEn` | 0 | 0 or 1 | Adds the MPAM bus to REQ and SNP. |
| `mteEn` | 0 | 0 or 1 | Affects DCT eligibility only. MTE semantics are absent. |
| `mecEn` | 0 | 0 or 1; mutually exclusive with `cdaEn` | Adds the 16-bit MECID to REQ, SNP and DAT. |
| `pbhaEn` | 0 | 0 or 1 | Adds the 4-bit PBHA field to REQ. |
| `cdaEn` | 0 | 0 or 1; mutually exclusive with `mecEn` | Adds `StreamID` and `SecSID1` to REQ. |
| `multiReqEn` | 0 | 0 or 1 | Checked metadata. No multi-request behaviour. |
| `dctEn` | 1 | if 1, RN-F and HN-F must exist | Enables DCT eligibility and forwarding snoops. |
| `dmtEn` | 1 | if 1, a Home and SN-F must exist | Enables direct memory transfer. |
| `dwtEn` | 1 | if 1, a Home and SN-F must exist | Enables direct write transfer. |
| `atomicEn` | 1 | if 1, a Home must exist | Enables the atomic transaction path. |
| `dvmEn` | 1 | if 1, an MN and a Requester must exist | Enables the MN sequencer. |
| `stashEn` | 1 | if 1, RN-F and HN-F must exist | Enables stash decode, stash snoops and Data Pull. |
| `exclEn` | 1 | if 1, a Home and monitors must exist | Enables exclusive monitors. |
| `cfgAccess` | `CFG_PARAM_ONLY` | enum; CHI MMIO also requires HN-I | Selects no runtime writes, APB, or CHI MMIO. |

Because MECID and StreamID share one REQ field of width `Max(E,R)`, only one
of MEC and RME-CDA can be carried on a given interface. Elaboration rejects
both being enabled.

Derived packed widths at the default configuration are REQ 153, RSP 79,
SNP 106 and DAT 437 bits. The formulas are `reqFlitWidth`, `rspFlitWidth`,
`snpFlitWidth` and `datFlitWidth` in `chi_pkg`, and
`top/chi_stage1_compile.sv` checks each one against an independent sum of the
field list so that a field added to a record cannot silently bypass the width
helper.

## 3.2 Top parameters and illegal combinations

| Parameter | Default and legal rule | Effect |
|---|---|---|
| `AGE_LIMIT` | 16; positive | QoS arbiter starvation promotion threshold. |
| `NUM_REGIONS` | 4; positive | SAM table depth and select width. |
| `NUM_NODES` | sum of all node counts; must equal that sum | Fabric endpoint count and the index space for the link status outputs. |
| `NODE_IDS` | all-ones sentinel derives the default; effective IDs must be unique | Endpoint identities and routing targets. |
| `USE_DEFAULT_PLACEMENTS` | 1 | Selects the fixed 14-entry map; requires exactly 14 nodes. |
| `PLACEMENTS` | each valid, correct class and index, in range, collision-free | Custom mesh and local-port placement. |
| `CFG_MMIO_BASE` | top 4 KiB of the address space | Must be 4 KiB aligned in CHI-MMIO mode. |
| `USE_DEFAULT_REGIONS` | 1 | Selects the default map in Section 6. |
| `REGION_*` | arrays of `NUM_REGIONS` | Custom base, inclusive limit, target and attributes. |

For the mesh, `meshX*meshY*numDevPortsPerXp >= NUM_NODES`,
`deviceIdWidth(CFG) > 0`, placement coordinates and ports must fit, NodeIDs
must encode the placement routing fields, and no NodeID or placement may
collide. Default placement is valid only for the default 14-node population.
HN-F to SN-F and HN-I to SN-I striping uses modulo, so the nonzero
subordinate checks are essential.

## 3.3 Top-level ports beyond the interfaces

| Port | Direction | Width | Purpose |
|---|---|---:|---|
| `clk`, `resetn` | in | 1 | Single clock and synchronous active-low reset. |
| `PADDR`, `PSEL`, `PENABLE`, `PWRITE`, `PWDATA`, `PSTRB`, `PPROT` | in | 12, 1, 1, 1, 32, 4, 3 | APB4 configuration request. |
| `PRDATA`, `PREADY`, `PSLVERR` | out | 32, 1, 1 | APB4 configuration response. |
| `linkUp` | out | `NUM_NODES` | Set while any receive channel of that node's link is in RUN. |
| `linkParityError` | out | `NUM_NODES` | Flit parity mismatch observed on that node's link. |
| `linkCreditError` | out | `NUM_NODES` | Receive-buffer overflow or L-Credit overflow or underflow on that node's link. |

Bits of the three status vectors that correspond to the internal HN-F, HN-I
and MN ordinals read zero, because those endpoints have no external link.

# 4 The single `chi_if` node-facing interface

## 4.1 Superset rule

There is exactly one SystemVerilog interface declaration in the repository:
`if/chi_if.sv`. Every external RN-F, RN-D, RN-I, SN-F and SN-I port is an
array of this superset interface. There are no class-specific interfaces and
no separate internal transport interface.

The interface has no modports, so the directions below are integration rules
rather than compiler-enforced directions. "Node" means the external endpoint
and "IC" means `chi_interconnect_top`. A logical count of zero still creates
one sentinel interface, because portable SystemVerilog cannot declare a
zero-length interface array. That sentinel is inactive and must be tied off.

## 4.2 Signal widths and drivers

Let `RW=reqFlitWidth(CFG)`, `SW=rspFlitWidth(CFG)`, `NW=snpFlitWidth(CFG)`,
`DW=datFlitWidth(CFG)` and `PW(W)=ceil(W/8)`.

| Signal group | Width | Driver | Consumer | Applicability |
|---|---:|---|---|---|
| `CLK`, `RESETn` | 1 each | IC | Node | All classes; mirrors `clk` and the synchronous active-low `resetn`. |
| `TXLINKACTIVEREQ` | 1 | Node | IC | All classes; drives the node-to-IC link FSM out of STOP. |
| `TXLINKACTIVEACK` | 1 | IC | Node | All classes; asserted once the IC receivers have credits to advertise. |
| `RXLINKACTIVEREQ` | 1 | IC | Node | All classes; the IC activates its transmit links while out of reset. |
| `RXLINKACTIVEACK` | 1 | Node | IC | All classes; gates IC credit acceptance and flit transmission. |
| `TXSACTIVE`, `RXSACTIVE` | 1 each | IC | Node | All classes; follow reset. |
| `SYSCOREQ` | 1 | Node | IC | All classes. |
| `SYSCOACK` | 1 | IC | Node | All classes; echoes `SYSCOREQ`. |
| `TXREQFLITPEND`, `TXREQFLITV`, `TXREQFLIT[RW-1:0]` | 1, 1, RW | Node | IC | RN-F, RN-D, RN-I. `PEND` is accepted and not used for early arbitration. |
| `TXREQLCRDV` | 1 | IC | Node | Requesters; one pulse per REQ L-Credit granted by the IC receiver. |
| `RXREQFLITPEND`, `RXREQFLITV`, `RXREQFLIT[RW-1:0]` | 1, 1, RW | IC | Node | SN-F, SN-I. |
| `RXREQLCRDV` | 1 | Node | IC | SN-F, SN-I; one pulse per REQ L-Credit granted to the IC transmitter. |
| `TXRSPFLITPEND`, `TXRSPFLITV`, `TXRSPFLIT[SW-1:0]` | 1, 1, SW | Node | IC | All five classes. |
| `TXRSPLCRDV` | 1 | IC | Node | All classes; RSP L-Credit pulse. |
| `RXRSPFLITPEND`, `RXRSPFLITV`, `RXRSPFLIT[SW-1:0]` | 1, 1, SW | IC | Node | All five classes. |
| `RXRSPLCRDV` | 1 | Node | IC | All classes; RSP L-Credit pulse. |
| `TXSNPFLITPEND`, `TXSNPFLITV`, `TXSNPFLIT[NW-1:0]` | 1, 1, NW | Node | IC | Unused for every external class; no port in this design receives snoops from a node. |
| `TXSNPLCRDV` | 1 | IC | Node | Tied low for every class. |
| `RXSNPFLITPEND`, `RXSNPFLITV`, `RXSNPFLIT[NW-1:0]` | 1, 1, NW | IC | Node | RN-F, RN-D, RN-I; tied inactive for SN-F and SN-I. |
| `RXSNPLCRDV` | 1 | Node | IC | Requesters; SNP L-Credit pulse. |
| `TXDATFLITPEND`, `TXDATFLITV`, `TXDATFLIT[DW-1:0]` | 1, 1, DW | Node | IC | All five classes. |
| `TXDATLCRDV` | 1 | IC | Node | All classes; DAT L-Credit pulse. |
| `RXDATFLITPEND`, `RXDATFLITV`, `RXDATFLIT[DW-1:0]` | 1, 1, DW | IC | Node | All five classes. |
| `RXDATLCRDV` | 1 | Node | IC | All classes; DAT L-Credit pulse. |
| `TXREQFLITCHK`, `RXREQFLITCHK` | `PW(RW)` | Same side as the flit | Opposite side | Live per-byte flit parity when `parityEn` is set. |
| `TXRSPFLITCHK`, `RXRSPFLITCHK` | `PW(SW)` | Same side as the flit | Opposite side | Live per-byte flit parity when `parityEn` is set. |
| `TXSNPFLITCHK`, `RXSNPFLITCHK` | `PW(NW)` | Same side as the flit | Opposite side | Live per-byte flit parity when `parityEn` is set. |
| `TXDATFLITCHK`, `RXDATFLITCHK` | `PW(DW)` | Same side as the flit | Opposite side | Live per-byte flit parity when `parityEn` is set. |
| scalar `*CHK` beside control, valid and credit signals | 1 each | Same side as the checked base signal | Opposite side | Declared for all classes. Node-driven checks are ignored and IC-driven checks are zero. |

Unused node outputs must be tied to zero. Unused IC outputs are already
driven inactive. Integrators must not infer legal channel capability from the
presence of a signal in this superset.

## 4.3 Link credit behaviour

Each channel in each direction has its own credit counter and its own
activation FSM. On leaving STOP, a receiver advertises `lcrdDepth` credits
one `LCRDV` pulse at a time and refills a credit every time a buffered flit
is consumed by the fabric. A transmitter sends a flit only while in RUN and
holding at least one credit. Deactivation waits until the channel's credits
are quiescent, which is why the port ORs the per-channel activation signals:
the OR holds the handshake asserted until the last channel has drained.

Receive-buffer overflow, credit overflow and credit underflow are detected
and reported on `linkCreditError`; they indicate a peer that violated the
credit contract, not a recoverable condition.

# 5 Topologies, routing, arbitration and progress

## 5.1 Common transport

`chi_noc_flit_t` carries the channel, QoS, target NodeID and an opaque
maximum-size DAT payload. REQ, RSP, SNP and DAT are separate ready/valid
fabrics that share no buffers and no arbiters. Backpressure requires valid
and payload stability. These are internal ready/valid channels; the CHI
L-Credit channels terminate in `chi_link_port`.

## 5.2 Crossbar

Each output selects the highest-QoS request. Equal QoS starts at a rotating
index. Once a request's age reaches `AGE_LIMIT`, aged requests exclude
non-aged requests. A stalled grant locks until it is accepted. An uncongested
output accepts one flit per channel per cycle. Unknown target IDs remain
backpressured.

## 5.3 Bidirectional ring

Distance is computed from endpoint array order. The shorter direction wins
and an exact tie goes clockwise. Each node, direction and channel has one
registered slot. When local injection and transit contend for an empty slot,
a preference bit alternates after the winner, which prevents permanent local
or transit starvation under continued service. Clockwise, counter-clockwise
and local ejection requests use a three-way rotating priority. The ring has
no QoS or age threshold.

For planning, use a conservative sustained rate of 0.5 flit per cycle per
directional link per channel under injection and transit contention. That is
a budgeting bound, not a guarantee: uncongested trains do better and blocked
ejection does worse.

## 5.4 Mesh, placement and NodeID

Routing is deterministic XY: east or west to the destination X, then north or
south to the destination Y, then the local device port. Coordinates start at
the south-west corner `(0,0)`.

```
                         north
        x=0                    x=1                    x=2
y=2  [p0 HNF2, p1 --]     [p0 --,   p1 --]      [p0 HNF3, p1 --]
y=1  [p0 SNI0, p1 RNF2]---[p0 MN0,  p1 HNI0]----[p0 SNF1, p1 RNF3]
y=0  [p0 HNF0, p1 RNF0]---[p0 SNF0, p1 RNF1]----[p0 HNF1, p1 RNI0]
                         south
```

The project-defined NodeID encoding is:

```
NodeID     = {meshY, meshX, devicePort, deviceId}
field width = max(1, ceil(log2(cardinality)))   for Y, X and port
deviceId width = nodeIdW - Ywidth - Xwidth - portwidth
```

At the defaults this gives `[10:9]=Y`, `[8:7]=X`, `[6]=port` and
`[5:0]=ordinal`. Ordinals run RN-F, RN-D, RN-I, SN-F, SN-I, HN-F, HN-I, MN.
The default HN-F NodeIDs are HNF0 `11'h008`, HNF1 `11'h109`, HNF2 `11'h40a`
and HNF3 `11'h50b`. The hash array follows ordinal order and the corner
placement supplies the spatial distribution.

Each `chi_router` contributes one registered crosspoint output stage, and the
wires between crosspoints are combinational. For source `(sx,sy)` and
destination `(dx,dy)`:

```
hops = |dx-sx| + |dy-sy|
planning latency ~ (hops + 1) crosspoint cycles + endpoint and link cycles
```

Stalls add arbitration and destination-backpressure cycles. The link layer
adds one receive-buffer cycle in each direction.

## 5.5 Snoop distribution, deadlock and livelock

Home snoops are sequential unicasts in ascending sharer index, and only one
snoop is outstanding from the generator, so latency sums the round trips of
all sharers. HN-F `i` is statically striped to SN-F `i % numSnf`, and the
HN-I uses the same rule for SN-I. `PrefetchTgt` does not follow that
striping: it uses its own address-to-SN-F mapper.

Separate channel fabrics prevent one protocol channel from consuming another
channel's transport buffer, and mesh XY routing is dimension-ordered. Those
choices remove routing-dependency cycles, but there is no complete
protocol-level deadlock proof in this repository. Ring finite slots plus
blocked ejection can backpressure a direction globally. Crossbar and mesh age
arbitration and the ring's rotating preferences address local starvation, but
there is no end-to-end livelock watchdog and no bounded-completion proof.

# 6 System Address Map

## 6.1 Lookup and default regions

Regions use inclusive `[base, limit]` bounds with ascending-index first-match
priority. Attributes are `[3:2]=kind`, `[1]=secureOnly`, `[0]=valid`. A
secure-only match by a non-secure request returns `unmappedError`; the lookup
does not fall through to an overlapping lower-priority region.

With `NUM_REGIONS=4` and `USE_DEFAULT_REGIONS=1`:

| Index | Base | Inclusive limit | Kind and target | Valid |
|---:|---|---|---|---:|
| 0 | `0` | `2^(addrW-1)-1` | HN-F hash | 1 |
| 1 | `2^(addrW-1)` | `CFG_MMIO_BASE-1` | HNI0 when present | 1 |
| 2 | `CFG_MMIO_BASE` | `2^addrW-1` | MMIO, HNI0 when present | 1 |
| 3 | `0` | `0` | zero target | 0 |

The default `CFG_MMIO_BASE` is `2^addrW - 4096`.

## 6.2 HN hash and worked example

```
granuleNumber = address >> log2(interleaveGranule)
hashValue     = granuleNumber xor (granuleNumber >> hnHashShift)
hnfIndex      = hashValue mod numHnf
target        = HN_NODE_IDS[hnfIndex]
```

At the defaults, address `0x0000_0000_10c0` gives granule number `0x43`,
folded value `0x42`, index `2` and target HNF2 (`11'h40a`).

## 6.3 `PrefetchTgt` mapping

`PrefetchTgt` is sent by a Requester directly to a Subordinate and never
reaches the Home, so it cannot use the HN hash. `chi_prefetch_map` maps the
address to an SN-F with the same interleave granule:

```
granuleNumber = address >> log2(interleaveGranule)
snfIndex      = granuleNumber mod numSnf
target        = SNF_NODE_IDS[snfIndex]
```

The transaction has no response, so nothing is tracked for it, and it must
never be given a `RetryAck`. Both Home types accept and discard it if one
reaches them.

## 6.4 Retargeting

APB or CHI-MMIO updates replace one active region atomically at the SAM clock
edge, and the update is broadcast to the requester SAMs and to the HN-I
staging and SAM state. APB requires the top's `trafficQuiescent`, which
checks external fabric ingress valids and Home and MN idle, but not every
internal topology slot. CHI-MMIO commit has no quiescence check. Software
must avoid overlapping active traffic and must stage base, limit, target and
attributes before commit. The RTL does not validate `base <= limit` or target
existence on a runtime update.

# 7 Configuration access

CHI defines no register map for this project. The access mechanism, offsets,
security policy and commit protocol in this section are
**implementation defined**.

## 7.1 APB4 map

APB runs on `clk` and `PREADY` is always 1. Addresses are 12-bit and word
aligned. Writes merge the bytes selected by `PSTRB`. Reads are unrestricted.
A write with `PPROT[1]=1` is rejected as non-secure. Unsupported or
misaligned accesses, out-of-range SELECT writes and non-quiescent COMMIT
writes return `PSLVERR`.

| Offset | Name | Access | Reset or read value | Write effect |
|---:|---|---|---|---|
| `0x000` | SELECT | RW | 0 | Select a region; reject a value at or above `NUM_REGIONS`. |
| `0x004` | BASE_LO | RW | `REGION_BASE[n][31:0]` | Stage the low address bytes. |
| `0x008` | BASE_HI | RW | upper configured address bits | Stage bits `addrW-1:32`. |
| `0x00c` | LIMIT_LO | RW | `REGION_LIMIT[n][31:0]` | Stage the low limit bytes. |
| `0x010` | LIMIT_HI | RW | upper configured limit bits | Stage bits `addrW-1:32`. |
| `0x014` | TARGET | RW | `REGION_TARGET[n]` | Stage the target NodeID. |
| `0x018` | ATTRIBUTES | RW | `REGION_ATTRIBUTES[n]` | Stage the low four bits. |
| `0x01c` | COMMIT | W, reads zero | 0 | If byte strobe 0 is set and traffic is quiescent, pulse one region update. |

The required software order is SELECT, stage all changed fields, stop
initiators, observe system-specific quiescence, then COMMIT. A COMMIT with
`PSTRB[0]=0` does nothing and does not error.

## 7.2 CHI MMIO map and limitations

The HN-I recognizes any address in the 4 KiB window at `CFG_MMIO_BASE`.

| Low-byte offset | Read and write object |
|---:|---|
| `0x00` | selected region |
| `0x08` | full staged base |
| `0x10` | full staged inclusive limit |
| `0x18` | staged target |
| `0x20` | staged attributes |
| `0x28` | a write commits; a read falls through to the selected-region value |

A read returns one `CompData`; a write consumes the next DAT flit and returns
`Comp`. The path does not check the DAT opcode, byte enables, security or
PAS, privilege, base and limit validity, target validity, or quiescence.
Unsupported offsets silently read SELECT or ignore the write and still
complete successfully, and an invalid SELECT payload is silently ignored.
Only one HN-I transaction is active at a time. This is a reference control
path, not a hardened management interface.

# 8 Transaction flows

Each flow below is the architecturally intended sequence. The note after each
table states what the RTL does.

## 8.1 ReadShared with DCT

| Step | From | To | Message |
|---:|---|---|---|
| 1 | Requesting RN-F | HN-F | `ReadShared` |
| 2 | HN-F | Owning RN-F | `SnpSharedFwd` |
| 3 | Owning RN-F | Requesting RN-F | `CompData` with the forwarded line |
| 4 | Owning RN-F | HN-F | `SnpRespFwded` |
| 5 | HN-F | Requesting RN-F | completion as required |

RTL status: Partial. Eligibility, the forwarding snoop and `SnpRespFwded`
collection exist. The fallback when the forwarding peer cannot supply data is
not implemented.

## 8.2 ReadUnique with DMT

| Step | From | To | Message |
|---:|---|---|---|
| 1 | RN-F | HN-F | `ReadUnique` |
| 2 | HN-F | RN-F sharers | snoops as required by the directory |
| 3 | HN-F | SN-F | `ReadNoSnp` with `ReturnNID` and `ReturnTxnID` naming the Requester |
| 4 | SN-F | RN-F | `CompData` direct to the Requester |
| 5 | HN-F | RN-F | the response the Home still owes, when one is required |

RTL status: Implemented. `chi_dmt_ctrl` decides eligibility, the downstream
request carries the Requester's identity and a Home-unique TxnID, and the
Home issues only its own remaining response. `ReadNoSnpSep` is handled on the
same path.

## 8.3 WriteBackFull with DWT

| Step | From | To | Message |
|---:|---|---|---|
| 1 | RN-F | HN-F | `WriteBackFull` |
| 2 | HN-F | SN-F | forwarded write with `DoDWT` set |
| 3 | SN-F | RN-F | `DBIDResp` direct to the Requester |
| 4 | RN-F | SN-F | `CopyBackWrData` via the Home |
| 5 | SN-F | HN-F | `Comp` |
| 6 | HN-F | RN-F | forwarded completion |

RTL status: Implemented for the direct-write path. Without DWT the Home
combines `Comp` into `CompDBIDResp` itself. Partial-write byte-enable rules
and write cancellation remain incomplete.

## 8.4 CleanUnique with snoops

| Step | From | To | Message |
|---:|---|---|---|
| 1 | RN-F | HN-F | `CleanUnique` |
| 2 | HN-F | Sharer A | selected snoop |
| 3 | Sharer A | HN-F | `SnpResp` |
| 4 | HN-F | Sharer B | selected snoop |
| 5 | Sharer B | HN-F | `SnpResp` |
| 6 | HN-F | SN-F | downstream request when required |
| 7 | HN-F | RN-F | completion |

RTL status: Partial and sequential. The opcode is recognized, but snoop
selection and directory transitions are simplified.

## 8.5 AtomicLoad

| Step | From | To | Message |
|---:|---|---|---|
| 1 | Requester | HN-F | `AtomicLoad` with the operation in the opcode |
| 2 | HN-F | Requester | `DBIDResp` |
| 3 | Requester | HN-F | `NonCopyBackWrData` carrying the operand |
| 4 | HN-F | RN-F sharers | snoops when the line is shared, which may supply the initial value |
| 5 | HN-F | SN-F | `ReadNoSnp` for the initial value when no snoop supplied it |
| 6 | SN-F | HN-F | `CompData` with the initial value |
| 7 | HN-F | SN-F | `WriteNoSnpFull` with the computed value |
| 8 | HN-F | Requester | `CompData` with the original value, or `Comp` for a store |

RTL status: Implemented. `chi_atomic_alu` computes `AtomicStore`,
`AtomicLoad`, `AtomicSwap` and `AtomicCompare` with both operand
endiannesses. Big-endian operands are byte-reversed within the operand size
before the arithmetic and reversed again on the way out, because atomic data
is byte invariant. A snoop that invalidates a dirty peer copy supplies the
initial value and removes the downstream read. The datapath is 64 bits wide,
so operands wider than 8 bytes are unsupported. The operation is always
performed at the Home; there is no far-atomic negotiation.

## 8.6 Request Retry

| Step | From | To | Message |
|---:|---|---|---|
| 1 | Requester | HN-F | request with `AllowRetry=1` |
| 2 | HN-F | Requester | `RetryAck` carrying the Home's chosen `PCrdType` |
| 3 | HN-F | Requester | `PCrdGrant` with the same `PCrdType` once a resource exists |
| 4 | Requester | HN-F | the request re-sent with `AllowRetry=0` and the granted `PCrdType` |
| 5 | Requester | HN-F | `PCrdReturn` instead of step 4 if the credit is no longer needed |

RTL status: Implemented. The Home records the `SrcID`, QoS and credit class
behind each `RetryAck` in a `retryRecords`-deep table, and the record is taken
when the `RetryAck` is accepted rather than when it is first presented, so a
back-pressured response channel cannot book the same Requester twice. QoS
selects which record is granted next and age breaks ties. `PCrdGrant` names
the recorded Requester and carries no `TxnID` and no `DBID`. When the record
table is full, the request is back-pressured instead of retried, which keeps
the credit accounting exact.

## 8.7 WriteUniqueFullStash with Data Pull

| Step | From | To | Message |
|---:|---|---|---|
| 1 | RN-I | HN-F | `WriteUniqueFullStash` with `StashNID` and optional `StashLPID` |
| 2 | HN-F | RN-I | `DBIDResp` |
| 3 | RN-I | HN-F | `NonCopyBackWrData` |
| 4 | HN-F | Stash target RN-F | `SnpMakeInvalidStash` or `SnpUniqueStash` |
| 5 | Stash target RN-F | HN-F | `SnpResp` with `DataPull` set, or without it |
| 6 | HN-F | SN-F | the read implied by the Data Pull |
| 7 | SN-F | HN-F | `CompData` |
| 8 | HN-F | Stash target RN-F | `CompData` completing the implied read |
| 9 | HN-F | RN-I | `Comp` |

RTL status: Implemented. `chi_stash_ctrl` chooses the snoop from the stash
opcode and whether the line is fully written, resolves the target from
`StashNID` and `StashNIDValid`, and passes `StashLPID` and `StashLPIDValid`
through the snoop's 12-bit slot. An accepted Data Pull is turned into
`ReadUnique` or `ReadNotSharedDirty` and the directory records the stash
target as the new owner. The independent `StashOnce` forms return `StashDone`,
and `StashOnceSep` forms return the combined `CompStashDone`.

## 8.8 DVM Sync

| Step | From | To | Message |
|---:|---|---|---|
| 1 | Initiating Requester | MN | `DVMOp` |
| 2 | MN | Requester A | `SnpDVMOp` |
| 3 | Requester A | MN | `SnpResp` |
| 4 | MN | Requester B | `SnpDVMOp` |
| 5 | Requester B | MN | `SnpResp` |
| 6 | MN | Initiating Requester | `Comp` |

RTL status: Partial. Sequential broadcast and response collection exist. The
two-part DVM payload is not decoded, so no operation-specific ordering is
applied.

# 9 Home Node internals

## 9.1 Serialization

`chi_pos` holds `posEntries` records with the line address, requester, TxnID,
opcode and completion flags. `chi_hazard` blocks same-line overlap, blocks an
ordered request while any POS entry is active, and blocks all new requests
while an ordered entry is active. That is more conservative than a line-only
POS.

The controlling FSM in `chi_hnf_top` is the stronger limitation. It accepts a
normal request only in `HNF_IDLE`, stores one `activeReq`, and does not
return to idle until completion or `CompAck`. Therefore all normal Home
transactions are globally serialized regardless of `posEntries`, and the
multi-entry POS does not create concurrency. The FSM has 22 states: the
baseline request, snoop, response and back-invalidation states; eight atomic
states; an ordered-receipt state; a DMT response state; two stash completion
states; and two Data Pull states.

Two requests bypass the FSM entirely. `PCrdReturn` carries no transaction and
`PrefetchTgt` has no response and must never be retried, so both are accepted
and discarded without allocating a POS entry.

## 9.2 Directory

The snoop filter is set-associative, tracks precise RN-F sharers and one
owner, uses rotating replacement ways, and requests sequential
back-invalidation before replacing a valid full set. Updates are simplified:
a write invalidates, a unique read makes the requester the sole sharer and
owner, and another recognized coherent read ORs the requester into the sharer
vector. After an accepted Data Pull the stash target becomes the owner. This
is not the complete Issue H state machine.

## 9.3 Retry credits

`chi_retry` is the complete credit loop. On a `RetryAck` it records the
`SrcID`, the QoS and the credit class derived from the request category, and
it reports the per-class pending count and the per-class outstanding-credit
count. `CHI_CREDIT_TYPES` is 4 of the 16 `PCrdType` values Issue H allows; the
Home partitions its resources by request category. A grant is issued only
when the Home is idle, the POS can allocate, no back-invalidation is running,
and no previously granted credit is still outstanding, which prevents the Home
from promising the same resource twice. A credit leaves the accounting when a
request arrives with `AllowRetry` deasserted or when the Requester returns it
with `PCrdReturn`.

## 9.4 Ordering

A request that asks for a read receipt is answered with `ReadReceipt` from the
`HNF_ORDER_RECEIPT` state before the data path continues. Ordered requests are
globally serialized by the hazard logic. Endpoint order and request order are
not distinguished, so the implementation is stricter than Issue H requires.

# 10 RN-F boundary cache-state model

These tables are the required architectural model for an RN-F cache
controller that connects to this interconnect. They are not behaviour
implemented here. `chi_pkg` defines the I, SC, UC, UD, SD and UDP encodings,
but there is no RN line-state storage and no transition controller in this
repository.

## 10.1 Request-driven target states

| RN starting state | Operation | Intended successful target | Required external effects |
|---|---|---|---|
| I | `ReadShared` or `ReadClean` | SC, or a permitted dirty shared state from the response | Install the returned line and honour the response state. |
| I or SC | `ReadUnique` or `MakeUnique` | UC or UD according to the returned dirtiness | Other sharers must be invalidated before exclusive ownership. |
| SC | `CleanUnique` | UC | Complete snoops and cleaning before uniqueness. |
| UC | local write | UD | Mark dirty locally. |
| UD or SD | `WriteBackFull` | I, or a clean retained state according to the result | Transfer the full dirty line and wait for the required completion. |
| Any valid | `Evict` or `MakeInvalid` | I | Satisfy writeback and invalidation obligations first. |
| Any | atomic | the state dictated by the atomic response | Serialize the operand, the data update and the returned value. |
| Any | stash snoop target | the state the stash snoop requires | Optionally request a Data Pull and complete the implied read. |

## 10.2 Snoop-driven transitions

| Starting state | Snoop class | Intended result | Data obligation |
|---|---|---|---|
| I | any | I | Respond no copy; no data. |
| SC | shared or clean | SC | Usually no dirty data. |
| SC | unique or make-invalid | I | Invalidate and respond. |
| UC | shared | SC | Downgrade ownership. |
| UC | unique or make-invalid | I | Invalidate. |
| UD | shared | SD or SC as the response requires | Supply dirty data or transfer responsibility. |
| UD, SD or UDP | unique or make-invalid | I | Supply dirty or partial data as required, then invalidate. |
| Valid owner | forwarding snoop | the result dictated by the forward response | Send data to the forward target and the response to the Home. |
| Any | stash snoop | the state the stash opcode requires | Optionally set `DataPull` in the response to request the line. |

Partial and empty line handling, UDP rules, MTE allocation tags, poison and
DataCheck propagation, and the complete set of legal response-state
combinations remain the RN implementer's responsibility.

# 11 Clocking, reset, CDC and performance

All RTL uses one `clk`. APB `PCLK` is connected to it and every external
`chi_if.CLK` mirrors it. There are no asynchronous clock domains,
synchronizers or CDC FIFOs. Multi-clock integration requires external
adapters and CDC analysis.

`resetn` and `PRESETn` are active low but sampled synchronously, because
every sequential block uses `always_ff @(posedge clk)` and tests
`if (!resetn)`. There is no asynchronous reset edge. Integration must assert
reset long enough for it to be sampled and must deassert it synchronously.
The interconnect activates its own transmit links while out of reset;
sequenced link power-down is left to integration.

Reference throughput limits:

- Crossbar: at most one accepted flit per output, per channel, per cycle.
- Ring: one slot per node, direction and channel; use the conservative
  0.5 flit per cycle planning rate from Section 5.3.
- Mesh: one registered slot per crosspoint output and channel; no-contention
  network latency is approximately `hops+1` crosspoint cycles.
- Link: one receive-buffer cycle per direction, and a channel stalls whenever
  its credit count reaches zero, so `lcrdDepth` bounds the round-trip
  bandwidth of each channel.
- The Home, the HN-I and the MN each process one architectural transaction at
  a time, and sequential snoops and DVMs add one full response round trip per
  target.

No timing constraints, synthesis reports, PPA results, latency measurements
or performance guarantees are supplied.

# 12 Verification, source manifest and lint

## 12.1 Bound SVA inventory

| File | Assertions | Covers |
|---|---|---|
| `chi_link_sva.sv` | `NO_SEND_WITHOUT_RUN_OR_CREDIT`, `NO_CREDIT_OVERFLOW`, `NO_CREDIT_UNDERFLOW`, `STOP_TRANSITION_VALID`, `ACTIVATE_TRANSITION_VALID`, `RUN_TRANSITION_VALID`, `DEACTIVATE_TRANSITION_VALID`, `DEACTIVATION_CREDITS_DRAINED` | `LINK_ACTIVATION`, `LINK_DEACTIVATION` |
| `chi_link_rx_sva.sv` | `BUFFER_COUNT_IN_RANGE`, `NO_BUFFER_OVERFLOW`, `NO_RECEIVE_WITHOUT_RUN`, `STOP_TRANSITION_VALID`, `ACTIVATE_TRANSITION_VALID`, `RUN_TRANSITION_VALID`, `DEACTIVATE_TRANSITION_VALID`, `DEACTIVATION_BUFFER_DRAINED`, `PARITY_ERROR_OBSERVED`, `PARITY_ERROR_ONLY_WHEN_ENABLED` | `LINK_ACTIVATION`, `LINK_DEACTIVATION` |
| `chi_proto_sva.sv` | `REQ_INPUT_STABLE_UNDER_BACKPRESSURE`, `RSP_INPUT_STABLE_UNDER_BACKPRESSURE`, `DAT_INPUT_STABLE_UNDER_BACKPRESSURE`, `REQ_STABLE_UNDER_BACKPRESSURE`, `RSP_STABLE_UNDER_BACKPRESSURE`, `SNP_STABLE_UNDER_BACKPRESSURE`, `DAT_STABLE_UNDER_BACKPRESSURE`, `ACTIVE_RESPONSE_ID_CONSISTENT`, `RETRY_RESPONSE_ID_CONSISTENT`, `ONE_COMPLETION_PATH`, `PCRD_GRANT_FIELDS_UNUSED`, `RETRY_ACK_GRANT_MUTUALLY_EXCLUSIVE` | `RETRY_ACK_THEN_PCRD_GRANT_CLASS`, `PCRD_GRANT_SENT`, `DCT_SNOOP_FORWARD_PATH`, `DIRECTORY_BACK_INVALIDATION`, `EXCLUSIVE_SUCCESS`, `BASIC_READ_FLOW`, `BASIC_WRITE_FLOW` |
| `chi_mn_sva.sv` | `REQ_INPUT_STABLE_UNDER_BACKPRESSURE`, `RSP_INPUT_STABLE_UNDER_BACKPRESSURE`, `SNP_STABLE_UNDER_BACKPRESSURE`, `RSP_STABLE_UNDER_BACKPRESSURE`, `DVM_RESPONSE_ID_CONSISTENT` | `DVM_COMPLETION` |
| `chi_ordering_sva.sv` | pairwise `NO_DUPLICATE_ACTIVE_LINE`, per-entry `ALLOCATION_LINE_NOT_ACTIVE` | none |
| `chi_hnf_ordering_sva.sv` | `ORDERED_REQUEST_STARTS_QUIESCENT`, `ACTIVE_ORDERED_REQUEST_SERIALIZES` | none |

These are local assertions. They do not check complete opcode legality,
credit conservation across the whole port, cache-state correctness, every
response dependency, or end-to-end forward progress.

Binding an assertion module that takes an unpacked array port is not portable
across simulators, so `chi_pos` exports its line-address array packed. This
is the reason `chi_pos.lineAddr`, `chi_hazard.activeLineAddr` and
`chi_ordering_sva.lineAddr` are packed two-dimensional rather than unpacked.

## 12.2 Functional coverage outline

A complete environment should cross topology, channel, source and
destination, QoS, backpressure length and route length; cover every supported
request, response, snoop and data opcode; and exercise the SAM first-match,
security and update cases. It should hit every Home state, snoop-filter hit,
miss and replacement, hazard reason, retry class, credit grant and return,
exclusive success and failure, DCT eligibility and fallback, DMT and DWT
selection, stash target and Data Pull accept and decline, `PrefetchTgt`
mapping, DVM target count, APB error and CHI-MMIO offset. Negative bins
should include unknown NodeIDs, illegal configuration, malformed completion
identifiers, flit parity faults and credit-contract violations.

## 12.3 UVM structure

```
chi_env
├── rn_agent[*] / sn_agent[*]      active node-facing chi_if agents
│                                  including L-Credit and activation
├── apb_agent                      active only for CFG_APB
├── protocol_scoreboard            TxnID, DBID, data and completion
├── directory_reference_model      architectural RN states and sharers
├── sam_reference_model            regions, security, hash, commit
├── topology_route_scoreboard      NodeID, channel preservation, ordering
├── link_credit_scoreboard         per-channel credit conservation
├── virtual_sequencer              reads, writes, atomics, snoops, DVM,
│                                  retry, stash
└── coverage_collector
```

Agents must apply the node-class channel rules from Section 4 rather than
drive every signal in the superset, and they must respect L-Credits: a flit
may be sent only while the link is in RUN and a credit is held.

## 12.4 Formal-friendly properties

Recommended proof targets are: ready/valid stability; no duplication or loss
in each topology; destination and channel preservation; one-hot grants;
bounded age service under permanently ready outputs; XY monotonicity; ring
slot conservation; L-Credit conservation across each link direction; SAM
first-match determinism; commit atomicity; no duplicate Home line ownership;
sequential snoop target uniqueness; retry records never double-booked;
outstanding P-Credits never exceeding the granted resource; completion
identifiers matching the accepted request; and reset returning all valid
state to empty. Liveness assumptions must state eventual downstream ready and
eventual legal response.

## 12.5 Source manifest

`filelist.f` is the authoritative compile order:

```
pkg/chi_cfg_pkg.sv
pkg/chi_pkg.sv
if/chi_if.sv
link/chi_lcrd_mgr.sv
link/chi_link_fsm.sv
link/chi_link_tx.sv
link/chi_link_rx.sv
link/chi_link_port.sv
noc/chi_vc_arb.sv
noc/chi_xbar.sv
noc/chi_ring.sv
noc/chi_route_compute.sv
noc/chi_router.sv
noc/chi_mesh_xp.sv
noc/chi_mesh.sv
noc/chi_noc_top.sv
sam/chi_hn_hash.sv
sam/chi_sam.sv
sam/chi_prefetch_map.sv
hni/chi_cfg_slave.sv
hni/chi_hni_top.sv
mn/chi_mn_dvm.sv
hnf/chi_pos.sv
hnf/chi_hazard.sv
hnf/chi_snoop_filter.sv
hnf/chi_snp_gen.sv
hnf/chi_retry.sv
hnf/chi_dct_ctrl.sv
hnf/chi_atomic_alu.sv
hnf/chi_dmt_ctrl.sv
hnf/chi_dwt_ctrl.sv
hnf/chi_stash_ctrl.sv
hnf/chi_cmo.sv
hnf/chi_excl_mon.sv
hnf/chi_hnf_top.sv
top/chi_interconnect_top.sv
top/chi_interconnect_compile.sv
top/chi_link_compile.sv
top/chi_hnf_compile.sv
sva/chi_link_sva.sv
sva/chi_link_rx_sva.sv
sva/chi_proto_sva.sv
sva/chi_mn_sva.sv
sva/chi_ordering_sva.sv
sva/chi_hnf_ordering_sva.sv
top/chi_sva_compile.sv
```

`top/chi_stage1_compile.sv`, `top/chi_sam_compile.sv`,
`top/chi_xbar_compile.sv`, `top/chi_ring_compile.sv` and
`top/chi_mesh_compile.sv` are supplemental elaboration harnesses. They are
not entries in `filelist.f` and are not product hierarchy.

`tb/chi_smoke_tb.sv` is the simulation top described in Section 12.7. It is
also outside `filelist.f`, and it is not synthesizable. `Makefile` drives
lint, the smoke run and document generation.

## 12.6 Passing lint commands

`chi_interconnect_compile` is the lint and elaboration target for the product
top. The product top's node-facing ports are `chi_if` arrays, and a tool that
elaborates `chi_interconnect_top` as the design root has no interface
instances to bind them to, so the harness creates them.

```sh
verilator --lint-only --assert --sv -Wall -Wno-fatal \
  -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-UNDRIVEN -Wno-BLKLOOPINIT \
  -f filelist.f --top-module chi_interconnect_compile

verilator --lint-only --assert --sv -Wall -Wno-fatal \
  -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-UNDRIVEN -Wno-BLKLOOPINIT \
  -f filelist.f --top-module chi_sva_compile
```

Both commands produce no warnings, including no `UNOPTFLAT`, so the design
has no circular combinational logic. `UNUSEDSIGNAL` and `UNUSEDPARAM` are
suppressed because superset protocol records, optional ports and compile
harnesses intentionally expose fields that a given configuration does not
consume. `UNDRIVEN` is suppressed because the lint harnesses do not
instantiate external node drivers for `chi_if`. `BLKLOOPINIT` is suppressed
for Verilator 5.020's restriction on nonblocking initialization loops over
the unpacked snoop-filter arrays. `Wno-fatal` reports remaining warnings
without turning them into failures.

A supplemental harness is checked by appending its file and selecting it as
the top, for example:

```sh
verilator --lint-only --assert --sv -Wall -Wno-fatal \
  -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-UNDRIVEN -Wno-BLKLOOPINIT \
  -f filelist.f top/chi_ring_compile.sv --top-module chi_ring_compile
```

The harnesses `chi_hnf_compile`, `chi_link_compile`, `chi_mesh_compile`,
`chi_ring_compile`, `chi_xbar_compile`, `chi_sam_compile` and
`chi_stage1_compile` all pass with the same options.

## 12.7 Reset and idle smoke run

Lint elaborates the design but never executes it, so neither the
`chi_cfg_check` elaboration checks of Section 3.2 nor any bound assertion
actually runs during a lint pass. `tb/chi_smoke_tb.sv` closes that gap. It is
not a protocol testbench: it instantiates `chi_interconnect_compile`, holds
synchronous reset for eight cycles, releases it, and runs the idle fabric for
512 cycles.

```sh
make sim
```

The run fails if any elaboration check calls `$fatal`, if any bound assertion
fires out of reset, if the idle fabric presents a snoop flit to an RN-F or a
request flit to an SN-F, or if any port reports a flit parity or L-Credit
error while no traffic is in flight. Because the elaboration checks execute,
this run is what confirms at runtime that the default configuration is legal,
that every node has a unique placement, that each NodeID's routing fields
decode back to the placement that produced it, and that all four derived flit
widths fall inside the Issue H ranges.

The node count is derived from `CHI_CFG_DEFAULT` rather than written as a
literal, so the testbench follows a reconfigured node list without edits.

## 12.8 Regenerating this document

The Word file in `docs/` is generated from `doc-src/`:

```sh
make doc
```

which runs:

```sh
pandoc doc-src/chi_interconnect_design_spec.md --toc --toc-depth=2 \
  -o docs/chi_interconnect_design_spec.docx
```

Section numbers are written into the headings rather than generated, so that
the cross-references in the prose stay correct in every output format.

# 13 Open issues, known limitations and decisions

## 13.1 Known limitations

1. Exactly one interface per node and one channel replica are accepted. There
   is no top-level interface or channel replication.
2. Per-hop CHI L-Credits do not exist inside the fabric. The internal
   topology uses ready/valid with registered crosspoint outputs, and CHI
   L-Credits terminate at the node ports.
3. Only flit parity is live. The scalar `*CHK` control and credit checks are
   declared and driven to zero.
4. The Home, the HN-I and the MN globally serialize transactions, so the
   configured POS depth does not provide Home parallelism.
5. No RN cache controller is provided; Section 10 is the contract, not RTL.
6. MultiReq and `CacheLineID`, PBHA, MTE tag semantics and MEC access control
   are carriage only. MPAM is carried but not enforced.
7. Atomics are always executed at the Home rather than negotiated to the
   Subordinate, the atomic datapath is 64 bits so wider operands are
   unsupported, and DCT has no fallback path.
8. DVM decodes no payload, so no operation-specific ordering is applied.
9. Runtime SAM writes lack complete validation, CHI-MMIO lacks security and
   quiescent commit, and APB quiescence does not inspect every internal
   topology slot.
10. An unknown fabric destination is back-pressured indefinitely and has no
    error sink.
11. System coherency and link power sequencing are placeholders.
12. There is no full protocol testbench, no formal proof closure, no
    interoperability evidence, no CDC signoff, no synthesis signoff and no
    performance characterization.

## 13.2 Implementation-defined decision log

| Decision | Current choice | Consequence |
|---|---|---|
| Node-facing interfaces | One superset `chi_if` | Applicability is documented and tied off; direction is not modport-enforced. |
| Zero logical node count | A one-element sentinel array | The integrator ties the inactive sentinel outputs low. |
| Internal flow control | Ready/valid with registered crosspoint outputs | No claim of per-hop CHI L-Credits. |
| Handshake structure | Valid never depends on its ready; forward and backward directions live in separate blocks | The fabric elaborates with no circular combinational logic. |
| P-Credit types | 4 of the 16 Issue H values, indexed by request category | Resources are partitioned by category rather than per requester. |
| Retry record capacity | `retryRecords` entries; back-pressure when full | Credit accounting stays exact instead of over-promising. |
| `PrefetchTgt` target | A separate address-to-SN-F mapper | The hint reaches memory without consuming Home resources. |
| HN selection | XOR-folded granule modulo `numHnf` | Supports non-power-of-two Home counts. |
| SAM overlap | The lowest region index wins | A security rejection at the first match does not fall through. |
| NodeID | `{Y, X, port, ordinal}` | Placement and route fields must agree. |
| Mesh route | Deterministic XY | Simple dependency ordering, no adaptive balancing. |
| Ring tie | Clockwise | Deterministic equal-distance selection. |
| Snoop and DVM fanout | Sequential unicast | Minimal replication state, additive target latency. |
| Home to subordinate mapping | Index modulo the subordinate count | Static striping rather than address-based balancing. |
| Atomic execution point | Always the Home | No far-atomic negotiation, but one serialization point. |
| APB security | Writes require `PPROT[1]==0` | Reads remain unrestricted. |
| Reconfiguration | Staged fields plus an explicit commit | Software owns the ordering; CHI-MMIO is less protected than APB. |
| Reset | Synchronous active low | No asynchronous reset behaviour and no CDC support. |
| Bound assertion array ports | Packed two-dimensional, never unpacked | `bind` elaborates portably across simulators. |
| Loop bounds in helper functions | Computed once into a local, never a call in the loop condition | The bound is not recomputed per iteration, and the design simulates. |
