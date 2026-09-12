module chi_stage1_compile #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT
);
  import chi_cfg_pkg::*;
  import chi_pkg::*;

  localparam int unsigned NUM_LOGICAL_NODES =
    CFG.numRnf + CFG.numRnd + CFG.numRni + CFG.numSnf + CFG.numSni
    + CFG.numHnf + CFG.numHni + CFG.numMn;
  // Independent sums of the fields consumed by each pack/unpack function.
  localparam int unsigned REQ_PACKED_FIELDS_W =
    4 + CFG.nodeIdW + CFG.nodeIdW + CFG.txnIdW + CFG.nodeIdW + 1
    + CFG.txnIdW + 7 + 3 + CFG.addrW + 1 + 1 + 1 + 1 + 2 + 4 + 4 + 1
    + reqGroupLpidWidth(CFG) + 1 + 1 + 2 + 1
    + (CFG.mpamEn ? CHI_MPAM_W : 0) + (CFG.mecEn ? CHI_MECID_W : 0)
    + CFG.rsvdcW;
  localparam int unsigned RSP_PACKED_FIELDS_W =
    4 + CFG.nodeIdW + CFG.nodeIdW + CFG.txnIdW + 5 + 2 + 3 + 3 + 3
    + rspDbidGroupWidth(CFG) + 4 + 2 + 1;
  localparam int unsigned SNP_PACKED_FIELDS_W =
    4 + CFG.nodeIdW + CFG.txnIdW + CFG.nodeIdW
    + snpTxnLpidVmidWidth(CFG) + 5 + (CFG.addrW - 3) + 1 + 1 + 1 + 1 + 1
    + (CFG.mpamEn ? CHI_MPAM_W : 0) + (CFG.mecEn ? CHI_MECID_W : 0);
  localparam int unsigned DAT_PACKED_FIELDS_W =
    4 + CFG.nodeIdW + CFG.nodeIdW + CFG.txnIdW + CFG.nodeIdW
    + 4 + 2 + 3 + 8 + 1 + 3 + datDbidMecWidth(CFG) + CFG.ccidW
    + 2 + 2 + (CFG.dataW / 32) + (CFG.dataW / 128) + 1 + 1 + 2 + 1
    + CFG.rsvdcW + (CFG.dataW / 8) + CFG.dataW
    + (CFG.dataCheckEn ? (CFG.dataW / 8) : 0)
    + (CFG.poisonEn ? (CFG.dataW / 64) : 0);

  chi_if      #(.CFG(CFG)) nodeLink();

  generate
    begin : chi_cfg_check
      if (!((CFG.dataW == 128) || (CFG.dataW == 256) || (CFG.dataW == 512))) begin : check_data_w
        initial $fatal(1, "CHI DATA_W must be 128, 256, or 512");
      end
      if ((CFG.addrW < CHI_MIN_ADDR_W) || (CFG.addrW > CHI_MAX_ADDR_W)) begin : check_addr_w
        initial $fatal(1, "CHI ADDR_W must be in [44,52]");
      end
      if ((CFG.nodeIdW < CHI_MIN_NODEID_W) || (CFG.nodeIdW > CHI_MAX_NODEID_W)) begin : check_nodeid_w
        initial $fatal(1, "CHI NODEID_W must be in [7,11]");
      end
      if ((CFG.txnIdW < CHI_MIN_TXNID_W) || (CFG.txnIdW > CHI_MAX_TXNID_W)) begin : check_txnid_w
        initial $fatal(1, "CHI TXNID_W must be in [8,12]");
      end
      if ((CFG.lpidW < CHI_MIN_LPID_W) || (CFG.lpidW > CHI_MAX_LPID_W)) begin : check_lpid_w
        initial $fatal(1, "CHI LPID_W must be in [1,5]");
      end
      if ((CFG.groupIdW < CHI_MIN_GROUPID_W) || (CFG.groupIdW > CHI_MAX_GROUPID_W)) begin : check_groupid_w
        initial $fatal(1, "CHI GROUPID_W must be in [1,8]");
      end
      if ((CFG.ccidW < CHI_MIN_CCID_W) || (CFG.ccidW > CHI_MAX_CCID_W)) begin : check_ccid_w
        initial $fatal(1, "CHI CCID_W must be in [1,2]");
      end
      if ((reqFlitWidth(CFG) != REQ_PACKED_FIELDS_W)
          || (reqFlitWidth(CFG) > CHI_MAX_REQ_FLIT_W)) begin : check_req_layout_w
        initial $fatal(1, "REQ width helper does not match packed fields or backing storage");
      end
      if ((rspFlitWidth(CFG) != RSP_PACKED_FIELDS_W)
          || (rspFlitWidth(CFG) > CHI_MAX_RSP_FLIT_W)) begin : check_rsp_layout_w
        initial $fatal(1, "RSP width helper does not match packed fields or backing storage");
      end
      if ((snpFlitWidth(CFG) != SNP_PACKED_FIELDS_W)
          || (snpFlitWidth(CFG) > CHI_MAX_SNP_FLIT_W)) begin : check_snp_layout_w
        initial $fatal(1, "SNP width helper does not match packed fields or backing storage");
      end
      if ((datFlitWidth(CFG) != DAT_PACKED_FIELDS_W)
          || (datFlitWidth(CFG) > CHI_MAX_DAT_FLIT_W)) begin : check_dat_layout_w
        initial $fatal(1, "DAT width helper does not match packed fields or backing storage");
      end
      if (!((CFG.rsvdcW == 0) || (CFG.rsvdcW == 4) || (CFG.rsvdcW == 8)
            || (CFG.rsvdcW == 12) || (CFG.rsvdcW == 16)
            || (CFG.rsvdcW == 24) || (CFG.rsvdcW == CHI_MAX_RSVDC_W))) begin : check_rsvdc_w
        initial $fatal(1, "CHI RSVDC_W must be 0, 4, 8, 12, 16, 24, or 32");
      end
      if ((CFG.numIfPerNode == 0) || (CFG.replChannels == 0)
          || (CFG.posEntries == 0) || (CFG.lcrdDepth == 0)) begin : check_positive_counts
        initial $fatal(1, "Interface, replication, POS, and L-Credit counts must be positive");
      end
      if ((CFG.snpFilterEntries == 0) || (CFG.snpFilterWays == 0)
          || ((CFG.snpFilterEntries % CFG.snpFilterWays) != 0)) begin : check_snp_filter
        initial $fatal(1, "Invalid snoop-filter geometry");
      end
      if (CFG.dctEn && ((CFG.numRnf == 0) || (CFG.numHnf == 0))) begin : check_dct
        initial $fatal(1, "DCT requires RN-F and HN-F nodes");
      end
      if ((CFG.dmtEn || CFG.dwtEn) && (((CFG.numHnf + CFG.numHni) == 0) || (CFG.numSnf == 0))) begin : check_direct_transfer
        initial $fatal(1, "DMT/DWT requires a Home Node and SN-F");
      end
      if (CFG.stashEn && ((CFG.numRnf == 0) || (CFG.numHnf == 0))) begin : check_stash
        initial $fatal(1, "Stash requires RN-F and HN-F nodes");
      end
      if (CFG.dvmEn && ((CFG.numMn == 0) || ((CFG.numRnf + CFG.numRnd) == 0))) begin : check_dvm
        initial $fatal(1, "DVM requires an MN and a DVM-capable Request Node");
      end
      if (CFG.exclEn && (((CFG.numHnf + CFG.numHni) == 0) || (CFG.exclMonitors == 0))) begin : check_exclusive
        initial $fatal(1, "Exclusive accesses require a Home Node and monitor storage");
      end
      if (CFG.mecEn && (CHI_MECID_W != 16)) begin : check_mec
        initial $fatal(1, "Issue H MECID width must be 16");
      end
      if ((CFG.interleaveGranule < 64)
          || ((CFG.interleaveGranule & (CFG.interleaveGranule - 1)) != 0)) begin : check_interleave
        initial $fatal(1, "Interleave granule must be a power of two of at least 64 bytes");
      end
      if ((CFG.topology == MESH_2D)
          && ((CFG.meshX == 0) || (CFG.meshY == 0) || (CFG.numDevPortsPerXp == 0))) begin : check_mesh_dims
        initial $fatal(1, "Mesh dimensions and device-port count must be positive");
      end
      if ((CFG.topology == MESH_2D)
          && ((CFG.meshX * CFG.meshY * CFG.numDevPortsPerXp) < NUM_LOGICAL_NODES)) begin : check_mesh_capacity
        initial $fatal(1, "Mesh placement capacity is smaller than the logical node count");
      end
      if ((CFG.topology == MESH_2D) && (deviceIdWidth(CFG) <= 0)) begin : check_device_id_w
        initial $fatal(1, "NodeID has no deviceId bits");
      end
      if ((CFG.topology == MESH_2D)
          && (NUM_LOGICAL_NODES > (1 << deviceIdWidth(CFG)))) begin : check_device_id_capacity
        initial $fatal(1, "Logical node ordinal does not fit the NodeID deviceId field");
      end
      if ((CFG.cfgAccess == CFG_CHI_MMIO) && (CFG.numHni == 0)) begin : check_cfg_endpoint
        initial $fatal(1, "CHI-MMIO configuration requires an HN-I endpoint");
      end
    end
  endgenerate
endmodule
