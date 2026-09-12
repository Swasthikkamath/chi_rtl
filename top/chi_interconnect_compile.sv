// Elaboration harness for the product top.
//
// The interconnect's node-facing ports are `chi_if` arrays. A tool that
// elaborates chi_interconnect_top directly as the design root has no
// interface instances to bind those ports to, so this harness creates them
// and drives the configuration port inactive. Lint and elaboration targets
// use this module rather than the product top.
module chi_interconnect_compile #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned NUM_NODES =
    CFG.numRnf + CFG.numRnd + CFG.numRni + CFG.numSnf + CFG.numSni
    + CFG.numHnf + CFG.numHni + CFG.numMn
) (
  input  logic clk,
  input  logic resetn,
  output logic [31:0] PRDATA,
  output logic PREADY,
  output logic PSLVERR,
  output logic [NUM_NODES-1:0] linkUp,
  output logic [NUM_NODES-1:0] linkParityError,
  output logic [NUM_NODES-1:0] linkCreditError
);
  chi_if #(.CFG(CFG)) rnfIf [(CFG.numRnf > 0 ? CFG.numRnf : 1)-1:0] ();
  chi_if #(.CFG(CFG)) rndIf [(CFG.numRnd > 0 ? CFG.numRnd : 1)-1:0] ();
  chi_if #(.CFG(CFG)) rniIf [(CFG.numRni > 0 ? CFG.numRni : 1)-1:0] ();
  chi_if #(.CFG(CFG)) snfIf [(CFG.numSnf > 0 ? CFG.numSnf : 1)-1:0] ();
  chi_if #(.CFG(CFG)) sniIf [(CFG.numSni > 0 ? CFG.numSni : 1)-1:0] ();

  chi_interconnect_top #(.CFG(CFG)) fabric (
    .clk, .resetn,
    .rnf(rnfIf), .rnd(rndIf), .rni(rniIf), .snf(snfIf), .sni(sniIf),
    .PADDR('0), .PSEL(1'b0), .PENABLE(1'b0), .PWRITE(1'b0),
    .PWDATA('0), .PSTRB('0), .PPROT('0),
    .PRDATA, .PREADY, .PSLVERR,
    .linkUp, .linkParityError, .linkCreditError
  );
endmodule
