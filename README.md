# CHI interconnect testbench

Black-box UVM environment for `chi_interconnect_top`. The DUT sources stay
in the `chi_rtl` checkout. This tree is only the testbench and the DV spec.

Stage 1 elaborates the HDL top. Stage 2 adds the requester agent:
sequences state intent, and the driver proxy chooses the opcode from
its cache model. The subordinate agent, scoreboard, and tests are not
in this snapshot yet.

## Layout

- `DV/src/globals/chiGlobalsPkg.sv` owns the configuration and the flit model.
- `DV/src/hdlTop` holds the DUT, the BFMs, and `hdlTop`.
- `DV/src/hvlTop/chiRequester` is the RN-F, RN-D, and RN-I agent.
- `DV/sim/xcelium` is the Xcelium flow. `make check` elaborates it with slang.
- `DV/doc/open-questions.md` records the confirmed Stage 0 answers.
- `DV/doc/iteration-log.md` is the findings register and the bring-up log.
- `DV/doc/spec/fetchSpec.sh` fetches the CHI specification the flit model and
  every `[SPEC:IHI0050H ...]` citation were checked against. The document is
  Arm copyright and free to download but not ours to redistribute, so the
  script is here and the PDF is not.

## Elaborate

Sign-off, with Xcelium on `PATH`:

```
make -C DV/sim/xcelium compile
```

That elaborates `hdlTop` and `hvlTop`. `hvlTop` is added with the tests,
so until then the licence-free check is the command that passes:

```
make -C DV/sim/xcelium check SLANG=/path/to/slang UVM_HOME=/path/to/uvm-core-2020.3.1
```

`check` elaborates `hdlTop` and type-checks `chiRequesterPkg`. The DUT
list is generated from `chi_rtl/filelist.f` on each build.

```
make -C DV/sim/xcelium check-sweep
```

repeats that over nine configurations, which is what keeps the flit widths
formulas rather than constants fitted to the default. Port connections are
compiled with `-Wport-width-trunc` and `-Wport-width-expand` promoted to
errors, so a flit model that disagrees with the DUT's bus fails the build
instead of silently resizing.

The `chi_rtl` checkout is expected at the workspace root, next to `DV/`.
Clone it with `gh repo clone Swasthikkamath/chi_rtl` if it is not there.

Overrides, when a later test needs them, are `+define+CHI_TB_*` on the
xrun command. Counts and feature enables start from `CHI_CFG_DEFAULT`.
The placement table passed into the DUT is built for 1 to 32 nodes.
