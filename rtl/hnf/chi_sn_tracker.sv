// Downstream (Home to Subordinate) transaction trackers of one HN-F.
//
// One tracker per owner — POS entry or victim-buffer entry — so an owner
// has at most one downstream operation in flight, and the tracker index is
// the TxnID the Home uses towards the Subordinate. That TxnID space is
// separate from every Requester's: the Home never forwards a Requester's
// TxnID downstream (IHI 0050H B2.4.2, B2.3.9).
//
// An operation is one of:
//   HNF_DN_READ   ReadNoSnp; the Subordinate's CompData lands in the owner's
//                 line buffer (written by chi_hnf_top from the DAT input).
//   HNF_DN_WRITE  WriteNoSnpFull or WriteNoSnpPtl; the tracker sends the data
//                 packets once the DBID has arrived (IHI 0050H B2.3.9.2).
//   HNF_DN_CMO    a forwarded cache maintenance request; done on Comp.
//
// The tracker also runs Request Retry as a Requester (IHI 0050H B2.10): a
// RetryAck parks the operation until a PCrdGrant of the recorded type is
// available, the request is then re-sent with AllowRetry deasserted, and a
// credit that no parked operation can use is handed back with PCrdReturn once
// nothing in flight could still be retried.
//
// The issue valids never look at their readies (design specification,
// Section 2.8); a request or data packet is issued in a cycle where both are
// high.
module chi_sn_tracker #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned NUM_OWNERS = 1,
  parameter int unsigned OWNER_W = chi_pkg::clog2Min1(NUM_OWNERS)
) (
  input  logic clk,
  input  logic resetn,
  input  logic [NUM_OWNERS-1:0] startValid,
  input  chi_hnf_pkg::chi_hnf_dn_e [NUM_OWNERS-1:0] startKind,
  // Read: granules the data message covers. Write: granules to send.
  input  logic [NUM_OWNERS-1:0][3:0] startGranules,
  // The data does not pass the Home (DMT read, DWT write).
  input  logic [NUM_OWNERS-1:0] startNoData,
  // Ask the Subordinate for a ReadReceipt (Order = Request accepted).
  input  logic [NUM_OWNERS-1:0] startWantReceipt,
  output logic [NUM_OWNERS-1:0] busy,
  output logic [NUM_OWNERS-1:0] done,
  // A request being re-sent carries AllowRetry = 0 and this PCrdType.
  output logic [NUM_OWNERS-1:0] resend,
  output logic [NUM_OWNERS-1:0][3:0] resendCreditType,
  input  logic reqIssueReady,
  output logic reqIssueValid,
  output logic [OWNER_W-1:0] reqIssueOwner,
  output logic reqIssueCreditReturn,
  output logic [3:0] reqIssueCreditType,
  input  logic datIssueReady,
  output logic datIssueValid,
  output logic [OWNER_W-1:0] datIssueOwner,
  output logic [1:0] datIssueDataId,
  output logic [chi_cfg_pkg::CHI_RSP_DBID_SLOT_W-1:0] datIssueTxnId,
  // Responses and data from the Subordinate, already filtered by SrcID.
  input  logic rspValid,
  input  chi_pkg::chi_rsp_flit_t rsp,
  input  logic datValid,
  input  chi_pkg::chi_dat_flit_t dat
);
  import chi_cfg_pkg::*;
  import chi_pkg::*;
  import chi_hnf_pkg::*;

  typedef enum logic [1:0] {
    DN_IDLE   = 2'd0,
    DN_REQ    = 2'd1,  // request waiting to be sent
    DN_ACTIVE = 2'd2,  // request sent
    DN_RETRY  = 2'd3   // RetryAck received, waiting for a P-Credit
  } dn_state_e;

  localparam int unsigned STEP = chi_pkg::datIdStep(CFG);

  dn_state_e [NUM_OWNERS-1:0] state;
  chi_hnf_dn_e [NUM_OWNERS-1:0] kind;
  logic [NUM_OWNERS-1:0] noData;
  logic [NUM_OWNERS-1:0] wantReceipt;
  logic [NUM_OWNERS-1:0] accepted;
  logic [NUM_OWNERS-1:0] gotDbid;
  logic [NUM_OWNERS-1:0] gotComp;
  logic [NUM_OWNERS-1:0] gotReceipt;
  logic [NUM_OWNERS-1:0][3:0] granules;
  logic [NUM_OWNERS-1:0][3:0] granulesDone;
  logic [NUM_OWNERS-1:0][CHI_RSP_DBID_SLOT_W-1:0] dbid;
  logic [NUM_OWNERS-1:0] resendReg;
  logic [NUM_OWNERS-1:0][3:0] creditTypeReg;
  logic [15:0][7:0] credits;
  logic [15:0][7:0] creditsNext;

  logic [OWNER_W-1:0] reqPointer;
  logic [OWNER_W-1:0] datPointer;
  logic reqOwnerFound;
  logic datOwnerFound;
  logic reqIssueFire;
  logic datIssueFire;
  logic [NUM_OWNERS-1:0] complete;
  logic [NUM_OWNERS-1:0] takeCredit;
  logic [15:0] creditWanted;
  logic anyUnaccepted;
  logic returnFound;
  int unsigned candidate;
  logic rspForOwner;
  logic [OWNER_W-1:0] rspOwner;
  logic datForOwner;
  logic [OWNER_W-1:0] datOwner;

  always_comb begin
    rspOwner = OWNER_W'(rsp.txnId);
    rspForOwner = rspValid && (int'(rsp.txnId) < NUM_OWNERS)
                  && (rsp.opcode != RSP_PCRD_GRANT);
    datOwner = OWNER_W'(dat.txnId);
    datForOwner = datValid && (int'(dat.txnId) < NUM_OWNERS)
                  && ((dat.opcode == DAT_COMP_DATA)
                      || (dat.opcode == DAT_DATA_SEP_RESP));

    for (int unsigned owner = 0; owner < NUM_OWNERS; owner++) begin
      busy[owner] = state[owner] != DN_IDLE;
      resend[owner] = resendReg[owner];
      resendCreditType[owner] = creditTypeReg[owner];
      case (kind[owner])
        HNF_DN_READ:
          complete[owner] = accepted[owner]
                            && (noData[owner]
                                || (granulesDone[owner] == granules[owner]))
                            && (!wantReceipt[owner] || gotReceipt[owner]);
        HNF_DN_WRITE:
          complete[owner] = gotComp[owner]
                            && (noData[owner]
                                || (gotDbid[owner]
                                    && (granulesDone[owner] == granules[owner])));
        default:
          complete[owner] = gotComp[owner];
      endcase
    end
  end

  // P-Credit accounting. A parked operation takes a credit of its type while
  // one is available, counting a grant that arrives this cycle and the
  // credits lower-numbered waiters take first. A credit that nothing waits for
  // is returned, but only once no request in flight could still be answered
  // with a RetryAck.
  always_comb begin
    creditWanted = '0;
    anyUnaccepted = 1'b0;
    for (int unsigned owner = 0; owner < NUM_OWNERS; owner++) begin
      if (state[owner] == DN_RETRY)
        creditWanted[creditTypeReg[owner]] = 1'b1;
      if ((state[owner] == DN_REQ)
          || ((state[owner] == DN_ACTIVE) && !accepted[owner]))
        anyUnaccepted = 1'b1;
    end

    creditsNext = credits;
    if (rspValid && (rsp.opcode == RSP_PCRD_GRANT))
      creditsNext[rsp.pCrdType] = creditsNext[rsp.pCrdType] + 8'd1;
    takeCredit = '0;
    for (int unsigned owner = 0; owner < NUM_OWNERS; owner++) begin
      if ((state[owner] == DN_RETRY)
          && (creditsNext[creditTypeReg[owner]] != '0)) begin
        takeCredit[owner] = 1'b1;
        creditsNext[creditTypeReg[owner]] =
          creditsNext[creditTypeReg[owner]] - 8'd1;
      end
    end

    returnFound = 1'b0;
    reqIssueCreditType = '0;
    for (int unsigned type_ = 0; type_ < 16; type_++)
      if (!returnFound && (credits[type_] != '0) && !creditWanted[type_]
          && !anyUnaccepted) begin
        returnFound = 1'b1;
        reqIssueCreditType = 4'(type_);
      end
  end

  always_comb begin
    reqOwnerFound = 1'b0;
    reqIssueOwner = '0;
    candidate = 0;
    for (int unsigned offset = 0; offset < NUM_OWNERS; offset++) begin
      candidate = int'(reqPointer) + offset;
      if (candidate >= NUM_OWNERS)
        candidate = candidate - NUM_OWNERS;
      if (!reqOwnerFound && (state[candidate] == DN_REQ)) begin
        reqOwnerFound = 1'b1;
        reqIssueOwner = OWNER_W'(candidate);
      end
    end
    reqIssueCreditReturn = !reqOwnerFound && returnFound;
    reqIssueValid = reqOwnerFound || returnFound;

    datOwnerFound = 1'b0;
    datIssueOwner = '0;
    for (int unsigned offset = 0; offset < NUM_OWNERS; offset++) begin
      candidate = int'(datPointer) + offset;
      if (candidate >= NUM_OWNERS)
        candidate = candidate - NUM_OWNERS;
      if (!datOwnerFound && (state[candidate] == DN_ACTIVE)
          && (kind[candidate] == HNF_DN_WRITE) && !noData[candidate]
          && gotDbid[candidate]
          && ((granules[candidate] & ~granulesDone[candidate]) != '0)) begin
        datOwnerFound = 1'b1;
        datIssueOwner = OWNER_W'(candidate);
      end
    end
    datIssueDataId = '0;
    for (int unsigned granule = 4; granule > 0; granule--)
      if (granules[datIssueOwner][granule-1]
          && !granulesDone[datIssueOwner][granule-1])
        datIssueDataId = 2'((granule - 1) & ~(STEP - 1));
    datIssueTxnId = dbid[datIssueOwner];
    datIssueValid = datOwnerFound;
  end

  always_comb begin
    reqIssueFire = reqIssueValid && reqIssueReady;
    datIssueFire = datIssueValid && datIssueReady;
  end

  always_ff @(posedge clk) begin
    if (!resetn) begin
      for (int unsigned owner = 0; owner < NUM_OWNERS; owner++) begin
        state[owner] <= DN_IDLE;
        kind[owner] <= HNF_DN_READ;
      end
      noData <= '0;
      wantReceipt <= '0;
      accepted <= '0;
      gotDbid <= '0;
      gotComp <= '0;
      gotReceipt <= '0;
      granules <= '0;
      granulesDone <= '0;
      dbid <= '0;
      resendReg <= '0;
      creditTypeReg <= '0;
      credits <= '0;
      reqPointer <= '0;
      datPointer <= '0;
      done <= '0;
    end else begin
      done <= '0;
      credits <= creditsNext;
      if (reqIssueFire && reqIssueCreditReturn)
        credits[reqIssueCreditType] <= creditsNext[reqIssueCreditType] - 8'd1;

      if (reqIssueFire && !reqIssueCreditReturn)
        reqPointer <= (int'(reqIssueOwner) == (NUM_OWNERS - 1))
                      ? '0 : (reqIssueOwner + 1'b1);
      if (datIssueFire)
        datPointer <= (int'(datIssueOwner) == (NUM_OWNERS - 1))
                      ? '0 : (datIssueOwner + 1'b1);

      for (int unsigned owner = 0; owner < NUM_OWNERS; owner++) begin
        case (state[owner])
          DN_IDLE: begin
            if (startValid[owner]) begin
              state[owner] <= DN_REQ;
              kind[owner] <= startKind[owner];
              granules[owner] <= startGranules[owner];
              noData[owner] <= startNoData[owner];
              wantReceipt[owner] <= startWantReceipt[owner];
              accepted[owner] <= 1'b0;
              gotDbid[owner] <= 1'b0;
              gotComp[owner] <= 1'b0;
              gotReceipt[owner] <= 1'b0;
              granulesDone[owner] <= '0;
              resendReg[owner] <= 1'b0;
            end
          end
          DN_REQ: begin
            if (reqIssueFire && !reqIssueCreditReturn
                && (reqIssueOwner == OWNER_W'(owner)))
              state[owner] <= DN_ACTIVE;
          end
          DN_ACTIVE: begin
            if (rspForOwner && (rspOwner == OWNER_W'(owner))) begin
              case (rsp.opcode)
                RSP_RETRY_ACK: begin
                  state[owner] <= DN_RETRY;
                  resendReg[owner] <= 1'b1;
                  creditTypeReg[owner] <= rsp.pCrdType;
                end
                RSP_DBID_RESP, RSP_DBID_RESP_ORD: begin
                  accepted[owner] <= 1'b1;
                  gotDbid[owner] <= 1'b1;
                  dbid[owner] <= rsp.dbIdOrGroupId;
                end
                RSP_COMP_DBID_RESP: begin
                  accepted[owner] <= 1'b1;
                  gotDbid[owner] <= 1'b1;
                  gotComp[owner] <= 1'b1;
                  dbid[owner] <= rsp.dbIdOrGroupId;
                end
                RSP_COMP, RSP_COMP_PERSIST, RSP_COMP_CMO: begin
                  accepted[owner] <= 1'b1;
                  gotComp[owner] <= 1'b1;
                end
                RSP_READ_RECEIPT: begin
                  accepted[owner] <= 1'b1;
                  gotReceipt[owner] <= 1'b1;
                end
                default: begin
                end
              endcase
            end
            if (datForOwner && (datOwner == OWNER_W'(owner))) begin
              accepted[owner] <= 1'b1;
              for (int unsigned g = 0; g < 4; g++)
                if ((g >= int'(dat.dataId)) && (g < (int'(dat.dataId) + STEP)))
                  granulesDone[owner][g] <= 1'b1;
            end
            if (datIssueFire && (datIssueOwner == OWNER_W'(owner))) begin
              for (int unsigned g = 0; g < 4; g++)
                if ((g >= int'(datIssueDataId)) && (g < (int'(datIssueDataId) + STEP)))
                  granulesDone[owner][g] <= 1'b1;
            end
            if (complete[owner]) begin
              state[owner] <= DN_IDLE;
              done[owner] <= 1'b1;
            end
          end
          default: begin
            if (takeCredit[owner])
              state[owner] <= DN_REQ;
          end
        endcase
      end
    end
  end
endmodule
