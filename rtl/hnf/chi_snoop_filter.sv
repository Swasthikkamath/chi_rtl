module chi_snoop_filter #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned ENTRIES = CFG.snpFilterEntries,
  parameter int unsigned WAYS = CFG.snpFilterWays,
  parameter int unsigned NUM_RNF = (CFG.numRnf > 0) ? CFG.numRnf : 1
) (
  input  logic clk,
  input  logic resetn,
  input  logic lookupValid,
  input  logic [CFG.addrW-7:0] lookupLineAddr,
  output logic lookupHit,
  output logic [NUM_RNF-1:0] lookupSharers,
  output logic lookupPrecise,
  output logic lookupHasOwner,
  output logic [chi_pkg::clog2Min1(NUM_RNF)-1:0] lookupOwner,
  input  logic updateValid,
  output logic updateReady,
  input  logic [CFG.addrW-7:0] updateLineAddr,
  input  logic [NUM_RNF-1:0] updateSharers,
  input  logic updatePrecise,
  input  logic updateHasOwner,
  input  logic [chi_pkg::clog2Min1(NUM_RNF)-1:0] updateOwner,
  input  logic invalidate,
  output logic backInvValid,
  input  logic backInvReady,
  output logic [CFG.addrW-7:0] backInvLineAddr,
  output logic [NUM_RNF-1:0] backInvSharers,
  input  logic backInvDone
);
  import chi_pkg::*;

  localparam int unsigned SETS = (ENTRIES / WAYS) > 0 ? (ENTRIES / WAYS) : 1;
  localparam int unsigned SET_W = clog2Min1(SETS);
  localparam int unsigned WAY_W = clog2Min1(WAYS);
  localparam int unsigned LINE_W = CFG.addrW - 6;
  localparam int unsigned TAG_W = LINE_W - SET_W;

  logic validRam [SETS][WAYS];
  logic [TAG_W-1:0] tagRam [SETS][WAYS];
  logic [NUM_RNF-1:0] sharerRam [SETS][WAYS];
  logic preciseRam [SETS][WAYS];
  logic ownerValidRam [SETS][WAYS];
  logic [clog2Min1(NUM_RNF)-1:0] ownerRam [SETS][WAYS];
  logic [WAY_W-1:0] replaceWay [SETS];

  logic pendingReplacement;
  logic pendingIssued;
  logic [SET_W-1:0] pendingSet;
  logic [WAY_W-1:0] pendingWay;
  logic [TAG_W-1:0] pendingTag;
  logic [NUM_RNF-1:0] pendingSharers;
  logic pendingPrecise;
  logic pendingHasOwner;
  logic pendingInvalidate;
  logic [clog2Min1(NUM_RNF)-1:0] pendingOwner;

  logic [SET_W-1:0] lookupSet;
  logic [TAG_W-1:0] lookupTag;
  logic updateHit;
  logic [WAY_W-1:0] updateHitWay;
  logic updateHasInvalid;
  logic [WAY_W-1:0] updateInvalidWay;
  logic [SET_W-1:0] updateSet;
  logic [TAG_W-1:0] updateTag;

  always_comb begin
    lookupSet = lookupLineAddr[SET_W-1:0];
    lookupTag = lookupLineAddr[LINE_W-1:SET_W];
    lookupHit = 1'b0;
    lookupSharers = '0;
    lookupPrecise = 1'b0;
    lookupHasOwner = 1'b0;
    lookupOwner = '0;
    for (int unsigned way = 0; way < WAYS; way++) begin
      if (lookupValid && validRam[lookupSet][way]
          && (tagRam[lookupSet][way] == lookupTag)) begin
        lookupHit = 1'b1;
        lookupSharers = sharerRam[lookupSet][way];
        lookupPrecise = preciseRam[lookupSet][way];
        lookupHasOwner = ownerValidRam[lookupSet][way];
        lookupOwner = ownerRam[lookupSet][way];
      end
    end
  end

  always_comb begin
    updateSet = updateLineAddr[SET_W-1:0];
    updateTag = updateLineAddr[LINE_W-1:SET_W];
    updateHit = 1'b0;
    updateHitWay = '0;
    updateHasInvalid = 1'b0;
    updateInvalidWay = '0;
    for (int unsigned way = 0; way < WAYS; way++) begin
      if (validRam[updateSet][way] && (tagRam[updateSet][way] == updateTag)) begin
        updateHit = 1'b1;
        updateHitWay = way[WAY_W-1:0];
      end
      if (!updateHasInvalid && !validRam[updateSet][way]) begin
        updateHasInvalid = 1'b1;
        updateInvalidWay = way[WAY_W-1:0];
      end
    end
    updateReady = !pendingReplacement;
    backInvValid = pendingReplacement && !pendingIssued;
    backInvLineAddr = {tagRam[pendingSet][pendingWay], pendingSet};
    backInvSharers = sharerRam[pendingSet][pendingWay];
  end

  always_ff @(posedge clk) begin
    if (!resetn) begin
      pendingReplacement <= 1'b0;
      pendingIssued <= 1'b0;
      pendingSet <= '0;
      pendingWay <= '0;
      pendingTag <= '0;
      pendingSharers <= '0;
      pendingPrecise <= 1'b0;
      pendingHasOwner <= 1'b0;
      pendingInvalidate <= 1'b0;
      pendingOwner <= '0;
      for (int unsigned set = 0; set < SETS; set++) begin
        replaceWay[set] <= '0;
        for (int unsigned way = 0; way < WAYS; way++) begin
          validRam[set][way] <= 1'b0;
          tagRam[set][way] <= '0;
          sharerRam[set][way] <= '0;
          preciseRam[set][way] <= 1'b0;
          ownerValidRam[set][way] <= 1'b0;
          ownerRam[set][way] <= '0;
        end
      end
    end else begin
      if (backInvValid && backInvReady)
        pendingIssued <= 1'b1;
      if (pendingReplacement && pendingIssued && backInvDone) begin
        validRam[pendingSet][pendingWay] <= !pendingInvalidate;
        tagRam[pendingSet][pendingWay] <= pendingTag;
        sharerRam[pendingSet][pendingWay] <= pendingSharers;
        preciseRam[pendingSet][pendingWay] <= pendingPrecise;
        ownerValidRam[pendingSet][pendingWay] <= pendingHasOwner;
        ownerRam[pendingSet][pendingWay] <= pendingOwner;
        if (pendingWay == WAY_W'(WAYS - 1))
          replaceWay[pendingSet] <= '0;
        else
          replaceWay[pendingSet] <= pendingWay + 1'b1;
        pendingReplacement <= 1'b0;
        pendingIssued <= 1'b0;
      end
      if (updateValid && updateReady) begin
        if (updateHit || updateHasInvalid) begin
          validRam[updateSet][updateHit ? updateHitWay : updateInvalidWay]
            <= !invalidate;
          tagRam[updateSet][updateHit ? updateHitWay : updateInvalidWay]
            <= updateTag;
          sharerRam[updateSet][updateHit ? updateHitWay : updateInvalidWay]
            <= updateSharers;
          preciseRam[updateSet][updateHit ? updateHitWay : updateInvalidWay]
            <= updatePrecise;
          ownerValidRam[updateSet][updateHit ? updateHitWay : updateInvalidWay]
            <= updateHasOwner;
          ownerRam[updateSet][updateHit ? updateHitWay : updateInvalidWay]
            <= updateOwner;
        end else begin
          pendingReplacement <= 1'b1;
          pendingIssued <= 1'b0;
          pendingSet <= updateSet;
          pendingWay <= replaceWay[updateSet];
          pendingTag <= updateTag;
          pendingSharers <= updateSharers;
          pendingPrecise <= updatePrecise;
          pendingHasOwner <= updateHasOwner;
          pendingInvalidate <= invalidate;
          pendingOwner <= updateOwner;
        end
      end
    end
  end
endmodule
