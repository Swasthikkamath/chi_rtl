// Per-port knobs for one SN-F or SN-I. As with the requester, the node
// class lives here rather than in a subclass, so one agent covers both.
//
// The response-shape knobs exist because the specification gives the
// Subordinate a genuine choice on two flows, and a testbench that always
// picks the same one leaves half of the DUT's receive logic unexercised.
// [SPEC:IHI0050H B2.3.9.2 Home to Subordinate Write transactions]
// [SPEC:IHI0050H B2.3.9.3 Home to Subordinate Write Zero transactions]

class chiSubordinateConfig extends uvm_object;
  chiNodeClassE nodeClass;
  int unsigned portIndex;
  int unsigned nodeOrdinal;
  chiNodeIdT nodeId;
  bit portActive;

  // How many requests this Subordinate will work on at once. Requests beyond
  // this sit in the BFM's receive queue and the credit loop stops granting,
  // which is the only backpressure a Subordinate has.
  int unsigned outstandingCap;

  // Write completion shape. 1 sends the combined CompDBIDResp, 0 sends
  // DBIDResp and then a separate Comp. Both are legal for every write this
  // Subordinate can receive. [SPEC:IHI0050H B2.3.9.2]
  bit combinedWriteResp;

  // The Subordinate has no choice of read response shape: ReadNoSnp is
  // answered with CompData and ReadNoSnpSep with DataSepResp, selected by
  // the opcode. What it does choose is whether to send the optional
  // ReadReceipt when the request carries a non-zero Order.
  // [SPEC:IHI0050H B2.3.9.1 Home to Subordinate Read transactions]
  bit sendReadReceipt;

  // Response latency in clocks, sampled uniformly per response. A zero-width
  // range is allowed and means a fixed latency.
  int unsigned minRespDelay;
  int unsigned maxRespDelay;

  // Error injection. The driver consults the sequence first; these are the
  // standing defaults for requests no sequence item matched.
  chiRespErrE defaultRespErr;

  // Retry. A Subordinate that is out of resources answers a retryable
  // request with RetryAck and later a PCrdGrant, and the Requester resends
  // with AllowRetry clear. Off by default because a Subordinate that always
  // retries hides every other check behind the retry loop.
  // [SPEC:IHI0050H B2.12 Transaction retry]
  bit enableRetry;

  // Passive port: drive the link pins to STOP so they are not X, and do
  // not activate or answer. See OPEN QUESTIONS Q18.
  bit holdQuiet;

  // Whether this port answers PrefetchTgt at all. The specification gives
  // PrefetchTgt no response, so the default is to silently drop it, and the
  // knob exists only so a test can prove the DUT does not wait for one.
  // [SPEC:IHI0050H C4.30 PrefetchTgt]
  bit dropPrefetchTgt;

  `uvm_object_utils(chiSubordinateConfig)

  function new(string name = "chiSubordinateConfig");
    super.new(name);
    nodeClass = SN_F;
    portIndex = 0;
    nodeOrdinal = 0;
    nodeId = '0;
    portActive = 1'b1;
    outstandingCap = CHI_TB_SN_OUTSTANDING_CAP;
    combinedWriteResp = 1'b1;
    sendReadReceipt = 1'b1;
    minRespDelay = 0;
    maxRespDelay = 4;
    defaultRespErr = RESP_ERR_OK;
    enableRetry = 1'b0;
    holdQuiet = 1'b0;
    dropPrefetchTgt = 1'b1;
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
      outstandingCap = CHI_TB_SN_OUTSTANDING_CAP;
    if (maxRespDelay < minRespDelay)
      maxRespDelay = minRespDelay;
  endfunction

  function string driverKey();
    return subordinateDriverBfmKey(nodeOrdinal);
  endfunction

  function string monitorKey();
    return monitorBfmKey(nodeOrdinal);
  endfunction
endclass
