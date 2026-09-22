// Per-port knobs for one SN-F or SN-I. The node class selects which
// requests are legal to answer without an error. SYSCO is not used:
// nodeClassUsesSysCo is RN-F only.
// [ASSUMPTION:4] [ASSUMPTION:15]

class chiSubordinateConfig extends uvm_object;
  chiNodeClassE nodeClass;
  int unsigned portIndex;
  int unsigned nodeOrdinal;
  chiNodeIdT nodeId;
  bit portActive;
  int unsigned outstandingCap;
  bit enableRetry;
  chiRespErrE injectRespErr;

  `uvm_object_utils(chiSubordinateConfig)

  function new(string name = "chiSubordinateConfig");
    super.new(name);
    nodeClass = SN_F;
    portIndex = 0;
    nodeOrdinal = 0;
    nodeId = '0;
    portActive = 1'b1;
    outstandingCap = CHI_TB_OUTSTANDING_CAP;
    enableRetry = 1'b0;
    injectRespErr = RESP_ERR_OK;
  endfunction

  function void chiNormalize();
    if ((nodeClass != SN_F) && (nodeClass != SN_I))
      nodeClass = SN_F;
    if (nodeClass == SN_I)
      nodeOrdinal = OFF_SNI + portIndex;
    else
      nodeOrdinal = OFF_SNF + portIndex;
    nodeId = nodeIdOfOrdinal(nodeOrdinal);
    if (outstandingCap == 0)
      outstandingCap = CHI_TB_OUTSTANDING_CAP;
  endfunction

  function string driverKey();
    return subordinateDriverBfmKey(nodeOrdinal);
  endfunction

  function string monitorKey();
    return monitorBfmKey(nodeOrdinal);
  endfunction
endclass
