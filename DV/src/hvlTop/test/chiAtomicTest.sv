// One atomic load from RN-F 0 when atomicEn is set. The byte compare
// skips atomics. [ASSUMPTION:15] [SPEC:IHI0050H B8.3]

class chiAtomicTest extends chiBaseTest;
  `uvm_component_utils(chiAtomicTest)

  function new(string name = "chiAtomicTest", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task chiRun();
    if (!chiGate(CHI_CFG.atomicEn, "atomicEn"))
      return;
    chiStart(CHI_VSEQ_ATOMIC);
  endtask
endclass
