# Configurable AMBA CHI Interconnect

This repository contains a synthesizable SystemVerilog-2017 **partial/reference
implementation** of an on-chip interconnect informed by Arm AMBA CHI Issue H
(IHI 0050H). It is not a claim of CHI compliance or interoperability. CHI
Chip-to-Chip, CXS, CCIX, and die-to-die transports are outside scope.

The RTL includes configurable flit records, three internal topologies, address
mapping, limited HN-F/HN-I/MN transaction paths, standalone link components,
and local SVA. Important protocol behavior remains partial or absent, including
top-level link-credit/activation integration, parity, multiple interfaces,
replicated channels, complete cache-state transitions, atomics, DMT, DWT, and
MTE/MEC semantics.

There is exactly one node-facing SystemVerilog interface type:
[`if/chi_if.sv`](if/chi_if.sv). It is a superset used for RN-F, RN-D, RN-I,
SN-F, and SN-I arrays. Signal applicability varies by node class; unused
node-driven signals must be tied low. HN-F, HN-I, and MN are internal
ready/valid endpoints. See the
[`Stage 8 design specification`](docs/chi_interconnect_design_spec.md) for the
feature matrix, directions, constraints, flows, and limitations.

## Lint

These commands pass with Verilator:

```sh
verilator --lint-only --sv -Wall -Wno-fatal \
  -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-UNDRIVEN \
  -f filelist.f --top-module chi_interconnect_top

verilator --lint-only --sv -Wall -Wno-fatal \
  -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-UNDRIVEN \
  -f filelist.f --top-module chi_sva_compile
```

The unused-signal/parameter suppressions cover superset protocol records,
optional ports, and harness-only fields. `UNDRIVEN` covers external `chi_if`
inputs that have no node model in lint tops. `Wno-fatal` preserves warning
visibility without treating warnings as errors. Icarus Verilog was not
available in the verified environment.

## Directory map

| Path | Contents |
|---|---|
| `pkg/` | Configuration types, opcodes, flit records, pack/unpack, NodeID helpers |
| `if/` | The single superset node-facing `chi_if` |
| `link/` | Standalone activation, credit, TX, and RX blocks; not integrated at top |
| `noc/` | Crossbar, bidirectional ring, 2D mesh, route, router, and arbitration RTL |
| `sam/` | Region lookup and HN hashing |
| `hnf/` | Partial HN-F POS, hazards, directory, snoops, retry, DCT, CMO, exclusives |
| `hni/` | Partial HN-I forwarding and project-defined configuration access |
| `mn/` | Partial sequential DVM distribution |
| `sva/` | Bound local safety/stability assertions and cover properties |
| `top/` | Product top and compile/elaboration harnesses |
| `docs/` | Reconciled architecture and implementation specification |
| `filelist.f` | Authoritative source order for the main lint targets |
