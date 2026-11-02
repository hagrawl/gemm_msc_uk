`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/29/2026 01:15:27 PM
// Design Name: 
// Module Name: systolic_array
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


module systolic_array
#(parameter NR=4, NC=4, DW_r=8, DW_c=8, ACCW=32)   //NR Number of rows, NC Number of columns
( input logic clk,
input logic rst_n,
input logic acc_clear,

input logic [DW_r*NR -1:0] row_data,
input logic [NR -1:0] row_data_valid,

input logic [DW_c*NC -1:0] col_data,
input logic [NC -1:0] col_data_valid,

output logic [(NR*NC*ACCW)-1:0] c_flat,   //Here we need to have all data of PEs, so NR*NC= number of PEs and to get width multiplied by ACCW
output logic [NR*NC-1:0] c_valid_flat
    );

// A will be moving right, so for each PE output(with out I mean A and B) to feed to another PE, we need same number of registers as PE for both A and B 
/*logic [DW_r-1:0] row_data_reg [0:NR*NC-1];
logic            row_data_reg_v [0:NR*NC-1];

logic [DW_c-1:0] column_data_reg [0:NR*NC-1];
logic            column_data_reg_v [0:NR*NC-1]; */

/*logic [DW_r-1:0] row_data_reg [0:NR*NC-1];
logic            row_data_reg_v [0:NR*NC-1];

logic [DW_c-1:0] column_data_reg [0:NR*NC-1];
logic            column_data_reg_v [0:NR*NC-1];*/

//--------------------------------------------------
// Forwarding connections between PEs
//--------------------------------------------------

//--------------------------------------------------
// Forwarding connections between PEs
//--------------------------------------------------

logic signed [DW_r-1:0] a_forward [0:NR-1][0:NC-1];
logic signed [DW_c-1:0] b_forward [0:NR-1][0:NC-1];

logic a_forward_valid [0:NR-1][0:NC-1];
logic b_forward_valid [0:NR-1][0:NC-1];


//--------------------------------------------------
// Generate PE array
//--------------------------------------------------

genvar r, c;

generate

    for (r=0; r<NR; r=r+1)
    begin: gen_rows

        for (c=0; c<NC; c=c+1)
        begin: gen_columns

            // PE instance
            pe_overflow #(
                .DW_a(DW_r),
                .DW_b(DW_c),
                .Acc_ip_width(ACCW)
            ) pe_inst (

                .clk(clk),
                .rst_n(rst_n),
                .acc_clear(acc_clear),

                // A input: from external input or previous PE
                .a_in(
                    (c == 0) ?
                    row_data[r*DW_r +: DW_r] :   // if c=0, we are taking inputs from ports
                    a_forward[r][c-1]   // if c!=0, we are taking inputs fromregisters
                ),

                .a_valid_in(
                    (c == 0) ?
                    row_data_valid[r] :
                    a_forward_valid[r][c-1]
                ),

                // B input: from external input or PE above
                .b_in(
                    (r == 0) ?
                    col_data[c*DW_c +: DW_c] :
                    b_forward[r-1][c]
                ),

                .b_valid_in(
                    (r == 0) ?
                    col_data_valid[c] :
                    b_forward_valid[r-1][c]
                ),

                // Forwarding outputs
                .a_out(a_forward[r][c]),
                .a_out_valid(a_forward_valid[r][c]),

                .b_out(b_forward[r][c]),
                .b_out_valid(b_forward_valid[r][c]),

                // Accumulator outputs
                .acc_out(c_flat[(r*NC+c)*ACCW +: ACCW]),
                .acc_out_valid(c_valid_flat[r*NC+c]),

                .overflow()  // Currently unused
            );

        end
    end

endgenerate

endmodule
