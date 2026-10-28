// Point of Serialization: the HN-F transaction table.
//
// chi_pos allocates entries and holds the fields that identify a transaction
// and order it against the others: its location key, Requester, TxnID,
// opcode and Order field, whether it has started, and an age matrix. The
// per-entry transaction state that drives the protocol lives in chi_hnf_top;
// both are indexed by the same entry number.
//
// Several entries may hold the same location at once. Only the oldest of them
// runs; the rest wait in chi_hazard until it frees (IHI 0050H B4.11.2). The
// age matrix makes "older" exact without a sequence counter: older[i][j] is
// set when j was already active when i was allocated, and an entry's column is
// cleared when it is allocated again, so a reused index is never mistaken for
// an older transaction.
//
// reserved entries are held back from requests that arrive with AllowRetry
// set: one for every P-Credit the Home has granted and not yet seen used or
// returned, so a request re-sent on a P-Credit always finds a free entry
// (IHI 0050H B2.10.2).
module chi_pos #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned DEPTH = CFG.posEntries,
  parameter int unsigned KEY_W = CFG.addrW - 6,
  parameter int unsigned RESERVE_W = 16,
  parameter int unsigned IDX_W = chi_pkg::clog2Min1(DEPTH)
) (
  input  logic clk,
  input  logic resetn,
  input  logic allocValid,
  // The request may use a reserved entry: it was re-sent on a P-Credit.
  input  logic allocCredited,
  input  logic [RESERVE_W-1:0] reserved,
  output logic allocReady,
  output logic [IDX_W-1:0] allocIndex,
  input  logic [KEY_W-1:0] allocKey,
  input  logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] allocRequester,
  input  logic [chi_cfg_pkg::CHI_TXNID_FLIT_W-1:0] allocTxnId,
  input  chi_pkg::chi_req_opcode_e allocOpcode,
  input  chi_pkg::chi_order_e allocOrder,
  // Entries that leave the hazard wait this cycle.
  input  logic [DEPTH-1:0] startMask,
  // Entries that complete this cycle.
  input  logic [DEPTH-1:0] freeMask,
  output logic [DEPTH-1:0] active,
  output logic [DEPTH-1:0] started,
  output logic [IDX_W:0] freeCount,
  // Free entries beyond the reserved ones.
  output logic [IDX_W:0] unreservedCount,
  // Packed rather than unpacked because the bound ordering assertions take
  // these arrays as ports, and an unpacked array port is not portable across
  // every simulator's bind implementation.
  output logic [DEPTH-1:0][KEY_W-1:0] key,
  output logic [DEPTH-1:0][chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] requester,
  output logic [DEPTH-1:0][chi_cfg_pkg::CHI_TXNID_FLIT_W-1:0] txnId,
  output chi_pkg::chi_req_opcode_e [DEPTH-1:0] opcode,
  output chi_pkg::chi_order_e [DEPTH-1:0] order,
  output logic [DEPTH-1:0][DEPTH-1:0] older
);
  import chi_pkg::*;

  logic freeFound;
  logic [IDX_W-1:0] freeIndex;
  int unsigned freeTotal;

  always_comb begin
    freeFound = 1'b0;
    freeIndex = '0;
    freeTotal = 0;
    for (int unsigned i = 0; i < DEPTH; i++) begin
      if (!active[i]) begin
        freeTotal++;
        if (!freeFound) begin
          freeFound = 1'b1;
          freeIndex = IDX_W'(i);
        end
      end
    end
    freeCount = (IDX_W+1)'(freeTotal);
    unreservedCount = (freeTotal > int'(reserved))
                      ? (IDX_W+1)'(freeTotal - int'(reserved)) : '0;
    // An uncredited request may not take a reserved entry.
    allocReady = freeFound && (allocCredited || (unreservedCount != '0));
    allocIndex = freeIndex;
  end

  always_ff @(posedge clk) begin
    if (!resetn) begin
      active <= '0;
      started <= '0;
      key <= '0;
      requester <= '0;
      txnId <= '0;
      older <= '0;
      for (int unsigned i = 0; i < DEPTH; i++) begin
        opcode[i] <= REQ_LCRD_RETURN;
        order[i] <= ORDER_NONE;
      end
    end else begin
      for (int unsigned i = 0; i < DEPTH; i++) begin
        if (freeMask[i]) begin
          active[i] <= 1'b0;
          started[i] <= 1'b0;
        end else if (startMask[i]) begin
          started[i] <= 1'b1;
        end
      end
      if (allocValid && allocReady) begin
        active[allocIndex] <= 1'b1;
        started[allocIndex] <= 1'b0;
        key[allocIndex] <= allocKey;
        requester[allocIndex] <= allocRequester;
        txnId[allocIndex] <= allocTxnId;
        opcode[allocIndex] <= allocOpcode;
        order[allocIndex] <= allocOrder;
        // Everything active now is older than the new entry, and the new
        // entry is older than nothing.
        older[allocIndex] <= active & ~freeMask;
        for (int unsigned i = 0; i < DEPTH; i++)
          older[i][allocIndex] <= 1'b0;
      end
    end
  end
endmodule
