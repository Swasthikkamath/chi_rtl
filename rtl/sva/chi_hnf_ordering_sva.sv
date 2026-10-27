// HN-F request-ordering assertions (IHI 0050H B2.7.5).
//
//   ENDPOINT_ORDER_RESPECTED  an Endpoint-ordered request starts only when no
//       older ordered request from the same source is active; the endpoint
//       range of this Home is everything it serves.
//   ORDERED_REQUEST_STARTS_IN_ARRIVAL_ORDER  two ordered requests from one
//       source to one location start in the order they arrived; a younger
//       one never starts while the older one is active.
module chi_hnf_ordering_sva #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned DEPTH = CFG.posEntries,
  parameter int unsigned KEY_W = CFG.addrW - 6
) (
  input logic clk,
  input logic resetn,
  input logic [DEPTH-1:0] posStartMask,
  input logic [DEPTH-1:0] posActive,
  input chi_pkg::chi_order_e [DEPTH-1:0] posOrder,
  input logic [DEPTH-1:0][chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] posRequester,
  input logic [DEPTH-1:0][KEY_W-1:0] posKey,
  input logic [DEPTH-1:0][DEPTH-1:0] posOlder
);
  import chi_pkg::*;

  for (genvar entry = 0; entry < DEPTH; entry++) begin : per_entry
    for (genvar other = 0; other < DEPTH; other++) begin : per_other
      if (other != entry) begin : distinct
        ENDPOINT_ORDER_RESPECTED: assert property (
          @(posedge clk) disable iff (!resetn)
          posStartMask[entry] && (posOrder[entry] == ORDER_ENDPOINT)
            |-> !(posActive[other] && posOlder[entry][other]
                  && (posOrder[other] != ORDER_NONE)
                  && (posRequester[other] == posRequester[entry])));

        ORDERED_REQUEST_STARTS_IN_ARRIVAL_ORDER: assert property (
          @(posedge clk) disable iff (!resetn)
          posStartMask[entry] && (posOrder[entry] != ORDER_NONE)
            |-> !(posActive[other] && posOlder[entry][other]
                  && (posOrder[other] != ORDER_NONE)
                  && (posRequester[other] == posRequester[entry])
                  && (posKey[other] == posKey[entry])));
      end
    end
  end
endmodule

bind chi_hnf_top chi_hnf_ordering_sva #(
  .CFG(CFG),
  .DEPTH(POS_DEPTH),
  .KEY_W(KEY_W)
) chi_hnf_ordering_assertions (
  .clk(clk),
  .resetn(resetn),
  .posStartMask(posStartMask),
  .posActive(posActive),
  .posOrder(posOrder),
  .posRequester(posRequester),
  .posKey(posKey),
  .posOlder(posOlder)
);
