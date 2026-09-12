# Configurable AMBA CHI Interconnect Design Specification

## Document status

This revision is the Stage 0 architecture baseline. It contains the specification
declaration, proposed architecture, initial feature matrix, source manifest,
NodeID encoding, and default mesh placement. No RTL is delivered in Stage 0.

## 1. Scope and normative baseline

The normative protocol baseline is **Arm IHI 0050H, AMBA CHI Architecture
Specification, Issue H, dated 17 September 2025**. The section references below
are Issue H references. The official Arm document index identifies Issue H as
the latest issue:

- <https://developer.arm.com/documentation/ihi0050/h/>

The design targets coherent on-chip communication between Requesters,
Subordinates, Home Nodes, and a Miscellaneous Node. It does not target AMBA CHI
Chip-to-Chip (IHI 0098), CCIX, CXS, or a die-to-die transport.
`PrefetchTgtHint` behavior intended to reconstruct a dropped prefetch across a
C2C link, C2C-reserved encodings, containerization, and every C2C link service
are excluded. Ordinary on-chip `PrefetchTgt` remains in scope.

Issue H content used here has been checked for the relevant architecture,
transaction, coherence, link, RME/MEC, MTE, and interface chapters. The Issue H
errata document has not yet been incorporated. Consequently, no behavior
affected by an Issue H erratum will be claimed complete until the applicable
RTL stage reviews that erratum. Device Assignment, Coherent Device Assignment,
Granular Data Isolation, PBHA, Multi-request, Limited Data Elision, and RME
beyond the requested NonSecure/NSE and MEC handling are Issue H capabilities
but are not requested and are deferred.

CHI specifies externally visible protocol behavior and permits different
interconnect organizations; it does not require the crossbar, ring, or mesh
microarchitectures proposed here (IHI 0050H B1.1.3, B1.2, and Chapter B3).
All choices labeled **IMPLEMENTATION DEFINED** in this document are project
choices, not CHI requirements.

## 2. Stage 0 architecture proposal

### 2.1 Layering

```text
chi_interconnect_top
├── node interface shells (RN-F, RN-D, RN-I, SN-F, SN-I)
│   ├── link activation and L-Credit logic
│   └── packed-flit decode/encode
├── requester-side SAM
├── topology-independent transport adaptation
│   └── chi_noc_top
│       ├── chi_xbar       [TOPOLOGY == CROSSBAR]
│       ├── chi_ring       [TOPOLOGY == RING]
│       └── chi_mesh       [TOPOLOGY == MESH_2D]
│           └── MESH_X × MESH_Y chi_mesh_xp instances
├── NUM_HNF chi_hnf_top instances
│   ├── POS / transaction trackers
│   ├── same-line hazard control
│   ├── snoop filter and snoop generator
│   ├── retry and protocol-credit manager
│   ├── DCT controller and CMO controller
│   └── exclusive monitor
├── NUM_HNI chi_hni_top instances
├── NUM_MN chi_mn_dvm instances
└── configuration endpoint
```

Each CHI protocol channel is converted at a node shell into a common internal
router record containing channel class, source NodeID, target NodeID, QoS,
payload length, and an opaque packed protocol payload. REQ, RSP, SNP, and DAT
use physically independent queues, arbitration state, and credit counters from
ingress to egress. The protocol blocks therefore do not depend on the selected
topology.

The common router interface is `chi_link_if`. It is an internal transport
interface, not a replacement for any node-facing CHI interface. `chi_router`
selects the topology route and `chi_vc_arb` performs QoS-aware arbitration with
age override. A packet never changes protocol channel class in the NoC.

Node-facing ports are arrays of `chi_rnf_if`, `chi_rnd_if`, `chi_rni_if`,
`chi_snf_if`, and `chi_sni_if`. Parameterization is uniform within each class.
Width conversion, if introduced later, must use an explicit adapter outside the
interconnect and is not silently performed.

SystemVerilog has no portable zero-length unpacked interface array. To support a
logical count of zero, every class port will use a physical extent of
`max(1, NUM_<class>)`; index zero is an inactive sentinel when the logical count
is zero. Configuration checks and generated logic use only the logical count.
The integrator must tie the sentinel interface inactive. This is an
**IMPLEMENTATION DEFINED** language-portability choice.

### 2.2 Home Node organization

Each HN-F is both Point of Coherency and Point of Serialization for addresses
mapped to it. A POS entry owns one active cache-line transaction, tracks all
required responses and acknowledgments, and releases only after completion and
ordering obligations are satisfied. Same-cache-line requests serialize before
protocol side effects. Different lines can progress independently.

The snoop filter is set-associative and inclusive of cached copies known to the
HN-F. It stores a precise RN-F sharer vector and owner indication. Capacity
replacement that might discard the only directory knowledge first performs
back-invalidation and waits for completion. This costs `NUM_RNF` sharer bits per
entry but avoids coarse broadcast traffic. A coarse mode is not proposed for
the initial implementation.

The initial retry policy has four protocol-credit types: read, write, dataless,
and DVM/prefetch. Retry candidates are age ordered within type; an age threshold
overrides QoS so a continuously backpressured low-QoS request eventually
receives a grant. This is **IMPLEMENTATION DEFINED** policy built around the CHI
RetryAck/PCrdGrant rules in B2.10.

### 2.3 Topology choices

#### CROSSBAR

Every ingress can reach every egress through per-output arbitration. Each
output has independent REQ/RSP/SNP/DAT arbitration and buffering. Arbitration
is highest effective QoS followed by round-robin among equals, with age
promotion to prevent starvation. The crossbar offers one accepted flit per
channel per uncongested output per cycle, but mux, arbitration, and wire cost
grow approximately with the product of ingress and egress counts.

#### RING

The ring is bidirectional. Route selection compares clockwise and
counter-clockwise distances; an exact tie chooses clockwise. Each channel has
independent directional storage and credits. Local injection competes with
transit traffic using bounded-burst round-robin; an age override guarantees an
injection opportunity, while ejection is work-conserving and cannot be blocked
by local injection. Shortest-path routing lowers average hops, but bisection
bandwidth is lower than the crossbar and mesh.

#### MESH_2D

The mesh contains `MESH_X * MESH_Y` crosspoints. Each XP has north, south, east,
and west mesh links plus `NUM_DEV_PORTS_PER_XP` device ports. Missing edge links
are tied inactive. Routing is deterministic XY: traverse X until the target X
coordinate is reached, then traverse Y, then select the target device port.

Dimension-ordered routing is acyclic at the routing-dependency level because a
packet never returns from Y to X and never reverses within a dimension. Each
REQ/RSP/SNP/DAT channel also has independent buffers and link credits, so a
protocol dependency cannot consume another protocol channel's reserved
transport resource. This separates routing-deadlock prevention from the
protocol completion dependencies.

The selected snoop distribution policy is **sequential HN unicast**, an
**IMPLEMENTATION DEFINED** choice. The HN-F walks the precise sharer vector and
issues one unicast snoop at a time. This avoids multicast replication state,
branch-credit coupling, and extra multicast deadlock analysis in every XP. It
also bounds each POS entry to one active snoop destination plus the remaining
sharer vector. The cost is latency proportional to the number of sharers:
approximately the sum of each snoop round trip, rather than the maximum of
parallel round trips, and the POS remains occupied longer.

For source `(sx, sy)` and destination `(dx, dy)`:

```text
hops = abs(dx - sx) + abs(dy - sy)
networkLatency = injectionCost
               + hops * (linkCost + xpTraversalCost)
               + destinationEjectionCost
```

With one registered route/arbitration traversal and one registered link per hop,
the no-contention planning value is `1 + 2*hops + 1` cycles. The local
source-XP traversal is included in injection; each traversed next-hop XP adds
one traversal. Exact pipelining will be frozen in Stage 3 MESH_2D.

HN-F hashing spreads successive interleave stripes over HN-F placements in this
order: southwest, northeast, northwest, southeast for the default 3×3 grid.
That order alternates both X and Y for consecutive home selections rather than
concentrating traffic on one row or column.

### 2.4 SAM and configuration proposal

The requester-side SAM maps an address to an HN NodeID. The HN-side SAM maps the
same address to an SN NodeID. Both consume IDs produced by the NodeID encoder in
`chi_pkg`; no second encoding exists.

Within a striped region, the proposed home selection is:

```text
line       = address / INTERLEAVE_GRANULE
foldedHash = line xor (line >> HN_HASH_SHIFT)
homeIndex  = foldedHash mod NUM_HNF
```

`INTERLEAVE_GRANULE` is a power of two and at least one cache line.
`HN_HASH_SHIFT` is configurable. Modulo is exact for arbitrary `NUM_HNF`; power
of two counts reduce to bit selection after XOR folding.

`CFG_ACCESS` defaults to `CFG_PARAM_ONLY`. `CFG_APB` adds an APB4 sideband shim,
and `CFG_CHI_MMIO` routes a reserved HN-I region to the same internal register
bank. The register interface, address map, security filtering, and quiesce
sequence are wholly **IMPLEMENTATION DEFINED** because CHI defines no
configuration register architecture. They will be frozen in Stage 4.

### 2.5 Initial default configuration

| Parameter | Default |
|---|---:|
| `NUM_RNF`, `NUM_RND`, `NUM_RNI` | 4, 0, 1 |
| `NUM_SNF`, `NUM_SNI` | 2, 1 |
| `NUM_HNF`, `NUM_HNI`, `NUM_MN` | 4, 1, 1 |
| `DATA_W`, `ADDR_W`, `NODEID_W`, `TXNID_W` | 256, 48, 11, 12 |
| `LPID_W`, `RSVDC_W`, `CCID_W`, `GROUPID_W` | 5, 0, 2, 8 |
| `NUM_IF_PER_NODE`, `REPL_CHANNELS` | 1, 1 |
| `TOPOLOGY`, `MESH_X`, `MESH_Y` | `MESH_2D`, 3, 3 |
| `NUM_DEV_PORTS_PER_XP` | 2 |
| `SNPFILTER_ENTRIES`, `SNPFILTER_WAYS` | 1024, 4 |
| `POS_ENTRIES`, `LCRD_DEPTH` | 32, 8 |
| `DATACHECK_EN`, `POISON_EN`, `PARITY_EN` | 1, 1, 0 |
| `MPAM_EN`, `MTE_EN`, `MEC_EN` | 0, 0, 0 |
| `DCT_EN`, `DMT_EN`, `DWT_EN` | 1, 1, 1 |
| `ATOMIC_EN`, `DVM_EN`, `STASH_EN`, `EXCL_EN` | 1, 1, 1, 1 |
| `CFG_ACCESS` | `CFG_PARAM_ONLY` |

## 3. Feature matrix

Status describes delivered synthesizable RTL, not architectural intent. Since
Stage 0 contains no RTL, every in-scope RTL feature is accurately marked
**Not implemented**. The notes identify its planned stage. This matrix will be
updated after each stage.

| Feature | Issue H section | Status | Notes |
|---|---|---|---|
| REQ/RSP/SNP/DAT packed flits and typed views | B2.1-B2.2, B13.8-B13.10, C1 | Not implemented | Stage 1 package and interfaces |
| L-Credit accounting and return | B13.11, B14.2 | Not implemented | Stage 2; independent per channel |
| TX/RX activation and deactivation | B14.5-B14.6 | Not implemented | Stage 2; credit drain before STOP |
| RN-F system coherency handshake | B15.1-B15.2 | Not implemented | Stage 2 |
| Interface parity | B9.3 | Not implemented | Stage 2, `PARITY_EN` |
| Multiple interfaces and replicated channels | B13.7 | Not implemented | Stages 1-2; deterministic TxnID hash distribution |
| Read transaction family | B2.3.1, B4.2.1, B5.1, C4 | Not implemented | Stage 5: requested ReadNoSnp, Sep, Once variants, coherent reads |
| Write transaction family | B2.3.2, B4.2.3-B4.2.4, B5.3, C4 | Not implemented | Stage 5: full, partial, copyback, combined CMO, zero-data forms |
| Dataless, stash, and CMO family | B2.3.4-B2.3.5, B4.2.2, B5.2, B7 | Not implemented | Stage 5 |
| AtomicStore/Load/Swap/Compare | B2.3.3, B2.9.6, B4.2.5, B5.4 | Not implemented | Stage 5; all legal sizes and endian handling |
| DVMOp and MN sequencing | B2.3.7, B8 | Not implemented | Stages 5-6 |
| PrefetchTgt and response | B2.3.6, B4.2.6 | Not implemented | Stage 5; C2C reconstruction hint excluded |
| Exclusive accesses and HN monitor | B6 | Not implemented | Stage 5 |
| Non-forwarding, forwarding, stash, and DVM snoops | B4.3-B4.4, B4.8-B4.9, B8.3 | Not implemented | Stage 5 |
| I/SC/UC/SD/UD/UDP and partial/empty states | B4.1, B4.6-B4.8 | Not implemented | Stage 5 |
| PoC, PoS, and POS tracker | B1.5, B2.7, B4.11 | Not implemented | Stage 5 |
| Inclusive precise snoop filter | B4.4, B4.11 | Not implemented | Stage 5; capacity eviction back-invalidates |
| Same-address hazard serialization | B2.7, B4.11, B5.6 | Not implemented | Stage 5 |
| Order, ReadReceipt, ordered write observation | B2.7 | Not implemented | Stage 5 |
| RetryAck/PCrdGrant/AllowRetry | B2.10 | Not implemented | Stage 5; four implementation-defined credit types |
| TxnID, DBID, CompAck, combined/separate completion | B2.4-B2.5, B2.7.3-B2.7.4 | Not implemented | Stage 5 |
| DCT and forwarding fallback | B2.5.1.3, B4.8.3, B5.1.3 | Not implemented | Stage 5, `DCT_EN` |
| DMT including ReadNoSnpSep | B2.5.1.1-B2.5.1.2, B5.1 | Not implemented | Stage 5, `DMT_EN` |
| DWT | B2.3.2, B13.10.24 | Not implemented | Stage 5, `DWT_EN` |
| Requester-side and HN-side SAM | B3.1-B3.3 | Not implemented | Stage 4 |
| Crossbar transport | B1.2 (topology freedom) | Not implemented | Stage 3 CROSSBAR |
| Bidirectional ring transport | B1.2 (topology freedom) | Not implemented | Stage 3 RING |
| 2D mesh and XP routing | B1.2 (topology freedom) | Not implemented | Stage 3 MESH_2D |
| QoS and starvation control | B11.1, B13.10.1 | Not implemented | Stages 3 and 5 |
| MPAM propagation | B11.4, B13.10.43 | Not implemented | Stage 5, `MPAM_EN`; no resource regulation in initial scope |
| Completer Busy | B11.6, B13.10.48 | Not implemented | Stage 5 propagation |
| OK/EXOK/DERR/NDERR, poison, DataCheck, RSVDC | B9, B13.10.45, B13.10.53-B13.10.54, B13.10.60 | Not implemented | Stages 1 and 5 |
| NonSecure/NSE and MECID | B2.8.2, B10.2, B10.6, B13.10.61 | Not implemented | Stages 1 and 5; Issue H baseline supports MEC |
| MTE TagOp/TU/tag data | B12, B13.10.38-B13.10.41 | Not implemented | Stages 1 and 5, `MTE_EN` |
| Parameter validation | B16 plus project constraints | Not implemented | Stage 1, one `chi_cfg_check` block |
| Parameter-only/APB/CHI-MMIO configuration | Not defined by CHI | Not implemented | Stage 4; project-defined behavior |
| Bound protocol assertions | Relevant sections above | Not implemented | Stage 7 |
| C2C/CXS/CCIX/die-to-die services | IHI 0098, outside IHI 0050 scope | Not implemented | Deliberately excluded |
| Issue H Device Assignment, GDI, PBHA, Multi-request, Limited Data Elision | B2.6, B2.9.5, B10.7-B10.8, B11.5 | Not implemented | Explicitly deferred; not in requested feature set |

## 4. NodeID encoding

The following encoding is a single **IMPLEMENTATION DEFINED** project encoding
used by placement, routing, requester SAM targets, HN-side SAM targets, and
generated requests:

```text
NodeID = {meshY, meshX, devicePort, deviceId}
```

Field widths are:

```text
MESH_Y_BITS       = max(1, ceil(log2(MESH_Y)))
MESH_X_BITS       = max(1, ceil(log2(MESH_X)))
DEVICE_PORT_BITS  = max(1, ceil(log2(NUM_DEV_PORTS_PER_XP)))
DEVICE_ID_BITS    = NODEID_W - MESH_Y_BITS - MESH_X_BITS - DEVICE_PORT_BITS
```

`deviceId` is the stable logical-node ordinal: RN-Fs, RN-Ds, RN-Is, SN-Fs,
SN-Is, HN-Fs, HN-Is, then MNs. The elaboration checker rejects a non-positive
`DEVICE_ID_BITS`, an ordinal that does not fit, coordinates outside the mesh,
an unplaced node, and more than one logical node assigned to the same
`(meshX, meshY, devicePort)`.

For the default configuration the encoding is:

```text
NodeID[10:9] = meshY
NodeID[8:7]  = meshX
NodeID[6]    = devicePort
NodeID[5:0]  = deviceId
```

XY routing extracts only the coordinate fields. The destination XP extracts
`devicePort`; the endpoint checks `deviceId`. Crossbar and ring routing use the
same complete NodeID, so changing topology does not change SAM contents.

## 5. Default 3×3 mesh placement

Coordinates start at `(0,0)` in the southwest. Port 0 favors infrastructure and
Subordinates; port 1 favors Requesters. `--` is an unused physical port.

```text
                         north
        x=0                    x=1                    x=2
y=2  [p0 HNF2, p1 --]       [p0 --,   p1 --]       [p0 HNF3, p1 --]
          |                      |                      |
y=1  [p0 SNI0, p1 RNF2]----[p0 MN0,  p1 HNI0]----[p0 SNF1, p1 RNF3]
          |                      |                      |
y=0  [p0 HNF0, p1 RNF0]----[p0 SNF0, p1 RNF1]----[p0 HNF1, p1 RNI0]
                         south
```

| Logical node | `deviceId` | `(meshX, meshY, devicePort)` | Default NodeID |
|---|---:|---:|---:|
| RNF0 | 0 | (0, 0, 1) | `11'h040` |
| RNF1 | 1 | (1, 0, 1) | `11'h0C1` |
| RNF2 | 2 | (0, 1, 1) | `11'h242` |
| RNF3 | 3 | (2, 1, 1) | `11'h343` |
| RNI0 | 4 | (2, 0, 1) | `11'h144` |
| SNF0 | 5 | (1, 0, 0) | `11'h085` |
| SNF1 | 6 | (2, 1, 0) | `11'h306` |
| SNI0 | 7 | (0, 1, 0) | `11'h207` |
| HNF0 | 8 | (0, 0, 0) | `11'h008` |
| HNF1 | 9 | (2, 0, 0) | `11'h109` |
| HNF2 | 10 | (0, 2, 0) | `11'h40A` |
| HNF3 | 11 | (2, 2, 0) | `11'h50B` |
| HNI0 | 12 | (1, 1, 1) | `11'h2CC` |
| MN0 | 13 | (1, 1, 0) | `11'h28D` |

The four HN-Fs occupy the corners. The default hash order is HNF0, HNF3, HNF2,
HNF1, which alternates diagonals before reusing a row or column.

## 6. Planned elaboration checks

Stage 1 will place all project dependency checks in one named
`chi_cfg_check` generate block in the top-level:

- legal data, address, NodeID, and TxnID widths;
- nonnegative node counts and sufficient NodeID device ordinal space;
- positive interface/replication counts, POS depth, and L-Credit depth;
- legal snoop-filter geometry, including entries divisible by ways;
- `DCT_EN` requires at least one RN-F and HN-F;
- `DMT_EN` requires an HN and an SN-F;
- `DWT_EN` requires an HN and an SN-F;
- `STASH_EN` requires an RN-F and HN-F;
- `DVM_EN` requires at least one MN and one DVM-capable Requester;
- `EXCL_EN` requires a Home Node and positive monitor resources;
- `MTE_EN`, `MEC_EN`, and optional fields require widths and Issue H support;
- mesh dimensions, capacity, complete placement, and collision freedom;
- APB and CHI-MMIO configuration modes have exactly their required endpoint;
- each optional flit field has a consistent enable and width on every interface
  in its node-class array.

## 7. Source manifest and compile order

`filelist.f` is the simulator manifest. At Stage 0 it contains comments only
because there is no SystemVerilog source yet. Sources will be enabled in this
order as their stages are delivered:

```text
pkg/chi_pkg.sv
pkg/chi_cfg_pkg.sv
if/chi_rnf_if.sv
if/chi_rnd_if.sv
if/chi_rni_if.sv
if/chi_snf_if.sv
if/chi_sni_if.sv
if/chi_link_if.sv
link/chi_link_tx.sv
link/chi_link_rx.sv
link/chi_lcrd_mgr.sv
link/chi_link_fsm.sv
noc/chi_route_compute.sv
noc/chi_vc_arb.sv
noc/chi_router.sv
noc/chi_xbar.sv
noc/chi_ring.sv
noc/chi_mesh_xp.sv
noc/chi_mesh.sv
noc/chi_noc_top.sv
sam/chi_hn_hash.sv
sam/chi_sam.sv
hnf/chi_pos.sv
hnf/chi_snoop_filter.sv
hnf/chi_snp_gen.sv
hnf/chi_hazard.sv
hnf/chi_retry.sv
hnf/chi_dct_ctrl.sv
hnf/chi_cmo.sv
hnf/chi_excl_mon.sv
hnf/chi_hnf_top.sv
hni/chi_cfg_slave.sv
hni/chi_hni_top.sv
mn/chi_mn_dvm.sv
top/chi_interconnect_top.sv
sva/chi_link_sva.sv
sva/chi_proto_sva.sv
sva/chi_ordering_sva.sv
```

All design files will use SystemVerilog-2017. The primary compile target is
Verilator with:

```sh
verilator --lint-only --sv -Wall -Wno-fatal -f filelist.f \
  --top-module chi_interconnect_top
```

An independent syntax/elaboration check will use:

```sh
iverilog -g2012 -s chi_interconnect_top -f filelist.f
```

Icarus Verilog exposes a SystemVerilog-2012 switch rather than a 2017 switch;
the RTL will remain within the synthesizable subset common to both while
Verilator is the SystemVerilog-2017 lint authority.

## 8. Stage 0 deferrals

- All packages, interfaces, RTL, assertions, and coverage are deferred to their
  declared delivery stages.
- Exact bit-level flit layouts are deferred to Stage 1 and will be derived from
  Issue H field applicability rather than copied as fixed-width constants.
- Exact link race-state handling and deactivation timing are deferred to Stage
  2.
- Router pipeline depths are deferred to the applicable Stage 3 topology
  substage.
- SAM registers and safe reconfiguration sequencing are deferred to Stage 4.
- Transaction legality, cache transitions, and HN completion corner cases are
  deferred to Stage 5.
- The complete parameter, signal, flow, verification, and decisions chapters
  are deferred to Stage 8.
