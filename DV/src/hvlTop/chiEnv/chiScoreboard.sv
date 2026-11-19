`ifndef CHISCOREBOARD_INCLUDED
`define CHISCOREBOARD_INCLUDED

class chiScoreboard extends uvm_scoreboard;
  `uvm_component_utils(chiScoreboard)

  uvm_tlm_analysis_fifo#(chiRequestNodeTx) chiRequestNodeAnalysisFifo[NUMOFREQUESTNODE];
  uvm_tlm_analysis_fifo#(chiSubordinateNodeTx) chiSubordinateNodeAnalysisFifo[NUMOFSUBORDINATENODE];
  extern function new(string name="chiScoreboard",uvm_component parent=null);
  extern virtual function void build_phase(uvm_phase phase);
  extern virtual task run_phase(uvm_phase phase);
endclass
function chiScoreboard::new(string name="chiScoreboard",uvm_component parent=null);
  super.new(name,parent);
endfunction 

function void chiScoreboard::build_phase(uvm_phase phase);
  super.build_phase(phase);
  foreach(chiRequestNodeAnalysisFifo[i])begin 
    chiRequestNodeAnalysisFifo[i] = new($sformatf("chiRequestNodeAnalysisFifo[%d]",i),this);
  end 
  foreach(chiSubordinateNodeAnalysisFifo[i])begin
    chiSubordinateNodeAnalysisFifo[i] = new($sformatf("chiSubordinateNodeAnalysisFifo[%d]",i),this);
  end 
endfunction

task chiScoreboard:: run_phase(uvm_phase phase);
 //have forever begin and snoop checks and state check here 
  //and also look whether flist are sent only after credit is received 
endtask 
`endif 
