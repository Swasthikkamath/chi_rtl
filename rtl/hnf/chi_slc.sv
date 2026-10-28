// System Level Cache slice of one HN-F.
//
// A set-associative cache of 64-byte lines keyed, like everything else in the
// Home, by {PAS, line}. A line is invalid, clean (memory holds the same data)
// or dirty (the SLC holds the only up-to-date copy below the RN-F caches).
// The data array is written as a flop array with one read and one write
// port; a synthesis flow maps it to SRAM.
//
// Ports, each serving one request per cycle:
//   lookup  tag only, combinational: the HN-F reads it for the entry that
//           starts this cycle, in the same stage as the directory lookup.
//   read    the whole line of a location, and readHit, whether it is
//           present.
//   update  write a whole line, clean or dirty, or remove a location (with
//           updateDiscard when the HN-F has already written the latest data
//           to memory, so a dirty copy is dropped rather than written back). A
//           write that misses takes an invalid way, else a victim chosen by
//           slcReplPolicy among the ways no transaction or victim entry
//           holds. A dirty line leaving the cache, by eviction or removal,
//           goes out on victim* to the HN-F's victim buffer, which writes it
//           back; so the update waits for victimReady when it needs one. A
//           clean write that finds no usable way is dropped: allocation is
//           only ever a choice.
//   maintenance  a walk over every way, started by maintStart, that writes
//           back every dirty line and, with maintInvalidate, removes every
//           line. It uses the update port when the HN-F does not, and waits
//           on a way that a transaction holds.
//
// With slcEccEn each 64-bit word of a line carries SECDED check bits: a
// single-bit error is corrected on the way out, a double-bit error poisons
// that word (IHI 0050H B9.2.3) and is reported.
//
// With CFG.rasEn each way's {valid, dirty, tag} carries SECDED check bits
// too. A single-bit error is corrected wherever the way is read and written
// back corrected when the update port next writes its set. A double-bit
// error fences the way: it matches no location and is never replaced or
// walked, so whatever it held, Dirty data included, is lost; that loss is
// reported once, on tagUncorrected.
module chi_slc #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned KEY_W = CFG.addrW - 6,
  parameter int unsigned NUM_LOCKS = 1,
  parameter int unsigned WAYS = (CFG.slcWays > 0) ? CFG.slcWays : 1,
  parameter int unsigned SETS =
    ((CFG.slcSizePerHnf / (64 * WAYS)) > 0) ? (CFG.slcSizePerHnf / (64 * WAYS)) : 1,
  parameter int unsigned SET_W = chi_pkg::clog2Min1(SETS),
  parameter int unsigned WAY_W = chi_pkg::clog2Min1(WAYS)
) (
  input  logic clk,
  input  logic resetn,
  input  logic [KEY_W-1:0] lookupKey,
  output logic lookupHit,
  output logic lookupDirty,
  input  logic readValid,
  input  logic [KEY_W-1:0] readKey,
  output logic [511:0] readData,
  output logic [7:0] readPoison,
  output logic readCorrected,
  output logic readHit,
  input  logic updateValid,
  input  logic [KEY_W-1:0] updateKey,
  input  logic updateRemove,
  input  logic updateDiscard,
  input  logic updateDirty,
  input  logic [511:0] updateData,
  input  logic [7:0] updatePoison,
  output logic updateReady,
  input  logic [NUM_LOCKS-1:0] lockValid,
  input  logic [NUM_LOCKS-1:0][KEY_W-1:0] lockKey,
  input  logic victimReady,
  output logic victimValid,
  output logic [KEY_W-1:0] victimKey,
  output logic [511:0] victimData,
  output logic [7:0] victimPoison,
  input  logic maintStart,
  input  logic maintInvalidate,
  output logic maintWalking,
  // Events, for the counters of a later stage.
  output logic eventFill,
  output logic eventDirtyEviction,
  output logic eventUncorrectable,
  // A valid line replaced by a fill.
  output logic eventEviction,
  // Tag RAS events and the key the failing access used.
  output logic tagCorrected,
  output logic tagUncorrected,
  output logic [KEY_W-1:0] tagKey
);
  import chi_cfg_pkg::*;
  import chi_pkg::*;

  localparam int unsigned TAG_W = KEY_W - SET_W;
  localparam int unsigned LINES = SETS * WAYS;
  localparam int unsigned LINE_IDX_W = clog2Min1(LINES);
  localparam int unsigned PLRU_W = (WAYS > 1) ? (WAYS - 1) : 1;
  localparam int unsigned LEVELS = (WAYS > 1) ? $clog2(WAYS) : 0;

  logic [WAYS-1:0] validRam [SETS];
  logic [WAYS-1:0] dirtyRam [SETS];
  logic [TAG_W-1:0] tagRam [SETS][WAYS];
  logic [511:0] dataRam [LINES];
  logic [63:0] eccRam [LINES];
  logic [7:0] poisonRam [LINES];
  logic [PLRU_W-1:0] plruRam [SETS];
  logic [WAYS-1:0][1:0] rrpvRam [SETS];
  logic [15:0] lfsr;

  // Maintenance walk.
  logic walking;
  logic walkInvalidate;
  logic [SET_W-1:0] walkSet;
  logic [WAY_W-1:0] walkWay;

  function automatic logic [LINE_IDX_W-1:0] lineIndex(
    input logic [SET_W-1:0] set,
    input logic [WAY_W-1:0] way
  );
    return LINE_IDX_W'(int'(set) * WAYS + int'(way));
  endfunction

  // The line as stored, corrected; poison marks words a double-bit error hit.
  function automatic logic [511:0] lineOut(
    input logic [LINE_IDX_W-1:0] index,
    output logic [7:0] poison,
    output logic corrected
  );
    logic [511:0] line;
    poison = poisonRam[index];
    corrected = 1'b0;
    line = dataRam[index];
    if (CFG.slcEccEn) begin
      for (int unsigned word = 0; word < 8; word++) begin
        logic wordCorrected;
        logic wordBad;
        line[word*64 +: 64] = secdedDecode(dataRam[index][word*64 +: 64],
                                           eccRam[index][word*8 +: 8],
                                           wordCorrected, wordBad);
        if (wordCorrected)
          corrected = 1'b1;
        if (wordBad)
          poison[word] = 1'b1;
      end
    end
    return line;
  endfunction

  function automatic logic [63:0] eccOf(input logic [511:0] line);
    logic [63:0] check;
    for (int unsigned word = 0; word < 8; word++)
      check[word*8 +: 8] = secdedEncode(line[word*64 +: 64]);
    return check;
  endfunction

  // Tree pseudo-LRU: node n has children 2n and 2n+1, and its bit points at
  // the half to replace next.
  function automatic logic [WAY_W-1:0] plruVictim(input logic [PLRU_W-1:0] bits);
    int unsigned node;
    node = 1;
    for (int unsigned level = 0; level < LEVELS; level++)
      node = node * 2 + int'(bits[node - 1]);
    return WAY_W'(node - WAYS);
  endfunction

  function automatic logic [PLRU_W-1:0] plruTouch(
    input logic [PLRU_W-1:0] bits,
    input logic [WAY_W-1:0] way
  );
    logic [PLRU_W-1:0] value;
    int unsigned node;
    int unsigned direction;
    value = bits;
    node = 1;
    for (int unsigned level = 0; level < LEVELS; level++) begin
      direction = (int'(way) >> (LEVELS - 1 - level)) & 1;
      value[node - 1] = !direction[0];
      node = node * 2 + direction;
    end
    return value;
  endfunction

  // Tag SECDED over each way's {valid, dirty, tag}, and the fenced ways.
  localparam int unsigned TSTATE_W = TAG_W + 2;
  localparam int unsigned TCHUNKS = (TSTATE_W + 63) / 64;
  localparam int unsigned TECC_W = 8 * TCHUNKS;
  logic [TECC_W-1:0] tagEccRam [SETS][WAYS];
  logic [WAYS-1:0] fenceRam [SETS];

  function automatic logic [TECC_W-1:0] tagCheck(
    input logic valid,
    input logic dirty,
    input logic [TAG_W-1:0] tag
  );
    logic [TCHUNKS*64-1:0] bits;
    logic [TECC_W-1:0] check;
    bits = '0;
    bits[TSTATE_W-1:0] = {valid, dirty, tag};
    check = '0;
    if (CFG.rasEn)
      for (int unsigned c = 0; c < TCHUNKS; c++)
        check[c*8 +: 8] = secdedEncode(bits[c*64 +: 64]);
    return check;
  endfunction

  // A way's {valid, dirty, tag} as stored, corrected.
  function automatic logic [TSTATE_W-1:0] tagRead(
    input logic [SET_W-1:0] set,
    input logic [WAY_W-1:0] way,
    output logic corrected,
    output logic bad
  );
    logic [TCHUNKS*64-1:0] bits;
    logic [TCHUNKS*64-1:0] fixed;
    corrected = 1'b0;
    bad = 1'b0;
    bits = '0;
    bits[TSTATE_W-1:0] = {validRam[set][way], dirtyRam[set][way], tagRam[set][way]};
    fixed = bits;
    if (CFG.rasEn)
      for (int unsigned c = 0; c < TCHUNKS; c++) begin
        logic chunkCorrected;
        logic chunkBad;
        fixed[c*64 +: 64] = secdedDecode(bits[c*64 +: 64],
                                         tagEccRam[set][way][c*8 +: 8],
                                         chunkCorrected, chunkBad);
        if (chunkCorrected)
          corrected = 1'b1;
        if (chunkBad)
          bad = 1'b1;
      end
    return fixed[TSTATE_W-1:0];
  endfunction

  // ---------------------------------------------------------------------
  // Lookup and read, over the corrected state; a fenced or failing way
  // takes no part.
  // ---------------------------------------------------------------------
  logic [SET_W-1:0] lookupSet;
  logic [WAY_W-1:0] lookupWay;
  logic [SET_W-1:0] readSet;
  logic [WAY_W-1:0] readWay;
  logic [WAYS-1:0] lookupBad;  // newly failing ways
  logic [WAYS-1:0] readBad;

  always_comb begin
    lookupSet = lookupKey[SET_W-1:0];
    lookupHit = 1'b0;
    lookupDirty = 1'b0;
    lookupWay = '0;
    lookupBad = '0;
    for (int unsigned way = 0; way < WAYS; way++) begin
      logic [TSTATE_W-1:0] state;
      logic wayCorrected;
      logic wayBad;
      state = tagRead(lookupSet, WAY_W'(way), wayCorrected, wayBad);
      lookupBad[way] = wayBad && !fenceRam[lookupSet][way];
      if (!wayBad && !fenceRam[lookupSet][way] && state[TSTATE_W-1]
          && (state[TAG_W-1:0] == lookupKey[KEY_W-1:SET_W])) begin
        lookupHit = 1'b1;
        lookupDirty = state[TAG_W];
        lookupWay = WAY_W'(way);
      end
    end

    readSet = readKey[SET_W-1:0];
    readHit = 1'b0;
    readWay = '0;
    readBad = '0;
    for (int unsigned way = 0; way < WAYS; way++) begin
      logic [TSTATE_W-1:0] state;
      logic wayCorrected;
      logic wayBad;
      state = tagRead(readSet, WAY_W'(way), wayCorrected, wayBad);
      readBad[way] = readValid && wayBad && !fenceRam[readSet][way];
      if (!wayBad && !fenceRam[readSet][way] && state[TSTATE_W-1]
          && (state[TAG_W-1:0] == readKey[KEY_W-1:SET_W])) begin
        readHit = 1'b1;
        readWay = WAY_W'(way);
      end
    end
    readData = lineOut(lineIndex(readSet, readWay), readPoison, readCorrected);
  end

  // ---------------------------------------------------------------------
  // Update and maintenance.
  // ---------------------------------------------------------------------
  logic [SET_W-1:0] updateSet;
  logic updateHit;
  logic [WAY_W-1:0] updateHitWay;
  logic [WAYS-1:0] lockedWays;
  logic invalidFound;
  logic [WAY_W-1:0] invalidWay;
  logic replaceFound;
  logic [WAY_W-1:0] replaceWay;
  logic doWrite;
  logic doRemove;
  logic [WAY_W-1:0] targetWay;
  logic evictDirty;
  logic walkActive;
  logic walkLocked;
  logic walkAdvance;
  logic walkClean;
  logic walkRemove;
  logic [SET_W-1:0] opSet;
  logic [WAY_W-1:0] opWay;
  logic [7:0] lineOutPoison;
  logic lineOutCorrected;
  // The corrected state of the update set and of the way the walk is on.
  logic [WAYS-1:0] upValid;
  logic [WAYS-1:0] upDirty;
  logic [TAG_W-1:0] upTag [WAYS];
  logic [WAYS-1:0] upCorrected;
  logic [WAYS-1:0] upBad;
  logic [WAYS-1:0] upDead;
  logic wkValid;
  logic wkDirty;
  logic [TAG_W-1:0] wkTag;
  logic wkCorrected;
  logic wkBad;
  logic wkDead;
  // For the bound assertions: two valid ways of the update set hold one
  // location, or a dirty line is about to leave without a write-back.
  logic setDuplicate;
  logic droppingDirty;

  always_comb begin
    updateSet = updateKey[SET_W-1:0];
    updateHit = 1'b0;
    updateHitWay = '0;
    invalidFound = 1'b0;
    invalidWay = '0;
    for (int unsigned way = 0; way < WAYS; way++) begin
      logic [TSTATE_W-1:0] state;
      logic wayCorrected;
      logic wayBad;
      state = tagRead(updateSet, WAY_W'(way), wayCorrected, wayBad);
      upValid[way] = state[TSTATE_W-1];
      upDirty[way] = state[TAG_W];
      upTag[way] = state[TAG_W-1:0];
      upCorrected[way] = wayCorrected && !wayBad;
      upBad[way] = wayBad && !fenceRam[updateSet][way];
      upDead[way] = wayBad || fenceRam[updateSet][way];
      // A dead way is never replaced.
      lockedWays[way] = upDead[way];
      for (int unsigned lock = 0; lock < NUM_LOCKS; lock++)
        if (lockValid[lock] && !upDead[way] && upValid[way]
            && (lockKey[lock] == {upTag[way], updateSet}))
          lockedWays[way] = 1'b1;
      if (!upDead[way] && upValid[way]
          && (upTag[way] == updateKey[KEY_W-1:SET_W])) begin
        updateHit = 1'b1;
        updateHitWay = WAY_W'(way);
      end
      if (!invalidFound && !upDead[way] && !upValid[way]) begin
        invalidFound = 1'b1;
        invalidWay = WAY_W'(way);
      end
    end

    // The policy's choice, moved on to the next unlocked way if it is held.
    replaceFound = 1'b0;
    replaceWay = '0;
    begin
      logic [WAY_W-1:0] preferred;
      logic [1:0] oldest;
      int unsigned candidate;
      case (CFG.slcReplPolicy)
        SLC_REPL_PLRU:
          preferred = plruVictim(plruRam[updateSet]);
        SLC_REPL_RRIP: begin
          preferred = '0;
          oldest = '0;
          for (int unsigned way = 0; way < WAYS; way++)
            if (!lockedWays[way] && (rrpvRam[updateSet][way] > oldest)) begin
              oldest = rrpvRam[updateSet][way];
              preferred = WAY_W'(way);
            end
        end
        default:
          preferred = WAY_W'(int'(lfsr) % WAYS);
      endcase
      for (int unsigned offset = 0; offset < WAYS; offset++) begin
        candidate = (int'(preferred) + offset) % WAYS;
        if (!replaceFound && !lockedWays[candidate]) begin
          replaceFound = 1'b1;
          replaceWay = WAY_W'(candidate);
        end
      end
    end

    doWrite = 1'b0;
    doRemove = 1'b0;
    targetWay = '0;
    evictDirty = 1'b0;
    updateReady = 1'b0;
    if (updateRemove) begin
      targetWay = updateHitWay;
      evictDirty = updateHit && upDirty[updateHitWay] && !updateDiscard;
      updateReady = !evictDirty || victimReady;
      doRemove = updateHit;
    end else if (updateHit) begin
      targetWay = updateHitWay;
      updateReady = 1'b1;
      doWrite = 1'b1;
    end else if (invalidFound) begin
      targetWay = invalidWay;
      updateReady = 1'b1;
      doWrite = 1'b1;
    end else if (replaceFound) begin
      targetWay = replaceWay;
      evictDirty = upValid[replaceWay] && upDirty[replaceWay];
      updateReady = !evictDirty || victimReady;
      doWrite = 1'b1;
    end else begin
      // Every way is held: a clean fill is dropped, a dirty line waits.
      updateReady = !updateDirty;
    end
    if (!updateValid) begin
      doWrite = 1'b0;
      doRemove = 1'b0;
      evictDirty = 1'b0;
    end

    // The walk takes the update port when the HN-F leaves it idle, and
    // passes over a dead way.
    walkActive = walking && !updateValid;
    begin
      logic [TSTATE_W-1:0] state;
      logic wayBad;
      state = tagRead(walkSet, walkWay, wkCorrected, wayBad);
      wkValid = state[TSTATE_W-1];
      wkDirty = state[TAG_W];
      wkTag = state[TAG_W-1:0];
      wkBad = walking && wayBad && !fenceRam[walkSet][walkWay];
      wkDead = wayBad || fenceRam[walkSet][walkWay];
    end
    walkLocked = 1'b0;
    for (int unsigned lock = 0; lock < NUM_LOCKS; lock++)
      if (lockValid[lock] && !wkDead && wkValid
          && (lockKey[lock] == {wkTag, walkSet}))
        walkLocked = 1'b1;
    walkClean = walkActive && !walkLocked && !wkDead && wkValid && wkDirty;
    walkRemove = walkActive && !walkLocked && !wkDead && wkValid
                 && walkInvalidate;
    walkAdvance = walkActive && (wkDead || (!walkLocked && (!walkClean || victimReady)));

    opSet = (walkActive) ? walkSet : updateSet;
    opWay = (walkActive) ? walkWay : targetWay;
    victimValid = evictDirty || (walkClean && walkAdvance);
    victimKey = {(walkActive ? wkTag : upTag[targetWay]), opSet};
    victimData = lineOut(lineIndex(opSet, opWay), lineOutPoison, lineOutCorrected);
    victimPoison = lineOutPoison;
    maintWalking = walking;

    eventFill = updateReady && doWrite && !updateHit;
    eventEviction = updateReady && doWrite && !updateHit && upValid[targetWay];

    setDuplicate = 1'b0;
    for (int unsigned first = 0; first < WAYS; first++)
      for (int unsigned second = first + 1; second < WAYS; second++)
        if (!upDead[first] && !upDead[second] && upValid[first]
            && upValid[second] && (upTag[first] == upTag[second]))
          setDuplicate = 1'b1;
    droppingDirty = (updateValid && updateReady
                     && ((doWrite && !updateHit
                          && upValid[targetWay] && upDirty[targetWay])
                         || (doRemove && upDirty[targetWay]
                             && !updateDiscard)))
                    || (walkRemove && walkAdvance && wkDirty);
    eventDirtyEviction = victimValid;
    eventUncorrectable = (readValid && (readPoison != poisonRam[lineIndex(readSet, readWay)]))
                         || (victimValid && (victimPoison
                                             != poisonRam[lineIndex(opSet, opWay)]));
  end

  // Tag RAS events: a way newly found failing, else a corrected way being
  // written back.
  always_comb begin
    logic [WAY_W-1:0] badWay;
    tagUncorrected = CFG.rasEn && ((lookupBad != '0) || (readBad != '0)
                                   || (upBad != '0) || wkBad);
    tagCorrected = CFG.rasEn
                   && ((updateValid && updateReady && (upCorrected != '0))
                       || ((walkClean || walkRemove) && walkAdvance && wkCorrected));
    badWay = '0;
    for (int unsigned way = WAYS; way > 0; way--)
      if (lookupBad[way-1] || readBad[way-1] || upBad[way-1])
        badWay = WAY_W'(way - 1);
    if (lookupBad != '0)
      tagKey = {tagRam[lookupSet][badWay], lookupSet};
    else if (readBad != '0)
      tagKey = {tagRam[readSet][badWay], readSet};
    else if (upBad != '0)
      tagKey = {tagRam[updateSet][badWay], updateSet};
    else if (wkBad)
      tagKey = {tagRam[walkSet][walkWay], walkSet};
    else if (updateValid && updateReady && (upCorrected != '0))
      tagKey = updateKey;
    else
      tagKey = {wkTag, walkSet};
  end

  always_ff @(posedge clk) begin
    if (!resetn) begin
      for (int unsigned set = 0; set < SETS; set++) begin
        validRam[set] <= '0;
        dirtyRam[set] <= '0;
        fenceRam[set] <= '0;
        plruRam[set] <= '0;
        rrpvRam[set] <= '1;
        for (int unsigned way = 0; way < WAYS; way++) begin
          tagRam[set][way] <= '0;
          tagEccRam[set][way] <= '0;
        end
      end
      for (int unsigned line = 0; line < LINES; line++) begin
        dataRam[line] <= '0;
        eccRam[line] <= '0;
        poisonRam[line] <= '0;
      end
      lfsr <= 16'hace1;
      walking <= 1'b0;
      walkInvalidate <= 1'b0;
      walkSet <= '0;
      walkWay <= '0;
    end else begin
      lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};

      // A newly failing way is fenced.
      for (int unsigned way = 0; way < WAYS; way++) begin
        if (lookupBad[way])
          fenceRam[lookupSet][way] <= 1'b1;
        if (readBad[way])
          fenceRam[readSet][way] <= 1'b1;
        if (upBad[way])
          fenceRam[updateSet][way] <= 1'b1;
      end
      if (wkBad)
        fenceRam[walkSet][walkWay] <= 1'b1;

      // The ways of the update set an update does not write go back
      // corrected.
      if (updateValid && updateReady)
        for (int unsigned way = 0; way < WAYS; way++)
          if ((!(doWrite || doRemove) || (WAY_W'(way) != targetWay))
              && upCorrected[way]) begin
            validRam[updateSet][way] <= upValid[way];
            dirtyRam[updateSet][way] <= upDirty[way];
            tagRam[updateSet][way] <= upTag[way];
            tagEccRam[updateSet][way] <= tagCheck(upValid[way], upDirty[way], upTag[way]);
          end

      if (updateValid && updateReady && doWrite) begin
        validRam[updateSet][targetWay] <= 1'b1;
        // A line that was dirty stays dirty until it is written back.
        dirtyRam[updateSet][targetWay] <= updateDirty
                                          || (updateHit && upDirty[targetWay]);
        tagRam[updateSet][targetWay] <= updateKey[KEY_W-1:SET_W];
        tagEccRam[updateSet][targetWay] <=
          tagCheck(1'b1, updateDirty || (updateHit && upDirty[targetWay]),
                   updateKey[KEY_W-1:SET_W]);
        dataRam[lineIndex(updateSet, targetWay)] <= updateData;
        eccRam[lineIndex(updateSet, targetWay)] <= eccOf(updateData);
        poisonRam[lineIndex(updateSet, targetWay)] <= updatePoison;
        plruRam[updateSet] <= plruTouch(plruRam[updateSet], targetWay);
        // Two-bit RRIP: a new line enters with a long re-reference
        // interval, a hit resets it, and filling ages the other lines.
        if (!updateHit) begin
          rrpvRam[updateSet][targetWay] <= 2'b10;
          for (int unsigned way = 0; way < WAYS; way++)
            if ((WAY_W'(way) != targetWay) && (rrpvRam[updateSet][way] != 2'b11))
              rrpvRam[updateSet][way] <= rrpvRam[updateSet][way] + 2'b01;
        end else begin
          rrpvRam[updateSet][targetWay] <= 2'b00;
        end
      end
      if (updateValid && updateReady && doRemove) begin
        validRam[updateSet][targetWay] <= 1'b0;
        dirtyRam[updateSet][targetWay] <= 1'b0;
        tagRam[updateSet][targetWay] <= upTag[targetWay];
        tagEccRam[updateSet][targetWay] <= tagCheck(1'b0, 1'b0, upTag[targetWay]);
      end

      // A lookup that hits marks the line recently used.
      if (lookupHit) begin
        plruRam[lookupSet] <= plruTouch(plruRam[lookupSet], lookupWay);
        rrpvRam[lookupSet][lookupWay] <= 2'b00;
      end

      // Maintenance.
      if (maintStart && !walking) begin
        walking <= 1'b1;
        walkInvalidate <= maintInvalidate;
        walkSet <= '0;
        walkWay <= '0;
      end else if (walkAdvance) begin
        if (walkClean || walkRemove) begin
          validRam[walkSet][walkWay] <= wkValid && !walkRemove;
          dirtyRam[walkSet][walkWay] <= wkDirty && !walkClean;
          tagRam[walkSet][walkWay] <= wkTag;
          tagEccRam[walkSet][walkWay] <=
            tagCheck(wkValid && !walkRemove, wkDirty && !walkClean, wkTag);
        end
        if (int'(walkWay) == (WAYS - 1)) begin
          walkWay <= '0;
          if (int'(walkSet) == (SETS - 1))
            walking <= 1'b0;
          else
            walkSet <= walkSet + 1'b1;
        end else begin
          walkWay <= walkWay + 1'b1;
        end
      end
    end
  end
endmodule
