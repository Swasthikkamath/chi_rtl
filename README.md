# CHI interconnect testbench

Black-box UVM environment for `chi_interconnect_top`. The DUT sources stay
in the `chi_rtl` checkout. This tree is only the testbench and the DV spec.

Stage 1 elaborates the HDL top with no UVM test. The clock, link, driver,
and monitor BFMs are in place. Requester and subordinate agents, the
scoreboard, and the tests are not in this snapshot yet.

## Layout

- `DV/src/globals/chiGlobalsPkg.sv` owns the configuration and the flit model.
- `DV/src/hdlTop` holds the DUT, the BFMs, and `hdlTop`.
- `DV/sim/xcelium` is the Xcelium flow.
- `DV/doc/open-questions.md` records the confirmed Stage 0 answers.

## Elaborate

From any directory, with Xcelium on `PATH`:

```
make -C DV/sim/xcelium compile
```

That runs:

```
xrun -sv -uvm -elaborate -access +rwc -top hdlTop -F DV/sim/xcelium/chiFileList.f
```

`-F` is required. `chiFileList.f` points `-F` at `chi_rtl/filelist.f`, and
paths inside that list resolve from the `chi_rtl` directory.

The `chi_rtl` checkout is expected at the workspace root, next to `DV/`.
Clone it with `gh repo clone Swasthikkamath/chi_rtl` if it is not there.

Overrides, when a later test needs them, are `+define+CHI_TB_*` on the
xrun command. Counts and feature enables start from `CHI_CFG_DEFAULT`.
The placement table passed into the DUT is built for 1 to 32 nodes.
