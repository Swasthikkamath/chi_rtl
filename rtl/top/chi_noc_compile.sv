// Elaboration harness for the fabric alone. It places the population CFG
// describes automatically, derives the NodeIDs from the placement, ties every
// node port off, and builds chi_noc_top, so one module covers every topology.
module chi_noc_compile #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned NUM_PORTS =
    CFG.numRnf + CFG.numRnd + CFG.numRni + CFG.numSnf + CFG.numSni
    + CFG.numHnf + CFG.numHni + CFG.numMn
) (
  input  logic clk,
  input  logic resetn,
  output logic routeError
);
  import chi_cfg_pkg::*;
  import chi_pkg::*;

  typedef chi_mesh_placement_t placement_array_t [NUM_PORTS-1:0];
  typedef logic [CHI_MAX_NODEID_W-1:0] node_id_array_t [NUM_PORTS-1:0];

  function automatic chi_hnf_snf_table_t moduloTable();
    chi_hnf_snf_table_t value;
    for (int unsigned i = 0; i < CHI_MAX_HNF; i++)
      value[i] = '0;
    return value;
  endfunction

  localparam chi_placement_table_t AUTO_PLACEMENTS =
    autoPlacements(CFG, moduloTable());

  function automatic placement_array_t makePlacements();
    placement_array_t value;
    for (int unsigned i = 0; i < NUM_PORTS; i++)
      value[i] = (i < CHI_MAX_NODES) ? AUTO_PLACEMENTS[i] : '0;
    return value;
  endfunction

  localparam placement_array_t PLACEMENTS = makePlacements();

  function automatic node_id_array_t makeNodeIds();
    node_id_array_t value;
    for (int unsigned i = 0; i < NUM_PORTS; i++)
      value[i] = encodeXpNodeId(CFG, xpIndexOfPlacement(CFG, PLACEMENTS[i]),
                                int'(PLACEMENTS[i].devicePort), i);
    return value;
  endfunction

  localparam node_id_array_t NODE_IDS = makeNodeIds();

  logic [NUM_PORTS-1:0] reqInValid, reqInReady, reqOutValid, reqOutReady;
  logic [NUM_PORTS-1:0] rspInValid, rspInReady, rspOutValid, rspOutReady;
  logic [NUM_PORTS-1:0] snpInValid, snpInReady, snpOutValid, snpOutReady;
  logic [NUM_PORTS-1:0] datInValid, datInReady, datOutValid, datOutReady;
  chi_noc_flit_t reqInFlit [NUM_PORTS-1:0];
  chi_noc_flit_t reqOutFlit [NUM_PORTS-1:0];
  chi_noc_flit_t rspInFlit [NUM_PORTS-1:0];
  chi_noc_flit_t rspOutFlit [NUM_PORTS-1:0];
  chi_noc_flit_t snpInFlit [NUM_PORTS-1:0];
  chi_noc_flit_t snpOutFlit [NUM_PORTS-1:0];
  chi_noc_flit_t datInFlit [NUM_PORTS-1:0];
  chi_noc_flit_t datOutFlit [NUM_PORTS-1:0];

  always_comb begin
    reqInValid = '0;
    rspInValid = '0;
    snpInValid = '0;
    datInValid = '0;
    reqOutReady = '1;
    rspOutReady = '1;
    snpOutReady = '1;
    datOutReady = '1;
    for (int unsigned node = 0; node < NUM_PORTS; node++) begin
      reqInFlit[node] = '0;
      rspInFlit[node] = '0;
      snpInFlit[node] = '0;
      datInFlit[node] = '0;
    end
  end

  chi_noc_top #(
    .CFG(CFG),
    .NUM_PORTS(NUM_PORTS),
    .NODE_IDS(NODE_IDS),
    .PLACEMENTS(PLACEMENTS)
  ) noc (
    .*,
    .fabricBusy(),
    .xpInjected(),
    .xpEjected()
  );
endmodule
