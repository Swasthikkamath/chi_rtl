// Request Retry credit management for a Completer (IHI 0050H B2.10).
//
// A Completer that cannot accept a request answers with RetryAck and owes the
// Requester a PCrdGrant of the credit type it chose; the Requester re-sends
// the request with AllowRetry deasserted once it holds the credit. A granted
// credit leaves the Completer's accounting when a request arrives with
// AllowRetry deasserted or when the Requester hands it back with PCrdReturn
// (IHI 0050H B2.10.1).
//
// Owed grants are counted per Requester and credit type rather than recorded
// per RetryAck. A Requester has at most 1024 requests outstanding
// (IHI 0050H B2.4.2), so the counters cannot overflow and the Completer can
// always answer with RetryAck. That keeps the REQ input of every Home
// consumed unconditionally, which the deadlock argument in the design
// specification depends on. Only a request from a node outside
// REQUESTER_NODE_IDS cannot be retried; it is held with back-pressure.
//
// Grants go to the waiting Requester with the highest recorded QoS
// (IHI 0050H B2.10 lets QoS order them), and among equals in round-robin
// order, so no Requester waits forever behind another of its own QoS.
//
// creditsOutstanding counts credits granted and not yet used or returned.
// The Home keeps that many transaction entries reserved, so a request that
// arrives on a P-Credit is always accepted (IHI 0050H B2.10.2).
module chi_retry #(
  parameter int unsigned NODEID_W = 16,
  parameter int unsigned NUM_REQUESTERS = 1,
  parameter logic [chi_cfg_pkg::CHI_MAX_NODEID_W-1:0]
    REQUESTER_NODE_IDS [NUM_REQUESTERS] = '{default:'0},
  parameter int unsigned CREDIT_TYPES = 4,
  parameter int unsigned COUNT_W = 11,
  parameter int unsigned OUTSTANDING_W = 16
) (
  input  logic clk,
  input  logic resetn,
  // The request at the REQ input this cycle.
  input  logic requestValid,
  input  logic resourcesAvailable,
  input  logic allowRetry,
  input  logic [1:0] requestCategory,
  input  logic [NODEID_W-1:0] requestSrcId,
  input  logic [3:0] requestQos,
  output logic sendRetryAck,
  input  logic retryAckSent,
  output logic [3:0] retryClass,
  // A credited request was accepted, or a credit was handed back.
  input  logic creditUseValid,
  input  logic creditReturnValid,
  // The Home has an unreserved resource for the next grant.
  input  logic grantAllowed,
  output logic grantValid,
  input  logic grantReady,
  output logic [NODEID_W-1:0] grantTgtId,
  output logic [3:0] grantClass,
  output logic [OUTSTANDING_W-1:0] creditsOutstanding,
  // Some Requester is waiting for a credit.
  output logic grantsOwed
);
  localparam int unsigned REQ_W = chi_pkg::clog2Min1(NUM_REQUESTERS);
  localparam int unsigned TYPES = (CREDIT_TYPES > 0) ? CREDIT_TYPES : 1;
  localparam logic [COUNT_W-1:0] COUNT_MAX = '1;

  logic [COUNT_W-1:0] waiting [NUM_REQUESTERS][TYPES];
  logic [3:0] waitingQos [NUM_REQUESTERS];
  logic [REQ_W-1:0] grantPointer;
  logic requesterKnown;
  logic [REQ_W-1:0] requesterIndex;
  logic [REQ_W-1:0] selectIndex;
  logic [3:0] selectType;
  logic selectFound;
  logic recordValid;
  logic grantFire;

  // A single credit type is recommended when the Completer does not partition
  // its resources, so CREDIT_TYPES = 1 collapses every category onto type 0.
  always_comb begin
    if (TYPES <= 1)
      retryClass = 4'd0;
    else
      retryClass = 4'(int'(requestCategory) % TYPES);
  end

  always_comb begin
    requesterKnown = 1'b0;
    requesterIndex = '0;
    for (int unsigned r = 0; r < NUM_REQUESTERS; r++)
      if (requestSrcId == NODEID_W'(REQUESTER_NODE_IDS[r])) begin
        requesterKnown = 1'b1;
        requesterIndex = REQ_W'(r);
      end
    sendRetryAck = requestValid && !resourcesAvailable && allowRetry
                   && requesterKnown
                   && (waiting[requesterIndex][retryClass[chi_pkg::clog2Min1(TYPES)-1:0]]
                       != COUNT_MAX);
    // The grant is owed from the moment the RetryAck is accepted by the
    // output stage, so a back-pressured RSP channel never counts it twice.
    recordValid = sendRetryAck && retryAckSent;
  end

  // Highest QoS first, then the first waiting Requester at or after the
  // round-robin pointer; within a Requester the lowest credit type.
  always_comb begin
    logic [3:0] bestQos;
    int unsigned candidate;
    selectFound = 1'b0;
    selectIndex = '0;
    selectType = '0;
    bestQos = '0;
    grantsOwed = 1'b0;
    for (int unsigned offset = 0; offset < NUM_REQUESTERS; offset++) begin
      logic anyWaiting;
      logic [3:0] firstType;
      candidate = int'(grantPointer) + offset;
      if (candidate >= NUM_REQUESTERS)
        candidate = candidate - NUM_REQUESTERS;
      anyWaiting = 1'b0;
      firstType = '0;
      for (int unsigned t = TYPES; t > 0; t--)
        if (waiting[candidate][t-1] != '0) begin
          anyWaiting = 1'b1;
          firstType = 4'(t - 1);
        end
      if (anyWaiting) begin
        grantsOwed = 1'b1;
        if (!selectFound || (waitingQos[candidate] > bestQos)) begin
          selectFound = 1'b1;
          selectIndex = REQ_W'(candidate);
          selectType = firstType;
          bestQos = waitingQos[candidate];
        end
      end
    end
    grantValid = selectFound && grantAllowed;
    grantTgtId = NODEID_W'(REQUESTER_NODE_IDS[selectIndex]);
    grantClass = selectType;
  end

  always_comb begin
    grantFire = grantValid && grantReady;
  end

  always_ff @(posedge clk) begin
    if (!resetn) begin
      for (int unsigned r = 0; r < NUM_REQUESTERS; r++) begin
        waitingQos[r] <= '0;
        for (int unsigned t = 0; t < TYPES; t++)
          waiting[r][t] <= '0;
      end
      grantPointer <= '0;
      creditsOutstanding <= '0;
    end else begin
      // A grant and a record can name the same counter in one cycle, so the
      // counter is updated once with both.
      for (int unsigned r = 0; r < NUM_REQUESTERS; r++) begin
        logic [COUNT_W-1:0] remaining;
        logic anyLeft;
        anyLeft = 1'b0;
        for (int unsigned t = 0; t < TYPES; t++) begin
          remaining = waiting[r][t];
          if (recordValid && (requesterIndex == REQ_W'(r))
              && (int'(retryClass) == t))
            remaining = remaining + 1'b1;
          if (grantFire && (selectIndex == REQ_W'(r))
              && (int'(selectType) == t))
            remaining = remaining - 1'b1;
          waiting[r][t] <= remaining;
          if (remaining != '0)
            anyLeft = 1'b1;
        end
        if (recordValid && (requesterIndex == REQ_W'(r))
            && (requestQos > waitingQos[r]))
          waitingQos[r] <= requestQos;
        else if (!anyLeft)
          waitingQos[r] <= '0;
      end

      if (grantFire)
        grantPointer <= (int'(selectIndex) == (NUM_REQUESTERS - 1))
                        ? '0 : (selectIndex + 1'b1);

      creditsOutstanding <= creditsOutstanding
                            + OUTSTANDING_W'(grantFire)
                            - OUTSTANDING_W'(creditUseValid
                                             && (creditsOutstanding != '0))
                            - OUTSTANDING_W'(creditReturnValid
                                             && (creditsOutstanding
                                                 > OUTSTANDING_W'(creditUseValid)));
    end
  end
endmodule
