`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/31/2026 12:05:05 AM
// Design Name: 
// Module Name: systolic_array_forwarding
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



module systolic_array_forwarding #(
    parameter NR   = 4,
    parameter NC   = 4,
    parameter DW_r = 8,
    parameter DW_c = 8,
    parameter ACCW = 32
)(
    input logic clk,
    input logic rst_n,
    input logic acc_clear,

    input logic [DW_r*NR-1:0] row_data,
    input logic [NR-1:0]      row_data_valid,

    input logic [DW_c*NC-1:0] col_data,
    input logic [NC-1:0]      col_data_valid,

    output logic [(NR*NC*ACCW)-1:0] c_flat,
    output logic [NR*NC-1:0]        c_valid_flat
);

    // --------------------------------------------------------
    // Interconnection signals between PEs
    // --------------------------------------------------------

    logic signed [DW_r-1:0] a_forward [0:NR-1][0:NC-1];
    logic signed [DW_c-1:0] b_forward [0:NR-1][0:NC-1];

    logic a_forward_valid [0:NR-1][0:NC-1];
    logic b_forward_valid [0:NR-1][0:NC-1];

    // --------------------------------------------------------
    // Generate systolic array
    // --------------------------------------------------------

    genvar r, c;

    generate
        for (r = 0; r < NR; r = r + 1) begin : ROW_GEN

            for (c = 0; c < NC; c = c + 1) begin : COL_GEN

                // ------------------------------------------------
                // PE input connections
                // ------------------------------------------------

                wire signed [DW_r-1:0] pe_a_in;
                wire signed [DW_c-1:0] pe_b_in;

                wire pe_a_valid_in;
                wire pe_b_valid_in;

                // A moves from left to right
                if (c == 0) begin : A_INPUT

                    assign pe_a_in =
                        row_data[r*DW_r +: DW_r];

                    assign pe_a_valid_in =
                        row_data_valid[r];

                end
                else begin : A_FORWARD

                    assign pe_a_in =
                        a_forward[r][c-1];

                    assign pe_a_valid_in =
                        a_forward_valid[r][c-1];

                end

                // B moves from top to bottom
                if (r == 0) begin : B_INPUT

                    assign pe_b_in =
                        col_data[c*DW_c +: DW_c];

                    assign pe_b_valid_in =
                        col_data_valid[c];

                end
                else begin : B_FORWARD

                    assign pe_b_in =
                        b_forward[r-1][c];

                    assign pe_b_valid_in =
                        b_forward_valid[r-1][c];

                end

                // ------------------------------------------------
                // PE instantiation
                // ------------------------------------------------

                pe_overflow_forwarding #(
                    .DW_a(DW_r),
                    .DW_b(DW_c),
                    .Acc_ip_width(ACCW)
                ) pe_inst (

                    .clk(clk),
                    .rst_n(rst_n),
                    .acc_clear(acc_clear),

                    .a_in(pe_a_in),
                    .a_valid_in(pe_a_valid_in),

                    .b_in(pe_b_in),
                    .b_valid_in(pe_b_valid_in),

                    .a_out(a_forward[r][c]),
                    .a_out_valid(a_forward_valid[r][c]),

                    .b_out(b_forward[r][c]),
                    .b_out_valid(b_forward_valid[r][c]),

                    .acc_out(
                        c_flat[(r*NC+c)*ACCW +: ACCW]
                    ),

                    .acc_out_valid(
                        c_valid_flat[r*NC+c]
                    ),

                    .overflow()
                );

            end
        end
    endgenerate

endmodule
