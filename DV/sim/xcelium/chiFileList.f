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
../../../rtl/pkg/chi_cfg_pkg.sv
../../../rtl/pkg/chi_pkg.sv
../../../rtl/if/chi_if.sv
../../../rtl/link/chi_lcrd_mgr.sv
../../../rtl/link/chi_link_fsm.sv
../../../rtl/link/chi_link_tx.sv
../../../rtl/link/chi_link_rx.sv
../../../rtl/link/chi_link_port.sv
../../../rtl/noc/chi_vc_arb.sv
../../../rtl/noc/chi_xbar.sv
../../../rtl/noc/chi_ring.sv
../../../rtl/noc/chi_route_compute.sv
../../../rtl/noc/chi_router.sv
../../../rtl/noc/chi_mesh_xp.sv
../../../rtl/noc/chi_mesh.sv
../../../rtl/noc/chi_noc_top.sv
../../../rtl/sam/chi_hn_hash.sv
../../../rtl/sam/chi_sam.sv
../../../rtl/sam/chi_prefetch_map.sv
../../../rtl/hni/chi_cfg_slave.sv
../../../rtl/hni/chi_hni_top.sv
../../../rtl/mn/chi_mn_dvm.sv
../../../rtl/hnf/chi_pos.sv
../../../rtl/hnf/chi_hazard.sv
../../../rtl/hnf/chi_snoop_filter.sv
../../../rtl/hnf/chi_snp_gen.sv
../../../rtl/hnf/chi_retry.sv
../../../rtl/hnf/chi_dct_ctrl.sv
../../../rtl/hnf/chi_atomic_alu.sv
../../../rtl/hnf/chi_dmt_ctrl.sv
../../../rtl/hnf/chi_dwt_ctrl.sv
../../../rtl/hnf/chi_stash_ctrl.sv
../../../rtl/hnf/chi_cmo.sv
../../../rtl/hnf/chi_excl_mon.sv
../../../rtl/hnf/chi_hnf_top.sv
../../../rtl/top/chi_interconnect_top.sv

// ---------------------------------------------------------------------------
// DUT assertions
// ---------------------------------------------------------------------------
// These bind themselves into the fabric's internals, so they check the design
// during every testbench run without the testbench referencing them.
../../../rtl/sva/chi_link_sva.sv
../../../rtl/sva/chi_link_rx_sva.sv
../../../rtl/sva/chi_proto_sva.sv
../../../rtl/sva/chi_mn_sva.sv
../../../rtl/sva/chi_ordering_sva.sv
../../../rtl/sva/chi_hnf_ordering_sva.sv

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
