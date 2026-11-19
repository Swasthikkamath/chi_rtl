// One item of Requester activity, used both as stimulus and as observation.
//
// A sequence fills in the intent fields and leaves the flits alone: it asks
// for a read or a write at an address and the driver proxy decides which
// opcode realises that, because the choice depends on cache state the sequence
// cannot see. A monitor fills in the flit and leaves the intent alone.
//
// txKind is the discriminator. One analysis port carries both protocol flits
// and link events, so anything reading the port must check txKind before it
// reads another field. Carrying link activity on a second port would mean two
// ports, two FIFOs and two subscribe paths for what is one stream of
// observations from one interface.
class chiRequesterTx extends uvm_sequence_item;

  // ----- What kind of item this is -----
  rand chiTxKindE    txKind;
  rand chiDirectionE direction;
  rand chi_channel_e channel;

  // ----- Stimulus intent, set by a sequence -----
  rand chiAccessKindE  accessKind;
  // On a monitored item this is the address the flit carried, which only the
  // REQ and SNP channels have. addrValid says whether it means anything: a
  // subscriber that reads it regardless would be indexing on a field the wire
  // never supplied, and to recover the address of a response it has to follow
  // the TxnID back to the request itself [SPEC:IHI0050H B2.5].
  rand chiAddrT        addr;
  bit                  addrValid;
  rand logic [2:0]     size;
  rand logic [3:0]     qos;
  rand chiDataT        writeData;

  // ----- Protocol content, set by a driver or a monitor -----
  chi_req_flit_t reqFlit;
  chi_rsp_flit_t rspFlit;
  chi_snp_flit_t snpFlit;
  chi_dat_flit_t datFlit;

  // ----- Link content -----
  chiLinkEventS linkEvent;

  // ----- Identity -----
  int unsigned     agentId;
  chi_node_class_e nodeClass;

  // Outcome, filled in by the driver once the transaction completes, so a
  // sequence can react to what actually happened.
  chi_resp_e     completionResp;
  chi_resp_err_e completionErr;
  int unsigned   retryCount;
  chiDataT       readData;

  `uvm_object_utils(chiRequesterTx)

  function new(string name = "chiRequesterTx");
    super.new(name);
  endfunction

  // Stimulus defaults. A sequence narrows these; the constraints here only
  // keep an unconstrained item legal.
  //
  // The address is held below bit 47 because the default System Address Map
  // sends that range to the hashed Home Nodes, which is the only path that
  // reaches a fully coherent Subordinate. Above it the map points at the HN-I
  // and its configuration space [top/chi_interconnect_top.sv makeRegionBase].
  constraint addressSpace {
    addr[CHI_ADDR_W-1] == 1'b0;
    addr[CHI_LINE_OFF_W-1:0] == '0;
  }

  // Stage 1 moves whole cache lines only, so every transfer is the full 64
  // bytes and Size encodes that as 6 [SPEC:IHI0050H B13.10.21].
  constraint transferSize {
    size == 3'd6;
  }

  constraint intentKind {
    txKind     == CHI_TX_PROTOCOL_FLIT;
    direction  == CHI_DIR_TX;
    channel    == CHI_CHANNEL_REQ;
  }

  constraint qosRange {
    qos inside {[0:15]};
  }

  function void do_copy(uvm_object rhs);
    chiRequesterTx that;
    super.do_copy(rhs);
    if (!$cast(that, rhs)) begin
      `uvm_fatal("chiRequesterTx", "do_copy type mismatch")
    end
    txKind         = that.txKind;
    direction      = that.direction;
    channel        = that.channel;
    accessKind     = that.accessKind;
    addr           = that.addr;
    size           = that.size;
    qos            = that.qos;
    writeData      = that.writeData;
    reqFlit        = that.reqFlit;
    rspFlit        = that.rspFlit;
    snpFlit        = that.snpFlit;
    datFlit        = that.datFlit;
    linkEvent      = that.linkEvent;
    agentId        = that.agentId;
    nodeClass      = that.nodeClass;
    completionResp = that.completionResp;
    completionErr  = that.completionErr;
    retryCount     = that.retryCount;
    readData       = that.readData;
  endfunction

  function string convert2string();
    if (txKind == CHI_TX_LINK_EVENT)
      return $sformatf(
          "agent %0d %s: link %s %s channel %s state %s credits %0d",
          agentId, nodeClass.name(), linkEvent.kind.name(),
          linkEvent.direction.name(), linkEvent.channel.name(),
          linkEvent.state.name(), linkEvent.creditCount);

    // Source and target IDs are included on every channel because a flit
    // arriving where it does not belong looks perfectly well formed otherwise,
    // and those two fields are the only evidence of where it was meant to go.
    case (channel)
      CHI_CHANNEL_REQ:
        return $sformatf(
            {"agent %0d %s: %s REQ %s addr 0x%0h size %0d txnId 0x%0h ",
             "src 0x%0h tgt 0x%0h allowRetry %0b pCrdType %0h expCompAck %0b"},
            agentId, nodeClass.name(), direction.name(), reqFlit.opcode.name(),
            reqFlit.addr, reqFlit.size, reqFlit.txnId, reqFlit.srcId,
            reqFlit.tgtId, reqFlit.allowRetry, reqFlit.pCrdType,
            reqFlit.expCompAck);
      CHI_CHANNEL_RSP:
        return $sformatf(
            {"agent %0d %s: %s RSP %s txnId 0x%0h src 0x%0h tgt 0x%0h ",
             "resp %s respErr %s dbId 0x%0h pCrdType %0h"},
            agentId, nodeClass.name(), direction.name(), rspFlit.opcode.name(),
            rspFlit.txnId, rspFlit.srcId, rspFlit.tgtId, rspFlit.resp.name(),
            rspFlit.respErr.name(), rspFlit.dbIdOrGroupId, rspFlit.pCrdType);
      CHI_CHANNEL_SNP:
        return $sformatf(
            {"agent %0d %s: %s SNP %s addr 0x%0h txnId 0x%0h src 0x%0h ",
             "retToSrc %0b"},
            agentId, nodeClass.name(), direction.name(), snpFlit.opcode.name(),
            {snpFlit.addr, 3'b000}, snpFlit.txnId, snpFlit.srcId,
            snpFlit.retToSrc);
      default:
        return $sformatf(
            {"agent %0d %s: %s DAT %s txnId 0x%0h src 0x%0h tgt 0x%0h ",
             "resp %s dataId %0d dbId 0x%0h data 0x%0h"},
            agentId, nodeClass.name(), direction.name(), datFlit.opcode.name(),
            datFlit.txnId, datFlit.srcId, datFlit.tgtId, datFlit.resp.name(),
            datFlit.dataId, datFlit.dbId, datFlit.data[63:0]);
    endcase
  endfunction
endclass
