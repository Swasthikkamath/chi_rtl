//==============================================================================
// topDirectoryModel
//
// The coherence reference model. The DUT's directory and snoop filter are
// internal, so this model never sees them; what it can see is every grant of
// cache state delivered to an RN-F and every invalidation that RN-F shows at
// its boundary. From those it replays, per cache line, the ownership history
// and checks the one rule coherence may never break: a Unique grant may not
// coexist with any other copy of the line, and a Shared grant may not coexist
// with a Unique or dirty copy [SPEC:B2.4].
//
// The check runs at end of test over a per-line event log, sorted by sample
// time, because the grants and the invalidating snoop responses that justify
// them are observed on different ports and reach this model in arrival order,
// not causal order. Holders are tracked as the log is replayed:
//
//   GRANT(N, S)    - N was observed receiving state S for the line (a
//                    completion, or a snoop response that leaves N holding S).
//                    Every other current holder must not conflict with S.
//   RELEASE(N)     - N was observed giving the line up: a snoop response that
//                    ends in I, an Evict request, the last beat of a
//                    write-back's data, or an invalidating CMO's completion.
//   SNPDATA(N)     - N returned snoop data, which is only legal if N was
//                    granted the line at some earlier point in the log.
//
// A grant to N while another holder M is current and conflicting is reported.
// Because a correct Home invalidates M before granting, M's release is always
// in the log before such a grant; if it is not, either M still holds the line
// (a real coherence violation) or the Home's snoop filter forgot M without a
// back-invalidation (a DUT deviation worth a finding even when M happened to
// have silently evicted, which is the one corner that is not independently
// observable). See the DV plan's coherence section.
//
// Write-backs release at their last data beat, not their request and not
// their completion: the Home may re-grant the line as soon as it holds the
// dirty data, and may not before. Evict releases at the request (it carries
// no data); MakeInvalid/CleanInvalid release at their completion (the Home
// serialises them against other grants of the line).
//
// The model also owns the hard rule that a coherent snoop never targets an
// RN-D or RN-I [Q13]; DVM snoops are exempt and are otherwise left to the
// lifecycle model, since they carry no line state.
//==============================================================================

typedef enum bit [1:0] {
  DIR_EV_RELEASE,
  DIR_EV_GRANT_SNOOP,
  DIR_EV_GRANT_COMP,
  DIR_EV_SNPDATA
} topDirKindE;

class topDirEvent;
  int unsigned   node;
  chiCacheStateE state;
  topDirKindE    kind;
  time           t;
endclass

class topDirLine;
  topDirEvent evs[$];
endclass

// What a requester asked, so an address-less response can be interpreted.
class topDirReq;
  chiReqOpcodeE opcode;
  chiAddrT      line;
  bit           grantRecorded;
endclass

// A write-back in flight: its line, and how many data beats have returned.
class topDirCb;
  chiAddrT     line;
  int unsigned beats;
endclass

// A snoop a requester holds, so its response can be tied back to a line.
class topDirSnp;
  chiAddrT line;
  bit      respRecorded;
  bit      dataRecorded;
endclass

class topDirectoryModel extends uvm_component;

  topEnvConfig cfg;

  topDirReq  reqById[int unsigned];     // node * 2^TXN_ID_W + txnId
  topDirCb   cbById[int unsigned];      // node * 2^TXN_ID_W + dbId
  topDirSnp  snpById[int unsigned];     // node * 2^TXN_ID_W + snoop txnId
  topDirLine lines[chiAddrT];

  int unsigned grantCount;
  int unsigned releaseCount;
  int unsigned conflictCount;

  `uvm_component_utils(topDirectoryModel)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    grantCount = 0;
    releaseCount = 0;
    conflictCount = 0;
  endfunction

  function automatic int unsigned idKey(input int unsigned node,
                                        input chiTxnIdT txnId);
    return node * (32'h1 << chiGlobalsPkg::TXN_ID_W) + int'(txnId);
  endfunction

  function automatic void addEvent(input chiAddrT line,
                                   input int unsigned node,
                                   input chiCacheStateE state,
                                   input topDirKindE kind,
                                   input time t);
    topDirEvent ev;
    if (!lines.exists(line))
      lines[line] = new();
    ev = new();
    ev.node = node;
    ev.state = state;
    ev.kind = kind;
    ev.t = t;
    lines[line].evs.push_back(ev);
    if (kind == DIR_EV_RELEASE)
      releaseCount++;
    else
      grantCount++;
  endfunction

  // The final cache state a snoop response encodes: the testbench drives the
  // response's Resp field as final-state plus pass-dirty, so stripping the
  // dirty bit recovers the state [SPEC:B4.8].
  function automatic chiCacheStateE snoopFinalState(
      input logic [chiGlobalsPkg::RESP_W-1:0] resp);
    case (resp)
      chiGlobalsPkg::RESP_I, chiGlobalsPkg::RESP_I_PD:
        return chiCacheStateE'(chiGlobalsPkg::CACHE_I);
      chiGlobalsPkg::RESP_SC, chiGlobalsPkg::RESP_SC_PD:
        return chiCacheStateE'(chiGlobalsPkg::CACHE_SC);
      chiGlobalsPkg::RESP_UC_UD:
        return chiCacheStateE'(chiGlobalsPkg::CACHE_UC);
      chiGlobalsPkg::RESP_UC_PD:
        return chiCacheStateE'(chiGlobalsPkg::CACHE_UD);
      chiGlobalsPkg::RESP_SD, chiGlobalsPkg::RESP_SD_PD:
        return chiCacheStateE'(chiGlobalsPkg::CACHE_SD);
      default:
        return chiCacheStateE'(chiGlobalsPkg::CACHE_I);
    endcase
  endfunction

  // The state a completion leaves in the requester's cache, mirroring the
  // requester agent's own cache model so that this model's belief tracks what
  // the bench will actually do with the line. Opcodes that never allocate
  // produce no event.
  function automatic void noteCompletion(input int unsigned node,
      input topDirReq req, input logic [chiGlobalsPkg::RESP_W-1:0] resp,
      input time t);
    chiCacheStateE st;
    if (req.grantRecorded)
      return;
    req.grantRecorded = 1'b1;
    if (req.opcode inside {
        chiGlobalsPkg::REQ_READ_ONCE, chiGlobalsPkg::REQ_READ_NO_SNP,
        chiGlobalsPkg::REQ_DVM_OP, chiGlobalsPkg::REQ_PREFETCH_TGT,
        chiGlobalsPkg::REQ_WRITE_UNIQUE_FULL, chiGlobalsPkg::REQ_WRITE_UNIQUE_PTL,
        chiGlobalsPkg::REQ_WRITE_NO_SNP_FULL, chiGlobalsPkg::REQ_WRITE_NO_SNP_PTL,
        chiGlobalsPkg::REQ_WRITE_UNIQUE_ZERO, chiGlobalsPkg::REQ_WRITE_NO_SNP_ZERO})
      return;
    if ((req.opcode == chiGlobalsPkg::REQ_EVICT) ||
        (req.opcode == chiGlobalsPkg::REQ_WRITE_BACK_FULL) ||
        (req.opcode == chiGlobalsPkg::REQ_WRITE_CLEAN_FULL) ||
        (req.opcode == chiGlobalsPkg::REQ_MAKE_UNIQUE))
      st = (req.opcode == chiGlobalsPkg::REQ_MAKE_UNIQUE) ?
        chiCacheStateE'(chiGlobalsPkg::CACHE_UC) : chiCacheStateE'(chiGlobalsPkg::CACHE_I);
    else if ((resp == chiGlobalsPkg::RESP_SC) || (resp == chiGlobalsPkg::RESP_SC_PD))
      st = chiCacheStateE'(chiGlobalsPkg::CACHE_SC);
    else if (resp == chiGlobalsPkg::RESP_UC_UD)
      st = chiCacheStateE'(chiGlobalsPkg::CACHE_UC);
    else if (resp == chiGlobalsPkg::RESP_UC_PD)
      st = chiCacheStateE'(chiGlobalsPkg::CACHE_UD);
    else if ((resp == chiGlobalsPkg::RESP_SD) || (resp == chiGlobalsPkg::RESP_SD_PD))
      st = chiCacheStateE'(chiGlobalsPkg::CACHE_SD);
    else if (req.opcode == chiGlobalsPkg::REQ_CLEAN_UNIQUE)
      st = chiCacheStateE'(chiGlobalsPkg::CACHE_UC);
    else
      st = chiCacheStateE'(chiGlobalsPkg::CACHE_I);
    if (st == chiGlobalsPkg::CACHE_I)
      addEvent(req.line, node, st, DIR_EV_RELEASE, t);
    else
      addEvent(req.line, node, st, DIR_EV_GRANT_COMP, t);
  endfunction

  function automatic bit isCopyBack(input chiReqOpcodeE opcode);
    return (opcode == chiGlobalsPkg::REQ_WRITE_BACK_FULL) ||
           (opcode == chiGlobalsPkg::REQ_WRITE_CLEAN_FULL);
  endfunction

  function automatic void noteFlit(input chiGlobalsPkg::chiFlitSampleT sample);
    int unsigned node;
    if (!cfg.enableDirectoryChecks)
      return;
    if (sample.lcrdReturn)
      return;
    node = sample.nodeOrdinal;

    // A coherent snoop may only ever target an RN-F [Q13]. DVM snoops are
    // broadcast to every requester class and carry no line state, so they
    // are exempt here and handled by the lifecycle model.
    if ((sample.channel == chiGlobalsPkg::CHI_CH_SNP) &&
        (sample.direction == chiGlobalsPkg::CHI_DIR_RX)) begin
      chiGlobalsPkg::chiSnpFlitT snp;
      snp = chiGlobalsPkg::unpackSnp(sample.payload);
      if (sample.nodeClass != chiGlobalsPkg::RN_F) begin
        if (snp.opcode == chiGlobalsPkg::SNP_DVM_OP)
          return;
        `uvm_error("DIR/SNPTARGET", $sformatf(
          "node %0d (%s) received coherent snoop %s; only an RN-F may be snooped",
          node, chiGlobalsPkg::nodeClassName(sample.nodeClass), snp.opcode.name()))
        return;
      end
      if (snp.opcode == chiGlobalsPkg::SNP_DVM_OP)
        return;
      snpById[idKey(node, snp.txnId)] = new();
      snpById[idKey(node, snp.txnId)].line = chiGlobalsPkg::lineAlign(snp.addr);
      snpById[idKey(node, snp.txnId)].respRecorded = 1'b0;
      snpById[idKey(node, snp.txnId)].dataRecorded = 1'b0;
      return;
    end

    // Past this point only RN-F ports carry coherence state.
    if (sample.nodeClass != chiGlobalsPkg::RN_F)
      return;

    if ((sample.channel == chiGlobalsPkg::CHI_CH_REQ) &&
        (sample.direction == chiGlobalsPkg::CHI_DIR_TX)) begin
      chiGlobalsPkg::chiReqFlitT req;
      topDirReq info;
      req = chiGlobalsPkg::unpackReq(sample.payload);
      if (req.opcode == chiGlobalsPkg::REQ_P_CRD_RETURN)
        return;
      info = new();
      info.opcode = req.opcode;
      info.line = chiGlobalsPkg::lineAlign(req.addr);
      info.grantRecorded = 1'b0;
      reqById[idKey(node, req.txnId)] = info;
      // An Evict carries no data, so the line is given up at the request.
      if (req.opcode == chiGlobalsPkg::REQ_EVICT)
        addEvent(info.line, node, chiCacheStateE'(chiGlobalsPkg::CACHE_I),
                 DIR_EV_RELEASE, sample.sampleTime);
      return;
    end

    if ((sample.channel == chiGlobalsPkg::CHI_CH_RSP) &&
        (sample.direction == chiGlobalsPkg::CHI_DIR_RX)) begin
      chiGlobalsPkg::chiRspFlitT rsp;
      topDirReq info;
      rsp = chiGlobalsPkg::unpackRsp(sample.payload);
      if (!reqById.exists(idKey(node, rsp.txnId)))
        return;
      info = reqById[idKey(node, rsp.txnId)];
      case (rsp.opcode)
        chiGlobalsPkg::RSP_DBID_RESP, chiGlobalsPkg::RSP_DBID_RESP_ORD: begin
          if (isCopyBack(info.opcode)) begin
            cbById[idKey(node, rsp.dbId)] = new();
            cbById[idKey(node, rsp.dbId)].line = info.line;
            cbById[idKey(node, rsp.dbId)].beats = 0;
          end
        end
        chiGlobalsPkg::RSP_COMP_DBID_RESP: begin
          if (isCopyBack(info.opcode)) begin
            cbById[idKey(node, rsp.dbId)] = new();
            cbById[idKey(node, rsp.dbId)].line = info.line;
            cbById[idKey(node, rsp.dbId)].beats = 0;
          end
          noteCompletion(node, info, rsp.resp, sample.sampleTime);
        end
        chiGlobalsPkg::RSP_COMP, chiGlobalsPkg::RSP_COMP_CMO,
        chiGlobalsPkg::RSP_COMP_PERSIST, chiGlobalsPkg::RSP_PERSIST,
        chiGlobalsPkg::RSP_STASH_DONE, chiGlobalsPkg::RSP_COMP_STASH_DONE,
        chiGlobalsPkg::RSP_RESP_SEP_DATA:
          noteCompletion(node, info, rsp.resp, sample.sampleTime);
        default: ;
      endcase
      return;
    end

    if ((sample.channel == chiGlobalsPkg::CHI_CH_DAT) &&
        (sample.direction == chiGlobalsPkg::CHI_DIR_RX)) begin
      chiGlobalsPkg::chiDatFlitT dat;
      dat = chiGlobalsPkg::unpackDat(sample.payload);
      if (dat.opcode != chiGlobalsPkg::DAT_COMP_DATA)
        return;
      if (!reqById.exists(idKey(node, dat.txnId)))
        return;
      // CompData is completion and data in one; the first beat records it.
      noteCompletion(node, reqById[idKey(node, dat.txnId)], dat.resp,
                     sample.sampleTime);
      return;
    end

    if ((sample.channel == chiGlobalsPkg::CHI_CH_RSP) &&
        (sample.direction == chiGlobalsPkg::CHI_DIR_TX)) begin
      chiGlobalsPkg::chiRspFlitT rsp;
      topDirSnp snp;
      chiCacheStateE finalState;
      rsp = chiGlobalsPkg::unpackRsp(sample.payload);
      if (rsp.opcode != chiGlobalsPkg::RSP_SNP_RESP)
        return;
      if (!snpById.exists(idKey(node, rsp.txnId)))
        return;
      snp = snpById[idKey(node, rsp.txnId)];
      if (snp.respRecorded)
        return;
      snp.respRecorded = 1'b1;
      finalState = snoopFinalState(rsp.resp);
      if (finalState == chiGlobalsPkg::CACHE_I)
        addEvent(snp.line, node, finalState, DIR_EV_RELEASE, sample.sampleTime);
      else
        addEvent(snp.line, node, finalState, DIR_EV_GRANT_SNOOP, sample.sampleTime);
      return;
    end

    if ((sample.channel == chiGlobalsPkg::CHI_CH_DAT) &&
        (sample.direction == chiGlobalsPkg::CHI_DIR_TX)) begin
      chiGlobalsPkg::chiDatFlitT dat;
      dat = chiGlobalsPkg::unpackDat(sample.payload);
      if (dat.opcode == chiGlobalsPkg::DAT_SNP_RESP_DATA) begin
        topDirSnp snp;
        if (!snpById.exists(idKey(node, dat.txnId)))
          return;
        snp = snpById[idKey(node, dat.txnId)];
        if (snp.dataRecorded)
          return;
        snp.dataRecorded = 1'b1;
        addEvent(snp.line, node, chiCacheStateE'(chiGlobalsPkg::CACHE_I),
                 DIR_EV_SNPDATA, sample.sampleTime);
      end
      else if (dat.opcode == chiGlobalsPkg::DAT_COPY_BACK_WR_DATA) begin
        topDirCb cb;
        if (!cbById.exists(idKey(node, dat.txnId)))
          return;
        cb = cbById[idKey(node, dat.txnId)];
        cb.beats++;
        // A write-back is always a full line; its last beat is when the Home
        // holds the dirty data and may re-grant the line.
        if (cb.beats >= chiGlobalsPkg::datPacketCount(3'(6)))
          addEvent(cb.line, node, chiCacheStateE'(chiGlobalsPkg::CACHE_I),
                   DIR_EV_RELEASE, sample.sampleTime);
      end
      return;
    end
  endfunction

  // Two held states conflict when either is Unique (Unique tolerates no other
  // copy) or both are Shared-Dirty. Shared-clean company is legal.
  function automatic bit statesConflict(input chiCacheStateE a,
                                        input chiCacheStateE b);
    bit aUnique;
    bit bUnique;
    aUnique = (a == chiGlobalsPkg::CACHE_UC) || (a == chiGlobalsPkg::CACHE_UD);
    bUnique = (b == chiGlobalsPkg::CACHE_UC) || (b == chiGlobalsPkg::CACHE_UD);
    if (aUnique || bUnique)
      return 1'b1;
    if ((a == chiGlobalsPkg::CACHE_SD) && (b == chiGlobalsPkg::CACHE_SD))
      return 1'b1;
    return 1'b0;
  endfunction

  function automatic int unsigned kindRank(input topDirKindE kind);
    // At equal sample times a release justifies a grant, and a downgrade
    // (grant from a snoop response) justifies a later acquisition, so they
    // sort in that order. The sort is stable, so equal ranks keep arrival
    // order.
    case (kind)
      DIR_EV_RELEASE:     return 0;
      DIR_EV_GRANT_SNOOP: return 1;
      DIR_EV_GRANT_COMP:  return 2;
      default:            return 3;
    endcase
  endfunction

  function automatic void sortEvents(input topDirLine line);
    // Insertion sort by (time, rank); a line's log is a handful of events.
    for (int i = 1; i < line.evs.size(); i++) begin
      topDirEvent key;
      int j;
      key = line.evs[i];
      j = i - 1;
      while ((j >= 0) &&
             ((line.evs[j].t > key.t) ||
              ((line.evs[j].t == key.t) &&
               (kindRank(line.evs[j].kind) > kindRank(key.kind))))) begin
        line.evs[j + 1] = line.evs[j];
        j--;
      end
      line.evs[j + 1] = key;
    end
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (!cfg.enableDirectoryChecks)
      return;
    foreach (lines[line]) begin
      chiCacheStateE holderSt[int unsigned];
      bit everGranted[int unsigned];
      sortEvents(lines[line]);
      foreach (lines[line].evs[i]) begin
        topDirEvent ev;
        ev = lines[line].evs[i];
        case (ev.kind)
          DIR_EV_RELEASE: begin
            if (holderSt.exists(ev.node))
              holderSt.delete(ev.node);
          end
          DIR_EV_GRANT_SNOOP, DIR_EV_GRANT_COMP: begin
            foreach (holderSt[other]) begin
              if ((other != ev.node) && statesConflict(holderSt[other], ev.state)) begin
                conflictCount++;
                `uvm_error("DIR/COHERENCE", $sformatf(
                  "line 'h%0h: node %0d granted %s at %0t while node %0d holds %s with no invalidation observed in between",
                  line, ev.node, ev.state.name(), ev.t, other,
                  holderSt[other].name()))
              end
            end
            holderSt[ev.node] = ev.state;
            everGranted[ev.node] = 1'b1;
          end
          DIR_EV_SNPDATA: begin
            if (!everGranted.exists(ev.node) || !everGranted[ev.node])
              `uvm_error("DIR/SNPDATA", $sformatf(
                "line 'h%0h: node %0d returned snoop data at %0t but was never granted the line",
                line, ev.node, ev.t))
          end
          default: ;
        endcase
      end
    end
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("DIR/SUMMARY", $sformatf(
      "directory model: %0d lines tracked, %0d grant/snoop-data events, %0d releases, %0d conflicts",
      lines.num(), grantCount, releaseCount, conflictCount), UVM_MEDIUM)
  endfunction

endclass
