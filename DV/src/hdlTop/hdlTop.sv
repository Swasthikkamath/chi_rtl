//==============================================================================
// hdlTop
//
// Why the testbench has two tops, and why this one looks like this:
//
// Everything that touches a pin is here and nothing else is. The DUT, one
// chi_if array per node class, the clock and reset source, and one driver and
// monitor BFM per configured port. There is no class declaration in this file
// and no dependence on a test being loaded, so `xrun -top hdlTop` alone
// elaborates and a bring-up problem in the pin layer can be debugged without
// any UVM at all. The only UVM contact is the publication of virtual BFM
// handles into uvm_config_db, which is what lets hvlTop stay a two-line file.
//
// Interface arrays are sized exactly as the DUT sizes its ports, sentinel
// included: a node class configured out still has a one-element array, because
// SystemVerilog cannot declare a zero-length one, and the DUT builds no link
// layer behind it [TOP:ports]. BFMs are generated only for real nodes, so the
// sentinel port has no driver, no monitor and no agent, and nothing samples an
// undriven clock.
//
// Parameters passed to the DUT come from chiGlobalsPkg, which means the
// testbench knows every NodeID and every address region by construction rather
// than by inspection. USE_DEFAULT_PLACEMENTS and USE_DEFAULT_REGIONS are both
// turned off so that the tables actually used are the ones the testbench built
// [TOP:USE_DEFAULT_PLACEMENTS, USE_DEFAULT_REGIONS].
//==============================================================================

module hdlTop;

  import uvm_pkg::*;
  import chiGlobalsPkg::*;

  //----------------------------------------------------------------------------
  // Clock and reset
  //
  // This BFM drives the DUT's two scalar inputs only. CLK and RESETn inside
  // every chi_if are driven by the DUT itself [ASSUMPTION:2], so nothing here
  // may drive them.
  //----------------------------------------------------------------------------

  chiClkRstBfm clkRstBfm();

  //----------------------------------------------------------------------------
  // Configuration constraints, checked at elaboration
  //
  // These are not testbench preferences. Each one was found by compiling the
  // real RTL at a swept configuration and reading the error, which is what
  // OPEN QUESTIONS Q20 allows. Checking them here turns an internal DUT index
  // error into a message that names the configuration field a sweep has to
  // change, and keeps the constraint written down in one place.
  //
  //   numMn >= 1                  the DVM route reads NODE_IDS[OFF_MN] whether
  //                               or not numMn is zero, so ordinal OFF_MN has
  //                               to exist [TOP:requesterRouteTarget]
  //   numHnf > 0 -> numSnf >= 1   HN-F picks its Subordinate with i % numSnf
  //   numHni > 0 -> numSni >= 1   HN-I does the same with i % numSni
  //
  // The mesh checks are the testbench's own: its NodeID and placement tables
  // have to be a bijection, which needs room in the geometry and room in the
  // NodeID device field. See OPEN QUESTIONS Q5.
  //----------------------------------------------------------------------------

  if (chiGlobalsPkg::NUM_MN < 1)
    $error("[hdlTop] numMn must be at least 1: the DVM route indexes ordinal OFF_MN unconditionally");
  if ((chiGlobalsPkg::NUM_HNF > 0) && (chiGlobalsPkg::NUM_SNF < 1))
    $error("[hdlTop] numHnf > 0 needs numSnf >= 1: each HN-F selects a Subordinate with i %% numSnf");
  if ((chiGlobalsPkg::NUM_HNI > 0) && (chiGlobalsPkg::NUM_SNI < 1))
    $error("[hdlTop] numHni > 0 needs numSni >= 1: each HN-I selects a Subordinate with i %% numSni");
  if ((chiGlobalsPkg::CHI_CFG.meshX * chiGlobalsPkg::CHI_CFG.meshY *
       chiGlobalsPkg::CHI_CFG.numDevPortsPerXp) < chiGlobalsPkg::NUM_NODES)
    $error("[hdlTop] mesh geometry holds fewer positions than the %0d configured nodes",
           chiGlobalsPkg::NUM_NODES);
  if ((chiGlobalsPkg::NUM_NODES + 1) > ((1 << chiGlobalsPkg::DEVICE_ID_W) - 1))
    $error("[hdlTop] NodeID device field is %0d bits, too few for %0d nodes plus the reserved id 0",
           chiGlobalsPkg::DEVICE_ID_W, chiGlobalsPkg::NUM_NODES);

  // The flit model has two independent derivations that have to agree: the
  // width formula, whose coefficients were measured at the DUT boundary, and
  // the field list, read off the specification's B13.6 to B13.9 tables. If
  // they ever disagree the model has gained or lost a field, and every flit
  // above the missing one is misplaced. See OPEN QUESTIONS Q7.
  if (chiGlobalsPkg::REQ_NAMED_W != chiGlobalsPkg::REQ_FLIT_W)
    $error("[hdlTop] REQ fields sum to %0d but the bus is %0d bits wide",
           chiGlobalsPkg::REQ_NAMED_W, chiGlobalsPkg::REQ_FLIT_W);
  if (chiGlobalsPkg::RSP_NAMED_W != chiGlobalsPkg::RSP_FLIT_W)
    $error("[hdlTop] RSP fields sum to %0d but the bus is %0d bits wide",
           chiGlobalsPkg::RSP_NAMED_W, chiGlobalsPkg::RSP_FLIT_W);
  if (chiGlobalsPkg::SNP_NAMED_W != chiGlobalsPkg::SNP_FLIT_W)
    $error("[hdlTop] SNP fields sum to %0d but the bus is %0d bits wide",
           chiGlobalsPkg::SNP_NAMED_W, chiGlobalsPkg::SNP_FLIT_W);
  if (chiGlobalsPkg::DAT_NAMED_W != chiGlobalsPkg::DAT_FLIT_W)
    $error("[hdlTop] DAT fields sum to %0d but the bus is %0d bits wide",
           chiGlobalsPkg::DAT_NAMED_W, chiGlobalsPkg::DAT_FLIT_W);

  //----------------------------------------------------------------------------
  // Node interfaces
  //----------------------------------------------------------------------------

  chi_if #(.CFG(chiGlobalsPkg::CHI_CFG)) rnf [chiGlobalsPkg::NUM_RNF_IF-1:0] ();
  chi_if #(.CFG(chiGlobalsPkg::CHI_CFG)) rnd [chiGlobalsPkg::NUM_RND_IF-1:0] ();
  chi_if #(.CFG(chiGlobalsPkg::CHI_CFG)) rni [chiGlobalsPkg::NUM_RNI_IF-1:0] ();
  chi_if #(.CFG(chiGlobalsPkg::CHI_CFG)) snf [chiGlobalsPkg::NUM_SNF_IF-1:0] ();
  chi_if #(.CFG(chiGlobalsPkg::CHI_CFG)) sni [chiGlobalsPkg::NUM_SNI_IF-1:0] ();

  //----------------------------------------------------------------------------
  // DUT status outputs, indexed by node ordinal. The HN-F, HN-I and MN bits
  // read zero because those endpoints have no external link [TOP:linkUp].
  //----------------------------------------------------------------------------

  logic [chiGlobalsPkg::NUM_NODES-1:0] dutLinkUp;
  logic [chiGlobalsPkg::NUM_NODES-1:0] dutLinkParityError;
  logic [chiGlobalsPkg::NUM_NODES-1:0] dutLinkCreditError;

  //----------------------------------------------------------------------------
  // APB configuration port
  //
  // Tied off. The default configuration selects CFG_PARAM_ONLY, so the region
  // table is fixed at elaboration and there is nothing for an APB write to do;
  // the outputs are still brought out so that a test can assert the port stays
  // quiet. Driving it would make this a second stimulus interface, which is out
  // of scope [ASSUMPTION:18a].
  //----------------------------------------------------------------------------

  logic [31:0] apbPrdata;
  logic        apbPready;
  logic        apbPslverr;

  //----------------------------------------------------------------------------
  // DUT
  //----------------------------------------------------------------------------

  chi_interconnect_top #(
      .CFG(chiGlobalsPkg::CHI_CFG),
      .NUM_REGIONS(chiGlobalsPkg::NUM_REGIONS),
      .NODE_IDS(chiGlobalsPkg::NODE_IDS),
      .USE_DEFAULT_PLACEMENTS(1'b0),
      .PLACEMENTS(chiGlobalsPkg::PLACEMENTS),
      .CFG_MMIO_BASE(chiGlobalsPkg::CFG_MMIO_BASE),
      .USE_DEFAULT_REGIONS(1'b0),
      .REGION_BASE(chiGlobalsPkg::REGION_BASE),
      .REGION_LIMIT(chiGlobalsPkg::REGION_LIMIT),
      .REGION_TARGET(chiGlobalsPkg::REGION_TARGET),
      .REGION_ATTRIBUTES(chiGlobalsPkg::REGION_ATTRIBUTES)
  ) chiDut (
      .clk(clkRstBfm.clk),
      .resetn(clkRstBfm.resetn),
      .rnf(rnf),
      .rnd(rnd),
      .rni(rni),
      .snf(snf),
      .sni(sni),
      .PADDR(12'h000),
      .PSEL(1'b0),
      .PENABLE(1'b0),
      .PWRITE(1'b0),
      .PWDATA(32'h0000_0000),
      .PSTRB(4'h0),
      .PPROT(3'b000),
      .PRDATA(apbPrdata),
      .PREADY(apbPready),
      .PSLVERR(apbPslverr),
      .linkUp(dutLinkUp),
      .linkParityError(dutLinkParityError),
      .linkCreditError(dutLinkCreditError)
  );

  //----------------------------------------------------------------------------
  // BFMs
  //
  // One driver and one monitor per configured port. Each is configured with its
  // node ordinal and class at time 0 and published under the key chiGlobalsPkg
  // builds, so that a key typo cannot exist: both sides call the same function.
  //
  // The two connection macros exist because a BFM cannot take chi_if as an
  // interface port and still be reachable through a virtual interface handle
  // [SPEC:IEEE1800-2017 25.9], so every signal is connected by name. Writing
  // that list once and using it five times is the difference between one place
  // to fix a connection and five places to forget one. A name here that chi_if
  // does not have is a compile error. A width that disagrees with chiGlobalsPkg
  // is not: a port connection resizes silently, so the widths are compared
  // explicitly at time 0 below and a disagreement is fatal there.
  //----------------------------------------------------------------------------

`define CHI_TB_DRIVER_CONNECT(nodePort)                  \
      .CLK(nodePort.CLK),                                \
      .RESETn(nodePort.RESETn),                          \
      .TXLINKACTIVEREQ(nodePort.TXLINKACTIVEREQ),        \
      .TXLINKACTIVEACK(nodePort.TXLINKACTIVEACK),        \
      .RXLINKACTIVEREQ(nodePort.RXLINKACTIVEREQ),        \
      .RXLINKACTIVEACK(nodePort.RXLINKACTIVEACK),        \
      .SYSCOREQ(nodePort.SYSCOREQ),                      \
      .SYSCOACK(nodePort.SYSCOACK),                      \
      .TXREQFLITPEND(nodePort.TXREQFLITPEND),            \
      .TXREQFLITV(nodePort.TXREQFLITV),                  \
      .TXREQFLIT(nodePort.TXREQFLIT),                    \
      .TXREQFLITCHK(nodePort.TXREQFLITCHK),              \
      .TXREQLCRDV(nodePort.TXREQLCRDV),                  \
      .TXRSPFLITPEND(nodePort.TXRSPFLITPEND),            \
      .TXRSPFLITV(nodePort.TXRSPFLITV),                  \
      .TXRSPFLIT(nodePort.TXRSPFLIT),                    \
      .TXRSPFLITCHK(nodePort.TXRSPFLITCHK),              \
      .TXRSPLCRDV(nodePort.TXRSPLCRDV),                  \
      .TXDATFLITPEND(nodePort.TXDATFLITPEND),            \
      .TXDATFLITV(nodePort.TXDATFLITV),                  \
      .TXDATFLIT(nodePort.TXDATFLIT),                    \
      .TXDATFLITCHK(nodePort.TXDATFLITCHK),              \
      .TXDATLCRDV(nodePort.TXDATLCRDV),                  \
      .TXSNPFLITPEND(nodePort.TXSNPFLITPEND),            \
      .TXSNPFLITV(nodePort.TXSNPFLITV),                  \
      .TXSNPFLIT(nodePort.TXSNPFLIT),                    \
      .RXREQFLITPEND(nodePort.RXREQFLITPEND),            \
      .RXREQFLITV(nodePort.RXREQFLITV),                  \
      .RXREQFLIT(nodePort.RXREQFLIT),                    \
      .RXREQLCRDV(nodePort.RXREQLCRDV),                  \
      .RXRSPFLITPEND(nodePort.RXRSPFLITPEND),            \
      .RXRSPFLITV(nodePort.RXRSPFLITV),                  \
      .RXRSPFLIT(nodePort.RXRSPFLIT),                    \
      .RXRSPLCRDV(nodePort.RXRSPLCRDV),                  \
      .RXDATFLITPEND(nodePort.RXDATFLITPEND),            \
      .RXDATFLITV(nodePort.RXDATFLITV),                  \
      .RXDATFLIT(nodePort.RXDATFLIT),                    \
      .RXDATLCRDV(nodePort.RXDATLCRDV),                  \
      .RXSNPFLITPEND(nodePort.RXSNPFLITPEND),            \
      .RXSNPFLITV(nodePort.RXSNPFLITV),                  \
      .RXSNPFLIT(nodePort.RXSNPFLIT),                    \
      .RXSNPLCRDV(nodePort.RXSNPLCRDV)

`define CHI_TB_MONITOR_CONNECT(nodePort, ordinal)        \
      .CLK(nodePort.CLK),                                \
      .RESETn(nodePort.RESETn),                          \
      .TXLINKACTIVEREQ(nodePort.TXLINKACTIVEREQ),        \
      .TXLINKACTIVEACK(nodePort.TXLINKACTIVEACK),        \
      .RXLINKACTIVEREQ(nodePort.RXLINKACTIVEREQ),        \
      .RXLINKACTIVEACK(nodePort.RXLINKACTIVEACK),        \
      .TXSACTIVE(nodePort.TXSACTIVE),                    \
      .RXSACTIVE(nodePort.RXSACTIVE),                    \
      .SYSCOREQ(nodePort.SYSCOREQ),                      \
      .SYSCOACK(nodePort.SYSCOACK),                      \
      .TXREQFLITV(nodePort.TXREQFLITV),                  \
      .TXREQFLIT(nodePort.TXREQFLIT),                    \
      .TXREQLCRDV(nodePort.TXREQLCRDV),                  \
      .TXRSPFLITV(nodePort.TXRSPFLITV),                  \
      .TXRSPFLIT(nodePort.TXRSPFLIT),                    \
      .TXRSPLCRDV(nodePort.TXRSPLCRDV),                  \
      .TXDATFLITV(nodePort.TXDATFLITV),                  \
      .TXDATFLIT(nodePort.TXDATFLIT),                    \
      .TXDATLCRDV(nodePort.TXDATLCRDV),                  \
      .RXREQFLITV(nodePort.RXREQFLITV),                  \
      .RXREQFLIT(nodePort.RXREQFLIT),                    \
      .RXREQLCRDV(nodePort.RXREQLCRDV),                  \
      .RXRSPFLITV(nodePort.RXRSPFLITV),                  \
      .RXRSPFLIT(nodePort.RXRSPFLIT),                    \
      .RXRSPLCRDV(nodePort.RXRSPLCRDV),                  \
      .RXDATFLITV(nodePort.RXDATFLITV),                  \
      .RXDATFLIT(nodePort.RXDATFLIT),                    \
      .RXDATLCRDV(nodePort.RXDATLCRDV),                  \
      .RXSNPFLITV(nodePort.RXSNPFLITV),                  \
      .RXSNPFLIT(nodePort.RXSNPFLIT),                    \
      .RXSNPLCRDV(nodePort.RXSNPLCRDV),                  \
      .linkUp(dutLinkUp[ordinal]),                       \
      .linkParityError(dutLinkParityError[ordinal]),     \
      .linkCreditError(dutLinkCreditError[ordinal])

  // A node class configured to zero still has a one-element interface array,
  // because SystemVerilog cannot declare a zero-length one and the DUT sizes
  // its ports the same way [TOP:ports]. The default configuration has
  // numRnd = 0, so rnd[0] is a sentinel with no node behind it. It gets no
  // driver, no monitor and no agent, but its node-side signals are still DUT
  // inputs, so they are held at zero here. Leaving them floating would push X
  // into the DUT for a port that is supposed to be absent, and an X that
  // reaches linkUp would be indistinguishable from a real bring-up failure.
  // See OPEN QUESTIONS Q12.
`define CHI_TB_TIE_OFF_PORT(nodePort)                    \
    assign nodePort.TXLINKACTIVEREQ = 1'b0;              \
    assign nodePort.RXLINKACTIVEACK = 1'b0;              \
    assign nodePort.SYSCOREQ        = 1'b0;              \
    assign nodePort.TXREQFLITPEND   = 1'b0;              \
    assign nodePort.TXREQFLITV      = 1'b0;              \
    assign nodePort.TXREQFLIT       = '0;                \
    assign nodePort.TXREQFLITCHK    = '0;                \
    assign nodePort.TXRSPFLITPEND   = 1'b0;              \
    assign nodePort.TXRSPFLITV      = 1'b0;              \
    assign nodePort.TXRSPFLIT       = '0;                \
    assign nodePort.TXRSPFLITCHK    = '0;                \
    assign nodePort.TXDATFLITPEND   = 1'b0;              \
    assign nodePort.TXDATFLITV      = 1'b0;              \
    assign nodePort.TXDATFLIT       = '0;                \
    assign nodePort.TXDATFLITCHK    = '0;                \
    assign nodePort.TXSNPFLITPEND   = 1'b0;              \
    assign nodePort.TXSNPFLITV      = 1'b0;              \
    assign nodePort.TXSNPFLIT       = '0;                \
    assign nodePort.RXREQLCRDV      = 1'b0;              \
    assign nodePort.RXRSPLCRDV      = 1'b0;              \
    assign nodePort.RXDATLCRDV      = 1'b0;              \
    assign nodePort.RXSNPLCRDV      = 1'b0;

  for (genvar i = chiGlobalsPkg::NUM_RNF; i < chiGlobalsPkg::NUM_RNF_IF; i++)
  begin : rnfSentinel
    `CHI_TB_TIE_OFF_PORT(rnf[i])
  end
  for (genvar i = chiGlobalsPkg::NUM_RND; i < chiGlobalsPkg::NUM_RND_IF; i++)
  begin : rndSentinel
    `CHI_TB_TIE_OFF_PORT(rnd[i])
  end
  for (genvar i = chiGlobalsPkg::NUM_RNI; i < chiGlobalsPkg::NUM_RNI_IF; i++)
  begin : rniSentinel
    `CHI_TB_TIE_OFF_PORT(rni[i])
  end
  for (genvar i = chiGlobalsPkg::NUM_SNF; i < chiGlobalsPkg::NUM_SNF_IF; i++)
  begin : snfSentinel
    `CHI_TB_TIE_OFF_PORT(snf[i])
  end
  for (genvar i = chiGlobalsPkg::NUM_SNI; i < chiGlobalsPkg::NUM_SNI_IF; i++)
  begin : sniSentinel
    `CHI_TB_TIE_OFF_PORT(sni[i])
  end

  for (genvar i = 0; i < chiGlobalsPkg::NUM_RNF; i++) begin : rnfPorts
    localparam int unsigned PORT_ORDINAL = chiGlobalsPkg::OFF_RNF + i;
    chiRequesterDriverBfm driverBfm (`CHI_TB_DRIVER_CONNECT(rnf[i]));
    chiMonitorBfm monitorBfm (`CHI_TB_MONITOR_CONNECT(rnf[i], PORT_ORDINAL));
    initial begin
      driverBfm.configure(PORT_ORDINAL, chiGlobalsPkg::RN_F);
      monitorBfm.configure(PORT_ORDINAL, chiGlobalsPkg::RN_F);
      uvm_config_db#(virtual chiRequesterDriverBfm)::set(
          null, "*", chiGlobalsPkg::requesterDriverBfmKey(PORT_ORDINAL), driverBfm);
      uvm_config_db#(virtual chiMonitorBfm)::set(
          null, "*", chiGlobalsPkg::monitorBfmKey(PORT_ORDINAL), monitorBfm);
    end
  end

  for (genvar i = 0; i < chiGlobalsPkg::NUM_RND; i++) begin : rndPorts
    localparam int unsigned PORT_ORDINAL = chiGlobalsPkg::OFF_RND + i;
    chiRequesterDriverBfm driverBfm (`CHI_TB_DRIVER_CONNECT(rnd[i]));
    chiMonitorBfm monitorBfm (`CHI_TB_MONITOR_CONNECT(rnd[i], PORT_ORDINAL));
    initial begin
      driverBfm.configure(PORT_ORDINAL, chiGlobalsPkg::RN_D);
      monitorBfm.configure(PORT_ORDINAL, chiGlobalsPkg::RN_D);
      uvm_config_db#(virtual chiRequesterDriverBfm)::set(
          null, "*", chiGlobalsPkg::requesterDriverBfmKey(PORT_ORDINAL), driverBfm);
      uvm_config_db#(virtual chiMonitorBfm)::set(
          null, "*", chiGlobalsPkg::monitorBfmKey(PORT_ORDINAL), monitorBfm);
    end
  end

  for (genvar i = 0; i < chiGlobalsPkg::NUM_RNI; i++) begin : rniPorts
    localparam int unsigned PORT_ORDINAL = chiGlobalsPkg::OFF_RNI + i;
    chiRequesterDriverBfm driverBfm (`CHI_TB_DRIVER_CONNECT(rni[i]));
    chiMonitorBfm monitorBfm (`CHI_TB_MONITOR_CONNECT(rni[i], PORT_ORDINAL));
    initial begin
      driverBfm.configure(PORT_ORDINAL, chiGlobalsPkg::RN_I);
      monitorBfm.configure(PORT_ORDINAL, chiGlobalsPkg::RN_I);
      uvm_config_db#(virtual chiRequesterDriverBfm)::set(
          null, "*", chiGlobalsPkg::requesterDriverBfmKey(PORT_ORDINAL), driverBfm);
      uvm_config_db#(virtual chiMonitorBfm)::set(
          null, "*", chiGlobalsPkg::monitorBfmKey(PORT_ORDINAL), monitorBfm);
    end
  end

  for (genvar i = 0; i < chiGlobalsPkg::NUM_SNF; i++) begin : snfPorts
    localparam int unsigned PORT_ORDINAL = chiGlobalsPkg::OFF_SNF + i;
    chiSubordinateDriverBfm driverBfm (`CHI_TB_DRIVER_CONNECT(snf[i]));
    chiMonitorBfm monitorBfm (`CHI_TB_MONITOR_CONNECT(snf[i], PORT_ORDINAL));
    initial begin
      driverBfm.configure(PORT_ORDINAL, chiGlobalsPkg::SN_F);
      monitorBfm.configure(PORT_ORDINAL, chiGlobalsPkg::SN_F);
      uvm_config_db#(virtual chiSubordinateDriverBfm)::set(
          null, "*", chiGlobalsPkg::subordinateDriverBfmKey(PORT_ORDINAL), driverBfm);
      uvm_config_db#(virtual chiMonitorBfm)::set(
          null, "*", chiGlobalsPkg::monitorBfmKey(PORT_ORDINAL), monitorBfm);
    end
  end

  for (genvar i = 0; i < chiGlobalsPkg::NUM_SNI; i++) begin : sniPorts
    localparam int unsigned PORT_ORDINAL = chiGlobalsPkg::OFF_SNI + i;
    chiSubordinateDriverBfm driverBfm (`CHI_TB_DRIVER_CONNECT(sni[i]));
    chiMonitorBfm monitorBfm (`CHI_TB_MONITOR_CONNECT(sni[i], PORT_ORDINAL));
    initial begin
      driverBfm.configure(PORT_ORDINAL, chiGlobalsPkg::SN_I);
      monitorBfm.configure(PORT_ORDINAL, chiGlobalsPkg::SN_I);
      uvm_config_db#(virtual chiSubordinateDriverBfm)::set(
          null, "*", chiGlobalsPkg::subordinateDriverBfmKey(PORT_ORDINAL), driverBfm);
      uvm_config_db#(virtual chiMonitorBfm)::set(
          null, "*", chiGlobalsPkg::monitorBfmKey(PORT_ORDINAL), monitorBfm);
    end
  end

  initial begin
    uvm_config_db#(virtual chiClkRstBfm)::set(
        null, "*", chiGlobalsPkg::clkRstBfmKey(), clkRstBfm);
  end

  //----------------------------------------------------------------------------
  // Configuration report and self-checks
  //
  // Printed with $display rather than uvm_info so that it appears even when no
  // test is running, which is the mode `make compile` uses. Every quantity
  // printed here has a row in DV/doc/traceability.md, and the printout is what
  // that table is populated from, so the two cannot drift.
  //----------------------------------------------------------------------------

  function automatic int unsigned placementCollisionCount();
    int unsigned bad;
    bad = 0;
    for (int unsigned a = 0; a < chiGlobalsPkg::NUM_NODES; a++)
      for (int unsigned b = a + 1; b < chiGlobalsPkg::NUM_NODES; b++)
        if ((chiGlobalsPkg::PLACEMENTS[a].meshX == chiGlobalsPkg::PLACEMENTS[b].meshX) &&
            (chiGlobalsPkg::PLACEMENTS[a].meshY == chiGlobalsPkg::PLACEMENTS[b].meshY) &&
            (chiGlobalsPkg::PLACEMENTS[a].devicePort == chiGlobalsPkg::PLACEMENTS[b].devicePort))
          bad++;
    return bad;
  endfunction

  function automatic int unsigned nodeIdCollisionCount();
    int unsigned bad;
    bad = 0;
    for (int unsigned a = 0; a < chiGlobalsPkg::NUM_NODES; a++)
      for (int unsigned b = a + 1; b < chiGlobalsPkg::NUM_NODES; b++)
        if (chiGlobalsPkg::NODE_IDS[a] == chiGlobalsPkg::NODE_IDS[b])
          bad++;
    return bad;
  endfunction

  initial begin
    // The interface's own widths, read from a port that always exists. Read
    // procedurally because $bits() of a hierarchical reference cannot size a
    // localparam.
    int unsigned ifReqW;
    int unsigned ifRspW;
    int unsigned ifDatW;
    int unsigned ifSnpW;
    ifReqW = $bits(rnf[0].TXREQFLIT);
    ifRspW = $bits(rnf[0].TXRSPFLIT);
    ifDatW = $bits(rnf[0].TXDATFLIT);
    ifSnpW = $bits(rnf[0].RXSNPFLIT);

    $display({"[hdlTop] CHI interconnect testbench, hdlTop side.\n",
              "[hdlTop] Node counts  RN-F %0d  RN-D %0d  RN-I %0d  SN-F %0d",
              "  SN-I %0d  HN-F %0d  HN-I %0d  MN %0d  total %0d"},
             chiGlobalsPkg::NUM_RNF, chiGlobalsPkg::NUM_RND,
             chiGlobalsPkg::NUM_RNI, chiGlobalsPkg::NUM_SNF,
             chiGlobalsPkg::NUM_SNI, chiGlobalsPkg::NUM_HNF,
             chiGlobalsPkg::NUM_HNI, chiGlobalsPkg::NUM_MN,
             chiGlobalsPkg::NUM_NODES);
    $display({"[hdlTop] Widths  addr %0d  data %0d  nodeId %0d  txnId %0d",
              "  lcrdDepth %0d"},
             chiGlobalsPkg::ADDR_W, chiGlobalsPkg::DATA_W,
             chiGlobalsPkg::NODE_ID_W, chiGlobalsPkg::TXN_ID_W,
             chiGlobalsPkg::LCRD_DEPTH);
    $display({"[hdlTop] Flit widths, interface against the model's field sum:\n",
              "[hdlTop]   REQ %0d / %0d\n",
              "[hdlTop]   RSP %0d / %0d\n",
              "[hdlTop]   SNP %0d / %0d\n",
              "[hdlTop]   DAT %0d / %0d"},
             ifReqW, chiGlobalsPkg::REQ_NAMED_W,
             ifRspW, chiGlobalsPkg::RSP_NAMED_W,
             ifSnpW, chiGlobalsPkg::SNP_NAMED_W,
             ifDatW, chiGlobalsPkg::DAT_NAMED_W);

    // A model width that disagrees with the chi_if bus means every flit is
    // resized by the port connection, silently, in both directions, so it is
    // fatal rather than a warning. The two comparisons are different claims:
    // the first says the width formula matches the bus, the second says the
    // field list adds up to that width, so a field the model forgets shows up
    // here instead of shifting every field above it. See OPEN QUESTIONS Q7.
    if ((chiGlobalsPkg::REQ_FLIT_W != ifReqW) ||
        (chiGlobalsPkg::RSP_FLIT_W != ifRspW) ||
        (chiGlobalsPkg::SNP_FLIT_W != ifSnpW) ||
        (chiGlobalsPkg::DAT_FLIT_W != ifDatW))
      $fatal(1, {"[hdlTop] flit bus widths disagree with chiGlobalsPkg:",
                 " REQ %0d/%0d RSP %0d/%0d SNP %0d/%0d DAT %0d/%0d"},
             chiGlobalsPkg::REQ_FLIT_W, ifReqW, chiGlobalsPkg::RSP_FLIT_W, ifRspW,
             chiGlobalsPkg::SNP_FLIT_W, ifSnpW, chiGlobalsPkg::DAT_FLIT_W, ifDatW);

    for (int unsigned i = 0; i < chiGlobalsPkg::NUM_NODES; i++)
      $display({"[hdlTop] node %0d  %s  nodeId 0x%0h  mesh (%0d,%0d)",
                " port %0d  index %0d"},
               i, chiGlobalsPkg::nodeClassName(chiGlobalsPkg::nodeClassOfOrdinal(i)),
               chiGlobalsPkg::NODE_IDS[i],
               chiGlobalsPkg::PLACEMENTS[i].meshX,
               chiGlobalsPkg::PLACEMENTS[i].meshY,
               chiGlobalsPkg::PLACEMENTS[i].devicePort,
               chiGlobalsPkg::PLACEMENTS[i].nodeIndex);

    for (int unsigned r = 0; r < chiGlobalsPkg::NUM_REGIONS; r++)
      $display({"[hdlTop] region %0d  base 0x%0h  limit 0x%0h  target 0x%0h",
                "  attr 0x%0h"},
               r, chiGlobalsPkg::REGION_BASE[r], chiGlobalsPkg::REGION_LIMIT[r],
               chiGlobalsPkg::REGION_TARGET[r], chiGlobalsPkg::REGION_ATTRIBUTES[r]);

    // Every window a sequence is allowed to draw from has to map to a real
    // target. An unmapped request gets no error response from this DUT, so an
    // out-of-window address would show up as a hang with no explanation
    // rather than as a failed check. See OPEN QUESTIONS Q11.
    if (!chiGlobalsPkg::chiAddrIsDeliverable(chiGlobalsPkg::COHERENT_WINDOW_BASE, 1'b1))
      $fatal(1, "[hdlTop] the coherent stimulus window at 0x%0h is not mapped",
             chiGlobalsPkg::COHERENT_WINDOW_BASE);
    if (!chiGlobalsPkg::chiAddrIsDeliverable(chiGlobalsPkg::DIRECT_WINDOW_BASE, 1'b1))
      $fatal(1, "[hdlTop] the direct stimulus window at 0x%0h is not mapped",
             chiGlobalsPkg::DIRECT_WINDOW_BASE);

    if (nodeIdCollisionCount() != 0)
      $fatal(1, "[hdlTop] NodeID table has %0d collisions", nodeIdCollisionCount());
    if (placementCollisionCount() != 0)
      $fatal(1, "[hdlTop] placement table has %0d collisions", placementCollisionCount());
  end

  //----------------------------------------------------------------------------
  // The repository's filelist.f brings in bind files that attach assertions to
  // DUT internals. A firing internal assertion is a DUT finding, but it is
  // reported against a hierarchy this black-box testbench is not allowed to
  // reason about, so +chiSvaOff switches them off for the DUT instance only,
  // leaving any testbench assertion alive. See OPEN QUESTIONS Q21.
  //----------------------------------------------------------------------------

  initial begin
    if ($test$plusargs("chiSvaOff")) begin
      $assertoff(0, chiDut);
      $display("[hdlTop] DUT-internal assertions disabled by +chiSvaOff");
    end
  end

endmodule : hdlTop
