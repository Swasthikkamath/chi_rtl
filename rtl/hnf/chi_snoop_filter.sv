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
  input  logic [KEY_W-1:0] lookupKey,
  output logic lookupHit,
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
  output logic [RNF_W-1:0] victimOwner
);
  import chi_pkg::*;

  localparam int unsigned SETS = (ENTRIES / WAYS) > 0 ? (ENTRIES / WAYS) : 1;
  localparam int unsigned SET_W = clog2Min1(SETS);
  localparam int unsigned WAY_W = clog2Min1(WAYS);
  localparam int unsigned TAG_W = KEY_W - SET_W;
  localparam int unsigned TAG_LINE_W = (LINE_W > SET_W) ? (LINE_W - SET_W) : 1;

  logic validRam [SETS][WAYS];
  logic [TAG_W-1:0] tagRam [SETS][WAYS];
  logic [NUM_RNF-1:0] sharerRam [SETS][WAYS];
  logic ownerValidRam [SETS][WAYS];
  logic [RNF_W-1:0] ownerRam [SETS][WAYS];
  logic [WAY_W-1:0] replaceWay [SETS];

  logic [SET_W-1:0] lookupSet;
  logic [TAG_W-1:0] lookupTag;
  logic [SET_W-1:0] updateSet;
  logic [TAG_W-1:0] updateTag;
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
  // Another valid way already holds the location an update writes; the
  // bound assertion requires this never to happen.
  logic updateDuplicate;
  int unsigned candidate;

  always_comb begin
    lookupSet = lookupKey[SET_W-1:0];
    lookupTag = lookupKey[KEY_W-1:SET_W];
    lookupHit = 1'b0;
    lookupSharers = '0;
    lookupOwnerValid = 1'b0;
    lookupOwner = '0;
    lookupAliasValid = 1'b0;
    lookupAliasKey = '0;
    for (int unsigned way = 0; way < WAYS; way++) begin
      if (validRam[lookupSet][way] && (tagRam[lookupSet][way] == lookupTag)) begin
        lookupHit = 1'b1;
        lookupSharers = sharerRam[lookupSet][way];
        lookupOwnerValid = ownerValidRam[lookupSet][way];
        lookupOwner = ownerRam[lookupSet][way];
      end
      if ((LINE_W < KEY_W) && validRam[lookupSet][way]
          && (tagRam[lookupSet][way] != lookupTag)
          && (tagRam[lookupSet][way][TAG_LINE_W-1:0]
              == lookupTag[TAG_LINE_W-1:0])) begin
        lookupAliasValid = 1'b1;
        lookupAliasKey = {tagRam[lookupSet][way], lookupSet};
      end
    end
  end

  always_comb begin
    updateSet = updateKey[SET_W-1:0];
    updateTag = updateKey[KEY_W-1:SET_W];
    updateHit = 1'b0;
    updateHitWay = '0;
    freeWayFound = 1'b0;
    freeWay = '0;
    for (int unsigned way = 0; way < WAYS; way++) begin
      updateSetKeys[way] = {tagRam[updateSet][way], updateSet};
      updateSetValid[way] = validRam[updateSet][way];
      if (validRam[updateSet][way] && (tagRam[updateSet][way] == updateTag)) begin
        updateHit = 1'b1;
        updateHitWay = WAY_W'(way);
      end
      if (!freeWayFound && !validRam[updateSet][way]) begin
        freeWayFound = 1'b1;
        freeWay = WAY_W'(way);
      end
    end

    // Victim: the first unlocked way at or after the rotating pointer.
    victimFound = 1'b0;
    victimWay = '0;
    candidate = 0;
    for (int unsigned offset = 0; offset < WAYS; offset++) begin
      candidate = int'(replaceWay[updateSet]) + offset;
      if (candidate >= WAYS)
        candidate = candidate - WAYS;
      if (!victimFound && !updateLockedWays[candidate]) begin
        victimFound = 1'b1;
        victimWay = WAY_W'(candidate);
      end
    end

    removeLocation = updateEvict || (updateSharers == '0);
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

    updateDuplicate = 1'b0;
    for (int unsigned way = 0; way < WAYS; way++)
      if ((WAY_W'(way) != targetWay) && validRam[updateSet][way]
          && (tagRam[updateSet][way] == updateTag))
        updateDuplicate = 1'b1;

    victimKey = {tagRam[updateSet][victimSelWay], updateSet};
    victimSharers = sharerRam[updateSet][victimSelWay];
    victimOwnerValid = ownerValidRam[updateSet][victimSelWay];
    victimOwner = ownerRam[updateSet][victimSelWay];
  end

  always_ff @(posedge clk) begin
    if (!resetn) begin
      for (int unsigned set = 0; set < SETS; set++) begin
        replaceWay[set] <= '0;
        for (int unsigned way = 0; way < WAYS; way++) begin
          validRam[set][way] <= 1'b0;
          tagRam[set][way] <= '0;
          sharerRam[set][way] <= '0;
          ownerValidRam[set][way] <= 1'b0;
          ownerRam[set][way] <= '0;
        end
      end
    end else if (updateValid && updateReady && writeWay) begin
      validRam[updateSet][targetWay] <= !removeLocation;
      tagRam[updateSet][targetWay] <= updateTag;
      sharerRam[updateSet][targetWay] <= updateSharers;
      ownerValidRam[updateSet][targetWay] <= updateOwnerValid && !removeLocation;
      ownerRam[updateSet][targetWay] <= updateOwner;
      if (victimValid && !updateEvict)
        replaceWay[updateSet] <= (int'(victimWay) == (WAYS - 1))
                                 ? '0 : (victimWay + 1'b1);
    end
  end
endmodule
