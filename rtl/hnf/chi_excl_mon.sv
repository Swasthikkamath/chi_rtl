module chi_excl_mon #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned MONITORS = CFG.exclMonitors
) (
  input  logic clk,
  input  logic resetn,
  input  logic reserveValid,
  output logic reserveReady,
  input  logic [CFG.addrW-7:0] reserveLineAddr,
  input  logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] reserveRequester,
  input  logic exclusiveCheckValid,
  input  logic [CFG.addrW-7:0] exclusiveLineAddr,
  input  logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] exclusiveRequester,
  output logic exclusiveOkay,
  input  logic conflictValid,
  input  logic conflictIsWriteOrSnoop,
  input  logic [CFG.addrW-7:0] conflictLineAddr
);
  logic valid [MONITORS];
  logic [CFG.addrW-7:0] lineAddr [MONITORS];
  logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] requester [MONITORS];
  logic [chi_pkg::clog2Min1(MONITORS)-1:0] reserveIndex;
  logic reserveFound;

  always_comb begin
    reserveFound = 1'b0;
    reserveIndex = '0;
    exclusiveOkay = 1'b0;
    for (int unsigned i = 0; i < MONITORS; i++) begin
      if (!reserveFound
          && ((!valid[i]) || ((requester[i] == reserveRequester)
                              && (lineAddr[i] == reserveLineAddr)))) begin
        reserveFound = 1'b1;
        reserveIndex = i[chi_pkg::clog2Min1(MONITORS)-1:0];
      end
      if (exclusiveCheckValid && valid[i]
          && (requester[i] == exclusiveRequester)
          && (lineAddr[i] == exclusiveLineAddr))
        exclusiveOkay = 1'b1;
    end
    reserveReady = CFG.exclEn && reserveFound;
  end

  always_ff @(posedge clk) begin
    if (!resetn) begin
      for (int unsigned i = 0; i < MONITORS; i++) begin
        valid[i] <= 1'b0;
        lineAddr[i] <= '0;
        requester[i] <= '0;
      end
    end else begin
      if (conflictValid && conflictIsWriteOrSnoop) begin
        for (int unsigned i = 0; i < MONITORS; i++)
          if (valid[i] && (lineAddr[i] == conflictLineAddr))
            valid[i] <= 1'b0;
      end
      if (exclusiveCheckValid) begin
        for (int unsigned i = 0; i < MONITORS; i++)
          if (valid[i] && (requester[i] == exclusiveRequester)
              && (lineAddr[i] == exclusiveLineAddr))
            valid[i] <= 1'b0;
      end
      if (reserveValid && reserveReady) begin
        valid[reserveIndex] <= 1'b1;
        lineAddr[reserveIndex] <= reserveLineAddr;
        requester[reserveIndex] <= reserveRequester;
      end
    end
  end
endmodule
