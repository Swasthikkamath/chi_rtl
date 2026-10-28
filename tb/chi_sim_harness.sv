// Simulation harness for the product top.
//
// This is the counterpart of chi_interconnect_compile: it creates the same
// chi_if arrays, but it also attaches a node-side link model to every
// external port so that both directions of every link can reach RUN and
// L-Credits are exchanged. Lint uses the compile harness; simulation uses
// this one.
module chi_sim_harness #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned NUM_NODES =
    CFG.numRnf + CFG.numRnd + CFG.numRni + CFG.numSnf + CFG.numSni
    + CFG.numHnf + CFG.numHni + CFG.numMn,
  // Node ordinals below this are external ports with a link; the rest are
  // internal fabric endpoints.
  parameter int unsigned NUM_EXTERNAL =
    CFG.numRnf + CFG.numRnd + CFG.numRni + CFG.numSnf + CFG.numSni,
  parameter int unsigned LCRD_DEPTH = (CFG.lcrdDepth > 1) ? CFG.lcrdDepth : 2,
  parameter int unsigned COUNT_W = $clog2(LCRD_DEPTH + 1)
) (
  input  logic clk,
  input  logic resetn,
  output logic [31:0] PRDATA,
  output logic PREADY,
  output logic PSLVERR,
  output logic [NUM_NODES-1:0] linkUp,
  output logic [NUM_NODES-1:0] linkParityError,
  output logic [NUM_NODES-1:0] linkCreditError,
  // Per external port, aggregated across all of its channels.
  output logic [NUM_EXTERNAL-1:0] nodeLinkRun,
  output logic [NUM_EXTERNAL-1:0] nodeCreditsFull,
  output logic [NUM_EXTERNAL-1:0] nodeFlitSeen
);
  localparam int unsigned NUM_RNF_E = (CFG.numRnf > 0) ? CFG.numRnf : 1;
  localparam int unsigned NUM_RND_E = (CFG.numRnd > 0) ? CFG.numRnd : 1;
  localparam int unsigned NUM_RNI_E = (CFG.numRni > 0) ? CFG.numRni : 1;
  localparam int unsigned NUM_SNF_E = (CFG.numSnf > 0) ? CFG.numSnf : 1;
  localparam int unsigned NUM_SNI_E = (CFG.numSni > 0) ? CFG.numSni : 1;

  localparam int unsigned OFF_RNF = 0;
  localparam int unsigned OFF_RND = OFF_RNF + CFG.numRnf;
  localparam int unsigned OFF_RNI = OFF_RND + CFG.numRnd;
  localparam int unsigned OFF_SNF = OFF_RNI + CFG.numRni;
  localparam int unsigned OFF_SNI = OFF_SNF + CFG.numSnf;

  chi_if #(.CFG(CFG)) rnfIf [NUM_RNF_E-1:0] ();
  chi_if #(.CFG(CFG)) rndIf [NUM_RND_E-1:0] ();
  chi_if #(.CFG(CFG)) rniIf [NUM_RNI_E-1:0] ();
  chi_if #(.CFG(CFG)) snfIf [NUM_SNF_E-1:0] ();
  chi_if #(.CFG(CFG)) sniIf [NUM_SNI_E-1:0] ();

  chi_interconnect_top #(.CFG(CFG)) fabric (
    .clk, .resetn,
    .rnf(rnfIf), .rnd(rndIf), .rni(rniIf), .snf(snfIf), .sni(sniIf),
    .PADDR('0), .PSEL(1'b0), .PENABLE(1'b0), .PWRITE(1'b0),
    .PWDATA('0), .PSTRB('0), .PPROT('0), .PNSE(1'b0),
    .PRDATA, .PREADY, .PSLVERR,
    .linkUp, .linkParityError, .linkCreditError
  );

  // A Requester is credited on REQ, RSP and DAT and receives RSP, SNP and
  // DAT. A Subordinate is credited on RSP and DAT and receives REQ, RSP and
  // DAT. "Credits full" therefore means a different set of channels for the
  // two classes, and each class expects flits on a different set.
`define CHI_ATTACH_NODE_BFM(NAME, PORTS, COUNT, OFFSET, IS_REQUESTER) \
  if (COUNT > 0) begin : NAME``_bfm \
    for (genvar i = 0; i < COUNT; i++) begin : port \
      logic portLinkRun; \
      logic [COUNT_W-1:0] reqCredits; \
      logic [COUNT_W-1:0] rspCredits; \
      logic [COUNT_W-1:0] datCredits; \
      int unsigned reqSeen; \
      int unsigned rspSeen; \
      int unsigned snpSeen; \
      int unsigned datSeen; \
      chi_node_link_bfm #( \
        .CFG(CFG), .REQUESTER_PORT(IS_REQUESTER), \
        .LCRD_DEPTH(LCRD_DEPTH), .COUNT_W(COUNT_W) \
      ) node ( \
        .clk, .resetn, .chiPort(PORTS[i]), \
        .nodeLinkRun(portLinkRun), \
        .reqTxCredits(reqCredits), .rspTxCredits(rspCredits), \
        .datTxCredits(datCredits), \
        .reqRxCount(reqSeen), .rspRxCount(rspSeen), \
        .snpRxCount(snpSeen), .datRxCount(datSeen) \
      ); \
      assign nodeLinkRun[OFFSET+i] = portLinkRun; \
      assign nodeCreditsFull[OFFSET+i] = \
        (rspCredits == COUNT_W'(LCRD_DEPTH)) \
        && (datCredits == COUNT_W'(LCRD_DEPTH)) \
        && (!IS_REQUESTER || (reqCredits == COUNT_W'(LCRD_DEPTH))); \
      assign nodeFlitSeen[OFFSET+i] = \
        (reqSeen != 0) || (rspSeen != 0) || (snpSeen != 0) || (datSeen != 0); \
    end \
  end

  `CHI_ATTACH_NODE_BFM(rnf, rnfIf, CFG.numRnf, OFF_RNF, 1'b1)
  `CHI_ATTACH_NODE_BFM(rnd, rndIf, CFG.numRnd, OFF_RND, 1'b1)
  `CHI_ATTACH_NODE_BFM(rni, rniIf, CFG.numRni, OFF_RNI, 1'b1)
  `CHI_ATTACH_NODE_BFM(snf, snfIf, CFG.numSnf, OFF_SNF, 1'b0)
  `CHI_ATTACH_NODE_BFM(sni, sniIf, CFG.numSni, OFF_SNI, 1'b0)

`undef CHI_ATTACH_NODE_BFM
endmodule
