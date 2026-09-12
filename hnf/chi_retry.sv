// Request Retry credit management for a Completer (IHI 0050H B2.10).
//
// A Completer that cannot accept a request answers with RetryAck, records the
// SrcID of that request together with the P-Credit type it must later grant,
// and issues PCrdGrant once the resource exists. The Completer chooses the
// credit type; the value carried in the request is only echoed back when a
// credited request is re-sent. A granted credit leaves the Completer's
// accounting either when a request arrives with AllowRetry deasserted or when
// the Requester hands the credit back with PCrdReturn (IHI 0050H B2.10.1).
module chi_retry #(
  parameter int unsigned NODEID_W = 16,
  parameter int unsigned ENTRIES = 16,
  parameter int unsigned CREDIT_TYPES = 4,
  parameter int unsigned COUNT_W = 8,
  parameter int unsigned AGE_W = 12
) (
  input  logic clk,
  input  logic resetn,
  input  logic requestValid,
  input  logic resourcesAvailable,
  input  logic allowRetry,
  input  logic [1:0] requestCategory,
  input  logic [NODEID_W-1:0] requestSrcId,
  input  logic [3:0] requestQos,
  output logic acceptRequest,
  output logic sendRetryAck,
  output logic [3:0] retryClass,
  output logic recordFull,
  input  logic creditUseValid,
  input  logic [3:0] creditUseClass,
  input  logic creditReturnValid,
  input  logic [3:0] creditReturnClass,
  input  logic grantAllowed,
  output logic grantValid,
  input  logic grantReady,
  output logic [NODEID_W-1:0] grantTgtId,
  output logic [3:0] grantClass,
  output logic [COUNT_W-1:0] pendingCount [CREDIT_TYPES],
  output logic [COUNT_W-1:0] creditsOutstanding [CREDIT_TYPES],
  output logic creditsPending
);
  localparam int unsigned IDX_W = (ENTRIES > 1) ? $clog2(ENTRIES) : 1;

  logic [ENTRIES-1:0] entryValid;
  logic [NODEID_W-1:0] entrySrcId [ENTRIES];
  logic [3:0] entryClass [ENTRIES];
  logic [3:0] entryQos [ENTRIES];
  logic [AGE_W-1:0] entryAge [ENTRIES];
  logic [COUNT_W-1:0] outstanding [CREDIT_TYPES];
  logic [COUNT_W-1:0] outstandingNext [CREDIT_TYPES];

  logic allocValid;
  logic [IDX_W-1:0] allocIndex;
  logic selectValid;
  logic [IDX_W-1:0] selectIndex;
  logic [3:0] selectQos;
  logic [AGE_W-1:0] selectAge;
  logic recordValid;

  // A single credit type is recommended when the Completer does not partition
  // its resources, so CREDIT_TYPES = 1 collapses every category onto type 0.
  always_comb begin
    if (CREDIT_TYPES <= 1)
      retryClass = 4'd0;
    else
      retryClass = 4'(int'(requestCategory) % CREDIT_TYPES);
  end

  always_comb begin
    allocValid = 1'b0;
    allocIndex = '0;
    for (int unsigned e = 0; e < ENTRIES; e++)
      if (!entryValid[e] && !allocValid) begin
        allocValid = 1'b1;
        allocIndex = IDX_W'(e);
      end
    recordFull = !allocValid;

    acceptRequest = requestValid && resourcesAvailable;
    sendRetryAck = requestValid && !resourcesAvailable && allowRetry
                   && allocValid;
    recordValid = sendRetryAck;
  end

  // QoS influences the order in which credits are handed out as resources
  // become available (IHI 0050H B2.10); age breaks ties so that no recorded
  // Requester is starved.
  always_comb begin
    selectValid = 1'b0;
    selectIndex = '0;
    selectQos = '0;
    selectAge = '0;
    for (int unsigned e = 0; e < ENTRIES; e++)
      if (entryValid[e]
          && (!selectValid || (entryQos[e] > selectQos)
              || ((entryQos[e] == selectQos) && (entryAge[e] > selectAge))))
      begin
        selectValid = 1'b1;
        selectIndex = IDX_W'(e);
        selectQos = entryQos[e];
        selectAge = entryAge[e];
      end

    grantValid = selectValid && grantAllowed;
    grantTgtId = entrySrcId[selectIndex];
    grantClass = entryClass[selectIndex];
  end

  // A grant and a credit consumption or return can land on the same type in
  // the same cycle, so the next count is accumulated before it is registered.
  always_comb begin
    creditsPending = 1'b0;
    for (int unsigned c = 0; c < CREDIT_TYPES; c++) begin
      creditsOutstanding[c] = outstanding[c];
      if (outstanding[c] != '0)
        creditsPending = 1'b1;
      pendingCount[c] = '0;
      for (int unsigned e = 0; e < ENTRIES; e++)
        if (entryValid[e] && (entryClass[e] == 4'(c)))
          pendingCount[c] = pendingCount[c] + 1'b1;

      outstandingNext[c] = outstanding[c];
      if (grantValid && grantReady && (grantClass == 4'(c))
          && !(&outstandingNext[c]))
        outstandingNext[c] = outstandingNext[c] + 1'b1;
      if (creditUseValid && (creditUseClass == 4'(c))
          && (outstandingNext[c] != '0))
        outstandingNext[c] = outstandingNext[c] - 1'b1;
      if (creditReturnValid && (creditReturnClass == 4'(c))
          && (outstandingNext[c] != '0))
        outstandingNext[c] = outstandingNext[c] - 1'b1;
    end
  end

  always_ff @(posedge clk) begin
    if (!resetn) begin
      entryValid <= '0;
      for (int unsigned e = 0; e < ENTRIES; e++) begin
        entrySrcId[e] <= '0;
        entryClass[e] <= '0;
        entryQos[e] <= '0;
        entryAge[e] <= '0;
      end
      for (int unsigned c = 0; c < CREDIT_TYPES; c++)
        outstanding[c] <= '0;
    end else begin
      for (int unsigned e = 0; e < ENTRIES; e++)
        if (entryValid[e] && !(&entryAge[e]))
          entryAge[e] <= entryAge[e] + 1'b1;

      if (grantValid && grantReady) begin
        entryValid[selectIndex] <= 1'b0;
        entryAge[selectIndex] <= '0;
      end

      if (recordValid) begin
        entryValid[allocIndex] <= 1'b1;
        entrySrcId[allocIndex] <= requestSrcId;
        entryClass[allocIndex] <= retryClass;
        entryQos[allocIndex] <= requestQos;
        entryAge[allocIndex] <= '0;
      end

      for (int unsigned c = 0; c < CREDIT_TYPES; c++)
        outstanding[c] <= outstandingNext[c];
    end
  end
endmodule
