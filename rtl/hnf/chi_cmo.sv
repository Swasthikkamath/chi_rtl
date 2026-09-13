module chi_cmo (
  input  logic clk,
  input  logic resetn,
  input  chi_pkg::chi_req_opcode_e opcode,
  input  logic startValid,
  input  logic completionValid,
  input  logic persistValid,
  output logic isCmo,
  output logic isWrite,
  output logic combinedWriteCmo,
  output logic requiresSnoopCompletion,
  output logic requiresPersist,
  output logic [2:0] category,
  output logic completionPending,
  output logic persistPending,
  output logic done
);
  import chi_pkg::*;

  typedef enum logic [2:0] {
    CMO_NONE, CMO_CLEAN_SHARED, CMO_CLEAN_INVALID, CMO_MAKE_INVALID,
    CMO_PERSIST, CMO_WRITE_CLEAN, CMO_WRITE_INVALID
  } cmo_category_e;
  cmo_category_e decodedCategory;
  logic active;

  always_comb begin
    decodedCategory = CMO_NONE;
    isWrite = 1'b0;
    combinedWriteCmo = 1'b0;
    requiresPersist = 1'b0;
    case (opcode)
      REQ_CLEAN_SHARED: decodedCategory = CMO_CLEAN_SHARED;
      REQ_CLEAN_INVALID, REQ_CLEAN_INVALID_POPA:
        decodedCategory = CMO_CLEAN_INVALID;
      REQ_MAKE_INVALID: decodedCategory = CMO_MAKE_INVALID;
      REQ_CLEAN_SHARED_PERSIST, REQ_CLEAN_SHARED_PERSIST_SEP: begin
        decodedCategory = CMO_PERSIST;
        requiresPersist = 1'b1;
      end
      REQ_WRITE_NO_SNP_FULL_CLEAN_SH,
      REQ_WRITE_UNIQUE_FULL_CLEAN_SH,
      REQ_WRITE_BACK_FULL_CLEAN_SH,
      REQ_WRITE_CLEAN_FULL_CLEAN_SH,
      REQ_WRITE_NO_SNP_PTL_CLEAN_SH,
      REQ_WRITE_UNIQUE_PTL_CLEAN_SH: begin
        decodedCategory = CMO_WRITE_CLEAN;
        isWrite = 1'b1;
        combinedWriteCmo = 1'b1;
      end
      REQ_WRITE_NO_SNP_FULL_CLEAN_SH_PER_SEP,
      REQ_WRITE_UNIQUE_FULL_CLEAN_SH_PER_SEP,
      REQ_WRITE_BACK_FULL_CLEAN_SH_PER_SEP,
      REQ_WRITE_CLEAN_FULL_CLEAN_SH_PER_SEP,
      REQ_WRITE_NO_SNP_PTL_CLEAN_SH_PER_SEP,
      REQ_WRITE_UNIQUE_PTL_CLEAN_SH_PER_SEP: begin
        decodedCategory = CMO_WRITE_CLEAN;
        isWrite = 1'b1;
        combinedWriteCmo = 1'b1;
        requiresPersist = 1'b1;
      end
      REQ_WRITE_NO_SNP_FULL_CLEAN_INV,
      REQ_WRITE_BACK_FULL_CLEAN_INV,
      REQ_WRITE_NO_SNP_PTL_CLEAN_INV,
      REQ_WRITE_NO_SNP_PTL_CLEAN_INV_POPA,
      REQ_WRITE_NO_SNP_FULL_CLEAN_INV_POPA,
      REQ_WRITE_BACK_FULL_CLEAN_INV_POPA: begin
        decodedCategory = CMO_WRITE_INVALID;
        isWrite = 1'b1;
        combinedWriteCmo = 1'b1;
      end
      default: begin
        isWrite = (opcode == REQ_WRITE_EVICT_FULL)
                  || (opcode == REQ_WRITE_CLEAN_FULL)
                  || (opcode == REQ_WRITE_UNIQUE_PTL)
                  || (opcode == REQ_WRITE_UNIQUE_FULL)
                  || (opcode == REQ_WRITE_BACK_PTL)
                  || (opcode == REQ_WRITE_BACK_FULL)
                  || (opcode == REQ_WRITE_NO_SNP_PTL)
                  || (opcode == REQ_WRITE_NO_SNP_FULL)
                  || (opcode == REQ_WRITE_UNIQUE_ZERO)
                  || (opcode == REQ_WRITE_NO_SNP_ZERO);
      end
    endcase
    isCmo = decodedCategory != CMO_NONE;
    requiresSnoopCompletion = isCmo && (decodedCategory != CMO_PERSIST);
    category = decodedCategory;
  end

  always_ff @(posedge clk) begin
    if (!resetn) begin
      active <= 1'b0;
      completionPending <= 1'b0;
      persistPending <= 1'b0;
      done <= 1'b0;
    end else begin
      done <= 1'b0;
      if (startValid && isCmo) begin
        active <= 1'b1;
        completionPending <= requiresSnoopCompletion;
        persistPending <= requiresPersist;
        if (!requiresSnoopCompletion && !requiresPersist) begin
          active <= 1'b0;
          done <= 1'b1;
        end
      end
      if (active) begin
        if (completionValid)
          completionPending <= 1'b0;
        if (persistValid)
          persistPending <= 1'b0;
        if ((!completionPending || completionValid)
            && (!persistPending || persistValid)) begin
          active <= 1'b0;
          done <= 1'b1;
        end
      end
    end
  end
endmodule
