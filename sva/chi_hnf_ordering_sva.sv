module chi_hnf_ordering_sva #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned DEPTH = CFG.posEntries
) (
  input logic clk,
  input logic resetn,
  input logic requestHandshake,
  input chi_pkg::chi_order_e requestOrder,
  input logic [DEPTH-1:0] posActive,
  input logic [DEPTH-1:0] activeOrdered
);
  import chi_pkg::*;

  ORDERED_REQUEST_STARTS_QUIESCENT: assert property (
    @(posedge clk) disable iff (!resetn)
    requestHandshake && (requestOrder != ORDER_NONE)
      |-> (posActive == '0));

  ACTIVE_ORDERED_REQUEST_SERIALIZES: assert property (
    @(posedge clk) disable iff (!resetn)
    requestHandshake |-> (activeOrdered == '0));
endmodule

bind chi_hnf_top chi_hnf_ordering_sva #(
  .CFG(CFG),
  .DEPTH(POS_DEPTH)
) chi_hnf_ordering_assertions (
  .clk(clk),
  .resetn(resetn),
  .requestHandshake(requestHandshake),
  .requestOrder(incomingReq.order),
  .posActive(posActive),
  .activeOrdered(activeOrdered)
);
