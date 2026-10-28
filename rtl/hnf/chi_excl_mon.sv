// Exclusive monitor of a Home: the PoC monitor of an HN-F for Snoopable
// locations and the System monitor for Non-snoopable ones (IHI 0050H B6.2).
//
// A Logical Processor (LP) is a Requester ordinal, from the SrcID, with an
// LPID below RN_NUM_LP of that Requester. Every exclusive-capable LP has the
// single bit B6.2.2 requires of any monitor, so forward progress never
// depends on how many address monitors exist. With exclAddrCheck each LP
// also has an address monitor, the {line, PAS} key of its sequence, which
// lets a store pass after another LP's store to a different location
// (B6.2.2). In EXCL_PER_LP mode every LP has its own address monitor; in
// EXCL_POOL mode exclMonitors of them are shared in least-recently-used
// order, and losing one only takes that enhancement away from its LP.
//
// One commit per cycle, made by the Home after its same-location ordering,
// decides and updates everything at once:
//   load   an Exclusive Load registers the LP: bit set, address recorded.
//   store  an Exclusive Store passes if the LP's bit is set, or its address
//          monitor holds the store's location. A pass clears every other
//          LP's bit, and every other address monitor holding that location
//          (B6.2.1, B6.2.2); the passing LP stays registered. A fail
//          registers the LP, so a retry can pass (B6.2.1).
//   update a write to a Non-snoopable location by another LP resets the
//          System monitors of that location (B6.2.4): LPs whose address
//          monitor holds it, or whose location is unknown, lose their bit.
//          Without exclAddrCheck no location is known, so every other LP
//          loses its bit.
// While a passing Exclusive Store from one LP waits for its CompAck, no
// other LP registers (B6.2.1); its load or failed store is answered as not
// registered and it tries again.
// A store from an LP that is not identifiable is handled as one from an LP
// that never registered (B6.2.1): it fails and registers nothing.
module chi_excl_mon #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned NUM_REQUESTERS = 1,
  parameter logic [chi_cfg_pkg::CHI_MAX_NODEID_W-1:0]
    REQUESTER_NODE_IDS [NUM_REQUESTERS] = '{default:'0},
  // Exclusive-capable LPs of each Requester, in Requester order, and their
  // sum.
  parameter int unsigned RN_NUM_LP [NUM_REQUESTERS] = '{default:1},
  parameter int unsigned NUM_LP = NUM_REQUESTERS,
  // The location key: the line and, where the Home keys by it, the PAS.
  parameter int unsigned ADDR_W = CFG.addrW - 6
) (
  input  logic clk,
  input  logic resetn,
  input  logic commitValid,
  input  logic commitLoad,
  input  logic commitStore,
  input  logic commitUpdate,
  input  logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] commitSrcId,
  input  logic [chi_cfg_pkg::CHI_MAX_GROUPID_W-1:0] commitLpid,
  input  logic [ADDR_W-1:0] commitKey,
  // A passing Exclusive Store from another LP still waits for CompAck.
  input  logic registerBlocked,
  // The store passed; the load or the failed store registered.
  output logic pass,
  output logic registered,
  // The request comes from an exclusive-capable LP.
  output logic lpKnown,
  output logic [chi_pkg::clog2Min1(NUM_LP)-1:0] lpIndex
);
  import chi_cfg_pkg::*;
  import chi_pkg::*;

  function automatic int unsigned lpCount(input int unsigned counts [NUM_REQUESTERS]);
    int unsigned total;
    total = 0;
    for (int unsigned r = 0; r < NUM_REQUESTERS; r++)
      total += counts[r];
    return (total > 0) ? total : 1;
  endfunction

  function automatic int unsigned lpBase(
    input int unsigned counts [NUM_REQUESTERS],
    input int unsigned requester
  );
    int unsigned base;
    base = 0;
    for (int unsigned r = 0; r < NUM_REQUESTERS; r++)
      if (r < requester)
        base += counts[r];
    return base;
  endfunction

  localparam int unsigned LP_W = clog2Min1(NUM_LP);
  localparam bit ADDR_CHECK = CFG.exclAddrCheck;
  localparam bit POOL = CFG.exclMonMode == EXCL_POOL;
  localparam int unsigned POOL_SIZE = (CFG.exclMonitors > 0) ? CFG.exclMonitors : 1;
  localparam int unsigned AMON = POOL ? POOL_SIZE : NUM_LP;
  localparam int unsigned AMON_W = clog2Min1(AMON);

  generate
    begin : chi_cfg_check
      initial begin
        if (NUM_LP != lpCount(RN_NUM_LP))
          $fatal(1, "chi_excl_mon NUM_LP (%0d) must be the sum of RN_NUM_LP (%0d)",
                 NUM_LP, lpCount(RN_NUM_LP));
        for (int unsigned r = 0; r < NUM_REQUESTERS; r++)
          if (RN_NUM_LP[r] > (1 << CFG.lpidW))
            $fatal(1, "RN_NUM_LP[%0d] is %0d but an LPID of %0d bits names only %0d LPs",
                   r, RN_NUM_LP[r], CFG.lpidW, 1 << CFG.lpidW);
      end
    end
  endgenerate

  // The minimum monitor: one bit per exclusive-capable LP.
  logic [NUM_LP-1:0] lpBit;
  // Address monitors. In PER_LP mode monitor i belongs to LP i.
  logic [AMON-1:0] amValid;
  logic [AMON-1:0][ADDR_W-1:0] amKey;
  logic [AMON-1:0][LP_W-1:0] amLp;
  logic [AMON-1:0][AMON_W-1:0] amAge;   // POOL: 0 is the most recent

  // The LP committing. knownRequester is for the bound LPID-range check.
  logic knownRequester;
  always_comb begin
    lpKnown = 1'b0;
    lpIndex = '0;
    knownRequester = 1'b0;
    for (int unsigned r = 0; r < NUM_REQUESTERS; r++)
      if (commitSrcId == CHI_NODEID_SLOT_W'(REQUESTER_NODE_IDS[r])) begin
        knownRequester = 1'b1;
        if (int'(commitLpid) < RN_NUM_LP[r]) begin
          lpKnown = 1'b1;
          lpIndex = LP_W'(lpBase(RN_NUM_LP, r) + int'(commitLpid));
        end
      end
  end

  // The LP's address monitor, and in POOL mode the one to replace.
  logic ownFound;
  logic [AMON_W-1:0] ownMonitor;
  logic [AMON_W-1:0] victimMonitor;

  always_comb begin
    ownFound = 1'b0;
    ownMonitor = '0;
    victimMonitor = '0;
    if (POOL) begin
      for (int unsigned m = 0; m < AMON; m++)
        if (amValid[m] && (amLp[m] == lpIndex)) begin
          ownFound = 1'b1;
          ownMonitor = AMON_W'(m);
        end
      // A free monitor, else the least recently used.
      begin
        logic freeFound;
        logic [AMON_W-1:0] oldest;
        freeFound = 1'b0;
        oldest = '0;
        for (int unsigned m = 0; m < AMON; m++) begin
          if (!freeFound && !amValid[m]) begin
            freeFound = 1'b1;
            victimMonitor = AMON_W'(m);
          end
          if (amAge[m] > oldest)
            oldest = amAge[m];
        end
        if (!freeFound)
          for (int unsigned m = AMON; m > 0; m--)
            if (amAge[m-1] == oldest)
              victimMonitor = AMON_W'(m - 1);
      end
    end else begin
      ownFound = amValid[AMON_W'(lpIndex)];
      ownMonitor = AMON_W'(lpIndex);
    end
  end

  // Decision.
  logic doRegister;
  always_comb begin
    pass = 1'b0;
    if (commitValid && commitStore && lpKnown)
      pass = lpBit[lpIndex]
             || (ADDR_CHECK && ownFound && (amKey[ownMonitor] == commitKey));
    doRegister = commitValid && lpKnown && !registerBlocked
                 && (commitLoad || (commitStore && !pass));
    registered = doRegister;
  end

  always_ff @(posedge clk) begin
    if (!resetn) begin
      lpBit <= '0;
      amValid <= '0;
      amKey <= '0;
      amLp <= '0;
      for (int unsigned m = 0; m < AMON; m++)
        amAge[m] <= AMON_W'(m);
    end else if (commitValid) begin
      if (pass) begin
        // Every other LP loses its bit; every other address monitor on this
        // location is reset.
        for (int unsigned lp = 0; lp < NUM_LP; lp++)
          if (LP_W'(lp) != lpIndex)
            lpBit[lp] <= 1'b0;
        if (ADDR_CHECK)
          for (int unsigned m = 0; m < AMON; m++)
            if (amValid[m] && (amLp[m] != lpIndex) && (amKey[m] == commitKey))
              amValid[m] <= 1'b0;
      end

      if (commitUpdate) begin
        // A Non-snoopable update by another LP resets the System monitors
        // of the location (B6.2.4).
        for (int unsigned lp = 0; lp < NUM_LP; lp++)
          if (!lpKnown || (LP_W'(lp) != lpIndex)) begin
            if (!ADDR_CHECK)
              lpBit[lp] <= 1'b0;
            else begin
              logic located;
              logic here;
              located = 1'b0;
              here = 1'b0;
              for (int unsigned m = 0; m < AMON; m++)
                if (amValid[m] && (amLp[m] == LP_W'(lp))) begin
                  located = 1'b1;
                  if (amKey[m] == commitKey)
                    here = 1'b1;
                end
              if (!located || here)
                lpBit[lp] <= 1'b0;
            end
          end
        if (ADDR_CHECK)
          for (int unsigned m = 0; m < AMON; m++)
            if (amValid[m] && (amKey[m] == commitKey)
                && (!lpKnown || (amLp[m] != lpIndex)))
              amValid[m] <= 1'b0;
      end

      if (doRegister) begin
        lpBit[lpIndex] <= 1'b1;
        if (ADDR_CHECK) begin
          logic [AMON_W-1:0] slot;
          slot = ownFound ? ownMonitor : (POOL ? victimMonitor : AMON_W'(lpIndex));
          amValid[slot] <= 1'b1;
          amKey[slot] <= commitKey;
          amLp[slot] <= lpIndex;
          if (POOL)
            for (int unsigned m = 0; m < AMON; m++)
              if (AMON_W'(m) == slot)
                amAge[m] <= '0;
              else if (amAge[m] < amAge[slot])
                amAge[m] <= amAge[m] + 1'b1;
        end
      end
    end
  end
endmodule
