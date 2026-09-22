// Subordinates answer the next request with NDERR. The read must still
// complete so the link can deactivate. [SPEC:IHI0050H B4.8]

class chiRespErrTest extends chiBaseTest;
  `uvm_component_utils(chiRespErrTest)

  function new(string name = "chiRespErrTest", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task chiRun();
    chiStart(CHI_VSEQ_RESP_ERR);
  endtask
endclass
