// Far-atomic datapath for the Home Node. The operation set, the operand
// sizes, and the endianness rules follow IHI 0050H B4.2.5 and B2.9.6.
//
// `size` is the operand size, encoded as the CHI Size field. AtomicCompare
// carries the compare and swap values together, so its request Size covers
// both operands and the caller must present the halved operand size here
// along with the two operands already separated.
module chi_atomic_alu (
  input  chi_pkg::chi_req_opcode_e opcode,
  input  logic [2:0] size,
  input  logic bigEndian,
  input  logic [63:0] initialData,
  input  logic [63:0] transactionData,
  input  logic [63:0] compareData,
  output logic isAtomic,
  output logic returnsData,
  output logic updateEnable,
  output logic [63:0] updateData,
  output logic [63:0] originalData
);
  import chi_pkg::*;

  localparam logic [2:0] SIZE_1B = 3'd0;
  localparam logic [2:0] SIZE_2B = 3'd1;
  localparam logic [2:0] SIZE_4B = 3'd2;
  localparam logic [2:0] SIZE_8B = 3'd3;

  logic [63:0] initialHost;
  logic [63:0] transactionHost;
  logic [63:0] compareHost;
  logic [63:0] resultHost;
  logic [63:0] sumHost;
  logic signed [63:0] initialSigned;
  logic signed [63:0] transactionSigned;
  logic [63:0] initialUnsigned;
  logic [63:0] transactionUnsigned;
  logic replaceWithTransaction;
  logic atomicStore;
  logic atomicLoad;

  // Big-endian atomic data is byte invariant, so the operand bytes are
  // reversed within the operand size before any arithmetic is applied.
  function automatic logic [63:0] toHostOrder(
    input logic [63:0] value,
    input logic [2:0] operandSize,
    input logic swapBytes
  );
    logic [63:0] result;
    result = value;
    if (swapBytes) begin
      result = '0;
      case (operandSize)
        SIZE_2B: for (int unsigned i = 0; i < 2; i++)
          result[i*8 +: 8] = value[(1-i)*8 +: 8];
        SIZE_4B: for (int unsigned i = 0; i < 4; i++)
          result[i*8 +: 8] = value[(3-i)*8 +: 8];
        SIZE_8B: for (int unsigned i = 0; i < 8; i++)
          result[i*8 +: 8] = value[(7-i)*8 +: 8];
        default: result = value;
      endcase
    end
    return result;
  endfunction

  function automatic logic [63:0] maskToSize(
    input logic [63:0] value,
    input logic [2:0] operandSize
  );
    case (operandSize)
      SIZE_1B: return {56'b0, value[7:0]};
      SIZE_2B: return {48'b0, value[15:0]};
      SIZE_4B: return {32'b0, value[31:0]};
      default: return value;
    endcase
  endfunction

  function automatic logic signed [63:0] signExtendToSize(
    input logic [63:0] value,
    input logic [2:0] operandSize
  );
    case (operandSize)
      SIZE_1B: return {{56{value[7]}}, value[7:0]};
      SIZE_2B: return {{48{value[15]}}, value[15:0]};
      SIZE_4B: return {{32{value[31]}}, value[31:0]};
      default: return value;
    endcase
  endfunction

  always_comb begin
    atomicStore = (opcode >= REQ_ATOMIC_STORE_ADD)
                  && (opcode <= REQ_ATOMIC_STORE_UMIN);
    atomicLoad = (opcode >= REQ_ATOMIC_LOAD_ADD)
                 && (opcode <= REQ_ATOMIC_LOAD_UMIN);
    isAtomic = atomicStore || atomicLoad
               || (opcode == REQ_ATOMIC_SWAP)
               || (opcode == REQ_ATOMIC_COMPARE);
    // Every atomic except AtomicStore returns the original value.
    returnsData = isAtomic && !atomicStore;

    initialHost = maskToSize(toHostOrder(initialData, size, bigEndian), size);
    transactionHost =
      maskToSize(toHostOrder(transactionData, size, bigEndian), size);
    compareHost = maskToSize(toHostOrder(compareData, size, bigEndian), size);

    initialSigned = signExtendToSize(initialHost, size);
    transactionSigned = signExtendToSize(transactionHost, size);
    initialUnsigned = initialHost;
    transactionUnsigned = transactionHost;
    sumHost = maskToSize(transactionHost + initialHost, size);

    // The maximum and minimum operations are specified as the sign of the
    // difference between the transaction operand and the stored value.
    replaceWithTransaction = 1'b0;
    case (opcode)
      REQ_ATOMIC_STORE_SMAX, REQ_ATOMIC_LOAD_SMAX:
        replaceWithTransaction = (transactionSigned - initialSigned) > 0;
      REQ_ATOMIC_STORE_SMIN, REQ_ATOMIC_LOAD_SMIN:
        replaceWithTransaction = (transactionSigned - initialSigned) < 0;
      REQ_ATOMIC_STORE_UMAX, REQ_ATOMIC_LOAD_UMAX:
        replaceWithTransaction = transactionUnsigned > initialUnsigned;
      REQ_ATOMIC_STORE_UMIN, REQ_ATOMIC_LOAD_UMIN:
        replaceWithTransaction = transactionUnsigned < initialUnsigned;
      default: replaceWithTransaction = 1'b0;
    endcase

    resultHost = initialHost;
    updateEnable = isAtomic;
    case (opcode)
      REQ_ATOMIC_STORE_ADD, REQ_ATOMIC_LOAD_ADD:
        resultHost = sumHost;
      REQ_ATOMIC_STORE_CLR, REQ_ATOMIC_LOAD_CLR:
        resultHost = maskToSize(initialHost & ~transactionHost, size);
      REQ_ATOMIC_STORE_EOR, REQ_ATOMIC_LOAD_EOR:
        resultHost = maskToSize(initialHost ^ transactionHost, size);
      REQ_ATOMIC_STORE_SET, REQ_ATOMIC_LOAD_SET:
        resultHost = maskToSize(initialHost | transactionHost, size);
      REQ_ATOMIC_STORE_SMAX, REQ_ATOMIC_LOAD_SMAX,
      REQ_ATOMIC_STORE_SMIN, REQ_ATOMIC_LOAD_SMIN,
      REQ_ATOMIC_STORE_UMAX, REQ_ATOMIC_LOAD_UMAX,
      REQ_ATOMIC_STORE_UMIN, REQ_ATOMIC_LOAD_UMIN: begin
        resultHost = replaceWithTransaction ? transactionHost : initialHost;
        updateEnable = replaceWithTransaction;
      end
      REQ_ATOMIC_SWAP:
        resultHost = transactionHost;
      REQ_ATOMIC_COMPARE: begin
        updateEnable = (compareHost == initialHost);
        resultHost = (compareHost == initialHost) ? transactionHost
                                                  : initialHost;
      end
      default: begin
        resultHost = initialHost;
        updateEnable = 1'b0;
      end
    endcase

    updateData = toHostOrder(resultHost, size, bigEndian);
    originalData = toHostOrder(initialHost, size, bigEndian);
  end
endmodule
