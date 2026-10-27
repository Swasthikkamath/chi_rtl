// Supplemental harness: the default population on a four-crosspoint crossbar,
// and on a one-crosspoint crossbar, which is the central crossbar.
module chi_xbar_compile (
  input  logic clk,
  input  logic resetn,
  output logic routeError
);
  import chi_cfg_pkg::*;

  function automatic chi_cfg_t xbarCfg(
    input int unsigned numXp,
    input int unsigned numDevPortsPerXp
  );
    chi_cfg_t cfg;
    cfg = CHI_CFG_DEFAULT;
    cfg.topology = CROSSBAR;
    cfg.numXp = numXp;
    cfg.numDevPortsPerXp = numDevPortsPerXp;
    return cfg;
  endfunction

  logic distributedError;
  logic centralError;

  chi_noc_compile #(.CFG(xbarCfg(4, 4))) distributed (
    .clk, .resetn, .routeError(distributedError)
  );

  chi_noc_compile #(.CFG(xbarCfg(1, 16))) central (
    .clk, .resetn, .routeError(centralError)
  );

  assign routeError = distributedError || centralError;
endmodule
