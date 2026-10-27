// POS ordering assertions.
//
//   ONE_RUNNING_ENTRY_PER_LOCATION  at most one started entry holds a
//       location; younger entries for it wait (IHI 0050H B4.11.2).
//   START_ONLY_AFTER_OLDER_SAME_LOCATION  an entry starts only when no older
//       active entry holds its location.
//   STARTED_IMPLIES_ACTIVE  a started entry is allocated.
module chi_ordering_sva #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned DEPTH = CFG.posEntries,
  parameter int unsigned KEY_W = CFG.addrW - 6
) (
  input logic clk,
  input logic resetn,
  input logic [DEPTH-1:0] active,
  input logic [DEPTH-1:0] started,
  input logic [DEPTH-1:0] startMask,
  input logic [DEPTH-1:0][KEY_W-1:0] key,
  input logic [DEPTH-1:0][DEPTH-1:0] older
);
  for (genvar firstEntry = 0; firstEntry < DEPTH;
       firstEntry++) begin : started_first
    for (genvar secondEntry = firstEntry + 1;
         secondEntry < DEPTH;
         secondEntry++) begin : started_second
      ONE_RUNNING_ENTRY_PER_LOCATION: assert property (
        @(posedge clk) disable iff (!resetn)
        !(started[firstEntry] && started[secondEntry]
          && (key[firstEntry] == key[secondEntry])));
    end
  end

  for (genvar entry = 0; entry < DEPTH; entry++) begin : per_entry
    for (genvar other = 0; other < DEPTH; other++) begin : per_other
      if (other != entry) begin : distinct
        START_ONLY_AFTER_OLDER_SAME_LOCATION: assert property (
          @(posedge clk) disable iff (!resetn)
          startMask[entry]
            |-> !(active[other] && older[entry][other]
                  && (key[other] == key[entry])));
      end
    end

    STARTED_IMPLIES_ACTIVE: assert property (
      @(posedge clk) disable iff (!resetn)
      started[entry] |-> active[entry]);
  end
endmodule

bind chi_pos chi_ordering_sva #(
  .CFG(CFG),
  .DEPTH(DEPTH),
  .KEY_W(KEY_W)
) chi_pos_ordering_assertions (
  .clk(clk),
  .resetn(resetn),
  .active(active),
  .started(started),
  .startMask(startMask),
  .key(key),
  .older(older)
);
