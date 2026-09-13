// Requester side pin interface: link layer peer plus the protocol level send
// and receive services the driver proxy calls.
//
// The link layer itself is shared with the Subordinate BFM and is included
// rather than repeated, because a Requester and a Subordinate differ in which
// channels apply and in what they do with a flit, not in how activation and
// L-Credits work.
//
// This BFM converts between the flit structs in chi_pkg and the packed vectors
// on the pins. The DUT's own pack and unpack functions are used, so a field
// that moves in the spec moves for the testbench and the fabric together
// [SPEC:IHI0050H B13.9.1-B13.9.4].
interface chiRequesterDriverBfm (
  chi_if chiPort
);
  import chi_cfg_pkg::*;
  import chi_pkg::*;
  import chiGlobalsPkg::*;

  // Fixed rather than a parameter so that "virtual chiRequesterDriverBfm" is a
  // single type. A parameterised interface would make every config_db lookup
  // carry the parameterisation with it for no benefit, since a Requester port
  // is never anything else.
  localparam bit REQUESTER_PORT = 1'b1;

  `include "chiLinkLayerBfm.svh"

  // The class this instance is playing. Set by hdlTop before bring-up, because
  // whether system coherency applies and whether snoops are expected both
  // follow from it.
  chi_node_class_e nodeClass = NODE_RNF;
  int unsigned     agentId   = 0;

  function automatic void configure(input int unsigned id,
                                    input chi_node_class_e cls);
    agentId   = id;
    nodeClass = cls;
  endfunction

  // -------------------------------------------------------------------------
  // Bring-up
  // -------------------------------------------------------------------------
  // Ordering matters. The link must be running in both directions before any
  // flit moves, and a fully coherent Requester must additionally be admitted
  // to system coherency before it may issue a coherent request
  // [SPEC:IHI0050H B14.7]. An I/O coherent Requester has no coherent state to
  // join with, so it skips that step.
  task automatic bringUp();
    waitOutOfReset();
    activateLink();
    waitLinkRun();
    waitTxCreditsReady();
    if (isFullyCoherent(nodeClass)) enterSystemCoherency();
  endtask

  // -------------------------------------------------------------------------
  // Transmit
  // -------------------------------------------------------------------------
  task automatic sendRequest(input chi_req_flit_t flit);
    logic [CHI_MAX_REQ_FLIT_W-1:0] packed_;
    packed_ = packReqFlit(CHI_CFG, flit);
    sendReqFlit(packed_[REQ_FLIT_W-1:0]);
  endtask

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

  // -------------------------------------------------------------------------
  // Receive
  // -------------------------------------------------------------------------
  task automatic getResponse(output chi_rsp_flit_t flit);
    logic [RSP_FLIT_W-1:0] raw;
    getRspFlit(raw);
    flit = unpackRspFlit(CHI_CFG, {{(CHI_MAX_RSP_FLIT_W-RSP_FLIT_W){1'b0}}, raw});
  endtask

  task automatic getSnoop(output chi_snp_flit_t flit);
    logic [SNP_FLIT_W-1:0] raw;
    getSnpFlit(raw);
    flit = unpackSnpFlit(CHI_CFG, {{(CHI_MAX_SNP_FLIT_W-SNP_FLIT_W){1'b0}}, raw});
  endtask

  task automatic getData(output chi_dat_flit_t flit);
    logic [DAT_FLIT_W-1:0] raw;
    getDatFlit(raw);
    flit = unpackDatFlit(CHI_CFG, {{(CHI_MAX_DAT_FLIT_W-DAT_FLIT_W){1'b0}}, raw});
  endtask

  // Non-blocking peek, so the driver proxy can poll a channel it does not want
  // to commit a thread to.
  function automatic bit snoopPending();
    return (snpRxQueue.size() != 0);
  endfunction

  task automatic waitCycles(input int unsigned count);
    repeat (count) @(posedge chiPort.CLK);
  endtask
endinterface
