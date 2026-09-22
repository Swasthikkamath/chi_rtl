// The Subordinate side of two flows has a genuine choice of shape, and the
// rest of the test list always takes the same branch of each. Here every
// Subordinate takes the other one: a write is completed with DBIDResp and
// then a separate Comp instead of the combined CompDBIDResp, and the
// optional ReadReceipt on an ordered read is withheld.
//
// Both are legal, so a DUT that only works against the default shape is
// broken and nothing else in the list would find out.
// [SPEC:IHI0050H B2.3.9.1 Figure B2.15] [SPEC:IHI0050H B2.3.9.2 Figure B2.16]

class chiRespShapeTest extends chiBaseTest;
  `uvm_component_utils(chiRespShapeTest)

  function new(string name = "chiRespShapeTest", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task chiRun();
    chiStart(CHI_VSEQ_SEPARATE_RESP);
  endtask

  // The point of the test is that the alternative shape was actually driven
  // somewhere. If the DUT sent the Subordinates nothing, the run would be
  // clean and empty, which is not the same as passing.
  function void check_phase(uvm_phase phase);
    int unsigned separateSeen;
    super.check_phase(phase);
    separateSeen = 0;
    foreach (env.agents.snfAgent[i])
      if (env.agents.snfAgent[i].driver != null)
        separateSeen += env.agents.snfAgent[i].driver.separateRespSent;
    foreach (env.agents.sniAgent[i])
      if (env.agents.sniAgent[i].driver != null)
        separateSeen += env.agents.sniAgent[i].driver.separateRespSent;
    if (separateSeen == 0)
      `uvm_error("chiRespShapeTest",
        {"no Subordinate ever sent the separate DBIDResp and Comp pair, so the ",
         "alternative response shape was never presented to the DUT"})
    else
      `uvm_info("chiRespShapeTest",
        $sformatf("%0d writes completed with the separate response pair", separateSeen),
        UVM_LOW)
  endfunction
endclass
