module width_adapter_32_to_64
(
  input logic 	      clk,
  input logic 	      rst,

  // start of packet
  input logic         sop,

  // 32 bit wide input
  input logic         input_valid,
  input logic [31:0]  input_data,
  output logic        input_ready,

  // 64 bit wide output
  output logic        output_valid,
  output logic [63:0] output_data,
  input logic         output_ready
);

  logic i_input_ready;
  assign i_input_ready = input_valid;
  assign input_ready = i_input_ready;

  // FSM states
  enum {
    STATE_TIK,
    STATE_TOK
  } state;

  always_ff @(posedge clk) begin
    if (rst | sop) begin
      state        <= STATE_TIK;
      output_valid <= 1'b0;
      output_data  <= 'b0;

    end else begin
      case (state)
        STATE_TIK: begin
          if (input_valid) begin
            state              <= STATE_TOK;
            output_valid       <= 1'b0;
            output_data[31:0]  <= {{input_data[7:0]}, {input_data[15:8]}, {input_data[23:16]}, {input_data[31:24]}};
          end else begin
            state              <= STATE_TIK;
            output_valid       <= 1'b0;
          end
        end

        STATE_TOK: begin
          if (input_valid) begin
            state              <= STATE_TIK;
            output_valid       <= 1'b1;
            output_data[63:32] <= {{input_data[7:0]}, {input_data[15:8]}, {input_data[23:16]}, {input_data[31:24]}};
          end else begin
            state              <= STATE_TOK;
            output_valid       <= 1'b0;
          end;
        end

        default: begin
          state        <= STATE_TIK;
          output_valid <= 1'b0;
          output_data  <= 'b0;
        end

      endcase
    end
  end
 
endmodule 

