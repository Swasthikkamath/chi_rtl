// No protocol traffic. The base run waits while every active driver
// brings its link to RUN and the shutdown phase deactivates it.
// [ASSUMPTION:3] [ASSUMPTION:16]

class chiLinkBringUpTest extends chiBaseTest;
  `uvm_component_utils(chiLinkBringUpTest)

  function new(string name = "chiLinkBringUpTest", uvm_component parent = null);
    super.new(name, parent);
  endfunction
endclass
