module chi_mn_dvm #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter logic [chi_cfg_pkg::CHI_MAX_NODEID_W-1:0] MN_NODE_ID = '0,
  parameter int unsigned NUM_DVM_NODES =
    ((CFG.numRnf + CFG.numRnd + CFG.numRni) > 0)
      ? (CFG.numRnf + CFG.numRnd + CFG.numRni) : 1,
  parameter logic [chi_cfg_pkg::CHI_MAX_NODEID_W-1:0]
    DVM_NODE_IDS [NUM_DVM_NODES-1:0] = '{default:'0}
) (
  input  logic clk,
  input  logic resetn,
  input  logic reqInValid,
  output logic reqInReady,
  input  chi_pkg::chi_noc_flit_t reqInFlit,
  input  logic rspInValid,
  output logic rspInReady,
  input  chi_pkg::chi_noc_flit_t rspInFlit,
  output logic snpOutValid,
  input  logic snpOutReady,
  output chi_pkg::chi_noc_flit_t snpOutFlit,
  output logic rspOutValid,
  input  logic rspOutReady,
  output chi_pkg::chi_noc_flit_t rspOutFlit,
  output logic idle
);
  import chi_pkg::*;

  typedef enum logic [2:0] {
    MN_IDLE, MN_SEND_SNOOP, MN_WAIT_RESPONSE, MN_SEND_COMPLETION
  } mn_state_e;

  mn_state_e state;
  chi_req_flit_t incomingReq;
  chi_rsp_flit_t incomingRsp;
  chi_req_flit_t activeReq;
  chi_snp_flit_t dvmSnoop;
  chi_rsp_flit_t completion;
  logic [clog2Min1(NUM_DVM_NODES)-1:0] targetIndex;
  logic requestSupported;

  always_comb begin
    incomingReq = unpackReqFlit(CFG, reqInFlit.payload[CHI_MAX_REQ_FLIT_W-1:0]);
    incomingRsp = unpackRspFlit(CFG, rspInFlit.payload[CHI_MAX_RSP_FLIT_W-1:0]);
    requestSupported = incomingReq.opcode == REQ_DVM_OP;

    dvmSnoop = '0;
    dvmSnoop.qos = activeReq.qos;
    dvmSnoop.srcId = MN_NODE_ID[CFG.nodeIdW-1:0];
    dvmSnoop.txnId = activeReq.txnId;
    dvmSnoop.fwdNidOrPbha = activeReq.srcId;
    dvmSnoop.fwdTxnIdOrStashLpidOrVmidExt = activeReq.txnId;
    dvmSnoop.opcode = SNP_DVM_OP;
    dvmSnoop.addr = '0;
    dvmSnoop.addr[CFG.addrW-4:0] = activeReq.addr[CFG.addrW-1:3];
    dvmSnoop.ns = activeReq.ns;
    dvmSnoop.nse = activeReq.nse;
    dvmSnoop.retToSrc = 1'b1;
    snpOutFlit = '0;
    snpOutFlit.channel = CHI_CHANNEL_SNP;
    snpOutFlit.targetNodeId = DVM_NODE_IDS[targetIndex];
    snpOutFlit.payload[CHI_MAX_SNP_FLIT_W-1:0] = packSnpFlit(CFG, dvmSnoop);
    snpOutValid = state == MN_SEND_SNOOP;

    completion = '0;
    completion.qos = activeReq.qos;
    completion.tgtId = activeReq.srcId;
    completion.srcId = MN_NODE_ID[CFG.nodeIdW-1:0];
    completion.txnId = activeReq.txnId;
    completion.opcode = RSP_COMP;
    completion.respErr = (activeReq.opcode == REQ_DVM_OP)
                         ? RESP_ERR_OK : RESP_ERR_NDERR;
    rspOutFlit = '0;
    rspOutFlit.channel = CHI_CHANNEL_RSP;
    rspOutFlit.targetNodeId = activeReq.srcId;
    rspOutFlit.payload[CHI_MAX_RSP_FLIT_W-1:0] = packRspFlit(CFG, completion);
    rspOutValid = state == MN_SEND_COMPLETION;

    reqInReady = state == MN_IDLE;
    rspInReady = (state == MN_WAIT_RESPONSE)
                 && (incomingRsp.srcId
                     == DVM_NODE_IDS[targetIndex][CFG.nodeIdW-1:0])
                 && (incomingRsp.txnId == activeReq.txnId)
                 && ((incomingRsp.opcode == RSP_SNP_RESP)
                     || (incomingRsp.opcode == RSP_SNP_RESP_FWDED));
    idle = state == MN_IDLE;
  end

  always_ff @(posedge clk) begin
    if (!resetn) begin
      state <= MN_IDLE;
      activeReq <= '0;
      targetIndex <= '0;
    end else begin
      case (state)
        MN_IDLE: begin
          if (reqInValid && reqInReady) begin
            activeReq <= incomingReq;
            targetIndex <= '0;
            if (requestSupported && CFG.dvmEn)
              state <= MN_SEND_SNOOP;
            else
              state <= MN_SEND_COMPLETION;
          end
        end
        MN_SEND_SNOOP:
          if (snpOutValid && snpOutReady)
            state <= MN_WAIT_RESPONSE;
        MN_WAIT_RESPONSE: begin
          if (rspInValid && rspInReady) begin
            if (targetIndex
                == clog2Min1(NUM_DVM_NODES)'(NUM_DVM_NODES - 1))
              state <= MN_SEND_COMPLETION;
            else begin
              targetIndex <= targetIndex + 1'b1;
              state <= MN_SEND_SNOOP;
            end
          end
        end
        MN_SEND_COMPLETION:
          if (rspOutValid && rspOutReady)
            state <= MN_IDLE;
        default: state <= MN_IDLE;
      endcase
    end
  end
endmodule
