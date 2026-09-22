//==============================================================================
// chiSubordinateDriverBfm
//
// Why this is a separate file from the Requester driver BFM rather than one
// parameterized BFM:
//
// The two roles use mirror-image channel sets. A Subordinate port receives REQ
// and never sends it, and never receives SNP at all [TOP:CHI_CONNECT_PORT with
// IS_REQUESTER=0]. Sharing one interface would mean every task testing the role
// at run time, when the role is fixed at elaboration. The part that genuinely
// is shared - the whole link layer - is included from the same file the
// Requester BFM includes, so a credit or activation fix lands on both.
//
// One instance exists per configured SN-F and SN-I port. Memory contents,
// latency policy and error injection are not here: they are the Subordinate
// agent's memory model and sequences, which reach this BFM only through a
// virtual interface.
//==============================================================================

interface chiSubordinateDriverBfm (
    // Clock and reset, both driven by the DUT onto chi_if [ASSUMPTION:2].
    input  logic CLK,
    input  logic RESETn,

    // Link activation. The node owns TXLINKACTIVEREQ and RXLINKACTIVEACK.
    output logic TXLINKACTIVEREQ,
    input  logic TXLINKACTIVEACK,
    input  logic RXLINKACTIVEREQ,
    output logic RXLINKACTIVEACK,

    // System coherency. SYSCOACK is a combinational copy of SYSCOREQ in this
    // DUT, so the handshake completes in zero time [ASSUMPTION:4].
    output logic SYSCOREQ,
    input  logic SYSCOACK,

    // Node to interconnect. The SNP direction is unused on every port class
    // and is held at zero rather than left floating [ASSUMPTION:1].
    output logic TXREQFLITPEND,
    output logic TXREQFLITV,
    output logic [chiGlobalsPkg::REQ_FLIT_W-1:0] TXREQFLIT,
    output logic [((chiGlobalsPkg::REQ_FLIT_W + 7) / 8)-1:0] TXREQFLITCHK,
    input  logic TXREQLCRDV,

    output logic TXRSPFLITPEND,
    output logic TXRSPFLITV,
    output logic [chiGlobalsPkg::RSP_FLIT_W-1:0] TXRSPFLIT,
    output logic [((chiGlobalsPkg::RSP_FLIT_W + 7) / 8)-1:0] TXRSPFLITCHK,
    input  logic TXRSPLCRDV,

    output logic TXDATFLITPEND,
    output logic TXDATFLITV,
    output logic [chiGlobalsPkg::DAT_FLIT_W-1:0] TXDATFLIT,
    output logic [((chiGlobalsPkg::DAT_FLIT_W + 7) / 8)-1:0] TXDATFLITCHK,
    input  logic TXDATLCRDV,

    output logic TXSNPFLITPEND,
    output logic TXSNPFLITV,
    output logic [chiGlobalsPkg::SNP_FLIT_W-1:0] TXSNPFLIT,

    // Interconnect to node.
    input  logic RXREQFLITPEND,
    input  logic RXREQFLITV,
    input  logic [chiGlobalsPkg::REQ_FLIT_W-1:0] RXREQFLIT,
    output logic RXREQLCRDV,

    input  logic RXRSPFLITPEND,
    input  logic RXRSPFLITV,
    input  logic [chiGlobalsPkg::RSP_FLIT_W-1:0] RXRSPFLIT,
    output logic RXRSPLCRDV,

    input  logic RXDATFLITPEND,
    input  logic RXDATFLITV,
    input  logic [chiGlobalsPkg::DAT_FLIT_W-1:0] RXDATFLIT,
    output logic RXDATLCRDV,

    input  logic RXSNPFLITPEND,
    input  logic RXSNPFLITV,
    input  logic [chiGlobalsPkg::SNP_FLIT_W-1:0] RXSNPFLIT,
    output logic RXSNPLCRDV
);

  import chiGlobalsPkg::*;

`include "chiLinkLayerBfm.svh"

  //----------------------------------------------------------------------------
  // Struct-level reception: a Subordinate is driven by the requests it receives
  //----------------------------------------------------------------------------

  task automatic getReq(output chiGlobalsPkg::chiReqFlitT flit,
                        output chiGlobalsPkg::chiRawFlitT raw);
    getReqFlit(raw);
    flit = chiGlobalsPkg::unpackReq(raw);
  endtask

  task automatic getDat(output chiGlobalsPkg::chiDatFlitT flit,
                        output chiGlobalsPkg::chiRawFlitT raw);
    getDatFlit(raw);
    flit = chiGlobalsPkg::unpackDat(raw);
  endtask

  task automatic getRsp(output chiGlobalsPkg::chiRspFlitT flit,
                        output chiGlobalsPkg::chiRawFlitT raw);
    getRspFlit(raw);
    flit = chiGlobalsPkg::unpackRsp(raw);
  endtask

  //----------------------------------------------------------------------------
  // Struct-level transmission
  //----------------------------------------------------------------------------

  task automatic driveRsp(input chiGlobalsPkg::chiRspFlitT flit);
    chiGlobalsPkg::chiRspFlitT stampedFlit;
    stampedFlit = flit;
    stampedFlit.srcId = chiGlobalsPkg::NODE_IDS[nodeOrdinal];
    sendRspFlit(chiGlobalsPkg::packRsp(stampedFlit));
  endtask

  task automatic driveDat(input chiGlobalsPkg::chiDatFlitT flit);
    chiGlobalsPkg::chiDatFlitT stampedFlit;
    stampedFlit = flit;
    stampedFlit.srcId = chiGlobalsPkg::NODE_IDS[nodeOrdinal];
    sendDatFlit(chiGlobalsPkg::packDat(stampedFlit));
  endtask

  function automatic chiGlobalsPkg::chiNodeIdT ownNodeId();
    return chiGlobalsPkg::NODE_IDS[nodeOrdinal];
  endfunction

  function automatic int unsigned ownOrdinal();
    return nodeOrdinal;
  endfunction

  function automatic chiGlobalsPkg::chiNodeClassE ownNodeClass();
    return nodeClass;
  endfunction

endinterface : chiSubordinateDriverBfm
