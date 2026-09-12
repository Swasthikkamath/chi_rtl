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
| `doc-src/` | Design specification source |
| `docs/` | Generated design specification (Word) |
| `filelist.f` | Authoritative source order for the main lint targets |
| `Makefile` | `make lint` and `make doc` |
