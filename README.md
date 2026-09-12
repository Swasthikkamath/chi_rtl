# Configurable AMBA CHI Interconnect

This project develops a synthesizable, parameterized AMBA CHI on-chip
interconnect using SystemVerilog-2017. The protocol baseline is Arm IHI 0050H,
Issue H. CHI C2C and all die-to-die transports are outside the project scope.

Development follows explicit delivery stages. Stage 0 is complete and records
the architecture, feature status, source manifest, NodeID encoding, and default
mesh placement in
[`docs/chi_interconnect_design_spec.md`](docs/chi_interconnect_design_spec.md).
No RTL is expected in Stage 0.

As RTL is added, the primary lint command will be:

```sh
verilator --lint-only --sv -Wall -Wno-fatal -f filelist.f \
  --top-module chi_interconnect_top
```

The secondary compile command will be:

```sh
iverilog -g2012 -s chi_interconnect_top -f filelist.f
```
