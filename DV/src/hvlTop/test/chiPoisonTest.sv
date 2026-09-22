// A WriteNoSnp carries a non-zero Poison and DataCheck, then a
// ReadNoSnp reads the line back. Skips when Poison is not on the bus.
// [ASSUMPTION:15] [SPEC:IHI0050H B9.6]

class chiPoisonTest extends chiBaseTest;
  `uvm_component_utils(chiPoisonTest)

  function new(string name = "chiPoisonTest", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task chiRun();
    if (!chiGate(CHI_CFG.poisonEn, "poisonEn"))
      return;
    pinPoison = 1'b1;
    poisonValue = 8'h1;
    if (CHI_CFG.dataCheckEn) begin
      pinDataCheck = 1'b1;
      dataCheckValue = 64'h1;
      env.scoreboard.memoryModel.expectDataCheck = 1'b1;
    end
    env.scoreboard.memoryModel.expectPoison = 1'b1;
    chiStart(CHI_VSEQ_POISON);
  endtask
endclass
