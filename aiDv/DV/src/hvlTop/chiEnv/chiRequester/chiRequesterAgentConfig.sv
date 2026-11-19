// Per-instance configuration for one Requester agent.
//
// Classification is held here rather than inferred inside the agent, because
// the whole point of the arrangement is that each Requester instance can be a
// different class: the env sets nodeClass from chiGlobalsPkg when it builds
// the agent, and everything the agent does that depends on class reads it back
// from this object.
class chiRequesterAgentConfig extends uvm_object;

  // Which agent this is, and therefore which BFM it takes from the config
  // database and which node ordinal and NodeID it owns.
  int unsigned agentId;

  // RN-F, RN-D or RN-I. Fully coherent, I/O coherent with DVM, or I/O coherent
  // [SPEC:IHI0050H B1.6.1].
  chi_node_class_e nodeClass;

  int unsigned nodeOrdinal;
  chiNodeIdT   nodeId;

  // An active agent drives; a passive one only observes. A passive Requester
  // still needs its link brought up by something, so passive is only useful
  // where another model is driving the same pins.
  uvm_active_passive_enum isActive = UVM_ACTIVE;

  // Whether this agent holds cacheable state, and so whether it has a cache
  // model and can be snooped. True only for RN-F.
  bit hasCache;

  // Whether this agent takes part in system coherency, which again is only the
  // fully coherent class [SPEC:IHI0050H B14.7].
  bit usesSystemCoherency;

  // Transactions in flight at once. One is the simplest thing that works and
  // will never provoke a retry; more than one is what makes the Home Node run
  // out of resources and exercise the retry path.
  int unsigned maxOutstanding = 4;

  // Requests are issued with AllowRetry set, which is what permits the Home to
  // answer RetryAck [SPEC:IHI0050H B2.10]. Clearing this is only legal on a
  // request that is already carrying a granted P-Credit.
  bit allowRetry = 1'b1;

  `uvm_object_utils(chiRequesterAgentConfig)

  function new(string name = "chiRequesterAgentConfig");
    super.new(name);
  endfunction

  // Derive everything that follows from the class, so a test only has to set
  // the class and the identity.
  function void configureFromClass();
    hasCache            = isFullyCoherent(nodeClass);
    usesSystemCoherency = isFullyCoherent(nodeClass);
    nodeOrdinal         = requesterOrdinalOf(agentId);
    nodeId              = nodeIdOf(nodeOrdinal);
  endfunction

  function string convert2string();
    return $sformatf(
        {"agent %0d class %s ordinal %0d nodeId 0x%0h cache %0b sysco %0b ",
         "maxOutstanding %0d"},
        agentId, nodeClass.name(), nodeOrdinal, nodeId, hasCache,
        usesSystemCoherency, maxOutstanding);
  endfunction
endclass
