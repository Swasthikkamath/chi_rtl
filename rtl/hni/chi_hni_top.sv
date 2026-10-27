module chi_hni_top #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter logic [chi_cfg_pkg::CHI_MAX_NODEID_W-1:0] HN_NODE_ID = '0,
  parameter int unsigned NUM_REGIONS = 4,
  parameter logic [CFG.addrW-1:0] CFG_MMIO_BASE = {CFG.addrW{1'b1}} - 12'hfff,
  parameter logic [CFG.addrW-1:0]
    REGION_BASE [NUM_REGIONS-1:0] = '{default:'0},
  parameter logic [CFG.addrW-1:0]
    REGION_LIMIT [NUM_REGIONS-1:0] = '{default:'0},
  parameter logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0]
    REGION_TARGET [NUM_REGIONS-1:0] = '{default:'0},
  parameter logic [3:0]
    REGION_ATTRIBUTES [NUM_REGIONS-1:0] = '{default:'0}
) (
  input  logic clk,
  input  logic resetn,
  input  logic reqInValid,
  output logic reqInReady,
  input  chi_pkg::chi_noc_flit_t reqInFlit,
  input  logic rspInValid,
  output logic rspInReady,
  input  chi_pkg::chi_noc_flit_t rspInFlit,
  input  logic datInValid,
  output logic datInReady,
  input  chi_pkg::chi_noc_flit_t datInFlit,
  output logic reqOutValid,
  input  logic reqOutReady,
  output chi_pkg::chi_noc_flit_t reqOutFlit,
  output logic rspOutValid,
  input  logic rspOutReady,
  output chi_pkg::chi_noc_flit_t rspOutFlit,
  output logic datOutValid,
  input  logic datOutReady,
  output chi_pkg::chi_noc_flit_t datOutFlit,
  input  logic regionUpdate,
  input  logic [chi_pkg::clog2Min1(NUM_REGIONS)-1:0] regionUpdateIndex,
  input  logic [CFG.addrW-1:0] regionUpdateBase,
  input  logic [CFG.addrW-1:0] regionUpdateLimit,
  input  logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] regionUpdateTarget,
  input  logic [3:0] regionUpdateAttributes,
  output logic mmioRegionUpdate,
  output logic [chi_pkg::clog2Min1(NUM_REGIONS)-1:0] mmioRegionUpdateIndex,
  output logic [CFG.addrW-1:0] mmioRegionUpdateBase,
  output logic [CFG.addrW-1:0] mmioRegionUpdateLimit,
  output logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] mmioRegionUpdateTarget,
  output logic [3:0] mmioRegionUpdateAttributes,
  output logic idle
);
  import chi_cfg_pkg::*;
  import chi_pkg::*;

  typedef enum logic [2:0] {
    HNI_IDLE, HNI_SEND_REQ, HNI_WAIT_SUBORDINATE, HNI_CFG_WAIT_DATA,
    HNI_CFG_RESPONSE
  } hni_state_e;

  hni_state_e state;
  chi_req_flit_t incomingReq;
  chi_rsp_flit_t incomingRsp;
  chi_dat_flit_t incomingDat;
  logic incomingDatLast;
  chi_req_flit_t activeReq;
  chi_req_flit_t forwardedReq;
  chi_rsp_flit_t returnedRsp;
  chi_rsp_flit_t configRsp;
  chi_dat_flit_t forwardedDat;
  chi_dat_flit_t returnedDat;
  chi_dat_flit_t configDat;
  logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] samTarget;
  logic [3:0] samAttributes;
  logic samError;
  logic configAccess;
  logic configRead;
  logic activeConfigRead;
  logic activeDecodeError;
  logic forwardRequesterData;
  logic droppedRequest;
  logic [clog2Min1(NUM_REGIONS)-1:0] selectedRegion;
  logic [CFG.addrW-1:0] stagedBase [NUM_REGIONS-1:0];
  logic [CFG.addrW-1:0] stagedLimit [NUM_REGIONS-1:0];
  logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] stagedTarget [NUM_REGIONS-1:0];
  logic [3:0] stagedAttributes [NUM_REGIONS-1:0];

  function automatic logic isRead(input chi_req_opcode_e opcode);
    return opcode inside {REQ_READ_NO_SNP, REQ_READ_NO_SNP_SEP,
                          REQ_READ_ONCE, REQ_READ_ONCE_CLEAN_INVALID,
                          REQ_READ_ONCE_MAKE_INVALID};
  endfunction

  // The HN-I decode never hashes, but the SAM still takes a hash table. It is
  // passed as a typed one-entry array: an assignment pattern written against
  // the parameter would be sized by the SAM's default NUM_HNF before the
  // override applies, which some tools reject.
  localparam logic [chi_cfg_pkg::CHI_MAX_NODEID_W-1:0]
    HNI_HASH_NODE_IDS [0:0] = '{HN_NODE_ID};

  chi_sam #(
    .CFG(CFG), .NUM_REGIONS(NUM_REGIONS), .HASH_TO_HNF(1'b0),
    .NUM_HNF(1), .HN_NODE_IDS(HNI_HASH_NODE_IDS),
    .REGION_BASE(REGION_BASE), .REGION_LIMIT(REGION_LIMIT),
    .REGION_TARGET(REGION_TARGET), .REGION_ATTRIBUTES(REGION_ATTRIBUTES)
  ) hni_sam (
    .clk, .resetn, .address(incomingReq.addr[CFG.addrW-1:0]),
    .nonSecure(pasNonSecure(incomingReq.pas)), .targetNodeId(samTarget),
    .matchedAttributes(samAttributes), .unmappedError(samError),
    .regionUpdate, .regionUpdateIndex, .regionUpdateBase,
    .regionUpdateLimit, .regionUpdateTarget, .regionUpdateAttributes
  );

  always_comb begin
    incomingReq = unpackReqFlit(CFG, reqInFlit.payload[CHI_MAX_REQ_FLIT_W-1:0]);
    incomingRsp = unpackRspFlit(CFG, rspInFlit.payload[CHI_MAX_RSP_FLIT_W-1:0]);
    incomingDat = unpackDatFlit(CFG, datInFlit.payload[CHI_MAX_DAT_FLIT_W-1:0]);
    // A data message occupies as many DAT packets as the data bus needs to
    // carry Size bytes, so the end of the message is a function of the
    // transaction and not of the packet alone (IHI 0050H B2.4.6).
    incomingDatLast = datLastPacket(CFG, incomingDat.dataId, incomingDat.numDat,
                                    activeReq.addr, activeReq.size);
    configAccess = (CFG.cfgAccess == CFG_CHI_MMIO)
                   && ((incomingReq.addr[CFG.addrW-1:0]
                        & ~CFG.addrW'(12'hfff))
                       == CFG_MMIO_BASE);
    configRead = isRead(incomingReq.opcode);
    // PCrdReturn carries no transaction and PrefetchTgt has no response, so
    // both are accepted and discarded (IHI 0050H B2.5.6, B4.2.6.2).
    droppedRequest = (incomingReq.opcode == REQ_PCRD_RETURN)
                     || (incomingReq.opcode == REQ_PREFETCH_TGT);
    activeConfigRead = isRead(activeReq.opcode);

    forwardedReq = activeReq;
    forwardedReq.tgtId = activeReq.tgtId;
    forwardedReq.srcId = HN_NODE_ID;
    reqOutFlit = '0;
    reqOutFlit.channel = CHI_CHANNEL_REQ;
    reqOutFlit.targetNodeId = activeReq.tgtId;
    reqOutFlit.payload[CHI_MAX_REQ_FLIT_W-1:0] = packReqFlit(CFG, forwardedReq);
    reqOutValid = state == HNI_SEND_REQ;

    returnedRsp = incomingRsp;
    returnedRsp.tgtId = activeReq.srcId;
    returnedRsp.srcId = HN_NODE_ID;
    returnedRsp.txnId = activeReq.txnId;
    configRsp = '0;
    configRsp.tgtId = activeReq.srcId;
    configRsp.srcId = HN_NODE_ID;
    configRsp.txnId = activeReq.txnId;
    configRsp.opcode = RSP_COMP;
    configRsp.respErr = activeDecodeError ? RESP_ERR_NDERR : RESP_ERR_OK;
    rspOutFlit = '0;
    rspOutFlit.channel = CHI_CHANNEL_RSP;
    rspOutFlit.targetNodeId = activeReq.srcId;
    rspOutFlit.payload[CHI_MAX_RSP_FLIT_W-1:0] =
      packRspFlit(CFG, (state == HNI_CFG_RESPONSE) ? configRsp : returnedRsp);
    rspOutValid = ((state == HNI_WAIT_SUBORDINATE) && rspInValid)
                  || ((state == HNI_CFG_RESPONSE) && !activeConfigRead);

    forwardedDat = incomingDat;
    forwardedDat.tgtId = activeReq.tgtId;
    forwardedDat.srcId = HN_NODE_ID;
    returnedDat = incomingDat;
    returnedDat.tgtId = activeReq.srcId;
    returnedDat.srcId = HN_NODE_ID;
    returnedDat.txnId = activeReq.txnId;
    forwardRequesterData = incomingDat.srcId == activeReq.srcId;
    configDat = '0;
    configDat.tgtId = activeReq.srcId;
    configDat.srcId = HN_NODE_ID;
    configDat.txnId = activeReq.txnId;
    configDat.opcode = DAT_COMP_DATA;
    configDat.respErr = RESP_ERR_OK;
    case (activeReq.addr[7:0])
      8'h08: configDat.data[CFG.addrW-1:0] = stagedBase[selectedRegion];
      8'h10: configDat.data[CFG.addrW-1:0] = stagedLimit[selectedRegion];
      8'h18: configDat.data[chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] = stagedTarget[selectedRegion];
      8'h20: configDat.data[3:0] = stagedAttributes[selectedRegion];
      default: configDat.data[clog2Min1(NUM_REGIONS)-1:0] = selectedRegion;
    endcase
    datOutFlit = '0;
    datOutFlit.channel = CHI_CHANNEL_DAT;
    datOutFlit.targetNodeId = (state == HNI_CFG_RESPONSE)
                              ? activeReq.srcId
                              : (forwardRequesterData
                                 ? forwardedDat.tgtId : returnedDat.tgtId);
    datOutFlit.payload = packDatFlit(
      CFG, (state == HNI_CFG_RESPONSE) ? configDat :
           (forwardRequesterData ? forwardedDat : returnedDat));
    datOutValid = ((state == HNI_WAIT_SUBORDINATE) && datInValid)
                  || ((state == HNI_CFG_RESPONSE) && activeConfigRead);

    idle = state == HNI_IDLE;
  end

  // The ready outputs pass the downstream readies straight through, so they
  // are written on their own to keep the flits and valids above clear of any
  // dependency on the ready they are paired with.
  always_comb begin
    reqInReady = state == HNI_IDLE;
    rspInReady = (state == HNI_WAIT_SUBORDINATE) && rspOutReady;
    datInReady = (state == HNI_CFG_WAIT_DATA)
                 || ((state == HNI_WAIT_SUBORDINATE) && datOutReady);
  end

  always_ff @(posedge clk) begin
    if (!resetn) begin
      state <= HNI_IDLE;
      activeReq <= '0;
      activeDecodeError <= 1'b0;
      selectedRegion <= '0;
      mmioRegionUpdate <= 1'b0;
      mmioRegionUpdateIndex <= '0;
      mmioRegionUpdateBase <= '0;
      mmioRegionUpdateLimit <= '0;
      mmioRegionUpdateTarget <= '0;
      mmioRegionUpdateAttributes <= '0;
      for (int unsigned region = 0; region < NUM_REGIONS; region++) begin
        stagedBase[region] <= REGION_BASE[region];
        stagedLimit[region] <= REGION_LIMIT[region];
        stagedTarget[region] <= REGION_TARGET[region];
        stagedAttributes[region] <= REGION_ATTRIBUTES[region];
      end
    end else begin
      mmioRegionUpdate <= 1'b0;
      if (regionUpdate) begin
        stagedBase[regionUpdateIndex] <= regionUpdateBase;
        stagedLimit[regionUpdateIndex] <= regionUpdateLimit;
        stagedTarget[regionUpdateIndex] <= regionUpdateTarget;
        stagedAttributes[regionUpdateIndex] <= regionUpdateAttributes;
      end
      case (state)
        HNI_IDLE: begin
          if (reqInValid && reqInReady && !droppedRequest) begin
            activeReq <= incomingReq;
            activeDecodeError <= samError && !configAccess;
            if (configAccess) begin
              if (configRead)
                state <= HNI_CFG_RESPONSE;
              else
                state <= HNI_CFG_WAIT_DATA;
            end else if (samError) begin
              state <= HNI_CFG_RESPONSE;
            end else begin
              activeReq.tgtId <= samTarget;
              state <= HNI_SEND_REQ;
            end
          end
        end
        HNI_SEND_REQ:
          if (reqOutValid && reqOutReady)
            state <= HNI_WAIT_SUBORDINATE;
        HNI_WAIT_SUBORDINATE: begin
          if (rspInValid && rspInReady
              && ((incomingRsp.opcode == RSP_COMP)
                  || (incomingRsp.opcode == RSP_COMP_DBID_RESP)
                  || (incomingRsp.opcode == RSP_COMP_CMO)
                  || (incomingRsp.opcode == RSP_COMP_PERSIST)
                  || (incomingRsp.opcode == RSP_RETRY_ACK)))
            state <= HNI_IDLE;
          else if (datInValid && datInReady
                   && (incomingDat.opcode == DAT_COMP_DATA)
                   && incomingDatLast)
            state <= HNI_IDLE;
        end
        HNI_CFG_WAIT_DATA: begin
          if (datInValid && datInReady) begin
            case (activeReq.addr[7:0])
              8'h00:
                if ((incomingDat.data[511:clog2Min1(NUM_REGIONS)] == '0)
                    && ({1'b0,
                         incomingDat.data[clog2Min1(NUM_REGIONS)-1:0]}
                        < (clog2Min1(NUM_REGIONS)+1)'(NUM_REGIONS)))
                  selectedRegion <= incomingDat.data[clog2Min1(NUM_REGIONS)-1:0];
              8'h08: stagedBase[selectedRegion] <= incomingDat.data[CFG.addrW-1:0];
              8'h10: stagedLimit[selectedRegion] <= incomingDat.data[CFG.addrW-1:0];
              8'h18: stagedTarget[selectedRegion] <= incomingDat.data[chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0];
              8'h20: stagedAttributes[selectedRegion] <= incomingDat.data[3:0];
              8'h28: begin
                mmioRegionUpdate <= 1'b1;
                mmioRegionUpdateIndex <= selectedRegion;
                mmioRegionUpdateBase <= stagedBase[selectedRegion];
                mmioRegionUpdateLimit <= stagedLimit[selectedRegion];
                mmioRegionUpdateTarget <= stagedTarget[selectedRegion];
                mmioRegionUpdateAttributes <= stagedAttributes[selectedRegion];
              end
              default: begin
              end
            endcase
            state <= HNI_CFG_RESPONSE;
          end
        end
        HNI_CFG_RESPONSE:
          if ((activeConfigRead && datOutValid && datOutReady)
              || (!activeConfigRead && rspOutValid && rspOutReady))
            state <= HNI_IDLE;
        default: state <= HNI_IDLE;
      endcase
    end
  end
endmodule
