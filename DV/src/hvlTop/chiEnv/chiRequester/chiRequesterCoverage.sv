// Functional coverage for one Requester port.
//
// Subscribes to the same analysis port the scoreboard uses; no extra port is
// needed because txKind already says whether an item is a flit or a link
// event.
//
// The groups are chosen around the things that can be silently untested. The
// retry path is the clearest example: a run can pass every check and never
// have provoked a RetryAck, and without a cover point on it there is nothing
// to say so. The same goes for the less common cache transitions, which only
// happen when two Requesters contend for one line.
class chiRequesterCoverage extends uvm_subscriber #(chiRequesterTx);

  chiRequesterAgentConfig cfg;

  `uvm_component_utils(chiRequesterCoverage)

  // Requests this Requester issues, crossed with its class, because which
  // opcodes are legal depends on the class: an I/O coherent master may not
  // issue ReadShared and a fully coherent one is the only source of WriteBack
  // [SPEC:IHI0050H B2.3.1].
  covergroup requestCg with function sample(chi_req_opcode_e opcode,
                                            chi_node_class_e nodeClass,
                                            bit allowRetry,
                                            logic [2:0] size);
    option.per_instance = 1;
    opcodeCp: coverpoint opcode {
      bins readShared      = {REQ_READ_SHARED};
      bins readUnique      = {REQ_READ_UNIQUE};
      bins readOnce        = {REQ_READ_ONCE};
      bins readNoSnp       = {REQ_READ_NO_SNP};
      bins cleanUnique     = {REQ_CLEAN_UNIQUE};
      bins evict           = {REQ_EVICT};
      bins writeBackFull   = {REQ_WRITE_BACK_FULL};
      bins writeUniqueFull = {REQ_WRITE_UNIQUE_FULL};
      bins writeNoSnpFull  = {REQ_WRITE_NO_SNP_FULL};
      bins other           = default;
    }
    classCp: coverpoint nodeClass {
      bins rnf = {NODE_RNF};
      bins rnd = {NODE_RND};
      bins rni = {NODE_RNI};
      ignore_bins notRequester = {NODE_SNF, NODE_SNI, NODE_HNF, NODE_HNI,
                                  NODE_MN};
    }
    // A credited re-send carries AllowRetry clear, so this separates a first
    // attempt from a retried one [SPEC:IHI0050H B2.10.1].
    retryCp:  coverpoint allowRetry;
    sizeCp:   coverpoint size {
      bins line = {3'd6};
      bins other = default;
    }
    opcodeXclass: cross opcodeCp, classCp;
    opcodeXretry: cross opcodeCp, retryCp;
  endgroup

  // Responses arriving back, including the two that only appear on the retry
  // path.
  covergroup responseCg with function sample(chi_rsp_opcode_e opcode,
                                             chi_resp_e resp,
                                             chi_resp_err_e respErr);
    option.per_instance = 1;
    opcodeCp: coverpoint opcode {
      bins comp         = {RSP_COMP};
      bins compDbid     = {RSP_COMP_DBID_RESP};
      bins dbid         = {RSP_DBID_RESP};
      bins retryAck     = {RSP_RETRY_ACK};
      bins pCrdGrant    = {RSP_PCRD_GRANT};
      bins readReceipt  = {RSP_READ_RECEIPT};
      bins compAck      = {RSP_COMP_ACK};
      bins snpResp      = {RSP_SNP_RESP};
      bins other        = default;
    }
    // Resp[2] is PassDirty and Resp[1:0] the state, so these bins are the
    // states a completion can grant [SPEC:IHI0050H B13.10.34].
    respCp: coverpoint resp {
      bins invalid   = {RESP_I};
      bins shared    = {RESP_SC};
      bins unique_   = {RESP_UC_UD};
      bins sharedD   = {RESP_SD};
      bins passDirty = {RESP_I_PD, RESP_SC_PD, RESP_UD_PD, RESP_SD_PD};
    }
    errCp: coverpoint respErr {
      bins ok    = {RESP_ERR_OK};
      bins exok  = {RESP_ERR_EXOK};
      bins derr  = {RESP_ERR_DERR};
      bins nderr = {RESP_ERR_NDERR};
    }
    opcodeXresp: cross opcodeCp, respCp;
  endgroup

  // Snoops received and what they ask for. Only a fully coherent Requester
  // ever samples this.
  covergroup snoopCg with function sample(chi_snp_opcode_e opcode,
                                          bit retToSrc,
                                          bit doNotGoToSd);
    option.per_instance = 1;
    opcodeCp: coverpoint opcode {
      bins shared         = {SNP_SHARED};
      bins clean          = {SNP_CLEAN};
      bins once           = {SNP_ONCE};
      bins unique_        = {SNP_UNIQUE};
      bins cleanInvalid   = {SNP_CLEAN_INVALID};
      bins makeInvalid    = {SNP_MAKE_INVALID};
      bins notSharedDirty = {SNP_NOT_SHARED_DIRTY};
      bins other          = default;
    }
    // RetToSrc asks for the data even from a clean line, which is a distinct
    // behaviour from the same snoop without it [SPEC:IHI0050H B2.13.3].
    retToSrcCp:    coverpoint retToSrc;
    doNotGoToSdCp: coverpoint doNotGoToSd;
    opcodeXretToSrc: cross opcodeCp, retToSrcCp;
  endgroup

  // Link bring-up, per channel and direction. A channel that never leaves STOP
  // shows up here as a hole rather than as a passing idle test.
  covergroup linkCg with function sample(chiLinkEventKindE kind,
                                         chiDirectionE direction,
                                         chi_channel_e channel,
                                         chiLinkStateE state);
    option.per_instance = 1;
    kindCp:      coverpoint kind;
    directionCp: coverpoint direction;
    channelCp:   coverpoint channel;
    stateCp:     coverpoint state {
      bins stop       = {CHI_LINK_STOP};
      bins activate   = {CHI_LINK_ACTIVATE};
      bins run        = {CHI_LINK_RUN};
      bins deactivate = {CHI_LINK_DEACTIVATE};
    }
    stateXdirection: cross stateCp, directionCp;
  endgroup

  // Data movement. DataID placement is worth covering because a line is
  // carried in more than one packet whenever the data bus is narrower than the
  // line [SPEC:IHI0050H B2.9.4].
  covergroup dataCg with function sample(chi_dat_opcode_e opcode,
                                         logic [1:0] dataId,
                                         chiDirectionE direction);
    option.per_instance = 1;
    opcodeCp: coverpoint opcode {
      bins compData      = {DAT_COMP_DATA};
      bins copyBack      = {DAT_COPY_BACK_WR_DATA};
      bins nonCopyBack   = {DAT_NON_COPY_BACK_WR_DATA};
      bins snpRespData   = {DAT_SNP_RESP_DATA};
      bins other         = default;
    }
    dataIdCp:    coverpoint dataId;
    directionCp: coverpoint direction;
    opcodeXdataId: cross opcodeCp, dataIdCp;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    requestCg  = new();
    responseCg = new();
    snoopCg    = new();
    linkCg     = new();
    dataCg     = new();
  endfunction

  function void write(chiRequesterTx t);
    if (t.txKind == CHI_TX_LINK_EVENT) begin
      linkCg.sample(t.linkEvent.kind, t.linkEvent.direction,
                    t.linkEvent.channel, t.linkEvent.state);
      return;
    end

    case (t.channel)
      CHI_CHANNEL_REQ:
        requestCg.sample(t.reqFlit.opcode, t.nodeClass, t.reqFlit.allowRetry,
                         t.reqFlit.size);
      CHI_CHANNEL_RSP:
        responseCg.sample(t.rspFlit.opcode, t.rspFlit.resp, t.rspFlit.respErr);
      CHI_CHANNEL_SNP:
        snoopCg.sample(t.snpFlit.opcode, t.snpFlit.retToSrc,
                       t.snpFlit.doNotGoToSd);
      default:
        dataCg.sample(t.datFlit.opcode, t.datFlit.dataId, t.direction);
    endcase
  endfunction
endclass
