// Per-port knobs for one RN-F, RN-D, or RN-I. The node class selects
// which requests are legal. SYSCO is performed only for RN-F, because
// that is the class nodeClassUsesSysCo accepts.
// [ASSUMPTION:4] [ASSUMPTION:13] [ASSUMPTION:14]

class chiRequesterConfig extends uvm_object;
  chiNodeClassE nodeClass;
  int unsigned portIndex;
  int unsigned nodeOrdinal;
  chiNodeIdT nodeId;
  bit portActive;
  int unsigned outstandingCap;
  bit useSysCo;
  // [ASSUMPTION:13] Default tolerates SnpDVMOp on RN-I and counts a warning.
  bit allowRniDvmSnoop;
  // [ASSUMPTION:14] Default does not require the missing DVM DBIDResp phase.
  bit expectDvmDbidResp;
  // Passive port: drive the link pins to STOP so they are not X, and
  // do not activate or issue requests. See OPEN QUESTIONS Q18.
  bit holdQuiet;

  `uvm_object_utils(chiRequesterConfig)

  function new(string name = "chiRequesterConfig");
    super.new(name);
    nodeClass = RN_F;
    portIndex = 0;
    nodeOrdinal = 0;
    nodeId = '0;
    portActive = 1'b1;
    outstandingCap = CHI_TB_OUTSTANDING_CAP;
    useSysCo = 1'b1;
    allowRniDvmSnoop = 1'b1;
    expectDvmDbidResp = 1'b0;
    holdQuiet = 1'b0;
  endfunction

  function void chiNormalize();
    if (!nodeClassIsRequester(nodeClass))
      nodeClass = RN_F;
    if (nodeClass == RN_D)
      nodeOrdinal = OFF_RND + portIndex;
    else if (nodeClass == RN_I)
      nodeOrdinal = OFF_RNI + portIndex;
    else
      nodeOrdinal = OFF_RNF + portIndex;
    nodeId = nodeIdOfOrdinal(nodeOrdinal);
    useSysCo = nodeClassUsesSysCo(nodeClass);
    if (outstandingCap == 0)
      outstandingCap = CHI_TB_OUTSTANDING_CAP;
  endfunction

  function string driverKey();
    return requesterDriverBfmKey(nodeOrdinal);
  endfunction

  function string monitorKey();
    return monitorBfmKey(nodeOrdinal);
  endfunction
endclass
