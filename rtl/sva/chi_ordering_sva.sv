module chi_ordering_sva #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned DEPTH = CFG.posEntries
) (
  input logic clk,
  input logic resetn,
  input logic allocValid,
  input logic allocReady,
  input logic [CFG.addrW-7:0] allocLineAddr,
  input logic [DEPTH-1:0] active,
  input logic [DEPTH-1:0][CFG.addrW-7:0] lineAddr
);
  for (genvar firstEntry = 0; firstEntry < DEPTH;
       firstEntry++) begin : active_line_first
    for (genvar secondEntry = firstEntry + 1;
         secondEntry < DEPTH;
         secondEntry++) begin : active_line_second
      NO_DUPLICATE_ACTIVE_LINE: assert property (
        @(posedge clk) disable iff (!resetn)
        !(active[firstEntry] && active[secondEntry]
          && (lineAddr[firstEntry] == lineAddr[secondEntry])));
    end
  end

  for (genvar entry = 0; entry < DEPTH;
       entry++) begin : allocation_line_entry
    ALLOCATION_LINE_NOT_ACTIVE: assert property (
      @(posedge clk) disable iff (!resetn)
      allocValid && allocReady
        |-> !(active[entry] && (lineAddr[entry] == allocLineAddr)));
  end
endmodule

bind chi_pos chi_ordering_sva #(
  .CFG(CFG),
  .DEPTH(DEPTH)
) chi_pos_ordering_assertions (
  .clk(clk),
  .resetn(resetn),
  .allocValid(allocValid),
  .allocReady(allocReady),
  .allocLineAddr(allocLineAddr),
  .active(active),
  .lineAddr(lineAddr)
);
