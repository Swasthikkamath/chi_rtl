// Analysis sink for the subordinate monitor's raw sample port. That
// port is the only one that carries CompAck and L-Credit returns.

class topFlitSink extends uvm_subscriber#(chiFlitSampleT);
  topScoreboard sb;

  `uvm_component_utils(topFlitSink)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void write(chiFlitSampleT t);
    sb.chiNoteSample(t);
  endfunction
endclass
