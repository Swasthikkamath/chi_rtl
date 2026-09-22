# CHI interconnect testbench

Black-box UVM environment for `chi_interconnect_top`. The DUT sources stay
in the `chi_rtl` checkout. This tree is only the testbench and the DV spec.

Stage 1 elaborates the HDL top. Stage 2 adds the requester agent:
sequences state intent, and the driver proxy chooses the opcode from
its cache model. Stage 3 adds the subordinate agent: it answers
whatever request arrives, from its own memory, and does not predict
the home. Stages 4–7 add the environment, four reference models, the
directed tests, and the DV spec. Nothing is marked Verified until an
Xcelium run passes.

## Layout

- `DV/src/globals/chiGlobalsPkg.sv` owns the configuration and the flit model.
- `DV/src/hdlTop` holds the DUT, the BFMs, and `hdlTop`.
- `DV/src/hvlTop/chiRequester` is the RN-F, RN-D, and RN-I agent.
- `DV/src/hvlTop/chiSubordinate` is the SN-F and SN-I agent.
- `DV/src/hvlTop/topEnv` is the environment, the scoreboard, and the four reference models.
- `DV/src/hvlTop/test` is the virtual sequence and the tests. `hvlTop` calls `run_test()`.
- `DV/sim/xcelium` is the Xcelium flow. `make check` elaborates `hdlTop` and `hvlTop` with slang.
- `DV/doc/dv-spec.md` is the DV specification, including the feature matrix.
- `DV/doc/traceability.md` lists every opcode, Resp, RespErr, link state, and PAS encoding.
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

That elaborates `hdlTop` and `hvlTop`. A test run, on a machine with
Xcelium, is:

```
make -C DV/sim/xcelium run TEST=chiLinkBringUpTest
```

`TEST` selects the UVM test name. `chiCoherentTrafficTest` is the
coherent smoke test. This image has no `xrun`, so the licence-free
check is:

```
make -C DV/sim/xcelium check SLANG=/path/to/slang UVM_HOME=/path/to/uvm-core-2020.3.1
```

`check` elaborates `hdlTop` and `hvlTop`. It does not execute a test.
Local evidence is that elaboration. Xcelium remains the sign-off path
(Q20). The DUT list is generated from `chi_rtl/filelist.f` on each build.

The DV spec PDF is built with `make -C DV/doc pdf`. The PDF is gitignored.

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
