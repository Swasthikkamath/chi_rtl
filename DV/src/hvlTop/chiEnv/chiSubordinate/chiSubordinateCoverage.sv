// Functional coverage for one Subordinate port.
//
// What matters at a memory endpoint is which downstream opcodes the fabric
// actually produces. The Home Node forwards the Requester's opcode rather than
// translating it, so this is also the place that shows which Requester-level
// operations reached memory at all.
class chiSubordinateCoverage extends uvm_subscriber #(chiSubordinateTx);

  chiSubordinateAgentConfig cfg;

  `uvm_component_utils(chiSubordinateCoverage)

  covergroup downstreamRequestCg with function sample(
      chi_req_opcode_e opcode, chi_node_class_e nodeClass, logic [2:0] size);
    option.per_instance = 1;
    opcodeCp: coverpoint opcode {
      bins readNoSnp       = {REQ_READ_NO_SNP};
      bins readShared      = {REQ_READ_SHARED};
      bins readUnique      = {REQ_READ_UNIQUE};
      bins readOnce        = {REQ_READ_ONCE};
      bins writeNoSnpFull  = {REQ_WRITE_NO_SNP_FULL};
      bins writeNoSnpPtl   = {REQ_WRITE_NO_SNP_PTL};
      bins writeBackFull   = {REQ_WRITE_BACK_FULL};
      bins writeUniqueFull = {REQ_WRITE_UNIQUE_FULL};
      bins evict           = {REQ_EVICT};
      bins other           = default;
    }
    classCp: coverpoint nodeClass {
      bins snf = {NODE_SNF};
      bins sni = {NODE_SNI};
      ignore_bins notSubordinate = {NODE_RNF, NODE_RND, NODE_RNI, NODE_HNF,
                                    NODE_HNI, NODE_MN};
    }
    sizeCp: coverpoint size {
      bins line  = {3'd6};
      bins other = default;
    }
    opcodeXclass: cross opcodeCp, classCp;
  endgroup

  covergroup responseCg with function sample(chi_rsp_opcode_e opcode,
                                             chi_resp_err_e respErr);
    option.per_instance = 1;
    opcodeCp: coverpoint opcode {
      bins comp     = {RSP_COMP};
      bins compDbid = {RSP_COMP_DBID_RESP};
      bins dbid     = {RSP_DBID_RESP};
      bins other    = default;
    }
    errCp: coverpoint respErr {
      bins ok    = {RESP_ERR_OK};
      bins derr  = {RESP_ERR_DERR};
      bins nderr = {RESP_ERR_NDERR};
      bins exok  = {RESP_ERR_EXOK};
    }
    opcodeXerr: cross opcodeCp, errCp;
  endgroup

  covergroup dataCg with function sample(chi_dat_opcode_e opcode,
                                         logic [1:0] dataId,
                                         chiDirectionE direction);
    option.per_instance = 1;
    opcodeCp: coverpoint opcode {
      bins compData    = {DAT_COMP_DATA};
      bins nonCopyBack = {DAT_NON_COPY_BACK_WR_DATA};
      bins copyBack    = {DAT_COPY_BACK_WR_DATA};
      bins cancel      = {DAT_WRITE_DATA_CANCEL};
      bins other       = default;
    }
    dataIdCp:    coverpoint dataId;
    directionCp: coverpoint direction;
    opcodeXdataId: cross opcodeCp, dataIdCp;
  endgroup

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

  function new(string name, uvm_component parent);
    super.new(name, parent);
    downstreamRequestCg = new();
    responseCg          = new();
    dataCg              = new();
    linkCg              = new();
  endfunction

  function void write(chiSubordinateTx t);
    if (t.txKind == CHI_TX_LINK_EVENT) begin
      linkCg.sample(t.linkEvent.kind, t.linkEvent.direction,
                    t.linkEvent.channel, t.linkEvent.state);
      return;
    end

    case (t.channel)
      CHI_CHANNEL_REQ:
        downstreamRequestCg.sample(t.reqFlit.opcode, t.nodeClass,
                                   t.reqFlit.size);
      CHI_CHANNEL_RSP:
        responseCg.sample(t.rspFlit.opcode, t.rspFlit.respErr);
      CHI_CHANNEL_DAT:
        dataCg.sample(t.datFlit.opcode, t.datFlit.dataId, t.direction);
      default: ;
    endcase
  endfunction
endclass
