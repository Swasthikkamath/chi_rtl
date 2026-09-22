// RN-F 0 reads a shared line, takes a second line unique, and writes
// that line back. The three requests are sequential.
// [SPEC:IHI0050H B4.2] [ASSUMPTION:18]

class chiCoherentTrafficTest extends chiBaseTest;
  `uvm_component_utils(chiCoherentTrafficTest)

  function new(string name = "chiCoherentTrafficTest", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task chiRun();
    chiStart(CHI_VSEQ_COHERENT);
  endtask
endclass
