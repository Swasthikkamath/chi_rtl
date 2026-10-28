// Supplemental harness: the three reference configurations of the
// configuration cookbook (design specification, Section 3.5), each
// elaborated as the whole product through chi_interconnect_compile.
//
//   smallCrossbar  two RN-Fs and one of every other class on one central
//                  crossbar of eight device ports, 128-bit data.
//   ring           four RN-Fs, an RN-D and two RN-Is with two HN-Fs on a
//                  four-crosspoint ring, APB with counters and the QoS
//                  regulator.
//   largeMesh      eight RN-Fs and eight HN-Fs with 256 KiB SLC slices on a
//                  4 x 4 mesh, the GPT walked from memory, RAS and counters.
module chi_cookbook_compile (
  input  logic clk,
  input  logic resetn
);
  import chi_cfg_pkg::*;

  function automatic chi_cfg_t smallCrossbarCfg();
    chi_cfg_t cfg;
    cfg = CHI_CFG_DEFAULT;
    cfg.topology = CROSSBAR;
    cfg.numXp = 1;
    cfg.numDevPortsPerXp = 8;
    cfg.numRnf = 2;
    cfg.numRnd = 0;
    cfg.numRni = 1;
    cfg.numHnf = 1;
    cfg.numHni = 1;
    cfg.numSnf = 1;
    cfg.numSni = 1;
    cfg.numMn = 1;
    cfg.dataW = 128;
    cfg.posEntries = 16;
    cfg.retryRecords = 8;
    cfg.maxOutstandingSnoops = 8;
    cfg.snpFilterEntries = 512;
    cfg.snpFilterWays = 4;
    cfg.hniEntries = 4;
    return cfg;
  endfunction

  function automatic chi_cfg_t ringCfg();
    chi_cfg_t cfg;
    cfg = CHI_CFG_DEFAULT;
    cfg.topology = RING;
    cfg.numXp = 4;
    cfg.numDevPortsPerXp = 4;
    cfg.numRnf = 4;
    cfg.numRnd = 1;
    cfg.numRni = 2;
    cfg.numHnf = 2;
    cfg.numHni = 1;
    cfg.numSnf = 2;
    cfg.numSni = 1;
    cfg.numMn = 1;
    cfg.posEntries = 32;
    cfg.retryRecords = 16;
    cfg.snpFilterEntries = 1024;
    cfg.snpFilterWays = 4;
    cfg.cfgAccess = CFG_APB;
    cfg.pmuEn = 1'b1;
    cfg.qosRegEn = 1'b1;
    cfg.qosRegRate = 128;
    cfg.qosRegBurst = 8;
    return cfg;
  endfunction

  function automatic chi_cfg_t largeMeshCfg();
    chi_cfg_t cfg;
    cfg = CHI_CFG_DEFAULT;
    cfg.topology = MESH_2D;
    cfg.meshX = 4;
    cfg.meshY = 4;
    cfg.numDevPortsPerXp = 2;
    cfg.numRnf = 8;
    cfg.numRnd = 1;
    cfg.numRni = 2;
    cfg.numHnf = 8;
    cfg.numHni = 1;
    cfg.numSnf = 4;
    cfg.numSni = 1;
    cfg.numMn = 1;
    cfg.posEntries = 64;
    cfg.retryRecords = 32;
    cfg.maxOutstandingSnoops = 32;
    cfg.snpFilterEntries = 4096;
    cfg.snpFilterWays = 8;
    cfg.slcEn = 1'b1;
    cfg.slcSizePerHnf = 262144;
    cfg.slcWays = 16;
    cfg.slcEccEn = 1'b1;
    cfg.gpcMode = GPC_WALK;
    cfg.gpcCacheEntries = 32;
    cfg.cfgAccess = CFG_APB;
    cfg.rasEn = 1'b1;
    cfg.pmuEn = 1'b1;
    return cfg;
  endfunction

  localparam chi_cfg_t SMALL_CROSSBAR_CFG = smallCrossbarCfg();
  localparam chi_cfg_t RING_CFG = ringCfg();
  localparam chi_cfg_t LARGE_MESH_CFG = largeMeshCfg();

  chi_interconnect_compile #(.CFG(SMALL_CROSSBAR_CFG)) small_crossbar (
    .clk, .resetn, .PRDATA(), .PREADY(), .PSLVERR(),
    .linkUp(), .linkParityError(), .linkCreditError()
  );

  chi_interconnect_compile #(.CFG(RING_CFG)) ring (
    .clk, .resetn, .PRDATA(), .PREADY(), .PSLVERR(),
    .linkUp(), .linkParityError(), .linkCreditError()
  );

  chi_interconnect_compile #(.CFG(LARGE_MESH_CFG)) large_mesh (
    .clk, .resetn, .PRDATA(), .PREADY(), .PSLVERR(),
    .linkUp(), .linkParityError(), .linkCreditError()
  );
endmodule
