// Analysis sink for RX SNP on one requester port.

class topSnpSink extends uvm_subscriber#(chiSnpFlitT);
  int unsigned ordinal;
  chiNodeClassE nodeClass;
  bit isTx;
  topScoreboard sb;

  `uvm_component_utils(topSnpSink)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ordinal = 0;
    isTx = 1'b0;
    nodeClass = RN_F;
  endfunction

  function void write(chiSnpFlitT t);
    sb.chiNoteSnp(ordinal, nodeClass, isTx, t);
  endfunction
endclass
