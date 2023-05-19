module width_adapter_64_to_32
(
  input logic 	      clk,
  input logic 	      rst,

  // start of packet
  input logic         sop,

  // 64 bit wide input
  input logic         input_valid,
  input logic [63:0]  input_data,
  output logic        input_ready,

  // 32 bit wide output
  output logic        output_valid,
  output logic [31:0] output_data,
  input logic         output_ready
);

  // FSM states
  enum {
    STATE_TIK,
    STATE_TOK
  } state;

  assign input_ready  = output_ready & (state == STATE_TOK);
  assign output_valid = input_valid;
  assign output_data = (state == STATE_TIK) ? {{input_data[7:0]},{input_data[15:8]},{input_data[23:16]},{input_data[31:24]}} 
                                            : {{input_data[39:32]},{input_data[47:40]},{input_data[55:48]},{input_data[63:56]}}; 

  always_ff @(posedge clk) begin
    if (rst | sop) begin
      state        <= STATE_TIK;

    end else begin
      case (state)
        STATE_TIK: begin
          if (input_valid) begin
            state        <= output_ready ? STATE_TOK : STATE_TIK;
          end else begin
            state        <= STATE_TIK;
          end
        end

        STATE_TOK: begin
          if (input_valid) begin
            state <= output_ready ? STATE_TIK : STATE_TOK;
          end else begin
            state <= STATE_TOK;
          end
        end

        default: begin
          state        <= STATE_TIK;
        end

      endcase
    end
  end
 
endmodule 

