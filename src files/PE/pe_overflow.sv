`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/26/2026 02:21:42 PM
// Design Name: 
// Module Name: pe
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module pe_overflow #(parameter DW_a=8, DW_b=8,Acc_ip_width=32)(
input logic clk, rst_n,
input logic acc_clear,
input logic signed [DW_a-1:0] a_in,
input logic a_valid_in,
input logic signed [DW_b-1:0] b_in,
input logic b_valid_in,
output logic signed [DW_a-1:0] a_out,
output logic a_out_valid,
output logic signed [DW_b-1:0]b_out,
output logic b_out_valid,
output logic signed [Acc_ip_width-1:0] acc_out,
output logic acc_out_valid,
output logic overflow  //  Overflow in a PE happens when data atfer accumlate is more than its Width
    );

localparam signed PRODW = DW_a + DW_b;

//Stage 0 Latches
logic signed [PRODW-1:0] prod_1_out;
logic signed prod_1_valid;
logic signed [DW_a-1:0] a_01; 
logic signed [DW_b-1:0] b_01;
logic  a_01_valid; 
logic  b_01_valid;

//Stage-1 Latches
logic signed [Acc_ip_width-1:0] acc_present_state, acc_next_state;
logic acc_next_valid ;

// <<< CHANGE: Sign-extended product
logic signed [Acc_ip_width-1:0] prod_ext;

// <<< CHANGE: Extra-bit accumulator sum
logic signed [Acc_ip_width:0] acc_sum_ext;


// <<< CHANGE: Sign-extend product to accumulator width
assign prod_ext = {{(Acc_ip_width-PRODW){prod_1_out[PRODW-1]}},
                   prod_1_out};

// <<< CHANGE: Perform addition with one extra bit
assign acc_sum_ext = $signed(acc_present_state) + $signed(prod_ext);

//STAGE-0 Code
always_ff @(posedge clk, negedge rst_n)
begin
      prod_1_out <= 'b0;
      prod_1_valid <= 1'b0;
           a_01 <= a_in;
           b_01 <= b_in;  
           a_01_valid <= 1'b0;
           b_01_valid <= 1'b0;  
  if (~rst_n)
    begin
      prod_1_out <= 'b0;
      prod_1_valid <= 1'b0;
      a_01 <= 'b0;
      b_01 <= 'b0;  
      a_01_valid <= 1'b0;
      b_01_valid <= 1'b0;     
    end
  else
    begin
      if (a_valid_in && b_valid_in)
         begin
           prod_1_out <= a_in * b_in;
           prod_1_valid <= 1'b1; 
           a_01 <= a_in;
           b_01 <= b_in;  
           a_01_valid <= 1'b1;
           b_01_valid <= 1'b1;
         end
    end
end


// Stage-1 Code
always_ff @(posedge clk, negedge rst_n)
begin
   //  acc_next_state <= 'b0;
     acc_next_valid <= 1'b0;
     a_out <= 'b0;
     a_out_valid <= 1'b0;
     b_out <= 'b0;
     b_out_valid <= 1'b0; 
     overflow <= 1'b0;
  if (~rst_n)
    begin
     acc_next_state <= 'b0;
     acc_next_valid <= 1'b0;
     a_out <= a_01;
     a_out_valid <= a_01_valid;
     b_out <= b_01;
     b_out_valid <= b_01_valid; 
     overflow <= 1'b0;   
    end
  else if (acc_clear)
    begin
    acc_next_state <= '0;
    acc_next_valid <= 1'b0;
    // <<< CHANGE: Clear overflow
    overflow <= 1'b0;
    end
  else if (prod_1_valid && a_01_valid && b_01_valid )
    begin
          // <<< CHANGE: Use sign-extended product
          acc_next_state <= acc_sum_ext;
          acc_next_valid <= 1'b1;
          
           // <<< CHANGE: Registered signed-overflow detection
          // Overflow occurs when the two operands have the
          // same sign but the result has the opposite sign.
// Signed overflow: extended result's top two bits differ
overflow <= acc_sum_ext[Acc_ip_width] ^
            acc_sum_ext[Acc_ip_width-1];
          
       a_out <= a_01;
       a_out_valid <= a_01_valid;
       b_out <= b_01;
       b_out_valid <= b_01_valid;       
    end
end

assign acc_out = acc_next_state;
assign acc_out_valid = acc_next_valid;
//assign acc_present_state = acc_next_state;
assign acc_present_state = acc_clear ? 'b0: acc_next_state;

endmodule
