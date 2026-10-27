// Output arbiter for one crosspoint output and channel: QoS first, then age,
// then round-robin.
//
// request says an input wants this output and drives the age counters, so a
// requester keeps ageing while it is held back. eligible says the request can
// be granted this cycle; a crosspoint clears it when the output buffer cannot
// take the flit, which for a ring injection under bubble flow control can last
// several cycles. Keeping the two apart stops a temporarily blocked requester
// from losing the age it has accumulated.
module chi_vc_arb #(
  parameter int unsigned NUM_REQUESTERS = 4,
  parameter int unsigned AGE_LIMIT = 16,
  parameter int unsigned INDEX_W =
    (NUM_REQUESTERS < 2) ? 1 : $clog2(NUM_REQUESTERS),
  parameter int unsigned AGE_W =
    (AGE_LIMIT < 1) ? 1 : $clog2(AGE_LIMIT + 1)
) (
  input  logic                                      clk,
  input  logic                                      resetn,
  input  logic [NUM_REQUESTERS-1:0]                 request,
  input  logic [NUM_REQUESTERS-1:0]                 eligible,
  input  logic [NUM_REQUESTERS-1:0][3:0]            qos,
  input  logic                                      ready,
  output logic [NUM_REQUESTERS-1:0]                 grant,
  output logic                                      grantValid
);
  localparam logic [AGE_W-1:0] AGE_LIMIT_COUNT = AGE_W'(AGE_LIMIT);

  logic [AGE_W-1:0] ageCount [NUM_REQUESTERS-1:0];
  logic [INDEX_W-1:0] roundRobinIndex;
  logic locked;
  logic [INDEX_W-1:0] lockedIndex;
  logic [NUM_REQUESTERS-1:0] candidate;
  logic agedRequestPresent;
  logic winnerFound;
  logic [3:0] winnerQos;
  logic [INDEX_W-1:0] grantIndex;
  int unsigned candidateIndex;

  always_comb begin
    candidate = request & eligible;
    agedRequestPresent = 1'b0;
    for (int unsigned requesterIndex = 0;
         requesterIndex < NUM_REQUESTERS; requesterIndex++) begin
      if (candidate[requesterIndex]
          && (ageCount[requesterIndex] >= AGE_LIMIT_COUNT)) begin
        agedRequestPresent = 1'b1;
      end
    end

    grant = '0;
    grantValid = 1'b0;
    grantIndex = '0;
    winnerFound = 1'b0;
    winnerQos = '0;
    candidateIndex = 0;

    if (locked && candidate[lockedIndex]) begin
      grant[lockedIndex] = 1'b1;
      grantValid = 1'b1;
      grantIndex = lockedIndex;
    end else begin
      for (int unsigned offset = 0; offset < NUM_REQUESTERS; offset++) begin
        candidateIndex = int'(roundRobinIndex);
        candidateIndex = candidateIndex + offset;
        if (candidateIndex >= NUM_REQUESTERS) begin
          candidateIndex = candidateIndex - NUM_REQUESTERS;
        end

        if (candidate[candidateIndex]
            && (!agedRequestPresent
                || (ageCount[candidateIndex] >= AGE_LIMIT_COUNT))) begin
          if (!winnerFound
              || (!agedRequestPresent && (qos[candidateIndex] > winnerQos))) begin
            winnerFound = 1'b1;
            winnerQos = qos[candidateIndex];
            grantIndex = INDEX_W'(candidateIndex);
          end
        end
      end

      if (winnerFound) begin
        grant[grantIndex] = 1'b1;
        grantValid = 1'b1;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!resetn) begin
      roundRobinIndex <= '0;
      locked <= 1'b0;
      lockedIndex <= '0;
      for (int unsigned requesterIndex = 0;
           requesterIndex < NUM_REQUESTERS; requesterIndex++) begin
        ageCount[requesterIndex] <= '0;
      end
    end else begin
      if (grantValid && ready) begin
        if (grantIndex == INDEX_W'(NUM_REQUESTERS - 1)) begin
          roundRobinIndex <= '0;
        end else begin
          roundRobinIndex <= grantIndex + 1'b1;
        end
        locked <= 1'b0;
      end else if (grantValid) begin
        locked <= 1'b1;
        lockedIndex <= grantIndex;
      end else begin
        locked <= 1'b0;
      end

      for (int unsigned requesterIndex = 0;
           requesterIndex < NUM_REQUESTERS; requesterIndex++) begin
        if (!request[requesterIndex]
            || (grant[requesterIndex] && ready)) begin
          ageCount[requesterIndex] <= '0;
        end else if (ageCount[requesterIndex] < AGE_LIMIT_COUNT) begin
          ageCount[requesterIndex] <= ageCount[requesterIndex] + 1'b1;
        end
      end
    end
  end
endmodule
