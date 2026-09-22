// ReadNoSnp with Order set. The lifecycle model reports an error if
// completion or data arrives before ReadReceipt. [SPEC:IHI0050H B2.7]

class chiOrderTest extends chiBaseTest;
  `uvm_component_utils(chiOrderTest)

  function new(string name = "chiOrderTest", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task chiRun();
    chiStart(CHI_VSEQ_ORDER);
  endtask
endclass
