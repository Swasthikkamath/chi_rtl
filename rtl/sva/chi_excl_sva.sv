// Exclusive monitor assertions (IHI 0050H B6.2).
//
//   EXCL_SECOND_PASS_NEEDS_REGISTRATION  after an Exclusive Store from one LP
//       passes on a location, a store from another LP to that location
//       passes only if that LP registered after the first pass.
//   EXCL_PASS_CLEARS_SAME_LOCATION  a pass resets every other LP's address
//       monitor on the location (with exclAddrCheck).
//   EXCL_PASS_KEEPS_OTHER_LOCATIONS  and no address monitor on any other
//       location.
//   EXCL_FAIL_REREGISTERS  a failing store leaves its LP registered, its
//       address monitor on the store's location (with exclAddrCheck), unless
//       registration was held off for a passing store's CompAck.
//   EXCL_ONE_MONITOR_PER_LP  no two address monitors belong to one LP.
//   EXCL_LPID_IN_RANGE  an exclusive access from a known Requester carries
//       an LPID below that Requester's RN_NUM_LP.
//
// Covers: a pass, a fail that registers, a failed store then a passing
// retry, two LPs on one location, two LPs passing on two locations, a fail
// because the address monitor holds another location.
module chi_excl_sva #(
  parameter int unsigned NUM_LP = 1,
  parameter int unsigned LP_W = 1,
  parameter int unsigned AMON = 1,
  parameter int unsigned AMON_W = 1,
  parameter int unsigned ADDR_W = 1,
  parameter bit ADDR_CHECK = 1'b1
) (
  input logic clk,
  input logic resetn,
  input logic commitValid,
  input logic commitLoad,
  input logic commitStore,
  input logic [ADDR_W-1:0] commitKey,
  input logic knownRequester,
  input logic registerBlocked,
  input logic lpKnown,
  input logic [LP_W-1:0] lpIndex,
  input logic pass,
  input logic doRegister,
  input logic [NUM_LP-1:0] lpBit,
  input logic [AMON-1:0] amValid,
  input logic [AMON-1:0][ADDR_W-1:0] amKey,
  input logic [AMON-1:0][LP_W-1:0] amLp
);
  // Reference: the last pass, and who registered since.
  logic lastPassValid;
  logic [LP_W-1:0] lastPassLp;
  logic [ADDR_W-1:0] lastPassKey;
  logic [NUM_LP-1:0] registeredSincePass;
  logic lastFailValid;
  logic [LP_W-1:0] lastFailLp;
  logic [ADDR_W-1:0] lastFailKey;

  always_ff @(posedge clk) begin
    if (!resetn) begin
      lastPassValid <= 1'b0;
      lastPassLp <= '0;
      lastPassKey <= '0;
      registeredSincePass <= '0;
      lastFailValid <= 1'b0;
      lastFailLp <= '0;
      lastFailKey <= '0;
    end else if (commitValid) begin
      if (pass) begin
        lastPassValid <= 1'b1;
        lastPassLp <= lpIndex;
        lastPassKey <= commitKey;
        registeredSincePass <= '0;
      end
      if (doRegister)
        registeredSincePass[lpIndex] <= 1'b1;
      if (commitStore && !pass && lpKnown) begin
        lastFailValid <= 1'b1;
        lastFailLp <= lpIndex;
        lastFailKey <= commitKey;
      end
    end
  end

  EXCL_SECOND_PASS_NEEDS_REGISTRATION: assert property (
    @(posedge clk) disable iff (!resetn)
    commitValid && pass && lastPassValid && (lpIndex != lastPassLp)
    && (commitKey == lastPassKey)
      |-> registeredSincePass[lpIndex]);

  for (genvar m = 0; m < AMON; m++) begin : per_monitor
    if (ADDR_CHECK) begin : address
      EXCL_PASS_CLEARS_SAME_LOCATION: assert property (
        @(posedge clk) disable iff (!resetn)
        commitValid && pass && amValid[m] && (amLp[m] != lpIndex)
        && (amKey[m] == commitKey)
          |=> !amValid[m]);

      EXCL_PASS_KEEPS_OTHER_LOCATIONS: assert property (
        @(posedge clk) disable iff (!resetn)
        commitValid && pass && amValid[m] && (amKey[m] != commitKey)
          |=> amValid[m]);
    end

    for (genvar n = m + 1; n < AMON; n++) begin : pairs
      EXCL_ONE_MONITOR_PER_LP: assert property (
        @(posedge clk) disable iff (!resetn)
        !(amValid[m] && amValid[n] && (amLp[m] == amLp[n])));
    end
  end

  EXCL_FAIL_REREGISTERS: assert property (
    @(posedge clk) disable iff (!resetn)
    commitValid && commitStore && !pass && lpKnown && !registerBlocked
      |=> lpBit[$past(lpIndex)]);

  EXCL_LPID_IN_RANGE: assert property (
    @(posedge clk) disable iff (!resetn)
    commitValid && (commitLoad || commitStore) && knownRequester |-> lpKnown);

  EXCL_PASS: cover property (
    @(posedge clk) disable iff (!resetn)
    commitValid && pass);

  EXCL_FAIL_REGISTERS: cover property (
    @(posedge clk) disable iff (!resetn)
    commitValid && commitStore && !pass && doRegister);

  EXCL_FAIL_THEN_PASS: cover property (
    @(posedge clk) disable iff (!resetn)
    commitValid && pass && lastFailValid && (lastFailLp == lpIndex)
    && (lastFailKey == commitKey));

  EXCL_TWO_LPS_ONE_LOCATION: cover property (
    @(posedge clk) disable iff (!resetn)
    commitValid && commitStore && lastPassValid && (lpIndex != lastPassLp)
    && (commitKey == lastPassKey));

  EXCL_TWO_LPS_TWO_LOCATIONS_PASS: cover property (
    @(posedge clk) disable iff (!resetn)
    commitValid && pass && lastPassValid && (lpIndex != lastPassLp)
    && (commitKey != lastPassKey));

  EXCL_ADDRESS_MISMATCH_FAIL: cover property (
    @(posedge clk) disable iff (!resetn)
    commitValid && commitStore && !pass && lpKnown && !lpBit[lpIndex]);
endmodule

bind chi_excl_mon chi_excl_sva #(
  .NUM_LP(NUM_LP),
  .LP_W(LP_W),
  .AMON(AMON),
  .AMON_W(AMON_W),
  .ADDR_W(ADDR_W),
  .ADDR_CHECK(ADDR_CHECK)
) chi_excl_assertions (
  .clk(clk),
  .resetn(resetn),
  .commitValid(commitValid),
  .commitLoad(commitLoad),
  .commitStore(commitStore),
  .commitKey(commitKey),
  .knownRequester(knownRequester),
  .registerBlocked(registerBlocked),
  .lpKnown(lpKnown),
  .lpIndex(lpIndex),
  .pass(pass),
  .doRegister(doRegister),
  .lpBit(lpBit),
  .amValid(amValid),
  .amKey(amKey),
  .amLp(amLp)
);
