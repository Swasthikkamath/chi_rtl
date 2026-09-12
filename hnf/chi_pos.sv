module chi_pos #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned DEPTH = CFG.posEntries
) (
  input  logic clk,
  input  logic resetn,
  input  logic allocValid,
  output logic allocReady,
  input  logic [CFG.addrW-7:0] allocLineAddr,
  input  logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] allocRequester,
  input  logic [CFG.txnIdW-1:0] allocTxnId,
  input  chi_pkg::chi_req_opcode_e allocOpcode,
  input  logic allocNeedSnoop,
  input  logic allocNeedData,
  input  logic allocNeedComp,
  input  logic allocNeedCompAck,
  output logic [chi_pkg::clog2Min1(DEPTH)-1:0] allocIndex,
  input  logic freeValid,
  input  logic [chi_pkg::clog2Min1(DEPTH)-1:0] freeIndex,
  input  logic progressValid,
  input  logic [chi_pkg::clog2Min1(DEPTH)-1:0] progressIndex,
  input  logic progressSnoopDone,
  input  logic progressDataDone,
  input  logic progressCompDone,
  input  logic progressCompAckDone,
  output logic sameAddressBusy,
  input  logic [CFG.addrW-7:0] queryLineAddr,
  output logic [DEPTH-1:0] active,
  output logic [DEPTH-1:0] readyToFree,
  // Packed rather than unpacked because the bound ordering assertions take
  // this array as a port, and an unpacked array port is not portable across
  // every simulator's bind implementation.
  output logic [DEPTH-1:0][CFG.addrW-7:0] lineAddr,
  output logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] requester [DEPTH],
  output logic [CFG.txnIdW-1:0] txnId [DEPTH],
  output chi_pkg::chi_req_opcode_e opcode [DEPTH],
  output logic [2:0] lifecycle [DEPTH]
);
  import chi_pkg::*;

  typedef enum logic [2:0] {
    POS_FREE, POS_ALLOCATED, POS_SNOOP, POS_DATA, POS_COMPLETION, POS_WAIT_ACK
  } pos_state_e;

  pos_state_e state [DEPTH];
  logic [DEPTH-1:0] needSnoop;
  logic [DEPTH-1:0] needData;
  logic [DEPTH-1:0] needComp;
  logic [DEPTH-1:0] needCompAck;

  always_comb begin
    allocReady = 1'b0;
    allocIndex = '0;
    sameAddressBusy = 1'b0;
    for (int unsigned i = 0; i < DEPTH; i++) begin
      active[i] = state[i] != POS_FREE;
      readyToFree[i] = active[i] && !needSnoop[i] && !needData[i]
                       && !needComp[i] && !needCompAck[i];
      lifecycle[i] = state[i];
      if (!allocReady && (state[i] == POS_FREE)) begin
        allocReady = 1'b1;
        allocIndex = i[clog2Min1(DEPTH)-1:0];
      end
      if ((state[i] != POS_FREE) && (lineAddr[i] == queryLineAddr))
        sameAddressBusy = 1'b1;
    end
  end

  always_ff @(posedge clk) begin
    if (!resetn) begin
      for (int unsigned i = 0; i < DEPTH; i++) begin
        state[i] <= POS_FREE;
        lineAddr[i] <= '0;
        requester[i] <= '0;
        txnId[i] <= '0;
        opcode[i] <= REQ_LCRD_RETURN;
        needSnoop[i] <= 1'b0;
        needData[i] <= 1'b0;
        needComp[i] <= 1'b0;
        needCompAck[i] <= 1'b0;
      end
    end else begin
      if (freeValid) begin
        state[freeIndex] <= POS_FREE;
        needSnoop[freeIndex] <= 1'b0;
        needData[freeIndex] <= 1'b0;
        needComp[freeIndex] <= 1'b0;
        needCompAck[freeIndex] <= 1'b0;
      end
      if (progressValid && (state[progressIndex] != POS_FREE)) begin
        if (progressSnoopDone) needSnoop[progressIndex] <= 1'b0;
        if (progressDataDone) needData[progressIndex] <= 1'b0;
        if (progressCompDone) needComp[progressIndex] <= 1'b0;
        if (progressCompAckDone) needCompAck[progressIndex] <= 1'b0;
        if (needSnoop[progressIndex] && !progressSnoopDone)
          state[progressIndex] <= POS_SNOOP;
        else if (needData[progressIndex] && !progressDataDone)
          state[progressIndex] <= POS_DATA;
        else if (needComp[progressIndex] && !progressCompDone)
          state[progressIndex] <= POS_COMPLETION;
        else if (needCompAck[progressIndex] && !progressCompAckDone)
          state[progressIndex] <= POS_WAIT_ACK;
        else
          state[progressIndex] <= POS_ALLOCATED;
      end
      if (allocValid && allocReady) begin
        state[allocIndex] <= allocNeedSnoop ? POS_SNOOP :
                             allocNeedData ? POS_DATA :
                             allocNeedComp ? POS_COMPLETION :
                             allocNeedCompAck ? POS_WAIT_ACK : POS_ALLOCATED;
        lineAddr[allocIndex] <= allocLineAddr;
        requester[allocIndex] <= allocRequester;
        txnId[allocIndex] <= allocTxnId;
        opcode[allocIndex] <= allocOpcode;
        needSnoop[allocIndex] <= allocNeedSnoop;
        needData[allocIndex] <= allocNeedData;
        needComp[allocIndex] <= allocNeedComp;
        needCompAck[allocIndex] <= allocNeedCompAck;
      end
    end
  end
endmodule
