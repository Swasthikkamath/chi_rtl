# Configurable AMBA 5 CHI Interconnect

A synthesizable SystemVerilog-2017 reference implementation of an on-chip
interconnect built against Arm AMBA 5 CHI Issue H (IHI 0050H). It is not a
claim of CHI compliance or interoperability. CHI Chip-to-Chip, CXS, CCIX and
die-to-die transports are outside scope.

The RTL covers configurable Issue H flit records, three selectable internal
topologies built from one crosspoint with automatic placement, address mapping, a real CHI link layer on every node port, and
coherent and noncoherent Home Node transaction paths. Implemented protocol
behaviour includes L-Credits and link activation, flit parity, the Request
Retry credit loop with `RetryAck`, `PCrdGrant` and `PCrdReturn` (with every
granted credit holding an entry in reserve), a coherent Home that runs one
transaction per POS entry concurrently with same-location ordering and
parallel snoops, a non-coherent Home with concurrent, Endpoint-ordered
transactions, Physical Address Space checks per address region with
`{line, PAS}` locations in both Homes, an optional System Level Cache slice
per HN-F, a completer-side Granule Protection Check (on-chip table or GPT
walk), concurrent DVM operations at the MN with Sync ordering, a directory with dirty-safe eviction, atomic transactions, cache
stashing with Data Pull, and `PrefetchTgt` routing.

Behaviour that is deliberately partial or absent includes multiple interfaces
per node, replicated channels, per-hop L-Credits inside the fabric, an RN-side
cache controller, MTE tag semantics, MEC access control, MPAM enforcement, and
the MultiReq, `CacheLineID` and PBHA fields, which are carried but have no
behaviour. The feature matrix in the design specification states the exact
boundary of every function.

There is exactly one node-facing SystemVerilog interface type,
[`rtl/if/chi_if.sv`](rtl/if/chi_if.sv). It is a superset used for the RN-F, RN-D,
RN-I, SN-F and SN-I arrays. Signal applicability varies by node class, and
unused node-driven signals must be tied low. HN-F, HN-I and MN are internal
fabric endpoints with no external link.

## Design specification

[`docs/chi_interconnect_design_spec.docx`](docs/chi_interconnect_design_spec.docx)
is the design document: feature matrix, hierarchy, parameters, interface
directions, transaction flows, Home Node internals, and limitations.

It is generated from the single Markdown source in
[`doc-src/`](doc-src/chi_interconnect_design_spec.md) so that the document and
the RTL cannot drift apart:

```sh
make doc
```

Regeneration needs `pandoc` and `python3`. The architecture diagrams are
generated from Graphviz sources in [`doc-src/figures/`](doc-src/figures);
`make figures` rebuilds the `.png` files and needs `dot`. The rendered images
are committed so `make doc` works without Graphviz installed.

Word styling comes from `doc-src/reference.docx`, which
[`doc-src/build_reference_docx.py`](doc-src/build_reference_docx.py) builds
from pandoc's own template: A4, Times New Roman body text set justified,
Courier New in boxed code blocks, thin table rules with a shaded header row,
9pt captions below the table or figure they name, and a footer carrying the
project name and page number. Chapter openings, capitalised chapter titles and
caption placement are applied by
[`doc-src/house_style.lua`](doc-src/house_style.lua). The Contents, List of
Tables and List of Figures are Word field codes, so they fill in the first
time Word opens the file.

## Lint

`make lint` runs every harness. The two main targets are:

```sh
verilator --lint-only --assert --sv -Wall -Wno-fatal \
  -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-UNDRIVEN -Wno-BLKLOOPINIT \
  -f filelist.f --top-module chi_interconnect_compile

verilator --lint-only --assert --sv -Wall -Wno-fatal \
  -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-UNDRIVEN -Wno-BLKLOOPINIT \
  -f filelist.f --top-module chi_sva_compile
```

Both produce no warnings, including no `UNOPTFLAT`: no outgoing valid depends
on the ready it is paired with, and no module drives both directions of a
handshake from one combinational block.

`chi_interconnect_compile` is the lint target rather than
`chi_interconnect_top` because the product top's node-facing ports are
`chi_if` arrays. A tool that elaborates the top as the design root has no
interface instances to bind them to, so the harness creates them.

The unused-signal and unused-parameter suppressions cover superset protocol
records, optional ports and harness-only fields. `UNDRIVEN` covers external
`chi_if` inputs that have no node model in a lint harness. `Wno-fatal` keeps
remaining warnings visible without treating them as errors. `BLKLOOPINIT` is
suppressed for Verilator 5.020's restriction on nonblocking initialization of
the unpacked directory arrays; the syntax is accepted by synthesis tools.

## Smoke run

Lint elaborates the design but never runs it, so the elaboration checks in
`chi_interconnect_top` and the bound assertions never execute during a lint
pass. `make sim` closes that gap:

```sh
make sim
```

It checks three things: the elaboration checks pass, every external link
reaches RUN in both directions and exchanges its full L-Credit allocation,
and an idle fabric with live links stays silent.

Link bring-up needs a peer, because the interconnect owns only its half of
each link. [`tb/chi_node_link_bfm.sv`](tb/chi_node_link_bfm.sv) is that peer,
mirroring `chi_link_port` from the node side, and
[`tb/chi_sim_harness.sv`](tb/chi_sim_harness.sv) attaches one per external
port. Without it the receive links never leave STOP, no credits are issued,
and a silent fabric would prove nothing.

Passing confirms at runtime that the default configuration is legal, that
node placements are unique, that every NodeID's routing fields decode back to
its placement, that all four flit widths are inside the Issue H ranges, and
that link activation and credit accounting work on all eight ports.

`make simrand` replays the same run under several initialisation seeds.
Verilator initialises state to zero, so anything depending on a register or
input having been driven passes by accident; a four-state simulator would
propagate X and fail. This is the only part of the flow that can catch a
missing driver, and it found one — see Section 12.7 of the specification.

This is a smoke test, not a protocol testbench. There is no traffic
generator, scoreboard or coverage model; Section 12 of the design
specification outlines what a complete environment would need, and
Section 12.8 records where Verilator shaped this code and what a commercial
simulator would check that this flow cannot.

## Directory map

| Path | Contents |
|---|---|
| `rtl/pkg/` | Configuration types, opcodes, flit records, pack and unpack, NodeID helpers |
| `rtl/if/` | The single superset node-facing `chi_if` |
| `rtl/link/` | L-Credit manager, activation FSM, link TX and RX, and the per-port link wrapper |
| `rtl/noc/` | One parameterized crosspoint (`chi_xp`: router, route compute, arbitration) and the mesh, ring and crossbar wiring around it |
| `rtl/sam/` | Region lookup, HN hashing and the `PrefetchTgt` mapper |
| `rtl/hnf/` | HN-F per-entry transactions: POS and hazards, directory and victim buffer, snoops, downstream trackers, retry credits, stash, atomics, exclusives; DCT, DMT and DWT decision blocks |
| `rtl/hni/` | HN-I transactions to SN-Is, the CHI MMIO configuration window, and the APB HN-F policy registers |
| `rtl/mn/` | Sequential DVM distribution |
| `rtl/sva/` | Bound local safety, stability and protocol-field assertions with covers |
| `rtl/top/` | Product top and the compile and elaboration harnesses |
| `tb/` | Node-side link model, simulation harness and smoke test (not synthesizable) |
| `DV/` | UVM verification environment, its documentation and the Xcelium run area |
| `doc-src/` | Design specification source, Graphviz figure sources, Word template |
| `docs/` | Generated design specification (Word) |
| `filelist.f` | Authoritative source order for the main lint targets |
| `Makefile` | `make lint`, `make sim`, `make simrand` and `make doc` |

## Verification environment

`DV/` holds a protocol-checking UVM environment that drives the fabric through
`chi_if` with configurable Requester and Subordinate agents, checks it against
independent address-map, directory and memory models, and collects functional
coverage. It runs under Xcelium:

```sh
cd DV/sim/xcelium
make compile
make run TEST=chiCoherentTrafficTest
```

`DV/doc/chi_dv_specification.md` is the verification specification: environment
architecture, agent and checker behaviour, the test and coverage plan, and the
traceability rules. `DV/doc/iteration-log.md` records the bring-up, including
the RTL bugs the environment found.
