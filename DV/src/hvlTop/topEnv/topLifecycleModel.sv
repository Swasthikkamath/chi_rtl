//==============================================================================
// topLifecycleModel
//
// The transaction-lifecycle reference model. From the boundary flit stream
// alone it tracks every requester transaction and every subordinate serve and
// checks the rules that make a CHI exchange well formed:
//
//   - identity: a flit a node transmits carries its own NodeID as SrcID; a
//     REQ/RSP/DAT flit the interconnect delivers carries the receiving node's
//     NodeID as TgtID. The second is the misdelivery check: the DUT's router
//     is what puts a flit on this port, so a wrong TgtId is a DUT bug.
//   - a flit never appears on a channel its port class does not use
//     [ASSUMPTION:1]: no REQ leaves a subordinate, none arrives at a
//     requester, no SNP moves on any TX, and a subordinate is never snooped.
//   - every opcode the DUT emits is a defined encoding (an undefined value
//     means corrupted or X wire bits).
//   - requester transactions follow a legal response flow: no unsolicited or
//     duplicate completions, RetryAck only for an AllowRetry request and then
//     exactly one reissue, data beats with distinct DataID and never more
//     than datPacketCount(size), CompAck only against a granted DBID.
//   - P-credits balance per (node, Home, type): a reissue or a PCrdReturn
//     spends a credit that must have been granted [SPEC:B4.4].
//   - snoops are answered: every snoop TxnID on a node gets a SnpResp, a
//     SnpRespData accompanies a real snoop, and a DVM snoop's two parts share
//     one TxnID [SPEC:B8.2.3.2].
//   - subordinate serves follow the same discipline from the other side.
//
// At end of test nothing may be left open: every requester transaction has
// its completion, its data and its CompAck, every serve is complete, and
// every snoop is answered. A dangling entry means the DUT dropped a response
// or the bench dropped a request; either way the test did not finish what it
// started.
//
// The model never predicts which Home or Subordinate a request visits: the
// hash is not observable [Q10/Q15], so matching is by (node, TxnID) on the
// requester side and (node, SrcID, TxnID) on the subordinate side only.
//==============================================================================

// One open requester transaction, keyed by (node, TxnID).
class topLifeTxn;
  chiReqOpcodeE opcode;
  chiAddrT      addr;
  logic [chiGlobalsPkg::SIZE_W-1:0] size;
  bit           allowRetry;
  bit           expCompAck;
  bit           isRead;
  bit           awaitingReissue;
  chiNodeIdT    retryHome;
  logic [chiGlobalsPkg::P_CRD_TYPE_W-1:0] retryPcrdType;
  bit           dbidSeen;
  chiTxnIdT     dbId;
  bit           compSeen;
  int unsigned  dataBeats;
  bit [3:0]     dataIdSeen;
  bit           compAckSent;
  time          reqTime;
endclass

// One open serve at a subordinate, keyed by (node, requester SrcID, TxnID).
class topLifeServe;
  chiReqOpcodeE opcode;
  chiAddrT      addr;
  bit           awaitingReissue;
  bit           dbidSeen;
  chiTxnIdT     dbId;
  bit           compSeen;
  time          reqTime;
endclass

// One snoop a requester has been sent, keyed by (node, TxnID).
class topLifeSnoop;
  chiSnpOpcodeE opcode;
  int unsigned  parts;      // DVM snoops arrive as two flits, one TxnID
  bit           answered;
  time          snpTime;
endclass

class topLifecycleModel extends uvm_component;

  topEnvConfig cfg;

  topLifeTxn    reqTxns[int unsigned];     // reqKey: node * 2^TXN_ID_W + txnId
  topLifeServe  serves[longint unsigned];  // serveKey: node | srcId | txnId
  topLifeSnoop  snops[int unsigned];       // reqKey on the snoop's txnId
  int           pcrdBal[int unsigned];     // pcrdKey: node | home | pCrdType
  // A DBID a requester was granted, keyed by (node, granting Home, DBID) so
  // that two Homes serving one node cannot collide. Write data matches
  // through HomeNid, CompAck through TgtID; both carry the granter.
  int unsigned  dbidToTxn[longint unsigned];
  // A DBID a subordinate granted, keyed by (node, DBID): the subordinate's
  // own allocation, so no cross-Home collision is possible.
  topLifeServe  subDbid[int unsigned];

  int unsigned flitCount;
  int unsigned reqOpened;
  int unsigned reqCompleted;
  int unsigned snopsSeen;
  int unsigned servesSeen;

  `uvm_component_utils(topLifecycleModel)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    flitCount = 0;
    reqOpened = 0;
    reqCompleted = 0;
    snopsSeen = 0;
    servesSeen = 0;
  endfunction

  //--------------------------------------------------------------------------
  // Key packing
  //--------------------------------------------------------------------------

  function automatic int unsigned reqKey(input int unsigned node,
                                         input chiTxnIdT txnId);
    return node * (32'h1 << chiGlobalsPkg::TXN_ID_W) + int'(txnId);
  endfunction

  function automatic longint unsigned serveKey(input int unsigned node,
                                               input chiNodeIdT srcId,
                                               input chiTxnIdT txnId);
    return (longint'(node) << 28) | (longint'(srcId) << 12) | longint'(txnId);
  endfunction

  function automatic longint unsigned homeDbidKey(input int unsigned node,
                                                  input chiNodeIdT home,
                                                  input chiTxnIdT dbId);
    return (longint'(node) << 28) | (longint'(home) << 12) | longint'(dbId);
  endfunction

  function automatic int unsigned subDbidKey(input int unsigned node,
                                             input chiTxnIdT dbId);
    return node * (32'h1 << chiGlobalsPkg::TXN_ID_W) + int'(dbId);
  endfunction

  function automatic int unsigned pcrdKey(input int unsigned node,
      input chiNodeIdT home, input logic [chiGlobalsPkg::P_CRD_TYPE_W-1:0] pctype);
    return (node << 20) | (int'(home) << 4) | int'(pctype);
  endfunction

  //--------------------------------------------------------------------------
  // Opcode classification
  //--------------------------------------------------------------------------

  function automatic bit isReadOpcode(input chiReqOpcodeE op);
    case (op)
      chiGlobalsPkg::REQ_READ_SHARED,
      chiGlobalsPkg::REQ_READ_CLEAN,
      chiGlobalsPkg::REQ_READ_ONCE,
      chiGlobalsPkg::REQ_READ_NO_SNP,
      chiGlobalsPkg::REQ_READ_NO_SNP_SEP,
      chiGlobalsPkg::REQ_READ_UNIQUE,
      chiGlobalsPkg::REQ_READ_NOT_SHARED_DIRTY,
      chiGlobalsPkg::REQ_READ_ONCE_CLEAN_INVALID,
      chiGlobalsPkg::REQ_READ_ONCE_MAKE_INVALID,
      chiGlobalsPkg::REQ_MAKE_READ_UNIQUE,
      chiGlobalsPkg::REQ_ATOMIC_LOAD_ADD,
      chiGlobalsPkg::REQ_ATOMIC_LOAD_CLR,
      chiGlobalsPkg::REQ_ATOMIC_LOAD_EOR,
      chiGlobalsPkg::REQ_ATOMIC_LOAD_SET,
      chiGlobalsPkg::REQ_ATOMIC_LOAD_SMAX,
      chiGlobalsPkg::REQ_ATOMIC_LOAD_SMIN,
      chiGlobalsPkg::REQ_ATOMIC_LOAD_UMAX,
      chiGlobalsPkg::REQ_ATOMIC_LOAD_UMIN,
      chiGlobalsPkg::REQ_ATOMIC_SWAP,
      chiGlobalsPkg::REQ_ATOMIC_COMPARE:
        return 1'b1;
      default:
        return 1'b0;
    endcase
  endfunction

  // A transaction is complete when its completion has been seen, all its
  // read data has arrived, any promised CompAck has been sent, and it is not
  // parked waiting to be reissued after a retry. Only a complete transaction
  // frees its TxnID for reuse.
  function automatic bit txnComplete(input topLifeTxn t);
    if (!t.compSeen || t.awaitingReissue)
      return 1'b0;
    if (t.isRead &&
        (t.dataBeats != chiGlobalsPkg::datPacketCount(t.size)))
      return 1'b0;
    if (t.expCompAck && !t.compAckSent)
      return 1'b0;
    return 1'b1;
  endfunction

  //--------------------------------------------------------------------------
  // P-credit balance [SPEC:B4.4]
  //--------------------------------------------------------------------------

  function automatic void pcrdCredit(input int unsigned node,
      input chiNodeIdT home, input logic [chiGlobalsPkg::P_CRD_TYPE_W-1:0] pctype);
    int unsigned k;
    k = pcrdKey(node, home, pctype);
    if (!pcrdBal.exists(k))
      pcrdBal[k] = 0;
    pcrdBal[k]++;
  endfunction

  function automatic void pcrdDebit(input int unsigned node,
      input chiNodeIdT home, input logic [chiGlobalsPkg::P_CRD_TYPE_W-1:0] pctype,
      input string what);
    int unsigned k;
    k = pcrdKey(node, home, pctype);
    if (!pcrdBal.exists(k))
      pcrdBal[k] = 0;
    pcrdBal[k]--;
    if (pcrdBal[k] < 0)
      `uvm_error("LIFE/PCRD", $sformatf(
        "node %0d spent a P-credit (type %0d, Home 'h%0h) on %s that was never granted",
        node, pctype, home, what))
  endfunction

  //--------------------------------------------------------------------------
  // Requester-side handlers
  //--------------------------------------------------------------------------

  function automatic void reqTxReq(input int unsigned node,
                                   input chiGlobalsPkg::chiReqFlitT req,
                                   input time now);
    int unsigned key;
    topLifeTxn t;
    if (req.srcId != chiGlobalsPkg::nodeIdOfOrdinal(node))
      `uvm_error("LIFE/SRCID", $sformatf(
        "node %0d sent a REQ with SrcID 'h%0h that is not its own", node, req.srcId))
    if (req.opcode.name().len() == 0)
      `uvm_error("LIFE/OPCODE", $sformatf(
        "node %0d sent a REQ with an undefined opcode encoding", node))
    if (req.opcode == chiGlobalsPkg::REQ_P_CRD_RETURN) begin
      pcrdDebit(node, req.tgtId, req.pCrdType, "PCrdReturn");
      return;
    end
    key = reqKey(node, req.txnId);
    if (reqTxns.exists(key)) begin
      t = reqTxns[key];
      if (t.awaitingReissue && !req.allowRetry) begin
        // The legal reissue after a RetryAck: same TxnID, AllowRetry=0, and
        // it spends the P-credit the RetryAck's Home granted.
        t.awaitingReissue = 1'b0;
        pcrdDebit(node, t.retryHome, t.retryPcrdType, "a retried reissue");
        return;
      end
      if (txnComplete(t)) begin
        reqCompleted++;
        reqTxns.delete(key);
      end
      else begin
        `uvm_error("LIFE/TXNID", $sformatf(
          "node %0d reused TxnID 'h%0h (opcode %s) while the previous %s was still open",
          node, req.txnId, req.opcode.name(), t.opcode.name()))
        return;
      end
    end
    t = new();
    t.opcode = req.opcode;
    t.addr = req.addr;
    t.size = req.size;
    t.allowRetry = req.allowRetry;
    t.expCompAck = req.expCompAck;
    t.isRead = isReadOpcode(req.opcode);
    t.awaitingReissue = 1'b0;
    t.retryHome = '0;
    t.retryPcrdType = '0;
    t.dbidSeen = 1'b0;
    t.dbId = '0;
    t.compSeen = 1'b0;
    t.dataBeats = 0;
    t.dataIdSeen = '0;
    t.compAckSent = 1'b0;
    t.reqTime = now;
    reqTxns[key] = t;
    reqOpened++;
  endfunction

  function automatic void reqRxRsp(input int unsigned node,
                                   input chiGlobalsPkg::chiRspFlitT rsp);
    int unsigned key;
    topLifeTxn t;
    if (rsp.tgtId != chiGlobalsPkg::nodeIdOfOrdinal(node)) begin
      `uvm_error("LIFE/TGTID", $sformatf(
        "node %0d received a RSP (%s) addressed to 'h%0h: misdelivered",
        node, rsp.opcode.name(), rsp.tgtId))
      return;
    end
    if (rsp.opcode.name().len() == 0) begin
      `uvm_error("LIFE/OPCODE", $sformatf(
        "node %0d received a RSP with an undefined opcode encoding", node))
      return;
    end
    if (!chiGlobalsPkg::isConfiguredNodeId(rsp.srcId) ||
        (rsp.srcId == chiGlobalsPkg::nodeIdOfOrdinal(node)))
      `uvm_error("LIFE/SRCID", $sformatf(
        "node %0d received a RSP from unconfigured or own SrcID 'h%0h",
        node, rsp.srcId))
    if (rsp.opcode == chiGlobalsPkg::RSP_P_CRD_GRANT) begin
      pcrdCredit(node, rsp.srcId, rsp.pCrdType);
      return;
    end
    key = reqKey(node, rsp.txnId);
    if (!reqTxns.exists(key)) begin
      `uvm_error("LIFE/UNSOLICITED", $sformatf(
        "node %0d received %s for TxnID 'h%0h with no open request",
        node, rsp.opcode.name(), rsp.txnId))
      return;
    end
    t = reqTxns[key];
    case (rsp.opcode)
      chiGlobalsPkg::RSP_RETRY_ACK: begin
        if (!t.allowRetry)
          `uvm_error("LIFE/RETRY", $sformatf(
            "node %0d TxnID 'h%0h got RetryAck for an AllowRetry=0 request",
            node, rsp.txnId))
        if (t.awaitingReissue)
          `uvm_error("LIFE/RETRY", $sformatf(
            "node %0d TxnID 'h%0h got a second RetryAck", node, rsp.txnId))
        if (t.compSeen || t.dbidSeen)
          `uvm_error("LIFE/RETRY", $sformatf(
            "node %0d TxnID 'h%0h got RetryAck after its completion began",
            node, rsp.txnId))
        t.awaitingReissue = 1'b1;
        t.retryHome = rsp.srcId;
        t.retryPcrdType = rsp.pCrdType;
      end
      chiGlobalsPkg::RSP_DBID_RESP, chiGlobalsPkg::RSP_DBID_RESP_ORD: begin
        if (t.dbidSeen)
          `uvm_error("LIFE/DBID", $sformatf(
            "node %0d TxnID 'h%0h got a duplicate DBIDResp", node, rsp.txnId))
        t.dbidSeen = 1'b1;
        t.dbId = rsp.dbId;
        dbidToTxn[homeDbidKey(node, rsp.srcId, rsp.dbId)] = key;
      end
      chiGlobalsPkg::RSP_COMP_DBID_RESP: begin
        if (t.dbidSeen || t.compSeen)
          `uvm_error("LIFE/DBID", $sformatf(
            "node %0d TxnID 'h%0h got a duplicate CompDBIDResp", node, rsp.txnId))
        t.dbidSeen = 1'b1;
        t.dbId = rsp.dbId;
        t.compSeen = 1'b1;
        dbidToTxn[homeDbidKey(node, rsp.srcId, rsp.dbId)] = key;
      end
      chiGlobalsPkg::RSP_COMP, chiGlobalsPkg::RSP_COMP_CMO,
      chiGlobalsPkg::RSP_COMP_PERSIST, chiGlobalsPkg::RSP_PERSIST,
      chiGlobalsPkg::RSP_STASH_DONE, chiGlobalsPkg::RSP_COMP_STASH_DONE,
      chiGlobalsPkg::RSP_RESP_SEP_DATA: begin
        if (t.compSeen)
          `uvm_error("LIFE/COMP", $sformatf(
            "node %0d TxnID 'h%0h got a duplicate completion (%s)",
            node, rsp.txnId, rsp.opcode.name()))
        t.compSeen = 1'b1;
        if (rsp.opcode == chiGlobalsPkg::RSP_RESP_SEP_DATA) begin
          t.dbidSeen = 1'b1;
          t.dbId = rsp.dbId;
          dbidToTxn[homeDbidKey(node, rsp.srcId, rsp.dbId)] = key;
        end
      end
      chiGlobalsPkg::RSP_READ_RECEIPT: begin
        // An ordering acknowledgement; always tolerable, tracks nothing.
      end
      default:
        `uvm_error("LIFE/RSP", $sformatf(
          "node %0d received %s, which never belongs on a requester's RX RSP",
          node, rsp.opcode.name()))
    endcase
  endfunction

  function automatic void reqRxDat(input int unsigned node,
                                   input chiGlobalsPkg::chiDatFlitT dat);
    int unsigned key;
    topLifeTxn t;
    if (dat.tgtId != chiGlobalsPkg::nodeIdOfOrdinal(node)) begin
      `uvm_error("LIFE/TGTID", $sformatf(
        "node %0d received a DAT (%s) addressed to 'h%0h: misdelivered",
        node, dat.opcode.name(), dat.tgtId))
      return;
    end
    if (dat.opcode.name().len() == 0) begin
      `uvm_error("LIFE/OPCODE", $sformatf(
        "node %0d received a DAT with an undefined opcode encoding", node))
      return;
    end
    if (!chiGlobalsPkg::isConfiguredNodeId(dat.srcId) ||
        (dat.srcId == chiGlobalsPkg::nodeIdOfOrdinal(node)))
      `uvm_error("LIFE/SRCID", $sformatf(
        "node %0d received a DAT from unconfigured or own SrcID 'h%0h",
        node, dat.srcId))
    if ((dat.opcode != chiGlobalsPkg::DAT_COMP_DATA) &&
        (dat.opcode != chiGlobalsPkg::DAT_DATA_SEP_RESP)) begin
      `uvm_error("LIFE/DAT", $sformatf(
        "node %0d received %s, which never belongs on a requester's RX DAT",
        node, dat.opcode.name()))
      return;
    end
    key = reqKey(node, dat.txnId);
    if (!reqTxns.exists(key)) begin
      `uvm_error("LIFE/UNSOLICITED", $sformatf(
        "node %0d received %s for TxnID 'h%0h with no open request",
        node, dat.opcode.name(), dat.txnId))
      return;
    end
    t = reqTxns[key];
    if (dat.opcode == chiGlobalsPkg::DAT_COMP_DATA && !t.compSeen) begin
      // CompData is the completion and the data in one; only the first beat
      // carries the completion.
      t.compSeen = 1'b1;
      t.dbidSeen = 1'b1;
      t.dbId = dat.dbId;
      dbidToTxn[homeDbidKey(node, dat.srcId, dat.dbId)] = key;
    end
    if (t.dataIdSeen[dat.dataId])
      `uvm_error("LIFE/DATAID", $sformatf(
        "node %0d TxnID 'h%0h repeated DataID %0d", node, dat.txnId, dat.dataId))
    t.dataIdSeen[dat.dataId] = 1'b1;
    t.dataBeats++;
    if (t.dataBeats > chiGlobalsPkg::datPacketCount(t.size))
      `uvm_error("LIFE/BEATS", $sformatf(
        "node %0d TxnID 'h%0h got more than %0d data beats",
        node, dat.txnId, chiGlobalsPkg::datPacketCount(t.size)))
  endfunction

  function automatic void reqTxRsp(input int unsigned node,
                                   input chiGlobalsPkg::chiRspFlitT rsp);
    longint unsigned dkey;
    if (rsp.srcId != chiGlobalsPkg::nodeIdOfOrdinal(node))
      `uvm_error("LIFE/SRCID", $sformatf(
        "node %0d sent a RSP with SrcID 'h%0h that is not its own", node, rsp.srcId))
    if (rsp.opcode.name().len() == 0) begin
      `uvm_error("LIFE/OPCODE", $sformatf(
        "node %0d sent a RSP with an undefined opcode encoding", node))
      return;
    end
    case (rsp.opcode)
      chiGlobalsPkg::RSP_SNP_RESP:
        snoopAnswered(node, rsp.txnId);
      chiGlobalsPkg::RSP_COMP_ACK: begin
        dkey = homeDbidKey(node, rsp.tgtId, rsp.txnId);
        if (!dbidToTxn.exists(dkey))
          `uvm_error("LIFE/COMPACK", $sformatf(
            "node %0d sent CompAck with DBID 'h%0h towards 'h%0h that was never granted",
            node, rsp.txnId, rsp.tgtId))
        else if (reqTxns.exists(dbidToTxn[dkey]))
          reqTxns[dbidToTxn[dkey]].compAckSent = 1'b1;
      end
      default:
        `uvm_error("LIFE/RSP", $sformatf(
          "node %0d sent %s; a requester transmits only SnpResp and CompAck on RSP",
          node, rsp.opcode.name()))
    endcase
  endfunction

  function automatic void reqTxDat(input int unsigned node,
                                   input chiGlobalsPkg::chiDatFlitT dat);
    longint unsigned dkey;
    if (dat.srcId != chiGlobalsPkg::nodeIdOfOrdinal(node))
      `uvm_error("LIFE/SRCID", $sformatf(
        "node %0d sent a DAT with SrcID 'h%0h that is not its own", node, dat.srcId))
    if (dat.opcode.name().len() == 0) begin
      `uvm_error("LIFE/OPCODE", $sformatf(
        "node %0d sent a DAT with an undefined opcode encoding", node))
      return;
    end
    case (dat.opcode)
      chiGlobalsPkg::DAT_COPY_BACK_WR_DATA,
      chiGlobalsPkg::DAT_NON_COPY_BACK_WR_DATA,
      chiGlobalsPkg::DAT_NCB_WR_DATA_COMP_ACK,
      chiGlobalsPkg::DAT_WRITE_DATA_CANCEL: begin
        // Write data spends a DBID the requester was granted; HomeNid names
        // the granter.
        dkey = homeDbidKey(node, dat.homeNid, dat.txnId);
        if (!dbidToTxn.exists(dkey))
          `uvm_error("LIFE/WRCREDIT", $sformatf(
            "node %0d sent %s with DBID 'h%0h towards 'h%0h that was never granted",
            node, dat.opcode.name(), dat.txnId, dat.homeNid))
      end
      chiGlobalsPkg::DAT_SNP_RESP_DATA:
        snoopDataBeat(node, dat.txnId);
      default:
        `uvm_error("LIFE/DAT", $sformatf(
          "node %0d sent %s; a requester transmits only write data and snoop data on DAT",
          node, dat.opcode.name()))
    endcase
  endfunction

  //--------------------------------------------------------------------------
  // Snoop tracking
  //--------------------------------------------------------------------------

  function automatic void reqRxSnp(input int unsigned node,
                                   input chiGlobalsPkg::chiSnpFlitT snp,
                                   input time now);
    int unsigned key;
    topLifeSnoop s;
    if (snp.opcode.name().len() == 0) begin
      `uvm_error("LIFE/OPCODE", $sformatf(
        "node %0d received a SNP with an undefined opcode encoding", node))
      return;
    end
    if (!chiGlobalsPkg::isConfiguredNodeId(snp.srcId) ||
        (snp.srcId == chiGlobalsPkg::nodeIdOfOrdinal(node))) begin
      `uvm_error("LIFE/SRCID", $sformatf(
        "node %0d received a SNP from unconfigured or own SrcID 'h%0h",
        node, snp.srcId))
      return;
    end
    // Snoops are issued only by a Home or the MN, both internal nodes.
    if (chiGlobalsPkg::ordinalOfNodeId(snp.srcId) < chiGlobalsPkg::OFF_HNF)
      `uvm_error("LIFE/SNPSRC", $sformatf(
        "node %0d received a snoop from 'h%0h, which is not a Home or the MN",
        node, snp.srcId))
    key = reqKey(node, snp.txnId);
    if (snops.exists(key)) begin
      s = snops[key];
      if (!s.answered && (s.opcode == chiGlobalsPkg::SNP_DVM_OP) &&
          (snp.opcode == chiGlobalsPkg::SNP_DVM_OP) && (s.parts == 1)) begin
        // The second half of a two-part DVM snoop shares the TxnID
        // [SPEC:B8.2.3.2].
        s.parts = 2;
        return;
      end
      if (s.answered)
        snops.delete(key);   // TxnID legitimately reused after completion
      else begin
        `uvm_error("LIFE/SNPID", $sformatf(
          "node %0d snoop TxnID 'h%0h reused while the previous %s was unanswered",
          node, snp.txnId, s.opcode.name()))
        return;
      end
    end
    s = new();
    s.opcode = snp.opcode;
    s.parts = 1;
    s.answered = 1'b0;
    s.snpTime = now;
    snops[key] = s;
    snopsSeen++;
  endfunction

  function automatic void snoopAnswered(input int unsigned node,
                                        input chiTxnIdT txnId);
    int unsigned key;
    key = reqKey(node, txnId);
    if (!snops.exists(key)) begin
      `uvm_error("LIFE/SNPRESP", $sformatf(
        "node %0d sent SnpResp for TxnID 'h%0h with no matching snoop",
        node, txnId))
      return;
    end
    if (snops[key].answered)
      `uvm_error("LIFE/SNPRESP", $sformatf(
        "node %0d sent a duplicate SnpResp for TxnID 'h%0h", node, txnId))
    snops[key].answered = 1'b1;
  endfunction

  function automatic void snoopDataBeat(input int unsigned node,
                                        input chiTxnIdT txnId);
    int unsigned key;
    key = reqKey(node, txnId);
    if (!snops.exists(key))
      `uvm_error("LIFE/SNPDATA", $sformatf(
        "node %0d sent SnpRespData for TxnID 'h%0h with no matching snoop",
        node, txnId))
    // The data beats follow the SnpResp, so the entry may already read
    // answered; that is the normal order, not an error.
  endfunction

  //--------------------------------------------------------------------------
  // Subordinate-side handlers
  //--------------------------------------------------------------------------

  function automatic void subRxReq(input int unsigned node,
                                   input chiGlobalsPkg::chiReqFlitT req,
                                   input time now);
    longint unsigned skey;
    topLifeServe s;
    if (req.tgtId != chiGlobalsPkg::nodeIdOfOrdinal(node)) begin
      `uvm_error("LIFE/TGTID", $sformatf(
        "subordinate %0d received a REQ (%s) addressed to 'h%0h: misdelivered",
        node, req.opcode.name(), req.tgtId))
      return;
    end
    if (req.opcode.name().len() == 0) begin
      `uvm_error("LIFE/OPCODE", $sformatf(
        "subordinate %0d received a REQ with an undefined opcode encoding", node))
      return;
    end
    if (!chiGlobalsPkg::isConfiguredNodeId(req.srcId) ||
        (req.srcId == chiGlobalsPkg::nodeIdOfOrdinal(node)))
      `uvm_error("LIFE/SRCID", $sformatf(
        "subordinate %0d received a REQ from unconfigured or own SrcID 'h%0h",
        node, req.srcId))
    if (req.opcode == chiGlobalsPkg::REQ_P_CRD_RETURN)
      return;   // a credit return, not a serve
    skey = serveKey(node, req.srcId, req.txnId);
    if (serves.exists(skey)) begin
      s = serves[skey];
      if (s.awaitingReissue && !req.allowRetry) begin
        s.awaitingReissue = 1'b0;
        return;
      end
      if (s.compSeen)
        serves.delete(skey);   // TxnID legitimately reused after completion
      else begin
        `uvm_error("LIFE/SERVEDUP", $sformatf(
          "subordinate %0d saw a duplicate request (SrcID 'h%0h TxnID 'h%0h) with the first still open",
          node, req.srcId, req.txnId))
        return;
      end
    end
    s = new();
    s.opcode = req.opcode;
    s.addr = req.addr;
    s.awaitingReissue = 1'b0;
    s.dbidSeen = 1'b0;
    s.dbId = '0;
    s.compSeen = 1'b0;
    s.reqTime = now;
    serves[skey] = s;
    servesSeen++;
  endfunction

  function automatic void subTxRsp(input int unsigned node,
                                   input chiGlobalsPkg::chiRspFlitT rsp);
    longint unsigned skey;
    topLifeServe s;
    if (rsp.srcId != chiGlobalsPkg::nodeIdOfOrdinal(node))
      `uvm_error("LIFE/SRCID", $sformatf(
        "subordinate %0d sent a RSP with SrcID 'h%0h that is not its own",
        node, rsp.srcId))
    if (rsp.opcode.name().len() == 0) begin
      `uvm_error("LIFE/OPCODE", $sformatf(
        "subordinate %0d sent a RSP with an undefined opcode encoding", node))
      return;
    end
    if (!chiGlobalsPkg::isConfiguredNodeId(rsp.tgtId) ||
        (rsp.tgtId == chiGlobalsPkg::nodeIdOfOrdinal(node)))
      `uvm_error("LIFE/TGTID", $sformatf(
        "subordinate %0d sent a RSP to unconfigured or own TgtID 'h%0h",
        node, rsp.tgtId))
    if (rsp.opcode == chiGlobalsPkg::RSP_P_CRD_GRANT)
      return;   // a credit grant, not serve-scoped
    skey = serveKey(node, rsp.tgtId, rsp.txnId);
    if (!serves.exists(skey)) begin
      `uvm_error("LIFE/SERVE", $sformatf(
        "subordinate %0d sent %s for (TgtID 'h%0h TxnID 'h%0h) with no matching request",
        node, rsp.opcode.name(), rsp.tgtId, rsp.txnId))
      return;
    end
    s = serves[skey];
    case (rsp.opcode)
      chiGlobalsPkg::RSP_RETRY_ACK: begin
        if (s.awaitingReissue)
          `uvm_error("LIFE/RETRY", $sformatf(
            "subordinate %0d retried (TgtID 'h%0h TxnID 'h%0h) twice",
            node, rsp.tgtId, rsp.txnId))
        s.awaitingReissue = 1'b1;
      end
      chiGlobalsPkg::RSP_DBID_RESP, chiGlobalsPkg::RSP_DBID_RESP_ORD: begin
        if (s.dbidSeen)
          `uvm_error("LIFE/DBID", $sformatf(
            "subordinate %0d sent a duplicate DBIDResp for TxnID 'h%0h",
            node, rsp.txnId))
        s.dbidSeen = 1'b1;
        s.dbId = rsp.dbId;
        subDbid[subDbidKey(node, rsp.dbId)] = s;
      end
      chiGlobalsPkg::RSP_COMP_DBID_RESP: begin
        if (s.dbidSeen || s.compSeen)
          `uvm_error("LIFE/DBID", $sformatf(
            "subordinate %0d sent a duplicate CompDBIDResp for TxnID 'h%0h",
            node, rsp.txnId))
        s.dbidSeen = 1'b1;
        s.dbId = rsp.dbId;
        s.compSeen = 1'b1;
        subDbid[subDbidKey(node, rsp.dbId)] = s;
      end
      chiGlobalsPkg::RSP_COMP, chiGlobalsPkg::RSP_COMP_CMO,
      chiGlobalsPkg::RSP_COMP_PERSIST, chiGlobalsPkg::RSP_PERSIST,
      chiGlobalsPkg::RSP_STASH_DONE, chiGlobalsPkg::RSP_COMP_STASH_DONE,
      chiGlobalsPkg::RSP_RESP_SEP_DATA: begin
        if (s.compSeen)
          `uvm_error("LIFE/COMP", $sformatf(
            "subordinate %0d sent a duplicate completion (%s) for TxnID 'h%0h",
            node, rsp.opcode.name(), rsp.txnId))
        s.compSeen = 1'b1;
      end
      chiGlobalsPkg::RSP_READ_RECEIPT: begin
        // Ordering acknowledgement; always tolerable.
      end
      default:
        `uvm_error("LIFE/RSP", $sformatf(
          "subordinate %0d sent %s, which never belongs on a subordinate's TX RSP",
          node, rsp.opcode.name()))
    endcase
  endfunction

  function automatic void subRxRsp(input int unsigned node,
                                   input chiGlobalsPkg::chiRspFlitT rsp);
    if (rsp.tgtId != chiGlobalsPkg::nodeIdOfOrdinal(node)) begin
      `uvm_error("LIFE/TGTID", $sformatf(
        "subordinate %0d received a RSP addressed to 'h%0h: misdelivered",
        node, rsp.tgtId))
      return;
    end
    if (rsp.opcode.name().len() == 0) begin
      `uvm_error("LIFE/OPCODE", $sformatf(
        "subordinate %0d received a RSP with an undefined opcode encoding", node))
      return;
    end
    // Only a CompAck ever arrives here, and it must name a DBID this
    // subordinate granted.
    if (rsp.opcode != chiGlobalsPkg::RSP_COMP_ACK) begin
      `uvm_error("LIFE/RSP", $sformatf(
        "subordinate %0d received %s; only CompAck arrives on a subordinate's RX RSP",
        node, rsp.opcode.name()))
      return;
    end
    if (!subDbid.exists(subDbidKey(node, rsp.txnId)))
      `uvm_error("LIFE/COMPACK", $sformatf(
        "subordinate %0d received CompAck with DBID 'h%0h it never granted",
        node, rsp.txnId))
  endfunction

  function automatic void subRxDat(input int unsigned node,
                                   input chiGlobalsPkg::chiDatFlitT dat);
    if (dat.tgtId != chiGlobalsPkg::nodeIdOfOrdinal(node)) begin
      `uvm_error("LIFE/TGTID", $sformatf(
        "subordinate %0d received a DAT addressed to 'h%0h: misdelivered",
        node, dat.tgtId))
      return;
    end
    if (dat.opcode.name().len() == 0) begin
      `uvm_error("LIFE/OPCODE", $sformatf(
        "subordinate %0d received a DAT with an undefined opcode encoding", node))
      return;
    end
    case (dat.opcode)
      chiGlobalsPkg::DAT_COPY_BACK_WR_DATA,
      chiGlobalsPkg::DAT_NON_COPY_BACK_WR_DATA,
      chiGlobalsPkg::DAT_NCB_WR_DATA_COMP_ACK,
      chiGlobalsPkg::DAT_WRITE_DATA_CANCEL: begin
        if (!subDbid.exists(subDbidKey(node, dat.txnId)))
          `uvm_error("LIFE/WRCREDIT", $sformatf(
            "subordinate %0d received %s with DBID 'h%0h it never granted",
            node, dat.opcode.name(), dat.txnId))
      end
      default:
        `uvm_error("LIFE/DAT", $sformatf(
          "subordinate %0d received %s; only write data arrives on a subordinate's RX DAT",
          node, dat.opcode.name()))
    endcase
  endfunction

  function automatic void subTxDat(input int unsigned node,
                                   input chiGlobalsPkg::chiDatFlitT dat);
    longint unsigned skey;
    if (dat.srcId != chiGlobalsPkg::nodeIdOfOrdinal(node))
      `uvm_error("LIFE/SRCID", $sformatf(
        "subordinate %0d sent a DAT with SrcID 'h%0h that is not its own",
        node, dat.srcId))
    if (dat.opcode.name().len() == 0) begin
      `uvm_error("LIFE/OPCODE", $sformatf(
        "subordinate %0d sent a DAT with an undefined opcode encoding", node))
      return;
    end
    if ((dat.opcode != chiGlobalsPkg::DAT_COMP_DATA) &&
        (dat.opcode != chiGlobalsPkg::DAT_DATA_SEP_RESP)) begin
      `uvm_error("LIFE/DAT", $sformatf(
        "subordinate %0d sent %s; a subordinate transmits only read data on DAT",
        node, dat.opcode.name()))
      return;
    end
    // Read data names the request it answers by (TgtID, TxnID).
    skey = serveKey(node, dat.tgtId, dat.txnId);
    if (!serves.exists(skey))
      `uvm_error("LIFE/SERVE", $sformatf(
        "subordinate %0d sent read data for (TgtID 'h%0h TxnID 'h%0h) with no matching request",
        node, dat.tgtId, dat.txnId))
  endfunction

  //--------------------------------------------------------------------------
  // Dispatch
  //--------------------------------------------------------------------------

  function void noteFlit(input chiGlobalsPkg::chiFlitSampleT sample);
    bit isReq;
    if (!cfg.enableLifecycleChecks)
      return;
    if (sample.lcrdReturn)
      return;
    flitCount++;
    isReq = chiGlobalsPkg::nodeClassIsRequester(sample.nodeClass);
    if (isReq) begin
      case ({sample.channel, sample.direction})
        {chiGlobalsPkg::CHI_CH_REQ, chiGlobalsPkg::CHI_DIR_TX}:
          reqTxReq(sample.nodeOrdinal, chiGlobalsPkg::unpackReq(sample.payload),
                   sample.sampleTime);
        {chiGlobalsPkg::CHI_CH_RSP, chiGlobalsPkg::CHI_DIR_TX}:
          reqTxRsp(sample.nodeOrdinal, chiGlobalsPkg::unpackRsp(sample.payload));
        {chiGlobalsPkg::CHI_CH_DAT, chiGlobalsPkg::CHI_DIR_TX}:
          reqTxDat(sample.nodeOrdinal, chiGlobalsPkg::unpackDat(sample.payload));
        {chiGlobalsPkg::CHI_CH_RSP, chiGlobalsPkg::CHI_DIR_RX}:
          reqRxRsp(sample.nodeOrdinal, chiGlobalsPkg::unpackRsp(sample.payload));
        {chiGlobalsPkg::CHI_CH_DAT, chiGlobalsPkg::CHI_DIR_RX}:
          reqRxDat(sample.nodeOrdinal, chiGlobalsPkg::unpackDat(sample.payload));
        {chiGlobalsPkg::CHI_CH_SNP, chiGlobalsPkg::CHI_DIR_RX}:
          reqRxSnp(sample.nodeOrdinal, chiGlobalsPkg::unpackSnp(sample.payload),
                   sample.sampleTime);
        default:
          `uvm_error("LIFE/CHANNEL", $sformatf(
            "node %0d: a %s flit moved %s, a channel this requester port does not use",
            sample.nodeOrdinal, chiGlobalsPkg::channelName(sample.channel),
            (sample.direction == chiGlobalsPkg::CHI_DIR_TX) ? "TX" : "RX"))
      endcase
    end
    else begin
      case ({sample.channel, sample.direction})
        {chiGlobalsPkg::CHI_CH_REQ, chiGlobalsPkg::CHI_DIR_RX}:
          subRxReq(sample.nodeOrdinal, chiGlobalsPkg::unpackReq(sample.payload),
                   sample.sampleTime);
        {chiGlobalsPkg::CHI_CH_RSP, chiGlobalsPkg::CHI_DIR_RX}:
          subRxRsp(sample.nodeOrdinal, chiGlobalsPkg::unpackRsp(sample.payload));
        {chiGlobalsPkg::CHI_CH_DAT, chiGlobalsPkg::CHI_DIR_RX}:
          subRxDat(sample.nodeOrdinal, chiGlobalsPkg::unpackDat(sample.payload));
        {chiGlobalsPkg::CHI_CH_RSP, chiGlobalsPkg::CHI_DIR_TX}:
          subTxRsp(sample.nodeOrdinal, chiGlobalsPkg::unpackRsp(sample.payload));
        {chiGlobalsPkg::CHI_CH_DAT, chiGlobalsPkg::CHI_DIR_TX}:
          subTxDat(sample.nodeOrdinal, chiGlobalsPkg::unpackDat(sample.payload));
        default:
          `uvm_error("LIFE/CHANNEL", $sformatf(
            "node %0d: a %s flit moved %s, a channel this subordinate port does not use",
            sample.nodeOrdinal, chiGlobalsPkg::channelName(sample.channel),
            (sample.direction == chiGlobalsPkg::CHI_DIR_TX) ? "TX" : "RX"))
      endcase
    end
  endfunction

  //--------------------------------------------------------------------------
  // End-of-test completeness
  //--------------------------------------------------------------------------

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (!cfg.enableLifecycleChecks)
      return;
    foreach (reqTxns[key]) begin
      if (!txnComplete(reqTxns[key])) begin
        topLifeTxn t;
        t = reqTxns[key];
        `uvm_error("LIFE/OPEN", $sformatf(
          "requester transaction left open at end of test: %s TxnID key 'h%0h (comp=%0b beats=%0d/%0d compAck=%0b/%0b retryPending=%0b)",
          t.opcode.name(), key, t.compSeen, t.dataBeats,
          t.isRead ? chiGlobalsPkg::datPacketCount(t.size) : 0,
          t.compAckSent, t.expCompAck, t.awaitingReissue))
      end
      else
        reqCompleted++;
    end
    foreach (serves[key]) begin
      if (!serves[key].compSeen || serves[key].awaitingReissue)
        `uvm_error("LIFE/SERVEOPEN", $sformatf(
          "subordinate serve left open at end of test: %s key 'h%0h (comp=%0b retryPending=%0b)",
          serves[key].opcode.name(), key, serves[key].compSeen,
          serves[key].awaitingReissue))
    end
    foreach (snops[key]) begin
      if (!snops[key].answered)
        `uvm_error("LIFE/SNPOPEN", $sformatf(
          "snoop %s (key 'h%0h) was never answered", snops[key].opcode.name(), key))
    end
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("LIFE/SUMMARY", $sformatf(
      "lifecycle model: %0d flits, %0d requester transactions (%0d completed), %0d serves, %0d snoops",
      flitCount, reqOpened, reqCompleted, servesSeen, snopsSeen), UVM_MEDIUM)
  endfunction

endclass
