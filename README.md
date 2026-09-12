# Configurable AMBA 5 CHI Interconnect

A synthesizable SystemVerilog-2017 reference implementation of an on-chip
interconnect built against Arm AMBA 5 CHI Issue H (IHI 0050H). It is not a
claim of CHI compliance or interoperability. CHI Chip-to-Chip, CXS, CCIX and
die-to-die transports are outside scope.

The RTL covers configurable Issue H flit records, three selectable internal
topologies, address mapping, a real CHI link layer on every node port, and
coherent and noncoherent Home Node transaction paths. Implemented protocol
behaviour includes L-Credits and link activation, flit parity, the Request
Retry credit loop with `RetryAck`, `PCrdGrant` and `PCrdReturn`, DMT and DWT
direct transfers, atomic transactions, cache stashing with Data Pull, and
`PrefetchTgt` routing.

Behaviour that is deliberately partial or absent includes multiple interfaces
per node, replicated channels, per-hop L-Credits inside the fabric, an RN-side
cache controller, MTE tag semantics, MEC access control, MPAM enforcement, and
the MultiReq, `CacheLineID` and PBHA fields, which are carried but have no
behaviour. The feature matrix in the design specification states the exact
boundary of every function.

There is exactly one node-facing SystemVerilog interface type,
[`if/chi_if.sv`](if/chi_if.sv). It is a superset used for the RN-F, RN-D,
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

Regeneration needs `pandoc`.

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
| `pkg/` | Configuration types, opcodes, flit records, pack and unpack, NodeID helpers |
| `if/` | The single superset node-facing `chi_if` |
| `link/` | L-Credit manager, activation FSM, link TX and RX, and the per-port link wrapper |
| `noc/` | Crossbar, bidirectional ring, 2D mesh, route compute, router and arbitration |
| `sam/` | Region lookup, HN hashing and the `PrefetchTgt` mapper |
| `hnf/` | HN-F POS, hazards, directory, snoops, retry credits, DCT, DMT, DWT, stash, atomics, CMO, exclusives |
| `hni/` | HN-I forwarding and the project-defined configuration access |
| `mn/` | Sequential DVM distribution |
| `sva/` | Bound local safety, stability and protocol-field assertions with covers |
| `top/` | Product top and the compile and elaboration harnesses |
| `tb/` | Node-side link model, simulation harness and smoke test (not synthesizable) |
| `doc-src/` | Design specification source |
| `docs/` | Generated design specification (Word) |
| `filelist.f` | Authoritative source order for the main lint targets |
| `Makefile` | `make lint`, `make sim`, `make simrand` and `make doc` |
