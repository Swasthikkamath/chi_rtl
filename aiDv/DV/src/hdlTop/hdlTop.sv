// Static side of the testbench: the DUT, one CHI interface per agent, and the
// pin level BFMs that sit on them.
//
// This is the counterpart of tb/chi_sim_harness, which attaches a flit
// counting link model to every port. Here each port gets a real link layer
// peer with a protocol layer above it, driven from UVM.
//
// One interface definition is used throughout. chi_if is the DUT's own port
// type, so the testbench instantiates that rather than declaring a parallel
// copy of the same hundred signals; a second definition would be a second
// thing to keep in step with the spec.
//
// The DUT is built from the testbench's configuration, not its own default.
// CHI_CFG is passed into chi_interconnect_top, which makes chiGlobalsPkg the
// single source of truth: there is no way for the fabric to be elaborated to
// one configuration while the checkers assume another.
module hdlTop;
  import uvm_pkg::*;
  import chi_cfg_pkg::*;
  import chi_pkg::*;
  import chiGlobalsPkg::*;

  chiClkRstBfm clkRstBfm();

  wire clk    = clkRstBfm.clk;
  wire resetn = clkRstBfm.resetn;

  // Interface arrays are sized exactly as the DUT sizes its ports, including
  // the max(count,1) sentinel that keeps a zero count elaborating.
  chi_if #(.CFG(CHI_CFG)) rnfIf [NUM_RNF_IF-1:0] ();
  chi_if #(.CFG(CHI_CFG)) rndIf [NUM_RND_IF-1:0] ();
  chi_if #(.CFG(CHI_CFG)) rniIf [NUM_RNI_IF-1:0] ();
  chi_if #(.CFG(CHI_CFG)) snfIf [NUM_SNF_IF-1:0] ();
  chi_if #(.CFG(CHI_CFG)) sniIf [NUM_SNI_IF-1:0] ();

  logic [31:0] PRDATA;
  logic        PREADY;
  logic        PSLVERR;
  logic [NUM_NODES-1:0] linkUp;
  logic [NUM_NODES-1:0] linkParityError;
  logic [NUM_NODES-1:0] linkCreditError;

  chi_interconnect_top #(.CFG(CHI_CFG)) fabric (
    .clk(clk),
    .resetn(resetn),
    .rnf(rnfIf),
    .rnd(rndIf),
    .rni(rniIf),
    .snf(snfIf),
    .sni(sniIf),
    // The configuration port is unused: cfgAccess defaults to CFG_PARAM_ONLY,
    // so the fabric takes its configuration from parameters and the APB slave
    // is not part of Stage 1 [CFGDOC:#3.1].
    .PADDR('0),
    .PSEL(1'b0),
    .PENABLE(1'b0),
    .PWRITE(1'b0),
    .PWDATA('0),
    .PSTRB('0),
    .PPROT('0),
    .PRDATA(PRDATA),
    .PREADY(PREADY),
    .PSLVERR(PSLVERR),
    .linkUp(linkUp),
    .linkParityError(linkParityError),
    .linkCreditError(linkCreditError)
  );

  // Note that nothing here drives chi_if.CLK or chi_if.RESETn. The fabric's
  // own link port assigns them from its clk and resetn inputs
  // [link/chi_link_port.sv], so the BFMs pick the clock up through the
  // interface they are attached to, and driving it here as well would put two
  // drivers on one variable.

  // -------------------------------------------------------------------------
  // Agent BFMs
  // -------------------------------------------------------------------------
  // Agents are numbered independently of node ordinals: Requester agents 0..N
  // in class order RN-F, RN-D, RN-I, and Subordinate agents 0..M in class
  // order SN-F, SN-I. The class of an agent index and its position inside that
  // class both come from chiGlobalsPkg, so the mapping the generate loops use
  // is the same one the env uses to configure the agents.
  //
  // The branch on class is resolved at elaboration, which is why each agent
  // can sit on a different interface array while there is still only one BFM
  // definition per role.
  `define CHI_PUBLISH_REQUESTER(IF_ARRAY, CLASS_INDEX)                       \
    chiRequesterDriverBfm driverBfm (IF_ARRAY[CLASS_INDEX]);                 \
    chiMonitorBfm         monitorBfm (IF_ARRAY[CLASS_INDEX]);                \
    initial begin                                                           \
      driverBfm.configure(i, AGENT_CLASS);                                   \
      monitorBfm.configure(i, AGENT_CLASS);                                  \
      uvm_config_db #(virtual chiRequesterDriverBfm)::set(                   \
          null, "*", $sformatf("chiRequesterDriverBfm_%0d", i), driverBfm);  \
      uvm_config_db #(virtual chiMonitorBfm)::set(                           \
          null, "*", $sformatf("chiRequesterMonitorBfm_%0d", i), monitorBfm);\
    end

  `define CHI_PUBLISH_SUBORDINATE(IF_ARRAY, CLASS_INDEX)                     \
    chiSubordinateDriverBfm driverBfm (IF_ARRAY[CLASS_INDEX]);               \
    chiMonitorBfm           monitorBfm (IF_ARRAY[CLASS_INDEX]);              \
    initial begin                                                           \
      driverBfm.configure(i, AGENT_CLASS);                                   \
      monitorBfm.configure(i, AGENT_CLASS);                                  \
      uvm_config_db #(virtual chiSubordinateDriverBfm)::set(                 \
          null, "*", $sformatf("chiSubordinateDriverBfm_%0d", i), driverBfm);\
      uvm_config_db #(virtual chiMonitorBfm)::set(                           \
          null, "*", $sformatf("chiSubordinateMonitorBfm_%0d", i),           \
          monitorBfm);                                                      \
    end

  generate
    for (genvar i = 0; i < NUM_REQUESTER_AGENTS; i++) begin : requesterAgent
      localparam chi_node_class_e AGENT_CLASS = requesterClassOf(i);
      localparam int unsigned     CLASS_INDEX = requesterClassIndexOf(i);

      if (AGENT_CLASS == NODE_RNF) begin : rnfPort
        `CHI_PUBLISH_REQUESTER(rnfIf, CLASS_INDEX)
      end else if (AGENT_CLASS == NODE_RND) begin : rndPort
        `CHI_PUBLISH_REQUESTER(rndIf, CLASS_INDEX)
      end else begin : rniPort
        `CHI_PUBLISH_REQUESTER(rniIf, CLASS_INDEX)
      end
    end

    for (genvar i = 0; i < NUM_SUBORDINATE_AGENTS; i++) begin : subordinateAgent
      localparam chi_node_class_e AGENT_CLASS = subordinateClassOf(i);
      localparam int unsigned     CLASS_INDEX = subordinateClassIndexOf(i);

      if (AGENT_CLASS == NODE_SNF) begin : snfPort
        `CHI_PUBLISH_SUBORDINATE(snfIf, CLASS_INDEX)
      end else begin : sniPort
        `CHI_PUBLISH_SUBORDINATE(sniIf, CLASS_INDEX)
      end
    end
  endgenerate

  `undef CHI_PUBLISH_REQUESTER
  `undef CHI_PUBLISH_SUBORDINATE

  // A class with a zero count still gets one sentinel interface instance,
  // because that is how the DUT declares its ports. No agent is created for it
  // and no link port inside the fabric reads it, so it is deliberately left
  // unconnected rather than tied off: a tie-off here would be a second driver
  // on any signal the fabric does happen to drive.

  initial begin
    uvm_config_db #(virtual chiClkRstBfm)::set(null, "*", "chiClkRstBfm",
                                               clkRstBfm);
  end
endmodule
