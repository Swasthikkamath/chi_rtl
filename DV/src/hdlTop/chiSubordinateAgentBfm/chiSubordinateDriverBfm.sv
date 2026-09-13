// Subordinate side pin interface: the same link layer peer as the Requester
// BFM, with the protocol services a Completer needs.
//
// A Subordinate receives requests and answers them with responses and data. It
// never issues a request and never receives a snoop, because only a fully
// coherent Requester holds cacheable state [SPEC:IHI0050H B1.6.1].
interface chiSubordinateDriverBfm (
  chi_if chiPort
);
  import chi_cfg_pkg::*;
  import chi_pkg::*;
  import chiGlobalsPkg::*;

  // See the note in chiRequesterDriverBfm: fixed, not a parameter, so the
  // virtual interface type stays simple.
  localparam bit REQUESTER_PORT = 1'b0;

  `include "chiLinkLayerBfm.svh"

  chi_node_class_e nodeClass = NODE_SNF;
  int unsigned     agentId   = 0;

  function automatic void configure(input int unsigned id,
                                    input chi_node_class_e cls);
    agentId   = id;
    nodeClass = cls;
  endfunction

  // A Subordinate takes no part in system coherency: it has no cache to bring
  // into the coherent domain, so SYSCOREQ stays deasserted.
  task automatic bringUp();
    waitOutOfReset();
    activateLink();
    waitLinkRun();
    waitTxCreditsReady();
  endtask

  // -------------------------------------------------------------------------
  // Receive
  // -------------------------------------------------------------------------
  task automatic getRequest(output chi_req_flit_t flit);
    logic [REQ_FLIT_W-1:0] raw;
    getReqFlit(raw);
    flit = unpackReqFlit(CHI_CFG, {{(CHI_MAX_REQ_FLIT_W-REQ_FLIT_W){1'b0}}, raw});
  endtask

  task automatic getData(output chi_dat_flit_t flit);
    logic [DAT_FLIT_W-1:0] raw;
    getDatFlit(raw);
    flit = unpackDatFlit(CHI_CFG, {{(CHI_MAX_DAT_FLIT_W-DAT_FLIT_W){1'b0}}, raw});
  endtask

  // The receive RSP channel is credited so that activation can complete, but
  // the spec shows no protocol response arriving at a Subordinate. Anything
  // that does arrive is surfaced here so the proxy can flag it rather than
  // silently dropping it. See OPEN QUESTIONS.
  task automatic getResponse(output chi_rsp_flit_t flit);
    logic [RSP_FLIT_W-1:0] raw;
    getRspFlit(raw);
    flit = unpackRspFlit(CHI_CFG, {{(CHI_MAX_RSP_FLIT_W-RSP_FLIT_W){1'b0}}, raw});
  endtask

  // -------------------------------------------------------------------------
  // Transmit
  // -------------------------------------------------------------------------
  task automatic sendResponse(input chi_rsp_flit_t flit);
    logic [CHI_MAX_RSP_FLIT_W-1:0] packed_;
    packed_ = packRspFlit(CHI_CFG, flit);
    sendRspFlit(packed_[RSP_FLIT_W-1:0]);
  endtask

  task automatic sendData(input chi_dat_flit_t flit);
    logic [CHI_MAX_DAT_FLIT_W-1:0] packed_;
    packed_ = packDatFlit(CHI_CFG, flit);
    sendDatFlit(packed_[DAT_FLIT_W-1:0]);
  endtask

  function automatic bit requestPending();
    return (reqRxQueue.size() != 0);
  endfunction

  function automatic bit writeDataPending();
    return (datRxQueue.size() != 0);
  endfunction

  task automatic waitCycles(input int unsigned count);
    repeat (count) @(posedge chiPort.CLK);
  endtask
endinterface
