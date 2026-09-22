// hdlTop is the pin-level top. It holds the interconnect, the clock
// generator, one chi_if per port the DUT declares (including a sentinel
// when a class count is zero), and the BFMs. It publishes virtual BFM
// handles and contains no classes. It elaborates with no UVM test.
// NodeIDs, placements, and regions are built here so the testbench knows
// them by construction. See OPEN QUESTIONS items 3, 6 and 8.
// [TOP:chi_interconnect_top] [ASSUMPTION:3] [ASSUMPTION:6] [ASSUMPTION:8]

`timescale 1ns/1ps

module hdlTop;
  import chiGlobalsPkg::*;
`ifndef CHI_TB_NO_UVM
  import uvm_pkg::*;
`endif

  localparam logic [CHI_CFG.addrW-1:0] CHI_TB_MMIO_BASE =
    {CHI_CFG.addrW{1'b1}} - CHI_CFG.addrW'(12'hfff);

  // [ASSUMPTION:6] Same windows the top module builds when
  // USE_DEFAULT_REGIONS is 1. Passed explicitly so the TB owns them.
  localparam logic [CHI_CFG.addrW-1:0]
    REGION_BASE [CHI_TB_NUM_REGIONS-1:0] = '{
      {CHI_CFG.addrW{1'b0}},
      {1'b1, {(CHI_CFG.addrW-1){1'b0}}},
      CHI_TB_MMIO_BASE,
      {CHI_CFG.addrW{1'b0}}
    };
  localparam logic [CHI_CFG.addrW-1:0]
    REGION_LIMIT [CHI_TB_NUM_REGIONS-1:0] = '{
      {1'b0, {(CHI_CFG.addrW-1){1'b1}}},
      CHI_TB_MMIO_BASE - CHI_CFG.addrW'(1),
      {CHI_CFG.addrW{1'b1}},
      {CHI_CFG.addrW{1'b0}}
    };
  localparam logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] CHI_TB_HNI_TARGET =
    (CHI_CFG.numHni > 0)
      ? chi_cfg_pkg::CHI_NODEID_SLOT_W'(chiNodeIdForOrdinal(CHI_CFG, chiOffHni(CHI_CFG)))
      : '0;
  localparam logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0]
    REGION_TARGET [CHI_TB_NUM_REGIONS-1:0] = '{
      {chi_cfg_pkg::CHI_NODEID_SLOT_W{1'b0}},
      CHI_TB_HNI_TARGET,
      CHI_TB_HNI_TARGET,
      {chi_cfg_pkg::CHI_NODEID_SLOT_W{1'b0}}
    };
  localparam logic [3:0] REGION_ATTRIBUTES [CHI_TB_NUM_REGIONS-1:0] = '{
    chiRegionAttributes(CHI_TB_REGION_KIND_HNF_HASH, 1'b0, 1'b1),
    chiRegionAttributes(CHI_TB_REGION_KIND_DIRECT, 1'b0, 1'b1),
    chiRegionAttributes(CHI_TB_REGION_KIND_MMIO, 1'b0, 1'b1),
    chiRegionAttributes(2'b00, 1'b0, 1'b0)
  };

  chiClkRstBfm clkRst ();

  // [TOP:rnf] Array size matches the DUT, including the max(count, 1) sentinel.
  chi_if rnf [CHI_TB_NUM_RNF_E-1:0] ();
  chi_if rnd [CHI_TB_NUM_RND_E-1:0] ();
  chi_if rni [CHI_TB_NUM_RNI_E-1:0] ();
  chi_if snf [CHI_TB_NUM_SNF_E-1:0] ();
  chi_if sni [CHI_TB_NUM_SNI_E-1:0] ();

  // [TOP:PADDR] APB is unused in the black-box bench and is tied inactive.
  logic [11:0] paddr;
  logic psel;
  logic penable;
  logic pwrite;
  logic [31:0] pwdata;
  logic [3:0] pstrb;
  logic [2:0] pprot;
  logic [31:0] prdata;
  logic pready;
  logic pslverr;

  assign paddr = '0;
  assign psel = 1'b0;
  assign penable = 1'b0;
  assign pwrite = 1'b0;
  assign pwdata = '0;
  assign pstrb = '0;
  assign pprot = '0;

  logic [CHI_TB_NUM_NODES-1:0] linkUp;
  logic [CHI_TB_NUM_NODES-1:0] linkParityError;
  logic [CHI_TB_NUM_NODES-1:0] linkCreditError;

  // [ASSUMPTION:3] Placement array is built as an assignment pattern.
  // See chiDutElab.svh.
  `include "chiDutElab.svh"

  generate
    for (genvar rnfIndex = 0; rnfIndex < CHI_TB_NUM_RNF_E; rnfIndex++) begin : rnfPort
      chiRequesterDriverBfm driver (
        rnf[rnfIndex], rnfIndex, rnfIndex < CHI_CFG.numRnf);
      chiMonitorBfm monitor (
        rnf[rnfIndex],
        (rnfIndex < CHI_CFG.numRnf) ? linkUp[rnfIndex] : 1'b0,
        (rnfIndex < CHI_CFG.numRnf) ? linkParityError[rnfIndex] : 1'b0,
        (rnfIndex < CHI_CFG.numRnf) ? linkCreditError[rnfIndex] : 1'b0,
        rnfIndex,
        rnfIndex < CHI_CFG.numRnf
      );
`ifndef CHI_TB_NO_UVM
      initial begin
        uvm_config_db#(virtual chiRequesterDriverBfm)::set(
          null, "*", $sformatf("rnfDriver%0d", rnfIndex), driver);
        uvm_config_db#(virtual chiMonitorBfm)::set(
          null, "*", $sformatf("rnfMonitor%0d", rnfIndex), monitor);
      end
`endif
    end
    for (genvar rndIndex = 0; rndIndex < CHI_TB_NUM_RND_E; rndIndex++) begin : rndPort
      chiRequesterDriverBfm driver (
        rnd[rndIndex],
        chiOffRnd(CHI_CFG) + rndIndex,
        rndIndex < CHI_CFG.numRnd);
      chiMonitorBfm monitor (
        rnd[rndIndex],
        (rndIndex < CHI_CFG.numRnd) ? linkUp[chiOffRnd(CHI_CFG) + rndIndex] : 1'b0,
        (rndIndex < CHI_CFG.numRnd) ? linkParityError[chiOffRnd(CHI_CFG) + rndIndex] : 1'b0,
        (rndIndex < CHI_CFG.numRnd) ? linkCreditError[chiOffRnd(CHI_CFG) + rndIndex] : 1'b0,
        chiOffRnd(CHI_CFG) + rndIndex,
        rndIndex < CHI_CFG.numRnd
      );
`ifndef CHI_TB_NO_UVM
      initial begin
        uvm_config_db#(virtual chiRequesterDriverBfm)::set(
          null, "*", $sformatf("rndDriver%0d", rndIndex), driver);
        uvm_config_db#(virtual chiMonitorBfm)::set(
          null, "*", $sformatf("rndMonitor%0d", rndIndex), monitor);
      end
`endif
    end
    for (genvar rniIndex = 0; rniIndex < CHI_TB_NUM_RNI_E; rniIndex++) begin : rniPort
      chiRequesterDriverBfm driver (
        rni[rniIndex],
        chiOffRni(CHI_CFG) + rniIndex,
        rniIndex < CHI_CFG.numRni);
      chiMonitorBfm monitor (
        rni[rniIndex],
        (rniIndex < CHI_CFG.numRni) ? linkUp[chiOffRni(CHI_CFG) + rniIndex] : 1'b0,
        (rniIndex < CHI_CFG.numRni) ? linkParityError[chiOffRni(CHI_CFG) + rniIndex] : 1'b0,
        (rniIndex < CHI_CFG.numRni) ? linkCreditError[chiOffRni(CHI_CFG) + rniIndex] : 1'b0,
        chiOffRni(CHI_CFG) + rniIndex,
        rniIndex < CHI_CFG.numRni
      );
`ifndef CHI_TB_NO_UVM
      initial begin
        uvm_config_db#(virtual chiRequesterDriverBfm)::set(
          null, "*", $sformatf("rniDriver%0d", rniIndex), driver);
        uvm_config_db#(virtual chiMonitorBfm)::set(
          null, "*", $sformatf("rniMonitor%0d", rniIndex), monitor);
      end
`endif
    end
    for (genvar snfIndex = 0; snfIndex < CHI_TB_NUM_SNF_E; snfIndex++) begin : snfPort
      chiSubordinateDriverBfm driver (
        snf[snfIndex],
        chiOffSnf(CHI_CFG) + snfIndex,
        snfIndex < CHI_CFG.numSnf);
      chiMonitorBfm monitor (
        snf[snfIndex],
        (snfIndex < CHI_CFG.numSnf) ? linkUp[chiOffSnf(CHI_CFG) + snfIndex] : 1'b0,
        (snfIndex < CHI_CFG.numSnf) ? linkParityError[chiOffSnf(CHI_CFG) + snfIndex] : 1'b0,
        (snfIndex < CHI_CFG.numSnf) ? linkCreditError[chiOffSnf(CHI_CFG) + snfIndex] : 1'b0,
        chiOffSnf(CHI_CFG) + snfIndex,
        snfIndex < CHI_CFG.numSnf
      );
`ifndef CHI_TB_NO_UVM
      initial begin
        uvm_config_db#(virtual chiSubordinateDriverBfm)::set(
          null, "*", $sformatf("snfDriver%0d", snfIndex), driver);
        uvm_config_db#(virtual chiMonitorBfm)::set(
          null, "*", $sformatf("snfMonitor%0d", snfIndex), monitor);
      end
`endif
    end
    for (genvar sniIndex = 0; sniIndex < CHI_TB_NUM_SNI_E; sniIndex++) begin : sniPort
      chiSubordinateDriverBfm driver (
        sni[sniIndex],
        chiOffSni(CHI_CFG) + sniIndex,
        sniIndex < CHI_CFG.numSni);
      chiMonitorBfm monitor (
        sni[sniIndex],
        (sniIndex < CHI_CFG.numSni) ? linkUp[chiOffSni(CHI_CFG) + sniIndex] : 1'b0,
        (sniIndex < CHI_CFG.numSni) ? linkParityError[chiOffSni(CHI_CFG) + sniIndex] : 1'b0,
        (sniIndex < CHI_CFG.numSni) ? linkCreditError[chiOffSni(CHI_CFG) + sniIndex] : 1'b0,
        chiOffSni(CHI_CFG) + sniIndex,
        sniIndex < CHI_CFG.numSni
      );
`ifndef CHI_TB_NO_UVM
      initial begin
        uvm_config_db#(virtual chiSubordinateDriverBfm)::set(
          null, "*", $sformatf("sniDriver%0d", sniIndex), driver);
        uvm_config_db#(virtual chiMonitorBfm)::set(
          null, "*", $sformatf("sniMonitor%0d", sniIndex), monitor);
      end
`endif
    end
  endgenerate

  // config_db keys, all under the empty path so any test can get them:
  //   chiClkRstBfm
  //   rnfDriver<n> rndDriver<n> rniDriver<n> snfDriver<n> sniDriver<n>
  //   rnfMonitor<n> rndMonitor<n> rniMonitor<n> snfMonitor<n> sniMonitor<n>
  // A sentinel index is published with portActive 0. Agents skip it.
  // Per-port sets live in the generate loops above, where the index is a
  // genvar. A variable index on those hierarchical names is rejected.
`ifndef CHI_TB_NO_UVM
  initial uvm_config_db#(virtual chiClkRstBfm)::set(null, "*", "chiClkRstBfm", clkRst);
`endif
endmodule
