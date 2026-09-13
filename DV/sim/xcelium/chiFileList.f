// Compile order for the CHI UVM testbench.
//
// Paths are relative to DV/sim/xcelium, which is where xrun is launched from
// so that xcelium.d, INCA_libs and any waveform database land inside the
// project.
//
// The RTL comes first and in the DUT's own order, because chiGlobalsPkg
// imports chi_cfg_pkg and chi_pkg and the BFMs attach to chi_if. This list is
// a superset of the repository's filelist.f rather than a replacement for it:
// the same RTL files in the same order, minus the lint-only compile harnesses
// in top/ that would elaborate extra copies of the fabric, plus the DV files.

-incdir ../../src/hdlTop/chiLink
-incdir ../../src/hvlTop/chiEnv
-incdir ../../src/hvlTop/chiEnv/chiRequester
-incdir ../../src/hvlTop/chiEnv/chiSubordinate
-incdir ../../src/hvlTop/chiEnv/chiVirtualSequencer
-incdir ../../src/hvlTop/chiEnv/chiVirtualSequences
-incdir ../../src/hvlTop/topEnv
-incdir ../../src/hvlTop/test

// ---------------------------------------------------------------------------
// DUT
// ---------------------------------------------------------------------------
../../../pkg/chi_cfg_pkg.sv
../../../pkg/chi_pkg.sv
../../../if/chi_if.sv
../../../link/chi_lcrd_mgr.sv
../../../link/chi_link_fsm.sv
../../../link/chi_link_tx.sv
../../../link/chi_link_rx.sv
../../../link/chi_link_port.sv
../../../noc/chi_vc_arb.sv
../../../noc/chi_xbar.sv
../../../noc/chi_ring.sv
../../../noc/chi_route_compute.sv
../../../noc/chi_router.sv
../../../noc/chi_mesh_xp.sv
../../../noc/chi_mesh.sv
../../../noc/chi_noc_top.sv
../../../sam/chi_hn_hash.sv
../../../sam/chi_sam.sv
../../../sam/chi_prefetch_map.sv
../../../hni/chi_cfg_slave.sv
../../../hni/chi_hni_top.sv
../../../mn/chi_mn_dvm.sv
../../../hnf/chi_pos.sv
../../../hnf/chi_hazard.sv
../../../hnf/chi_snoop_filter.sv
../../../hnf/chi_snp_gen.sv
../../../hnf/chi_retry.sv
../../../hnf/chi_dct_ctrl.sv
../../../hnf/chi_atomic_alu.sv
../../../hnf/chi_dmt_ctrl.sv
../../../hnf/chi_dwt_ctrl.sv
../../../hnf/chi_stash_ctrl.sv
../../../hnf/chi_cmo.sv
../../../hnf/chi_excl_mon.sv
../../../hnf/chi_hnf_top.sv
../../../top/chi_interconnect_top.sv

// ---------------------------------------------------------------------------
// DUT assertions
// ---------------------------------------------------------------------------
// These bind themselves into the fabric's internals, so they check the design
// during every testbench run without the testbench referencing them.
../../../sva/chi_link_sva.sv
../../../sva/chi_link_rx_sva.sv
../../../sva/chi_proto_sva.sv
../../../sva/chi_mn_sva.sv
../../../sva/chi_ordering_sva.sv
../../../sva/chi_hnf_ordering_sva.sv

// ---------------------------------------------------------------------------
// Testbench globals
// ---------------------------------------------------------------------------
../../src/globals/chiGlobalsPkg.sv

// ---------------------------------------------------------------------------
// HDL side
// ---------------------------------------------------------------------------
../../src/hdlTop/chiInterface/chiClkRstBfm.sv
../../src/hdlTop/chiRequesterAgentBfm/chiRequesterDriverBfm.sv
../../src/hdlTop/chiSubordinateAgentBfm/chiSubordinateDriverBfm.sv
../../src/hdlTop/chiMonitor/chiMonitorBfm.sv
../../src/hdlTop/hdlTop.sv

// ---------------------------------------------------------------------------
// HVL side
// ---------------------------------------------------------------------------
// Package order is dependency order: the two agent packages, then the
// environment that instantiates them, then the checking layer, then the tests.
../../src/hvlTop/chiEnv/chiRequester/chiRequesterPkg.sv
../../src/hvlTop/chiEnv/chiSubordinate/chiSubordinatePkg.sv
../../src/hvlTop/chiEnv/chiEnvPkg.sv
../../src/hvlTop/topEnv/topEnvPkg.sv
../../src/hvlTop/test/chiTestPkg.sv
../../src/hvlTop/hvlTop.sv
