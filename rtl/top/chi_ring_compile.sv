// Supplemental harness: the default population on a seven-crosspoint ring.
module chi_ring_compile (
  input  logic clk,
  input  logic resetn,
  output logic routeError
);
  import chi_cfg_pkg::*;

  function automatic chi_cfg_t ringCfg();
    chi_cfg_t cfg;
    cfg = CHI_CFG_DEFAULT;
    cfg.topology = RING;
    cfg.numXp = 7;
    cfg.numDevPortsPerXp = 2;
    return cfg;
  endfunction

  chi_noc_compile #(.CFG(ringCfg())) ring (.*);
endmodule
