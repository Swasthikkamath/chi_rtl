// Inclusive, precise snoop filter (directory) of one HN-F.
//
// Each way records which RN-Fs may hold a location and whether one of them
// may hold it in an owning state (UC, UD or SD). An RN-F may drop a clean
// copy silently (IHI 0050H B4.6), so the sharer vector is a superset: a stale
// bit costs a snoop that is answered SnpResp_I, never a missed copy.
//
// Lookup is combinational and serves the one entry that starts each cycle.
// Because entries for one location run one at a time, the state an entry
// reads stays valid until that entry writes it back.
//
// An update that needs a way in a full set evicts one. The HN-F supplies the
// ways whose location an active transaction holds, and those are never
// chosen. The evicted location, with its sharers, goes to the victim buffer,
// which snoops it out with SnpCleanInvalid and writes back any Dirty data
// before anything else may touch the location (IHI 0050H B4.4: a back
// invalidation uses SnpUnique or SnpCleanInvalid). When every unlocked way
// would need a victim entry and none is free, the update waits.
//
// A key is {PAS, line}; the set index comes from the line, so every PAS of a
// line shares a set. Lookup also reports another PAS of the same line held
// in the set (an alias), and an update with updateEvict moves the named
// location to the victim buffer: a physical-aliasing CMO uses the pair to
// clean its line in every PAS (IHI 0050H B4.2.2.1).
//
// An RN-F that has left system coherency (IHI 0050H B15) is hidden at once:
// liveMask removes it from every lookup, update and eviction. A walk over
// every set then removes its bits from the arrays, one set per cycle;
// cleared[r] says that the walk begun after r left has finished, and drops
// when r leaves again.
//
// With CFG.rasEn each way carries SECDED check bits. A single-bit error is
// corrected wherever the way is read, and the way is rewritten corrected by
// the next update of its set or by the walk, which then runs continuously as
// a patrol scrub. A double-bit error makes the way dead: it matches no
// location, is never replaced, and every lookup of its set reports
// lookupError, so the HN-F snoops every live RN-F rather than trust what the
// way recorded. Each error is reported once: a correction when the corrected
// way is written back, an uncorrectable error when the way is first found
// dead.
module chi_snoop_filter #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned ENTRIES = CFG.snpFilterEntries,
  parameter int unsigned WAYS = CFG.snpFilterWays,
  parameter int unsigned NUM_RNF = (CFG.numRnf > 0) ? CFG.numRnf : 1,
  parameter int unsigned KEY_W = CFG.addrW - 6,
  // Line bits at the bottom of the key; the rest is PAS.
  parameter int unsigned LINE_W = KEY_W,
  parameter int unsigned RNF_W = chi_pkg::clog2Min1(NUM_RNF)
) (
  input  logic clk,
  input  logic resetn,
  // RN-Fs inside system coherency.
  input  logic [NUM_RNF-1:0] liveMask,
  output logic [NUM_RNF-1:0] cleared,
  input  logic [KEY_W-1:0] lookupKey,
  output logic lookupHit,
  // A dead way shares the set: every live RN-F may hold the location.
  output logic lookupError,
  output logic [NUM_RNF-1:0] lookupSharers,
  output logic lookupOwnerValid,
  output logic [RNF_W-1:0] lookupOwner,
  output logic lookupAliasValid,
  output logic [KEY_W-1:0] lookupAliasKey,
  input  logic updateValid,
  // Move the location updateKey names to the victim buffer.
  input  logic updateEvict,
  input  logic [KEY_W-1:0] updateKey,
  // A zero sharer vector removes the location.
  input  logic [NUM_RNF-1:0] updateSharers,
  input  logic updateOwnerValid,
  input  logic [RNF_W-1:0] updateOwner,
  // Keys of the ways in the update set, so the HN-F can mark the locked ones.
  output logic [WAYS-1:0][KEY_W-1:0] updateSetKeys,
  output logic [WAYS-1:0] updateSetValid,
  input  logic [WAYS-1:0] updateLockedWays,
  input  logic victimReady,
  output logic updateReady,
  output logic victimValid,
  output logic [KEY_W-1:0] victimKey,
  output logic [NUM_RNF-1:0] victimSharers,
  output logic victimOwnerValid,
  output logic [RNF_W-1:0] victimOwner,
  // RAS events, one of each kind per cycle at most.
  output logic eccCorrected,
  output logic eccUncorrected,
  output logic [KEY_W-1:0] eccKey
);
  import chi_pkg::*;

  localparam int unsigned SETS = (ENTRIES / WAYS) > 0 ? (ENTRIES / WAYS) : 1;
  localparam int unsigned SET_W = clog2Min1(SETS);
  localparam int unsigned WAY_W = clog2Min1(WAYS);
  localparam int unsigned TAG_W = KEY_W - SET_W;
  localparam int unsigned TAG_LINE_W = (LINE_W > SET_W) ? (LINE_W - SET_W) : 1;

  typedef struct packed {
    logic               valid;
    logic [TAG_W-1:0]   tag;
    logic [NUM_RNF-1:0] sharers;
    logic               ownerValid;
    logic [RNF_W-1:0]   owner;
  } way_t;

  localparam int unsigned ENTRY_W = $bits(way_t);
  localparam int unsigned CHUNKS = (ENTRY_W + 63) / 64;
  localparam int unsigned ECC_W = 8 * CHUNKS;

  way_t wayRam [SETS][WAYS];
  logic [ECC_W-1:0] eccRam [SETS][WAYS];
  logic deadRam [SETS][WAYS];
  logic [WAY_W-1:0] replaceWay [SETS];

  // The stored way, corrected; corrected and bad report a single-bit and a
  // double-bit error.
  function automatic way_t wayRead(
    input way_t stored,
    input logic [ECC_W-1:0] check,
    output logic corrected,
    output logic bad
  );
    logic [CHUNKS*64-1:0] bits;
    logic [CHUNKS*64-1:0] fixed;
    corrected = 1'b0;
    bad = 1'b0;
    bits = '0;
    bits[ENTRY_W-1:0] = stored;
    fixed = bits;
    if (CFG.rasEn)
      for (int unsigned c = 0; c < CHUNKS; c++) begin
        logic chunkCorrected;
        logic chunkBad;
        fixed[c*64 +: 64] = secdedDecode(bits[c*64 +: 64], check[c*8 +: 8],
                                         chunkCorrected, chunkBad);
        if (chunkCorrected)
          corrected = 1'b1;
        if (chunkBad)
          bad = 1'b1;
      end
    return way_t'(fixed[ENTRY_W-1:0]);
  endfunction

  function automatic logic [ECC_W-1:0] wayCheck(input way_t w);
    logic [CHUNKS*64-1:0] bits;
    logic [ECC_W-1:0] check;
    bits = '0;
    bits[ENTRY_W-1:0] = w;
    check = '0;
    if (CFG.rasEn)
      for (int unsigned c = 0; c < CHUNKS; c++)
        check[c*8 +: 8] = secdedEncode(bits[c*64 +: 64]);
    return check;
  endfunction

  // A way as kept for the live RN-Fs: other bits cleared, and the location
  // removed when no sharer is left.
  function automatic way_t wayLive(input way_t w, input logic [NUM_RNF-1:0] live);
    way_t result;
    result = w;
    result.sharers = w.sharers & live;
    result.ownerValid = w.ownerValid && live[w.owner] && result.sharers[w.owner];
    if (result.sharers == '0) begin
      result.valid = 1'b0;
      result.ownerValid = 1'b0;
    end
    return result;
  endfunction

  // ---------------------------------------------------------------------
  // Lookup.
  // ---------------------------------------------------------------------
  logic [SET_W-1:0] lookupSet;
  logic [TAG_W-1:0] lookupTag;
  logic [WAYS-1:0] lookupBad;

  always_comb begin
    lookupSet = lookupKey[SET_W-1:0];
    lookupTag = lookupKey[KEY_W-1:SET_W];
    lookupHit = 1'b0;
    lookupError = 1'b0;
    lookupSharers = '0;
    lookupOwnerValid = 1'b0;
    lookupOwner = '0;
    lookupAliasValid = 1'b0;
    lookupAliasKey = '0;
    lookupBad = '0;
    for (int unsigned way = 0; way < WAYS; way++) begin
      way_t w;
      logic wayCorrected;
      logic wayBad;
      w = wayRead(wayRam[lookupSet][way], eccRam[lookupSet][way],
                  wayCorrected, wayBad);
      lookupBad[way] = wayBad && !deadRam[lookupSet][way];
      if (deadRam[lookupSet][way] || wayBad) begin
        lookupError = 1'b1;
      end else begin
        if (w.valid && (w.tag == lookupTag)) begin
          lookupHit = 1'b1;
          lookupSharers = w.sharers & liveMask;
          lookupOwnerValid = w.ownerValid && liveMask[w.owner];
          lookupOwner = w.owner;
        end
        if ((LINE_W < KEY_W) && w.valid && (w.tag != lookupTag)
            && (w.tag[TAG_LINE_W-1:0] == lookupTag[TAG_LINE_W-1:0])) begin
          lookupAliasValid = 1'b1;
          lookupAliasKey = {w.tag, lookupSet};
        end
      end
    end
    if (lookupError) begin
      lookupHit = 1'b1;
      lookupSharers = liveMask;
      lookupOwnerValid = 1'b0;
    end
  end

  // ---------------------------------------------------------------------
  // Update.
  // ---------------------------------------------------------------------
  logic [SET_W-1:0] updateSet;
  logic [TAG_W-1:0] updateTag;
  way_t updateWays [WAYS];
  logic [WAYS-1:0] updateWayCorrected;
  logic [WAYS-1:0] updateWayBad;
  logic [WAYS-1:0] updateWayDead;
  logic updateHit;
  logic [WAY_W-1:0] updateHitWay;
  logic freeWayFound;
  logic [WAY_W-1:0] freeWay;
  logic victimFound;
  logic [WAY_W-1:0] victimWay;
  logic writeWay;
  logic [WAY_W-1:0] targetWay;
  logic removeLocation;
  logic [WAY_W-1:0] victimSelWay;
  logic [NUM_RNF-1:0] liveSharers;
  way_t writtenWay;
  logic updateWrite;
  // Another valid way already holds the location an update writes; the
  // bound assertion requires this never to happen.
  logic updateDuplicate;
  int unsigned candidate;

  always_comb begin
    updateSet = updateKey[SET_W-1:0];
    updateTag = updateKey[KEY_W-1:SET_W];
    updateHit = 1'b0;
    updateHitWay = '0;
    freeWayFound = 1'b0;
    freeWay = '0;
    for (int unsigned way = 0; way < WAYS; way++) begin
      logic wayCorrected;
      logic wayBad;
      updateWays[way] = wayRead(wayRam[updateSet][way], eccRam[updateSet][way],
                                wayCorrected, wayBad);
      updateWayCorrected[way] = wayCorrected && !wayBad;
      updateWayBad[way] = wayBad && !deadRam[updateSet][way];
      updateWayDead[way] = wayBad || deadRam[updateSet][way];
      updateSetKeys[way] = {updateWays[way].tag, updateSet};
      updateSetValid[way] = updateWays[way].valid || updateWayDead[way];
      if (!updateWayDead[way] && updateWays[way].valid
          && (updateWays[way].tag == updateTag)) begin
        updateHit = 1'b1;
        updateHitWay = WAY_W'(way);
      end
      if (!freeWayFound && !updateWayDead[way] && !updateWays[way].valid) begin
        freeWayFound = 1'b1;
        freeWay = WAY_W'(way);
      end
    end

    // Victim: the first unlocked, live way at or after the rotating pointer.
    victimFound = 1'b0;
    victimWay = '0;
    candidate = 0;
    for (int unsigned offset = 0; offset < WAYS; offset++) begin
      candidate = int'(replaceWay[updateSet]) + offset;
      if (candidate >= WAYS)
        candidate = candidate - WAYS;
      if (!victimFound && !updateLockedWays[candidate]
          && !updateWayDead[candidate]) begin
        victimFound = 1'b1;
        victimWay = WAY_W'(candidate);
      end
    end

    liveSharers = updateSharers & liveMask;
    removeLocation = updateEvict || (liveSharers == '0);
    writeWay = 1'b0;
    targetWay = '0;
    victimValid = 1'b0;
    updateReady = 1'b0;
    victimSelWay = victimWay;
    if (updateEvict) begin
      // Nothing to evict once the location is gone.
      updateReady = !updateHit || victimReady;
      writeWay = updateHit;
      targetWay = updateHitWay;
      victimSelWay = updateHitWay;
      victimValid = updateValid && updateHit;
    end else if (removeLocation) begin
      updateReady = 1'b1;
      writeWay = updateHit;
      targetWay = updateHitWay;
    end else if (updateHit) begin
      updateReady = 1'b1;
      writeWay = 1'b1;
      targetWay = updateHitWay;
    end else if (freeWayFound) begin
      updateReady = 1'b1;
      writeWay = 1'b1;
      targetWay = freeWay;
    end else if (victimFound && victimReady) begin
      updateReady = 1'b1;
      writeWay = 1'b1;
      targetWay = victimWay;
      victimValid = updateValid;
    end
    updateWrite = updateValid && updateReady;

    writtenWay.valid = !removeLocation;
    writtenWay.tag = updateTag;
    writtenWay.sharers = liveSharers;
    writtenWay.ownerValid = updateOwnerValid && liveMask[updateOwner]
                            && !removeLocation;
    writtenWay.owner = updateOwner;

    updateDuplicate = 1'b0;
    for (int unsigned way = 0; way < WAYS; way++)
      if ((WAY_W'(way) != targetWay) && !updateWayDead[way]
          && updateWays[way].valid && (updateWays[way].tag == updateTag))
        updateDuplicate = 1'b1;

    victimKey = {updateWays[victimSelWay].tag, updateSet};
    victimSharers = updateWays[victimSelWay].sharers & liveMask;
    victimOwnerValid = updateWays[victimSelWay].ownerValid
                       && liveMask[updateWays[victimSelWay].owner];
    victimOwner = updateWays[victimSelWay].owner;
  end

  // ---------------------------------------------------------------------
  // Walk: removes the bits of RN-Fs that left, and with rasEn scrubs.
  // ---------------------------------------------------------------------
  logic [NUM_RNF-1:0] liveLast;
  logic [NUM_RNF-1:0] pendingClear;
  logic [NUM_RNF-1:0] walkClear;
  logic walking;
  logic [SET_W-1:0] walkSet;
  way_t walkWays [WAYS];
  logic [WAYS-1:0] walkWayCorrected;
  logic [WAYS-1:0] walkWayBad;
  logic [WAYS-1:0] walkWayDead;
  logic walkChange;
  logic walkWrite;
  logic walkAdvance;
  logic walkStart;
  logic [NUM_RNF-1:0] departed;

  always_comb begin
    departed = liveLast & ~liveMask;
    walkChange = 1'b0;
    for (int unsigned way = 0; way < WAYS; way++) begin
      logic wayCorrected;
      logic wayBad;
      walkWays[way] = wayRead(wayRam[walkSet][way], eccRam[walkSet][way],
                              wayCorrected, wayBad);
      walkWayCorrected[way] = wayCorrected && !wayBad;
      walkWayBad[way] = wayBad && !deadRam[walkSet][way];
      walkWayDead[way] = wayBad || deadRam[walkSet][way];
      if (walking && !walkWayDead[way]
          && (walkWayCorrected[way]
              || (wayLive(walkWays[way], liveMask) != walkWays[way])))
        walkChange = 1'b1;
    end
    // The walk writes its set when something changes there, but never the
    // set an update writes this cycle; it then tries again.
    walkWrite = walkChange && !(updateWrite && (updateSet == walkSet));
    walkAdvance = walking && (!walkChange || walkWrite);
    walkStart = !walking && ((pendingClear != '0) || CFG.rasEn);
  end

  // ---------------------------------------------------------------------
  // RAS reporting: the access that finds a new dead way, else a corrected
  // way being written back.
  // ---------------------------------------------------------------------
  logic [WAY_W-1:0] firstBadLookup;
  logic [WAY_W-1:0] firstBadUpdate;
  logic [WAY_W-1:0] firstBadWalk;
  always_comb begin
    firstBadLookup = '0;
    firstBadUpdate = '0;
    firstBadWalk = '0;
    for (int unsigned way = WAYS; way > 0; way--) begin
      if (lookupBad[way-1])
        firstBadLookup = WAY_W'(way - 1);
      if (updateWayBad[way-1])
        firstBadUpdate = WAY_W'(way - 1);
      if (walkWayBad[way-1])
        firstBadWalk = WAY_W'(way - 1);
    end
    eccUncorrected = CFG.rasEn
                     && ((lookupBad != '0) || (updateWayBad != '0)
                         || (walking && (walkWayBad != '0)));
    eccCorrected = CFG.rasEn
                   && ((updateWrite && (updateWayCorrected != '0))
                       || (walkWrite && (walkWayCorrected != '0)));
    if (lookupBad != '0)
      eccKey = {wayRam[lookupSet][firstBadLookup].tag, lookupSet};
    else if (updateWayBad != '0)
      eccKey = {wayRam[updateSet][firstBadUpdate].tag, updateSet};
    else if (walking && (walkWayBad != '0))
      eccKey = {wayRam[walkSet][firstBadWalk].tag, walkSet};
    else if (updateWrite && (updateWayCorrected != '0))
      eccKey = updateKey;
    else
      eccKey = {walkWays[0].tag, walkSet};
  end

  logic [NUM_RNF-1:0] clearedReg;
  // An RN-F stops counting as cleared in the cycle it leaves.
  assign cleared = clearedReg & ~departed;

  always_ff @(posedge clk) begin
    if (!resetn) begin
      for (int unsigned set = 0; set < SETS; set++) begin
        replaceWay[set] <= '0;
        for (int unsigned way = 0; way < WAYS; way++) begin
          wayRam[set][way] <= '0;
          eccRam[set][way] <= '0;
          deadRam[set][way] <= 1'b0;
        end
      end
      liveLast <= '0;
      pendingClear <= '0;
      walkClear <= '0;
      walking <= 1'b0;
      walkSet <= '0;
      // The directory starts empty, so nothing of any RN-F is held.
      clearedReg <= '1;
    end else begin
      liveLast <= liveMask;

      // A newly found double-bit error kills its way.
      for (int unsigned way = 0; way < WAYS; way++) begin
        if (lookupBad[way])
          deadRam[lookupSet][way] <= 1'b1;
        if (updateWayBad[way])
          deadRam[updateSet][way] <= 1'b1;
        if (walking && walkWayBad[way])
          deadRam[walkSet][way] <= 1'b1;
      end

      if (updateWrite) begin
        if (writeWay) begin
          wayRam[updateSet][targetWay] <= writtenWay;
          eccRam[updateSet][targetWay] <= wayCheck(writtenWay);
        end
        // The other ways of the set go back corrected.
        for (int unsigned way = 0; way < WAYS; way++)
          if ((!writeWay || (WAY_W'(way) != targetWay))
              && updateWayCorrected[way]) begin
            wayRam[updateSet][way] <= updateWays[way];
            eccRam[updateSet][way] <= wayCheck(updateWays[way]);
          end
        if (victimValid && !updateEvict)
          replaceWay[updateSet] <= (int'(victimWay) == (WAYS - 1))
                                   ? '0 : (victimWay + 1'b1);
      end

      if (walkWrite)
        for (int unsigned way = 0; way < WAYS; way++)
          if (!walkWayDead[way]) begin
            wayRam[walkSet][way] <= wayLive(walkWays[way], liveMask);
            eccRam[walkSet][way] <= wayCheck(wayLive(walkWays[way], liveMask));
          end

      // Departures wait for the next walk to begin; a walk removes every
      // RN-F it began without.
      pendingClear <= (walkStart ? '0 : pendingClear) | departed;
      clearedReg <= clearedReg & ~departed;
      if (walkStart) begin
        walking <= 1'b1;
        walkSet <= '0;
        walkClear <= pendingClear;
      end else if (walkAdvance) begin
        if (int'(walkSet) == (SETS - 1)) begin
          walking <= 1'b0;
          clearedReg <= (clearedReg & ~departed) | (walkClear & ~liveMask);
        end else begin
          walkSet <= walkSet + 1'b1;
        end
      end
    end
  end
endmodule
