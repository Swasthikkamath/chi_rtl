//==============================================================================
// chiRequesterDriverBfm
//
// Why this interface is so thin:
//
// Everything that is common to both node roles - activation, credits, drain,
// SYSCO, flit transmission and capture - is in chiLinkLayerBfm.svh and is
// included below. What is left here is only what a Requester port does that a
// Subordinate port does not: source REQ flits, sink SNP flits, and pack the
// testbench's REQ, RSP and DAT structs onto the wire. No decision about which
// opcode to send, which TxnID to use, or how to answer a snoop lives here;
// those belong to chiRequesterDriverProxy, which reaches this BFM through a
// virtual interface and never touches a pin.
//
// One instance exists per configured RN-F, RN-D and RN-I port. The node class
// arrives as a parameter so that the shared link layer can decide which
// channels are in use and whether SYSCO applies, without this file testing the
// class anywhere.
//==============================================================================

interface chiRequesterDriverBfm (
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
  // Struct-level transmission
  //
  // SrcID is stamped here from the NodeID table rather than trusted from the
  // proxy, so that no sequence can accidentally impersonate another node and
  // so that a swept configuration cannot leave a stale SrcID in an item.
  //----------------------------------------------------------------------------

  task automatic driveReq(input chiGlobalsPkg::chiReqFlitT flit);
    chiGlobalsPkg::chiReqFlitT stampedFlit;
    stampedFlit = flit;
    stampedFlit.srcId = chiGlobalsPkg::NODE_IDS[nodeOrdinal];
    sendReqFlit(chiGlobalsPkg::packReq(stampedFlit));
  endtask

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

  //----------------------------------------------------------------------------
  // Struct-level reception
  //
  // The raw form is kept available beside the unpacked form because the
  // scoreboard compares wire bits, and because an L-Credit return has to be
  // recognisable without trusting the field placement.
  //----------------------------------------------------------------------------

  task automatic getRsp(output chiGlobalsPkg::chiRspFlitT flit,
                        output chiGlobalsPkg::chiRawFlitT raw);
    getRspFlit(raw);
    flit = chiGlobalsPkg::unpackRsp(raw);
  endtask

  task automatic getDat(output chiGlobalsPkg::chiDatFlitT flit,
                        output chiGlobalsPkg::chiRawFlitT raw);
    getDatFlit(raw);
    flit = chiGlobalsPkg::unpackDat(raw);
  endtask

  task automatic getSnp(output chiGlobalsPkg::chiSnpFlitT flit,
                        output chiGlobalsPkg::chiRawFlitT raw);
    getSnpFlit(raw);
    flit = chiGlobalsPkg::unpackSnp(raw);
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

endinterface : chiRequesterDriverBfm
