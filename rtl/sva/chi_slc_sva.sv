// System Level Cache assertions.
//
// chi_slc_sva, bound to chi_slc:
//   SLC_ONE_WAY_PER_LOCATION  no set holds one {line, PAS} in two valid ways.
//   SLC_DIRTY_NEVER_DROPPED  a dirty line leaves the cache, by replacement,
//       removal or maintenance, only through the victim output, unless the
//       HN-F has already written the latest data to memory (discard).
//
// chi_hnf_slc_sva, bound to chi_hnf_top:
//   SLC_NO_DEVICE_ALLOCATION  only Cacheable, non-Device lines are written
//       into the SLC (IHI 0050H B2.8.3).
//   SLC_DISCARD_ONLY_AFTER_WRITEBACK  a retiring entry drops a dirty SLC copy
//       only after writing the latest line to memory itself.
//
// Covers: a hit, a fill on a miss, a dirty eviction, an eviction holding up
// a request to the same location, a CMO meeting a dirty line, a maintenance
// walk.
module chi_slc_sva (
  input logic clk,
  input logic resetn,
  input logic setDuplicate,
  input logic droppingDirty,
  input logic victimValid,
  input logic eventFill
);
  SLC_ONE_WAY_PER_LOCATION: assert property (
    @(posedge clk) disable iff (!resetn)
    !setDuplicate);

  SLC_DIRTY_NEVER_DROPPED: assert property (
    @(posedge clk) disable iff (!resetn)
    droppingDirty |-> victimValid);

  SLC_MISS_FILL: cover property (
    @(posedge clk) disable iff (!resetn)
    eventFill);
endmodule

module chi_hnf_slc_sva #(
  parameter int unsigned POS_DEPTH = 1
) (
  input logic clk,
  input logic resetn,
  input logic slcUpdateValid,
  input logic slcUpdateReady,
  input logic slcUpdateFromRetire,
  input logic slcUpdateRemove,
  input logic slcUpdateDiscard,
  input logic slcUpdateCacheable,
  input logic slcUpdateWroteBack,
  input logic startValid,
  input logic slcLookupHit,
  input logic slcLookupDirty,
  input logic slcFlushWant,
  input logic slcStartIsCmo,
  input logic slcVictimValid,
  input logic slcVictimReady,
  input logic [POS_DEPTH-1:0] hazardVictim,
  input logic slcMaintWalking
);
  SLC_NO_DEVICE_ALLOCATION: assert property (
    @(posedge clk) disable iff (!resetn)
    slcUpdateValid && slcUpdateReady && slcUpdateFromRetire && !slcUpdateRemove
      |-> slcUpdateCacheable);

  SLC_DISCARD_ONLY_AFTER_WRITEBACK: assert property (
    @(posedge clk) disable iff (!resetn)
    slcUpdateValid && slcUpdateReady && slcUpdateFromRetire && slcUpdateDiscard
      |-> slcUpdateWroteBack);

  SLC_HIT: cover property (
    @(posedge clk) disable iff (!resetn)
    startValid && slcLookupHit);

  SLC_DIRTY_EVICTION: cover property (
    @(posedge clk) disable iff (!resetn)
    slcVictimValid && slcVictimReady);

  SLC_EVICTION_HOLDS_REQUEST: cover property (
    @(posedge clk) disable iff (!resetn)
    slcVictimValid && slcVictimReady ##[1:64] (hazardVictim != '0));

  SLC_CMO_HITS_DIRTY: cover property (
    @(posedge clk) disable iff (!resetn)
    slcFlushWant && slcStartIsCmo && slcLookupDirty);

  SLC_MAINTENANCE: cover property (
    @(posedge clk) disable iff (!resetn)
    slcMaintWalking);
endmodule

bind chi_slc chi_slc_sva chi_slc_assertions (
  .clk(clk),
  .resetn(resetn),
  .setDuplicate(setDuplicate),
  .droppingDirty(droppingDirty),
  .victimValid(victimValid),
  .eventFill(eventFill)
);

bind chi_hnf_top chi_hnf_slc_sva #(
  .POS_DEPTH(POS_DEPTH)
) chi_hnf_slc_assertions (
  .clk(clk),
  .resetn(resetn),
  .slcUpdateValid(slcUpdateValid),
  .slcUpdateReady(slcUpdateReady),
  .slcUpdateFromRetire(slcUpdateFromRetire),
  .slcUpdateRemove(slcUpdateRemove),
  .slcUpdateDiscard(slcUpdateDiscard),
  .slcUpdateCacheable(slcUpdateCacheable),
  .slcUpdateWroteBack(slcUpdateWroteBack),
  .startValid(startValid),
  .slcLookupHit(slcLookupHit),
  .slcLookupDirty(slcLookupDirty),
  .slcFlushWant(slcFlushWant),
  .slcStartIsCmo(slcStartIsCmo),
  .slcVictimValid(slcVictimValid),
  .slcVictimReady(slcVictimReady),
  .hazardVictim(hazardVictim),
  .slcMaintWalking(slcMaintWalking)
);
