// Per-instance configuration for one Subordinate agent.
class chiSubordinateAgentConfig extends uvm_object;

  int unsigned     agentId;
  // SN-F or SN-I. A fully coherent Subordinate sits behind the Home Nodes and
  // backs coherent memory; an I/O Subordinate backs a peripheral region
  // [SPEC:IHI0050H B1.6.1].
  chi_node_class_e nodeClass;

  int unsigned nodeOrdinal;
  chiNodeIdT   nodeId;

  uvm_active_passive_enum isActive = UVM_ACTIVE;

  // Requests served concurrently. A Subordinate that served one at a time
  // would serialise the whole fabric behind it.
  int unsigned maxConcurrentRequests = 8;

  // Default answer latency in cycles when no sequence supplies a policy.
  int unsigned defaultResponseDelay = 2;

  `uvm_object_utils(chiSubordinateAgentConfig)

  function new(string name = "chiSubordinateAgentConfig");
    super.new(name);
  endfunction

  function void configureFromClass();
    nodeOrdinal = subordinateOrdinalOf(agentId);
    nodeId      = nodeIdOf(nodeOrdinal);
  endfunction

  function string convert2string();
    return $sformatf("subordinate %0d class %s ordinal %0d nodeId 0x%0h",
                     agentId, nodeClass.name(), nodeOrdinal, nodeId);
  endfunction
endclass
