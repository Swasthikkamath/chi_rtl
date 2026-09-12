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

  // One SnpDVMOp transaction is carried by two request packets whose Addr
  // fields together hold the payload, with Addr[0] selecting the part
  // (IHI 0050H B8.4.2). The payload bit assignment within a part below is a
  // documented local choice: the extracted specification table was not legible
  // enough to reproduce its exact bit positions.
  localparam int unsigned SNP_ADDR_W = CFG.addrW - 3;
  localparam int unsigned PART_PAYLOAD_W = SNP_ADDR_W - 1;
  localparam int unsigned REQ_PAYLOAD_W = CFG.addrW - 1;

  mn_state_e state;
  chi_req_flit_t incomingReq;
  chi_rsp_flit_t incomingRsp;
  chi_req_flit_t activeReq;
  chi_snp_flit_t dvmSnoop;
  chi_rsp_flit_t completion;
  logic [clog2Min1(NUM_DVM_NODES)-1:0] targetIndex;
  logic requestSupported;
  logic snoopPartTwo;
  chi_dvm_type_e dvmType;
  logic [REQ_PAYLOAD_W-1:0] dvmPayload;
  logic [SNP_ADDR_W-1:0] snoopPartAddr;

  always_comb begin
    // REQ.Addr[3] is unused in a DVMOp request and must be zero, so it is
    // dropped when the payload is reassembled.
    dvmPayload = {activeReq.addr[CFG.addrW-1:4], activeReq.addr[2:0]};
    dvmType = chi_dvm_type_e'(activeReq.addr[2:0]);
    snoopPartAddr = '0;
    snoopPartAddr[0] = snoopPartTwo;
    if (snoopPartTwo)
      snoopPartAddr[SNP_ADDR_W-1:1] =
        PART_PAYLOAD_W'(dvmPayload[REQ_PAYLOAD_W-1:PART_PAYLOAD_W]);
    else
      snoopPartAddr[SNP_ADDR_W-1:1] = dvmPayload[PART_PAYLOAD_W-1:0];
  end

  always_comb begin
    incomingReq = unpackReqFlit(CFG, reqInFlit.payload[CHI_MAX_REQ_FLIT_W-1:0]);
    incomingRsp = unpackRspFlit(CFG, rspInFlit.payload[CHI_MAX_RSP_FLIT_W-1:0]);
    requestSupported = (incomingReq.opcode == REQ_DVM_OP)
                       && (incomingReq.addr[2:0] <= DVM_TYPE_SYNC);

    dvmSnoop = '0;
    dvmSnoop.qos = activeReq.qos;
    dvmSnoop.srcId = MN_NODE_ID;
    dvmSnoop.txnId = activeReq.txnId;
    // SnpDVMOp carries the DVM payload, not a routing identity: FwdNID holds
    // the Range and Num fields, FwdTxnID must be zero, and PAS, RetToSrc, and
    // DoNotGoToSD must all be zero (IHI 0050H B8.3.3).
    dvmSnoop.fwdNidOrPbha = '0;
    dvmSnoop.fwdTxnIdOrStashLpidOrVmidExt = '0;
    dvmSnoop.opcode = SNP_DVM_OP;
    dvmSnoop.addr = (chi_cfg_pkg::CHI_MAX_ADDR_W-3)'(snoopPartAddr);
    dvmSnoop.pas = PAS_SECURE;
    dvmSnoop.doNotGoToSd = 1'b0;
    dvmSnoop.retToSrc = 1'b0;
    snpOutFlit = '0;
    snpOutFlit.channel = CHI_CHANNEL_SNP;
    snpOutFlit.targetNodeId = DVM_NODE_IDS[targetIndex];
    snpOutFlit.payload[CHI_MAX_SNP_FLIT_W-1:0] = packSnpFlit(CFG, dvmSnoop);
    snpOutValid = state == MN_SEND_SNOOP;

    completion = '0;
    completion.qos = activeReq.qos;
    completion.tgtId = activeReq.srcId;
    completion.srcId = MN_NODE_ID;
    completion.txnId = activeReq.txnId;
    completion.opcode = RSP_COMP;
    completion.respErr = ((activeReq.opcode == REQ_DVM_OP)
                          && (dvmType <= DVM_TYPE_SYNC))
                         ? RESP_ERR_OK : RESP_ERR_NDERR;
    rspOutFlit = '0;
    rspOutFlit.channel = CHI_CHANNEL_RSP;
    rspOutFlit.targetNodeId = activeReq.srcId;
    rspOutFlit.payload[CHI_MAX_RSP_FLIT_W-1:0] = packRspFlit(CFG, completion);
    rspOutValid = state == MN_SEND_COMPLETION;

    reqInReady = state == MN_IDLE;
    rspInReady = (state == MN_WAIT_RESPONSE)
                 && (incomingRsp.srcId
                     == DVM_NODE_IDS[targetIndex])
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
      snoopPartTwo <= 1'b0;
    end else begin
      case (state)
        MN_IDLE: begin
          if (reqInValid && reqInReady) begin
            activeReq <= incomingReq;
            targetIndex <= '0;
            snoopPartTwo <= 1'b0;
            if (requestSupported && CFG.dvmEn)
              state <= MN_SEND_SNOOP;
            else
              state <= MN_SEND_COMPLETION;
          end
        end
        MN_SEND_SNOOP:
          if (snpOutValid && snpOutReady) begin
            if (snoopPartTwo) begin
              snoopPartTwo <= 1'b0;
              state <= MN_WAIT_RESPONSE;
            end else begin
              snoopPartTwo <= 1'b1;
            end
          end
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
