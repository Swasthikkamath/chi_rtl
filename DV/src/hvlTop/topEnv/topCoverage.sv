// Cross-agent functional coverage.
//
// The per-agent collectors inside the agents see one port each, so they cannot
// tell how many Requesters held a line at once or whether a snoop and a
// writeback to the same line ever overlapped. Those are properties of the
// system rather than of a port, and they are the ones most likely to be
// silently untested, so they are sampled here where every port is visible.
class topCoverage extends uvm_component;

  chiEnvConfig cfg;

  uvm_tlm_analysis_fifo #(chiRequesterTx) requesterFifo [];

  // How each Requester's holding of a line evolves, tracked only well enough
  // to count sharers.
  protected chi_cache_state_e held [chiLineAddrT][int unsigned];

  // Address of each outstanding request, by agent and TxnID. A completion says
  // nothing about which line it completed, so the address has to be remembered
  // from the request that opened the transaction [SPEC:IHI0050H B2.5].
  protected chiAddrT pendingAddr [int unsigned][chiTxnIdT];

  `uvm_component_utils(topCoverage)

  // Sharers of one line at the moment a new holder is added. A fabric that
  // never gets beyond one sharer has never exercised its snoop filter's
  // multiple-sharer handling.
  covergroup sharingCg with function sample(int unsigned sharers,
                                            int unsigned uniqueHolders);
    option.per_instance = 1;
    sharersCp: coverpoint sharers {
      bins none  = {0};
      bins one   = {1};
      bins two   = {2};
      bins three = {3};
      bins many  = {[4:$]};
    }
    uniqueCp: coverpoint uniqueHolders {
      bins none = {0};
      bins one  = {1};
      // More than one is a coherence failure, which the scoreboard reports.
      // The bin exists so that if it is ever hit, coverage says so too.
      bins illegal = {[2:$]};
    }
    sharersXunique: cross sharersCp, uniqueCp;
  endgroup

  // Which Requester classes generated traffic. With a configurable class mix
  // this is what shows whether a class was present but idle.
  covergroup classActivityCg with function sample(chi_node_class_e nodeClass,
                                                  chi_req_opcode_e opcode);
    option.per_instance = 1;
    classCp: coverpoint nodeClass {
      bins rnf = {NODE_RNF};
      bins rnd = {NODE_RND};
      bins rni = {NODE_RNI};
      ignore_bins other = {NODE_SNF, NODE_SNI, NODE_HNF, NODE_HNI, NODE_MN};
    }
    kindCp: coverpoint opcode {
      bins read  = {REQ_READ_SHARED, REQ_READ_UNIQUE, REQ_READ_ONCE,
                    REQ_READ_CLEAN, REQ_READ_NOT_SHARED_DIRTY};
      bins write = {REQ_WRITE_BACK_FULL, REQ_WRITE_UNIQUE_FULL,
                    REQ_WRITE_NO_SNP_FULL};
      bins upgrade = {REQ_CLEAN_UNIQUE, REQ_MAKE_UNIQUE};
      bins evict   = {REQ_EVICT};
      bins other   = default;
    }
    classXkind: cross classCp, kindCp;
  endgroup

  // The retry handshake end to end: a refusal, then a credit, then a credited
  // re-send [SPEC:IHI0050H B2.10].
  covergroup retryCg with function sample(bit sawRetryAck, bit sawGrant,
                                          bit creditedResend);
    option.per_instance = 1;
    retryAckCp: coverpoint sawRetryAck;
    grantCp:    coverpoint sawGrant;
    resendCp:   coverpoint creditedResend;
    fullHandshake: cross retryAckCp, grantCp, resendCp;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    sharingCg       = new();
    classActivityCg = new();
    retryCg         = new();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(chiEnvConfig)::get(this, "", "chiEnvConfig", cfg))
      `uvm_fatal(get_type_name(), "no chiEnvConfig")
    requesterFifo = new[cfg.numRequesterAgents];
    foreach (requesterFifo[i])
      requesterFifo[i] = new($sformatf("topRequesterFifo_%0d", i), this);
  endfunction

  task run_phase(uvm_phase phase);
    foreach (requesterFifo[i])
      fork
        automatic int unsigned k = i;
        agentLoop(k);
      join_none
    wait fork;
  endtask

  protected bit anyRetryAck;
  protected bit anyGrant;
  protected bit anyCreditedResend;

  protected task agentLoop(int unsigned agentId);
    chiRequesterTx tx;
    forever begin
      requesterFifo[agentId].get(tx);
      if (tx.txKind == CHI_TX_LINK_EVENT) continue;

      case (tx.channel)
        CHI_CHANNEL_REQ: begin
          if (tx.direction != CHI_DIR_TX) continue;
          pendingAddr[agentId][tx.reqFlit.txnId] = tx.addr;
          classActivityCg.sample(tx.nodeClass, tx.reqFlit.opcode);
          if (!tx.reqFlit.allowRetry) begin
            anyCreditedResend = 1'b1;
            retryCg.sample(anyRetryAck, anyGrant, anyCreditedResend);
          end
        end

        CHI_CHANNEL_RSP: begin
          if (tx.direction != CHI_DIR_RX) continue;
          if (tx.rspFlit.opcode == RSP_RETRY_ACK) begin
            anyRetryAck = 1'b1;
            retryCg.sample(anyRetryAck, anyGrant, anyCreditedResend);
          end
          if (tx.rspFlit.opcode == RSP_PCRD_GRANT) begin
            anyGrant = 1'b1;
            retryCg.sample(anyRetryAck, anyGrant, anyCreditedResend);
          end
          // A completion changes what this Requester holds, which changes the
          // sharer count for the line.
          if ((tx.rspFlit.opcode == RSP_COMP)
              || (tx.rspFlit.opcode == RSP_COMP_DBID_RESP))
            sampleSharing(agentId, tx.rspFlit.txnId, tx.rspFlit.resp);
        end

        CHI_CHANNEL_DAT: begin
          if ((tx.direction == CHI_DIR_RX)
              && (tx.datFlit.opcode == DAT_COMP_DATA))
            sampleSharing(agentId, tx.datFlit.txnId, tx.datFlit.resp);
        end

        default: ;
      endcase
    end
  endtask

  protected function void sampleSharing(int unsigned agentId, chiTxnIdT txnId,
                                        chi_resp_e resp);
    chiLineAddrT line;
    int unsigned sharers;
    int unsigned uniqueHolders;

    // A response whose request was never seen cannot be attributed to a line.
    // That happens for the first completions of a passive agent and is the
    // scoreboard's business to report, not this collector's.
    if (!pendingAddr.exists(agentId)) return;
    if (!pendingAddr[agentId].exists(txnId)) return;

    line = lineAddrOf(pendingAddr[agentId][txnId]);
    case (resp[1:0])
      2'b00:   held[line][agentId] = CACHE_I;
      2'b01:   held[line][agentId] = CACHE_SC;
      2'b10:   held[line][agentId] = CACHE_UC;
      default: held[line][agentId] = CACHE_SD;
    endcase

    sharers       = 0;
    uniqueHolders = 0;
    foreach (held[line][agent]) begin
      if (held[line][agent] == CACHE_I) continue;
      sharers++;
      if ((held[line][agent] == CACHE_UC) || (held[line][agent] == CACHE_UD))
        uniqueHolders++;
    end
    sharingCg.sample(sharers, uniqueHolders);
  endfunction
endclass
