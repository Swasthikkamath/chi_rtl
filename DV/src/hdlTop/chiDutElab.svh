// Placement parameter for chi_interconnect_top.
// A function that returns an unpacked array of structs is not a
// constant expression on the local elaborator, so each legal node
// count is an assignment pattern of chiMakeOnePlacement. The
// rightmost element is ordinal 0. Counts outside 1..32 fail
// elaboration on purpose.
// [ASSUMPTION:5]

`define CHI_TB_PL_1(cfg) chiMakeOnePlacement((cfg), 0)
`define CHI_TB_PL_2(cfg) chiMakeOnePlacement((cfg), 1), `CHI_TB_PL_1(cfg)
`define CHI_TB_PL_3(cfg) chiMakeOnePlacement((cfg), 2), `CHI_TB_PL_2(cfg)
`define CHI_TB_PL_4(cfg) chiMakeOnePlacement((cfg), 3), `CHI_TB_PL_3(cfg)
`define CHI_TB_PL_5(cfg) chiMakeOnePlacement((cfg), 4), `CHI_TB_PL_4(cfg)
`define CHI_TB_PL_6(cfg) chiMakeOnePlacement((cfg), 5), `CHI_TB_PL_5(cfg)
`define CHI_TB_PL_7(cfg) chiMakeOnePlacement((cfg), 6), `CHI_TB_PL_6(cfg)
`define CHI_TB_PL_8(cfg) chiMakeOnePlacement((cfg), 7), `CHI_TB_PL_7(cfg)
`define CHI_TB_PL_9(cfg) chiMakeOnePlacement((cfg), 8), `CHI_TB_PL_8(cfg)
`define CHI_TB_PL_10(cfg) chiMakeOnePlacement((cfg), 9), `CHI_TB_PL_9(cfg)
`define CHI_TB_PL_11(cfg) chiMakeOnePlacement((cfg), 10), `CHI_TB_PL_10(cfg)
`define CHI_TB_PL_12(cfg) chiMakeOnePlacement((cfg), 11), `CHI_TB_PL_11(cfg)
`define CHI_TB_PL_13(cfg) chiMakeOnePlacement((cfg), 12), `CHI_TB_PL_12(cfg)
`define CHI_TB_PL_14(cfg) chiMakeOnePlacement((cfg), 13), `CHI_TB_PL_13(cfg)
`define CHI_TB_PL_15(cfg) chiMakeOnePlacement((cfg), 14), `CHI_TB_PL_14(cfg)
`define CHI_TB_PL_16(cfg) chiMakeOnePlacement((cfg), 15), `CHI_TB_PL_15(cfg)
`define CHI_TB_PL_17(cfg) chiMakeOnePlacement((cfg), 16), `CHI_TB_PL_16(cfg)
`define CHI_TB_PL_18(cfg) chiMakeOnePlacement((cfg), 17), `CHI_TB_PL_17(cfg)
`define CHI_TB_PL_19(cfg) chiMakeOnePlacement((cfg), 18), `CHI_TB_PL_18(cfg)
`define CHI_TB_PL_20(cfg) chiMakeOnePlacement((cfg), 19), `CHI_TB_PL_19(cfg)
`define CHI_TB_PL_21(cfg) chiMakeOnePlacement((cfg), 20), `CHI_TB_PL_20(cfg)
`define CHI_TB_PL_22(cfg) chiMakeOnePlacement((cfg), 21), `CHI_TB_PL_21(cfg)
`define CHI_TB_PL_23(cfg) chiMakeOnePlacement((cfg), 22), `CHI_TB_PL_22(cfg)
`define CHI_TB_PL_24(cfg) chiMakeOnePlacement((cfg), 23), `CHI_TB_PL_23(cfg)
`define CHI_TB_PL_25(cfg) chiMakeOnePlacement((cfg), 24), `CHI_TB_PL_24(cfg)
`define CHI_TB_PL_26(cfg) chiMakeOnePlacement((cfg), 25), `CHI_TB_PL_25(cfg)
`define CHI_TB_PL_27(cfg) chiMakeOnePlacement((cfg), 26), `CHI_TB_PL_26(cfg)
`define CHI_TB_PL_28(cfg) chiMakeOnePlacement((cfg), 27), `CHI_TB_PL_27(cfg)
`define CHI_TB_PL_29(cfg) chiMakeOnePlacement((cfg), 28), `CHI_TB_PL_28(cfg)
`define CHI_TB_PL_30(cfg) chiMakeOnePlacement((cfg), 29), `CHI_TB_PL_29(cfg)
`define CHI_TB_PL_31(cfg) chiMakeOnePlacement((cfg), 30), `CHI_TB_PL_30(cfg)
`define CHI_TB_PL_32(cfg) chiMakeOnePlacement((cfg), 31), `CHI_TB_PL_31(cfg)

`define CHI_TB_ELAB_DUT(placePattern) \
  chi_interconnect_top #( \
    .CFG(CHI_CFG), \
    .AGE_LIMIT(CHI_TB_AGE_LIMIT), \
    .NUM_REGIONS(CHI_TB_NUM_REGIONS), \
    .NUM_NODES(CHI_TB_NUM_NODES), \
    .NODE_IDS(chiMakeNodeIds(CHI_CFG)), \
    .USE_DEFAULT_PLACEMENTS(1'b0), \
    .PLACEMENTS(placePattern), \
    .CFG_MMIO_BASE(CHI_TB_MMIO_BASE), \
    .USE_DEFAULT_REGIONS(1'b0), \
    .REGION_BASE(REGION_BASE), \
    .REGION_LIMIT(REGION_LIMIT), \
    .REGION_TARGET(REGION_TARGET), \
    .REGION_ATTRIBUTES(REGION_ATTRIBUTES) \
  ) dut ( \
    .clk(clkRst.clk), \
    .resetn(clkRst.resetn), \
    .rnf(rnf), \
    .rnd(rnd), \
    .rni(rni), \
    .snf(snf), \
    .sni(sni), \
    .PADDR(paddr), \
    .PSEL(psel), \
    .PENABLE(penable), \
    .PWRITE(pwrite), \
    .PWDATA(pwdata), \
    .PSTRB(pstrb), \
    .PPROT(pprot), \
    .PRDATA(prdata), \
    .PREADY(pready), \
    .PSLVERR(pslverr), \
    .linkUp(linkUp), \
    .linkParityError(linkParityError), \
    .linkCreditError(linkCreditError) \
  );

generate
  if (CHI_TB_NUM_NODES == 1) begin : dutN1
    `CHI_TB_ELAB_DUT('{`CHI_TB_PL_1(CHI_CFG)})
  end
  else if (CHI_TB_NUM_NODES == 2) begin : dutN2
    `CHI_TB_ELAB_DUT('{`CHI_TB_PL_2(CHI_CFG)})
  end
  else if (CHI_TB_NUM_NODES == 3) begin : dutN3
    `CHI_TB_ELAB_DUT('{`CHI_TB_PL_3(CHI_CFG)})
  end
  else if (CHI_TB_NUM_NODES == 4) begin : dutN4
    `CHI_TB_ELAB_DUT('{`CHI_TB_PL_4(CHI_CFG)})
  end
  else if (CHI_TB_NUM_NODES == 5) begin : dutN5
    `CHI_TB_ELAB_DUT('{`CHI_TB_PL_5(CHI_CFG)})
  end
  else if (CHI_TB_NUM_NODES == 6) begin : dutN6
    `CHI_TB_ELAB_DUT('{`CHI_TB_PL_6(CHI_CFG)})
  end
  else if (CHI_TB_NUM_NODES == 7) begin : dutN7
    `CHI_TB_ELAB_DUT('{`CHI_TB_PL_7(CHI_CFG)})
  end
  else if (CHI_TB_NUM_NODES == 8) begin : dutN8
    `CHI_TB_ELAB_DUT('{`CHI_TB_PL_8(CHI_CFG)})
  end
  else if (CHI_TB_NUM_NODES == 9) begin : dutN9
    `CHI_TB_ELAB_DUT('{`CHI_TB_PL_9(CHI_CFG)})
  end
  else if (CHI_TB_NUM_NODES == 10) begin : dutN10
    `CHI_TB_ELAB_DUT('{`CHI_TB_PL_10(CHI_CFG)})
  end
  else if (CHI_TB_NUM_NODES == 11) begin : dutN11
    `CHI_TB_ELAB_DUT('{`CHI_TB_PL_11(CHI_CFG)})
  end
  else if (CHI_TB_NUM_NODES == 12) begin : dutN12
    `CHI_TB_ELAB_DUT('{`CHI_TB_PL_12(CHI_CFG)})
  end
  else if (CHI_TB_NUM_NODES == 13) begin : dutN13
    `CHI_TB_ELAB_DUT('{`CHI_TB_PL_13(CHI_CFG)})
  end
  else if (CHI_TB_NUM_NODES == 14) begin : dutN14
    `CHI_TB_ELAB_DUT('{`CHI_TB_PL_14(CHI_CFG)})
  end
  else if (CHI_TB_NUM_NODES == 15) begin : dutN15
    `CHI_TB_ELAB_DUT('{`CHI_TB_PL_15(CHI_CFG)})
  end
  else if (CHI_TB_NUM_NODES == 16) begin : dutN16
    `CHI_TB_ELAB_DUT('{`CHI_TB_PL_16(CHI_CFG)})
  end
  else if (CHI_TB_NUM_NODES == 17) begin : dutN17
    `CHI_TB_ELAB_DUT('{`CHI_TB_PL_17(CHI_CFG)})
  end
  else if (CHI_TB_NUM_NODES == 18) begin : dutN18
    `CHI_TB_ELAB_DUT('{`CHI_TB_PL_18(CHI_CFG)})
  end
  else if (CHI_TB_NUM_NODES == 19) begin : dutN19
    `CHI_TB_ELAB_DUT('{`CHI_TB_PL_19(CHI_CFG)})
  end
  else if (CHI_TB_NUM_NODES == 20) begin : dutN20
    `CHI_TB_ELAB_DUT('{`CHI_TB_PL_20(CHI_CFG)})
  end
  else if (CHI_TB_NUM_NODES == 21) begin : dutN21
    `CHI_TB_ELAB_DUT('{`CHI_TB_PL_21(CHI_CFG)})
  end
  else if (CHI_TB_NUM_NODES == 22) begin : dutN22
    `CHI_TB_ELAB_DUT('{`CHI_TB_PL_22(CHI_CFG)})
  end
  else if (CHI_TB_NUM_NODES == 23) begin : dutN23
    `CHI_TB_ELAB_DUT('{`CHI_TB_PL_23(CHI_CFG)})
  end
  else if (CHI_TB_NUM_NODES == 24) begin : dutN24
    `CHI_TB_ELAB_DUT('{`CHI_TB_PL_24(CHI_CFG)})
  end
  else if (CHI_TB_NUM_NODES == 25) begin : dutN25
    `CHI_TB_ELAB_DUT('{`CHI_TB_PL_25(CHI_CFG)})
  end
  else if (CHI_TB_NUM_NODES == 26) begin : dutN26
    `CHI_TB_ELAB_DUT('{`CHI_TB_PL_26(CHI_CFG)})
  end
  else if (CHI_TB_NUM_NODES == 27) begin : dutN27
    `CHI_TB_ELAB_DUT('{`CHI_TB_PL_27(CHI_CFG)})
  end
  else if (CHI_TB_NUM_NODES == 28) begin : dutN28
    `CHI_TB_ELAB_DUT('{`CHI_TB_PL_28(CHI_CFG)})
  end
  else if (CHI_TB_NUM_NODES == 29) begin : dutN29
    `CHI_TB_ELAB_DUT('{`CHI_TB_PL_29(CHI_CFG)})
  end
  else if (CHI_TB_NUM_NODES == 30) begin : dutN30
    `CHI_TB_ELAB_DUT('{`CHI_TB_PL_30(CHI_CFG)})
  end
  else if (CHI_TB_NUM_NODES == 31) begin : dutN31
    `CHI_TB_ELAB_DUT('{`CHI_TB_PL_31(CHI_CFG)})
  end
  else if (CHI_TB_NUM_NODES == 32) begin : dutN32
    `CHI_TB_ELAB_DUT('{`CHI_TB_PL_32(CHI_CFG)})
  end
  else begin : dutNOutOfRange
    chiTbNodeCountExceedsElabLimit unsupported ();
  end
endgenerate

`undef CHI_TB_ELAB_DUT
`undef CHI_TB_PL_1
`undef CHI_TB_PL_2
`undef CHI_TB_PL_3
`undef CHI_TB_PL_4
`undef CHI_TB_PL_5
`undef CHI_TB_PL_6
`undef CHI_TB_PL_7
`undef CHI_TB_PL_8
`undef CHI_TB_PL_9
`undef CHI_TB_PL_10
`undef CHI_TB_PL_11
`undef CHI_TB_PL_12
`undef CHI_TB_PL_13
`undef CHI_TB_PL_14
`undef CHI_TB_PL_15
`undef CHI_TB_PL_16
`undef CHI_TB_PL_17
`undef CHI_TB_PL_18
`undef CHI_TB_PL_19
`undef CHI_TB_PL_20
`undef CHI_TB_PL_21
`undef CHI_TB_PL_22
`undef CHI_TB_PL_23
`undef CHI_TB_PL_24
`undef CHI_TB_PL_25
`undef CHI_TB_PL_26
`undef CHI_TB_PL_27
`undef CHI_TB_PL_28
`undef CHI_TB_PL_29
`undef CHI_TB_PL_30
`undef CHI_TB_PL_31
`undef CHI_TB_PL_32
