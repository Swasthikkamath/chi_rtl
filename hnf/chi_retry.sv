module chi_retry #(
  parameter int unsigned COUNT_W = 8,
  parameter int unsigned AGE_W = 12
) (
  input  logic clk,
  input  logic resetn,
  input  logic requestValid,
  input  logic resourcesAvailable,
  input  logic allowRetry,
  input  logic [1:0] requestClass,
  output logic acceptRequest,
  output logic sendRetryAck,
  output logic [1:0] retryClass,
  input  logic creditReturnValid,
  input  logic [1:0] creditReturnClass,
  input  logic cancelValid,
  input  logic [1:0] cancelClass,
  output logic grantValid,
  input  logic grantReady,
  output logic [1:0] grantClass,
  output logic [COUNT_W-1:0] pendingCount [4]
);
  logic [AGE_W-1:0] age [4];
  logic candidateValid;
  logic [AGE_W-1:0] candidateAge;

  always_comb begin
    acceptRequest = requestValid && resourcesAvailable;
    sendRetryAck = requestValid && !resourcesAvailable && allowRetry;
    retryClass = requestClass;
    candidateValid = 1'b0;
    candidateAge = '0;
    grantClass = '0;
    for (int unsigned c = 0; c < 4; c++) begin
      if ((pendingCount[c] != '0)
          && (!candidateValid || (age[c] > candidateAge))) begin
        candidateValid = 1'b1;
        candidateAge = age[c];
        grantClass = c[1:0];
      end
    end
    grantValid = candidateValid;
  end

  always_ff @(posedge clk) begin
    if (!resetn) begin
      for (int unsigned c = 0; c < 4; c++) begin
        pendingCount[c] <= '0;
        age[c] <= '0;
      end
    end else begin
      for (int unsigned c = 0; c < 4; c++) begin
        if (pendingCount[c] != '0)
          age[c] <= &age[c] ? age[c] : age[c] + 1'b1;
        else
          age[c] <= '0;
      end
      if (sendRetryAck && !(&pendingCount[requestClass]))
        pendingCount[requestClass] <= pendingCount[requestClass] + 1'b1;
      if (creditReturnValid) begin
        if (pendingCount[creditReturnClass] != '0)
          pendingCount[creditReturnClass] <= pendingCount[creditReturnClass] - 1'b1;
        age[creditReturnClass] <= '0;
      end
      if (cancelValid) begin
        if (pendingCount[cancelClass] != '0)
          pendingCount[cancelClass] <= pendingCount[cancelClass] - 1'b1;
        age[cancelClass] <= '0;
      end
      if (grantValid && grantReady) begin
        if (pendingCount[grantClass] != '0)
          pendingCount[grantClass] <= pendingCount[grantClass] - 1'b1;
        age[grantClass] <= '0;
      end
    end
  end
endmodule
