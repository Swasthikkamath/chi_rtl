// Supplemental harness: the default 3x3 mesh with the default population.
module chi_mesh_compile (
  input  logic clk,
  input  logic resetn,
  output logic routeError
);
  chi_noc_compile #(.CFG(chi_cfg_pkg::CHI_CFG_DEFAULT)) mesh (.*);
endmodule
