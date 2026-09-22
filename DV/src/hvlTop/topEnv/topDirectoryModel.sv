// Directory reference model. A snoop response that claims a unique
// state is remembered by line address. Two requesters cannot both
// claim unique for the same line. The home that sent the snoop is
// not predicted. [ASSUMPTION:18] [SPEC:IHI0050H B4.8]
// See OPEN QUESTIONS Q18.

typedef struct packed {
  logic [31:0] ordinal;
  chiTxnIdT txnId;
} topDirKeyT;

class topSnoopNote;
  chiAddrT addr;
  bit answered;

  function new();
    answered = 1'b0;
    addr = '0;
  endfunction
endclass

class topDirectoryModel extends uvm_component;
  topSnoopNote snpNote[topDirKeyT];
  int unsigned uniqueOwner[chiAddrT];

  `uvm_component_utils(topDirectoryModel)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function topDirKeyT chiDirKey(input int unsigned ordinal, input chiTxnIdT txnId);
    topDirKeyT key;
    key.ordinal = ordinal;
    key.txnId = txnId;
    return key;
  endfunction

  function bit chiRespUnique(input logic [RESP_W-1:0] resp);
    return (resp == RESP_UC_UD) || (resp == RESP_SD)
      || (resp == RESP_UC_PD) || (resp == RESP_SD_PD);
  endfunction

  function void chiNoteSnp(
    input int unsigned ordinal,
    input chiNodeClassE nodeClass,
    input bit isTx,
    input chiSnpFlitT flit
  );
    topDirKeyT key;
    if (!nodeClassIsRequester(nodeClass) || isTx)
      return;
    if ((flit.opcode == SNP_LCRD_RETURN) || (flit.opcode == SNP_DVM_OP))
      return;
    key = chiDirKey(ordinal, flit.txnId);
    if (!snpNote.exists(key))
      snpNote[key] = new();
    snpNote[key].addr = flit.addr;
    snpNote[key].answered = 1'b0;
  endfunction

  function void chiApplyResp(
    input int unsigned ordinal,
    input chiTxnIdT txnId,
    input logic [RESP_W-1:0] resp
  );
    topDirKeyT key;
    chiAddrT line;
    key = chiDirKey(ordinal, txnId);
    if (!snpNote.exists(key)) begin
      `uvm_error("topDirectoryModel",
        {$sformatf("ordinal %0d snoop response txnId %0h has no snoop", ordinal, txnId)})
      return;
    end
    snpNote[key].answered = 1'b1;
    line = lineAlign(snpNote[key].addr);
    if (chiRespUnique(resp)) begin
      if (uniqueOwner.exists(line) && (uniqueOwner[line] != ordinal))
        `uvm_error("topDirectoryModel",
          {$sformatf("line %0h unique at ordinal %0d and ordinal %0d",
            line, uniqueOwner[line], ordinal)})
      uniqueOwner[line] = ordinal;
    end
    if ((resp == RESP_I) && uniqueOwner.exists(line) && (uniqueOwner[line] == ordinal))
      uniqueOwner.delete(line);
  endfunction

  function void chiNoteRsp(
    input int unsigned ordinal,
    input chiNodeClassE nodeClass,
    input bit isTx,
    input chiRspFlitT flit
  );
    if (!nodeClassIsRequester(nodeClass) || !isTx)
      return;
    if ((flit.opcode == RSP_SNP_RESP) || (flit.opcode == RSP_SNP_RESP_FWDED))
      chiApplyResp(ordinal, flit.txnId, flit.resp);
  endfunction

  function void chiNoteDat(
    input int unsigned ordinal,
    input chiNodeClassE nodeClass,
    input bit isTx,
    input chiDatFlitT flit
  );
    if (!nodeClassIsRequester(nodeClass) || !isTx)
      return;
    if ((flit.opcode == DAT_SNP_RESP_DATA) || (flit.opcode == DAT_SNP_RESP_DATA_PTL)
        || (flit.opcode == DAT_SNP_RESP_DATA_FWDED))
      chiApplyResp(ordinal, flit.txnId, flit.resp);
  endfunction

  function void chiCheckEnd();
    foreach (snpNote[key]) begin
      if (!snpNote[key].answered)
        `uvm_error("topDirectoryModel",
          {$sformatf("ordinal %0d snoop txnId %0h was not answered",
            key.ordinal, key.txnId)})
    end
  endfunction
endclass
