module chi_hazard #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned DEPTH = CFG.posEntries
) (
  input  logic [CFG.addrW-7:0] requestLineAddr,
  input  chi_pkg::chi_order_e requestOrder,
  input  logic [DEPTH-1:0] active,
  input  logic [CFG.addrW-7:0] activeLineAddr [DEPTH],
  input  logic [DEPTH-1:0] activeOrdered,
  output logic lineHazard,
  output logic orderHazard,
  output logic blocked
);
  import chi_pkg::*;

  always_comb begin
    lineHazard = 1'b0;
    orderHazard = 1'b0;
    for (int unsigned i = 0; i < DEPTH; i++) begin
      if (active[i] && (activeLineAddr[i] == requestLineAddr))
        lineHazard = 1'b1;
      if (active[i] && activeOrdered[i])
        orderHazard = 1'b1;
    end
    blocked = lineHazard
              || ((requestOrder != ORDER_NONE) && (|active))
              || orderHazard;
  end
endmodule
