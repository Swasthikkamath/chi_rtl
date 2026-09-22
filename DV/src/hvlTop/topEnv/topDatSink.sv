// Analysis sink for one DAT direction of one port.

class topDatSink extends uvm_subscriber#(chiDatFlitT);
  int unsigned ordinal;
  chiNodeClassE nodeClass;
  bit isTx;
  topScoreboard sb;

  `uvm_component_utils(topDatSink)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ordinal = 0;
    isTx = 1'b0;
    nodeClass = RN_F;
  endfunction

  function void write(chiDatFlitT t);
    sb.chiNoteDat(ordinal, nodeClass, isTx, t);
  endfunction
endclass
