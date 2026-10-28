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
//   read    the whole line of a location that is present.
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
  output logic eventUncorrectable
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

  // ---------------------------------------------------------------------
  // Lookup and read.
  // ---------------------------------------------------------------------
  logic [SET_W-1:0] lookupSet;
  logic [WAY_W-1:0] lookupWay;
  logic [SET_W-1:0] readSet;
  logic [WAY_W-1:0] readWay;
  logic readHit;

  always_comb begin
    lookupSet = lookupKey[SET_W-1:0];
    lookupHit = 1'b0;
    lookupDirty = 1'b0;
    lookupWay = '0;
    for (int unsigned way = 0; way < WAYS; way++)
      if (validRam[lookupSet][way]
          && (tagRam[lookupSet][way] == lookupKey[KEY_W-1:SET_W])) begin
        lookupHit = 1'b1;
        lookupDirty = dirtyRam[lookupSet][way];
        lookupWay = WAY_W'(way);
      end

    readSet = readKey[SET_W-1:0];
    readHit = 1'b0;
    readWay = '0;
    for (int unsigned way = 0; way < WAYS; way++)
      if (validRam[readSet][way]
          && (tagRam[readSet][way] == readKey[KEY_W-1:SET_W])) begin
        readHit = 1'b1;
        readWay = WAY_W'(way);
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
      lockedWays[way] = 1'b0;
      for (int unsigned lock = 0; lock < NUM_LOCKS; lock++)
        if (lockValid[lock] && validRam[updateSet][way]
            && (lockKey[lock] == {tagRam[updateSet][way], updateSet}))
          lockedWays[way] = 1'b1;
      if (validRam[updateSet][way]
          && (tagRam[updateSet][way] == updateKey[KEY_W-1:SET_W])) begin
        updateHit = 1'b1;
        updateHitWay = WAY_W'(way);
      end
      if (!invalidFound && !validRam[updateSet][way]) begin
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
      evictDirty = updateHit && dirtyRam[updateSet][updateHitWay]
                   && !updateDiscard;
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
      evictDirty = dirtyRam[updateSet][replaceWay];
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

    // The walk takes the update port when the HN-F leaves it idle.
    walkActive = walking && !updateValid;
    walkLocked = 1'b0;
    for (int unsigned lock = 0; lock < NUM_LOCKS; lock++)
      if (lockValid[lock] && validRam[walkSet][walkWay]
          && (lockKey[lock] == {tagRam[walkSet][walkWay], walkSet}))
        walkLocked = 1'b1;
    walkClean = walkActive && !walkLocked && validRam[walkSet][walkWay]
                && dirtyRam[walkSet][walkWay];
    walkRemove = walkActive && !walkLocked && validRam[walkSet][walkWay]
                 && walkInvalidate;
    walkAdvance = walkActive && !walkLocked && (!walkClean || victimReady);

    opSet = (walkActive) ? walkSet : updateSet;
    opWay = (walkActive) ? walkWay : targetWay;
    victimValid = evictDirty || (walkClean && walkAdvance);
    victimKey = {tagRam[opSet][opWay], opSet};
    victimData = lineOut(lineIndex(opSet, opWay), lineOutPoison, lineOutCorrected);
    victimPoison = lineOutPoison;
    maintWalking = walking;

    eventFill = updateReady && doWrite && !updateHit;

    setDuplicate = 1'b0;
    for (int unsigned first = 0; first < WAYS; first++)
      for (int unsigned second = first + 1; second < WAYS; second++)
        if (validRam[updateSet][first] && validRam[updateSet][second]
            && (tagRam[updateSet][first] == tagRam[updateSet][second]))
          setDuplicate = 1'b1;
    droppingDirty = (updateValid && updateReady
                     && ((doWrite && !updateHit
                          && validRam[updateSet][targetWay]
                          && dirtyRam[updateSet][targetWay])
                         || (doRemove && dirtyRam[updateSet][targetWay]
                             && !updateDiscard)))
                    || (walkRemove && walkAdvance && dirtyRam[walkSet][walkWay]);
    eventDirtyEviction = victimValid;
    eventUncorrectable = (readValid && (readPoison != poisonRam[lineIndex(readSet, readWay)]))
                         || (victimValid && (victimPoison
                                             != poisonRam[lineIndex(opSet, opWay)]));
  end

  always_ff @(posedge clk) begin
    if (!resetn) begin
      for (int unsigned set = 0; set < SETS; set++) begin
        validRam[set] <= '0;
        dirtyRam[set] <= '0;
        plruRam[set] <= '0;
        rrpvRam[set] <= '1;
        for (int unsigned way = 0; way < WAYS; way++)
          tagRam[set][way] <= '0;
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

      if (updateValid && updateReady && doWrite) begin
        validRam[updateSet][targetWay] <= 1'b1;
        // A line that was dirty stays dirty until it is written back.
        dirtyRam[updateSet][targetWay] <= updateDirty
                                          || (updateHit && dirtyRam[updateSet][targetWay]);
        tagRam[updateSet][targetWay] <= updateKey[KEY_W-1:SET_W];
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
        if (walkClean)
          dirtyRam[walkSet][walkWay] <= 1'b0;
        if (walkRemove)
          validRam[walkSet][walkWay] <= 1'b0;
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
