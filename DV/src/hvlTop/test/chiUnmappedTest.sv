// Always SKIP. An undeliverable address gets no response and would
// hang the link. The test does not drive one. See OPEN QUESTIONS
// finding F-7.

class chiUnmappedTest extends chiBaseTest;
  `uvm_component_utils(chiUnmappedTest)

  function new(string name = "chiUnmappedTest", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task chiRun();
    if (chiSkip(1'b1, "unmappedError is unconnected (F-7)"))
      return;
  endtask
endclass
