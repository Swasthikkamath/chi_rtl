# Package, node-interface, link, and crossbar compile order.
pkg/chi_cfg_pkg.sv
pkg/chi_pkg.sv
if/chi_if.sv
link/chi_lcrd_mgr.sv
link/chi_link_fsm.sv
link/chi_link_tx.sv
link/chi_link_rx.sv
noc/chi_vc_arb.sv
noc/chi_xbar.sv
noc/chi_ring.sv
top/chi_stage1_compile.sv
top/chi_link_compile.sv
top/chi_xbar_compile.sv
top/chi_ring_compile.sv
