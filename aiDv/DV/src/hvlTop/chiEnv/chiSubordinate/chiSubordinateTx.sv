// One item of Subordinate activity.
//
// A Subordinate is reactive: it does not originate transactions, so this type
// is mostly an observation record. As stimulus it carries response policy
// rather than a transaction, which is the only thing a test can usefully vary
// at a memory endpoint: how long it takes to answer, and whether it answers
// with an error.
class chiSubordinateTx extends uvm_sequence_item;

  rand chiTxKindE    txKind;
  rand chiDirectionE direction;
  rand chi_channel_e channel;

  // ----- Response policy, set by a sequence -----
  // Cycles to wait before answering a request. Latency variation is what makes
  // responses from different Subordinates interleave rather than arrive in
  // request order.
  rand int unsigned responseDelay;

  // Error to report instead of a normal completion. Stage 1 leaves this at OK;
  // it is the hook for error injection later [SPEC:IHI0050H B2.12].
  rand chi_resp_err_e injectError;

  // ----- Protocol content, set by a driver or a monitor -----
  chi_req_flit_t reqFlit;
  chi_rsp_flit_t rspFlit;
  chi_dat_flit_t datFlit;

  chiLinkEventS linkEvent;

  int unsigned     agentId;
  chi_node_class_e nodeClass;

  `uvm_object_utils(chiSubordinateTx)

  function new(string name = "chiSubordinateTx");
    super.new(name);
  endfunction

  constraint delayRange {
    responseDelay inside {[0:8]};
  }

  constraint noErrorByDefault {
    injectError == RESP_ERR_OK;
  }

  constraint kindDefault {
    txKind == CHI_TX_PROTOCOL_FLIT;
  }

  function void do_copy(uvm_object rhs);
    chiSubordinateTx that;
    super.do_copy(rhs);
    if (!$cast(that, rhs)) begin
      `uvm_fatal("chiSubordinateTx", "do_copy type mismatch")
    end
    txKind        = that.txKind;
    direction     = that.direction;
    channel       = that.channel;
    responseDelay = that.responseDelay;
    injectError   = that.injectError;
    reqFlit       = that.reqFlit;
    rspFlit       = that.rspFlit;
    datFlit       = that.datFlit;
    linkEvent     = that.linkEvent;
    agentId       = that.agentId;
    nodeClass     = that.nodeClass;
  endfunction

  function string convert2string();
    if (txKind == CHI_TX_LINK_EVENT)
      return $sformatf("subordinate %0d %s: link %s %s channel %s state %s",
                       agentId, nodeClass.name(), linkEvent.kind.name(),
                       linkEvent.direction.name(), linkEvent.channel.name(),
                       linkEvent.state.name());

    case (channel)
      CHI_CHANNEL_REQ:
        return $sformatf(
            "subordinate %0d %s: %s REQ %s addr 0x%0h txnId 0x%0h",
            agentId, nodeClass.name(), direction.name(), reqFlit.opcode.name(),
            reqFlit.addr, reqFlit.txnId);
      CHI_CHANNEL_RSP:
        return $sformatf(
            "subordinate %0d %s: %s RSP %s txnId 0x%0h dbId 0x%0h",
            agentId, nodeClass.name(), direction.name(), rspFlit.opcode.name(),
            rspFlit.txnId, rspFlit.dbIdOrGroupId);
      default:
        return $sformatf(
            "subordinate %0d %s: %s DAT %s txnId 0x%0h dataId %0d",
            agentId, nodeClass.name(), direction.name(), datFlit.opcode.name(),
            datFlit.txnId, datFlit.dataId);
    endcase
  endfunction
endclass
