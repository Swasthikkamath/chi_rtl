// Coherence reference model.
//
// Rebuilds, from boundary traffic alone, which RN-F holds each line and in
// what state, and checks the invariant the whole protocol exists to
// maintain: a line may be held Unique by one node, or Shared by any number,
// but never both at once and never Unique by two.
// [SPEC:IHI0050H B2.2 Cache state model] [SPEC:IHI0050H B4.8]
//
// Two things feed the holder set, and both are needed. A snoop response
// says what state the snooped node ended in; a CompData says what state the
// requesting node has just taken. A model fed only by snoop responses never
// sees a line acquired by a read that snooped nobody, and so cannot tell
// that a second node later taking it Unique was a violation.
//
// Snoops are keyed by TxnID rather than by address. The response carries
// the snoop's TxnID and no address at all, so keying by address would make
// a node with two snoops outstanding unattributable; keying by TxnID is
// exact. [SPEC:IHI0050H B2.4 Transaction identifier fields]
//
// Only RN-F is tracked. RN-D and RN-I keep no coherent copy, so they cannot
// break the invariant and are absent rather than tracked and ignored.
// [ASSUMPTION:18] See OPEN QUESTIONS Q18.

typedef struct packed {
  logic [31:0] ordinal;
  chiTxnIdT txnId;
} topDirKeyT;

class topSnoopNote;
  chiAddrT addr;
  chiSnpOpcodeE opcode;
  bit answered;

  function new();
    answered = 1'b0;
    addr = '0;
  endfunction
endclass

class topDirLine;
  // Per RN-F ordinal. Absent means Invalid.
  chiCacheStateE held[int unsigned];
  // Nodes snooped since the last completion on this line. Cleared when a
  // node acquires the line, because that closes the round of snooping the
  // acquisition needed.
  bit snooped[int unsigned];

  function new();
  endfunction
endclass

class topDirectoryModel extends uvm_component;
  topSnoopNote snpNote[topDirKeyT];
  topDirLine lines[chiAddrT];

  // Where each outstanding request was aimed, so a completion arriving
  // later can be given an address. The lifecycle model keeps its own table
  // keyed the same way and the two never share it.
  chiAddrT pendingAddr[topDirKeyT];

  int unsigned snoopsSeen;
  int unsigned acquisitionsSeen;
  int unsigned unsnoopedAcquisitions;

  `uvm_component_utils(topDirectoryModel)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    snoopsSeen = 0;
    acquisitionsSeen = 0;
    unsnoopedAcquisitions = 0;
  endfunction

  function topDirKeyT chiDirKey(input int unsigned ordinal, input chiTxnIdT txnId);
    topDirKeyT key;
    key.ordinal = ordinal;
    key.txnId = txnId;
    return key;
  endfunction

  function topDirLine chiLine(input chiAddrT addr);
    chiAddrT line;
    line = lineAlign(addr);
    if (!lines.exists(line))
      lines[line] = new();
    return lines[line];
  endfunction

  //----------------------------------------------------------------------------
  // Resp means different things on a snoop response and on a completion, so
  // the two are decoded separately rather than through one table.
  // [SPEC:IHI0050H B13.10.46 Table B13.35]
  //----------------------------------------------------------------------------

  function bit chiStateIsUnique(input chiCacheStateE state);
    return state inside {CACHE_UC, CACHE_UD, CACHE_UCE};
  endfunction

  function bit chiStateIsShared(input chiCacheStateE state);
    return state inside {CACHE_SC, CACHE_SD};
  endfunction

  function chiCacheStateE chiStateFromSnpResp(input logic [RESP_W-1:0] resp);
    case (resp)
      RESP_I, RESP_I_PD:      return CACHE_I;
      RESP_SC, RESP_SC_PD:    return CACHE_SC;
      RESP_UC_UD, RESP_UC_PD: return CACHE_UC;
      RESP_SD:                return CACHE_SD;
      default:                return CACHE_I;
    endcase
  endfunction

  // On a completion 0b110 is UD_PD and 0b111 is SD_PD; 0b011 to 0b101 are
  // reserved and are treated as Invalid rather than guessed at.
  function chiCacheStateE chiStateFromCompResp(input logic [RESP_W-1:0] resp);
    case (resp)
      RESP_I:     return CACHE_I;
      RESP_SC:    return CACHE_SC;
      RESP_UC_UD: return CACHE_UC;
      RESP_UC_PD: return CACHE_UD;
      RESP_SD_PD: return CACHE_SD;
      default:    return CACHE_I;
    endcase
  endfunction

  //----------------------------------------------------------------------------
  // The invariant
  //----------------------------------------------------------------------------

  function void chiCheckInvariant(input chiAddrT line, input string cause);
    topDirLine st;
    int unsigned uniqueCount;
    int unsigned sharedCount;
    string holders;
    if (!lines.exists(line))
      return;
    st = lines[line];
    uniqueCount = 0;
    sharedCount = 0;
    holders = "";
    foreach (st.held[ord]) begin
      if (chiStateIsUnique(st.held[ord]))
        uniqueCount++;
      else if (chiStateIsShared(st.held[ord]))
        sharedCount++;
      holders = {holders, $sformatf(" %0d:%s", ord, st.held[ord].name())};
    end
    if (uniqueCount > 1)
      `uvm_error("topDirectoryModel",
        $sformatf("line %0h is held Unique by %0d nodes after %s; holders are%s",
                  line, uniqueCount, cause, holders))
    else if ((uniqueCount == 1) && (sharedCount > 0))
      `uvm_error("topDirectoryModel",
        $sformatf("line %0h is held Unique and Shared at once after %s; holders are%s",
                  line, cause, holders))
  endfunction

  //----------------------------------------------------------------------------
  // Snoops
  //----------------------------------------------------------------------------

  function void chiNoteSnp(
    input int unsigned ordinal,
    input chiNodeClassE nodeClass,
    input bit isTx,
    input chiSnpFlitT flit
  );
    topDirKeyT key;
    if (!nodeClassIsRequester(nodeClass) || isTx)
      return;
    // A DVM snoop carries no address and touches no line.
    if ((flit.opcode == SNP_LCRD_RETURN) || (flit.opcode == SNP_DVM_OP))
      return;
    snoopsSeen++;
    key = chiDirKey(ordinal, flit.txnId);
    if (!snpNote.exists(key))
      snpNote[key] = new();
    snpNote[key].addr = flit.addr;
    snpNote[key].opcode = flit.opcode;
    snpNote[key].answered = 1'b0;
    if (nodeClass == RN_F)
      chiLine(flit.addr).snooped[ordinal] = 1'b1;
  endfunction

  function void chiApplyResp(
    input int unsigned ordinal,
    input chiNodeClassE nodeClass,
    input chiTxnIdT txnId,
    input logic [RESP_W-1:0] resp
  );
    topDirKeyT key;
    chiAddrT line;
    chiCacheStateE finalState;
    key = chiDirKey(ordinal, txnId);
    if (!snpNote.exists(key)) begin
      `uvm_error("topDirectoryModel",
        $sformatf("ordinal %0d answered a snoop with TxnID %0h that it was never sent",
                  ordinal, txnId))
      return;
    end
    snpNote[key].answered = 1'b1;
    line = lineAlign(snpNote[key].addr);
    if (nodeClass != RN_F)
      return;
    finalState = chiStateFromSnpResp(resp);
    if (finalState == CACHE_I)
      chiLine(line).held.delete(ordinal);
    else
      chiLine(line).held[ordinal] = finalState;
    chiCheckInvariant(line, $sformatf("a snoop response from ordinal %0d", ordinal));
  endfunction

  function void chiNoteRsp(
    input int unsigned ordinal,
    input chiNodeClassE nodeClass,
    input bit isTx,
    input chiRspFlitT flit
  );
    if (!nodeClassIsRequester(nodeClass) || !isTx)
      return;
    if ((flit.opcode == RSP_SNP_RESP) || (flit.opcode == RSP_SNP_RESP_FWDED))
      chiApplyResp(ordinal, nodeClass, flit.txnId, flit.resp);
  endfunction

  //----------------------------------------------------------------------------
  // Acquisition
  //----------------------------------------------------------------------------

  function void chiNoteReq(
    input int unsigned ordinal,
    input chiNodeClassE nodeClass,
    input bit isTx,
    input chiReqFlitT flit
  );
    if ((nodeClass != RN_F) || !isTx)
      return;
    if (flit.opcode == REQ_LCRD_RETURN)
      return;
    // DVMOp and PrefetchTgt have no cache state transition, and neither
    // carries a usable line address: a DVMOp puts an operation in the
    // address field and a PrefetchTgt is required to send TxnID 0, which is
    // the one TxnID a Requester may reuse while another transaction holds
    // it. Recording either would let a later completion that happens to
    // carry TxnID 0 be attributed to the wrong line.
    // [SPEC:IHI0050H B4.9] [SPEC:IHI0050H B2.4.2] [SPEC:IHI0050H B4.2.6.2]
    if (flit.opcode inside {REQ_DVM_OP, REQ_PREFETCH_TGT, REQ_P_CRD_RETURN})
      return;
    // Giving the line up needs no completion to be believed: the node has
    // said it no longer holds it.
    if (flit.opcode inside {REQ_EVICT, REQ_WRITE_BACK_FULL, REQ_WRITE_BACK_PTL,
                            REQ_WRITE_EVICT_FULL, REQ_WRITE_EVICT_OR_EVICT}) begin
      chiLine(flit.addr).held.delete(ordinal);
      return;
    end
    pendingAddr[chiDirKey(ordinal, flit.txnId)] = flit.addr;
  endfunction

  function void chiNoteDat(
    input int unsigned ordinal,
    input chiNodeClassE nodeClass,
    input bit isTx,
    input chiDatFlitT flit
  );
    if (!nodeClassIsRequester(nodeClass))
      return;
    if (isTx) begin
      if (flit.opcode inside {DAT_SNP_RESP_DATA, DAT_SNP_RESP_DATA_PTL,
                              DAT_SNP_RESP_DATA_FWDED})
        chiApplyResp(ordinal, nodeClass, flit.txnId, flit.resp);
      return;
    end
    if (nodeClass != RN_F)
      return;
    if (!(flit.opcode inside {DAT_COMP_DATA, DAT_DATA_SEP_RESP}))
      return;
    // Resp must be identical in every packet of a transfer, so only the
    // first is acted on. [SPEC:IHI0050H B13.10.46]
    if (flit.dataId != '0)
      return;
    chiAcquire(ordinal, flit.txnId, chiStateFromCompResp(flit.resp), "CompData");
  endfunction

  function void chiAcquire(
    input int unsigned ordinal,
    input chiTxnIdT txnId,
    input chiCacheStateE state,
    input string cause
  );
    topDirKeyT key;
    chiAddrT line;
    topDirLine st;
    string unsnooped;

    key = chiDirKey(ordinal, txnId);
    if (!pendingAddr.exists(key))
      return;
    line = lineAlign(pendingAddr[key]);
    st = chiLine(line);
    acquisitionsSeen++;

    // Taking a line Unique means every other holder had to be snooped
    // first. Anything still held and never snooped is the interconnect's
    // directory and this model disagreeing about who had the line, which is
    // the whole point of keeping this model.
    if (chiStateIsUnique(state)) begin
      unsnooped = "";
      foreach (st.held[other]) begin
        if (other == ordinal)
          continue;
        if (!st.snooped.exists(other))
          unsnooped = {unsnooped, $sformatf(" %0d", other)};
      end
      if (unsnooped != "") begin
        unsnoopedAcquisitions++;
        `uvm_error("topDirectoryModel",
          $sformatf({"ordinal %0d took line %0h Unique by %s while ordinal(s)%s still ",
                     "held it and were never snooped"}, ordinal, line, cause, unsnooped))
      end
      // Everyone else loses the line whether or not the snoop was seen, so
      // that one disagreement does not cascade into every later check.
      foreach (st.held[other])
        if (other != ordinal)
          st.held.delete(other);
    end

    if (state == CACHE_I)
      st.held.delete(ordinal);
    else
      st.held[ordinal] = state;
    st.snooped.delete();
    pendingAddr.delete(key);
    chiCheckInvariant(line, $sformatf("%s at ordinal %0d", cause, ordinal));
  endfunction

  //----------------------------------------------------------------------------
  // End of test
  //----------------------------------------------------------------------------

  function void chiCheckEnd();
    int unsigned stillHeld;
    stillHeld = 0;
    foreach (snpNote[key]) begin
      if (!snpNote[key].answered)
        `uvm_error("topDirectoryModel",
          $sformatf("ordinal %0d was snooped with TxnID %0h for line %0h and never answered",
                    key.ordinal, key.txnId, lineAlign(snpNote[key].addr)))
    end
    foreach (lines[line]) begin
      chiCheckInvariant(line, "end of test");
      if (lines[line].held.size() > 0)
        stillHeld++;
    end
    `uvm_info("topDirectoryModel",
      $sformatf("%0d snoops, %0d acquisitions, %0d lines still held at end of test",
                snoopsSeen, acquisitionsSeen, stillHeld), UVM_LOW)
  endfunction
endclass
