# CHI interconnect testbench

Black-box UVM environment for `chi_interconnect_top`. This tree is the
testbench and the DV spec. The DUT is the rest of this repository.

Stage 1 elaborates the HDL top. Stage 2 adds the requester agent:
sequences state intent, and the driver proxy chooses the opcode from
its cache model. Stage 3 adds the subordinate agent: it answers
whatever request arrives, from a shared memory, and does not predict
the home. Stages 4–7 add the environment, four reference models, the
directed tests, and the DV spec. Nothing is marked Verified until an
Xcelium run passes.

## Layout

- `src/globals/chiGlobalsPkg.sv` owns the configuration and the flit model.
- `src/hdlTop` holds the DUT wrapper, the BFMs, and `hdlTop`.
- `src/hvlTop/chiRequester` is the RN-F, RN-D, and RN-I agent.
- `src/hvlTop/chiSubordinate` is the SN-F and SN-I agent.
- `src/hvlTop/topEnv` is the environment, the scoreboard, and the four reference models.
- `src/hvlTop/test` is the virtual sequence and the tests. `hvlTop` calls `run_test()`.
- `sim/xcelium` is the Xcelium flow. `make check` elaborates `hdlTop` and `hvlTop` with slang.
- `doc/dv-spec.md` is the DV specification, including the feature matrix.
- `doc/traceability.md` lists every opcode, Resp, RespErr, link state, and PAS encoding.
- `doc/open-questions.md` records the confirmed Stage 0 answers.
- `doc/iteration-log.md` is the findings register and the bring-up log.
- `doc/spec/fetchSpec.sh` fetches the CHI specification the flit model and
  every `[SPEC:IHI0050H ...]` citation were checked against. The document is
  Arm copyright and free to download but not ours to redistribute, so the
  script is here and the PDF is not.

## Elaborate

Sign-off, with Xcelium on `PATH`:

```
make -C sim/xcelium compile
```

That elaborates `hdlTop` and `hvlTop`. A test run, on a machine with
Xcelium, is:

```
make -C sim/xcelium run TEST=chiLinkBringUpTest
```

`TEST` selects the UVM test name. `chiCoherentTrafficTest` is the
coherent smoke test. This image has no `xrun`, so the licence-free
check is:

```
make -C sim/xcelium check SLANG=/path/to/slang UVM_HOME=/path/to/uvm-core-2020.3.1
```

`check` elaborates `hdlTop` and `hvlTop`. It does not execute a test.
Local evidence is that elaboration. Xcelium remains the sign-off path
(Q20). The DUT list is generated from this repository's `filelist.f`
on each build.

The DV spec PDF is built with `make -C doc pdf`. The PDF is gitignored.

```
make -C sim/xcelium check-sweep
```

repeats that over nine configurations, which is what keeps the flit
widths formulas rather than constants fitted to the default.

Overrides, when a later test needs them, are `+define+CHI_TB_*` on the
xrun command. Counts and feature enables start from `CHI_CFG_DEFAULT`.
The placement table passed into the DUT is built for 1 to 32 nodes.
