`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/06/2026 02:16:54 PM
// Design Name: 
// Module Name: controller_preload_Data
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


module controller_preload_Data #(
parameter NR_A= 3, NR_B=3, NC_A=3, NC_B=3, MODE_A=0, MODE_B=1, DW=8)
(input logic clk, rst_n,

    output logic rd_req_A,
    input  logic rd_req_ready_A,
    input  logic [DW*NC_A-1:0] data_A,
    input  logic rd_valid_A,
    input  logic rd_done_A,
    output logic rd_ready_A,

    output logic rd_req_B,
    input  logic rd_req_ready_B,
    input  logic [DW*NR_B-1:0] data_B,
    input  logic rd_done_B,
    input  logic rd_valid_B,
    output logic rd_ready_B,
    
    input logic start,
    output logic busy,
    output logic done,

    output logic [DW*NR_A-1:0] data_A_out,
    output logic [NR_A-1:0]    data_A_vld,

    output logic [DW*NC_B-1:0] data_B_out,
    output logic [NC_B-1:0]    data_B_vld
);

    // A: one lane per row
    logic [DW*NR_A-1:0] A_data_next;
    logic [NR_A-1:0]    A_valid_next;

    // B: one lane per column
    logic [DW*NC_B-1:0] B_data_next;
    logic [NC_B-1:0]    B_valid_next;

logic [DW*NC_A-1:0] Mem_A [0: NR_A-1];
logic [DW*NR_B-1:0] Mem_B [0: NC_B-1];

    localparam int A_CNT_W = $clog2(NR_A+1);
    localparam int B_CNT_W = $clog2(NC_B+1);
    logic [A_CNT_W-1:0] A_received;
    logic [B_CNT_W-1:0] B_received;
//this module is based on three states: idle , fetch , delivery
//idle is where there is no data movement
//fetch is when Controller takes data from PPBuffer and stores it in memory
//Delivery is when it gives the data to PE.

typedef enum logic [1:0] {idle, fetch, delivery} state;
state state_reg, state_nxt;

localparam int ptr_width_A =  (NR_A <=1 ) ? 1 : $clog2(NR_A);
localparam int ptr_width_B =  (NC_B <=1 ) ? 1 : $clog2(NC_B);

logic [ptr_width_A-1:0] A_wr_ptr;
logic [ptr_width_B-1:0] B_wr_ptr;

// Number of Delivery Cycles Count
localparam int delivery_cycles =  NC_A + ((NR_A > NC_B) ? NR_A : NC_B) - 1;

localparam int rd_cntr_width =  (delivery_cycles == 1) ? 1 : $clog2(delivery_cycles);
logic [rd_cntr_width-1:0] read_cntr ;
    integer i;
    integer j;

//State logic FF block
always_ff @ (posedge clk, negedge rst_n)
begin
    if (!rst_n)
        begin
            state_reg <= idle;
        end
    else
        begin
            state_reg <= state_nxt;
        end
end

always_comb 
begin 
    busy = 1'b0;
    done=  1'b0;
    state_nxt = state_reg;
    case (state_reg)
    idle:
    begin
        rd_req_A = 1'b1;
        rd_req_B = 1'b1;
        if (start && rd_req_ready_A && rd_req_ready_B )
            begin
                state_nxt = fetch;
            end
    end  
    fetch:  //note memory write will  be sequential block, so we cant write that here
    begin
        busy = 1'b1;
        if (A_received == NR_A)
          rd_req_A = 1'b0;
        else
          rd_req_A = rd_req_A +1'b1;

        if (B_received == NC_B -1)    
          rd_req_B = 1'b0;
        else 
          rd_req_B = rd_req_B + 1'b1;

        rd_ready_A = 1'b1;
        rd_ready_B = 1'b1;
        

        if (A_received ==  NR_A && B_received == NC_B)
          state_nxt = delivery;   
    end
    delivery: // memory read will be sequential block so we cant write that here
    begin
        busy = 1'b1;
        rd_req_A = 1'b0;
        rd_req_B = 1'b0;
        rd_ready_A = 1'b0;
        rd_ready_B = 1'b0;
        if (read_cntr == delivery_cycles-1)
        begin
            state_nxt = idle;
            done = 1'b1;
        end
    end
   endcase
end

// Sequential Block to Write Memory

always_ff @(posedge clk, negedge rst_n)
begin
    if (~rst_n)
      begin
        A_wr_ptr <= 'b0;
        B_wr_ptr <= 'b0;
        A_received  <= 'b0;
        B_received  <= 'b0;
      end
    else
      begin
        if (state_reg == fetch && rd_valid_A && rd_ready_A)
        begin
            Mem_A [A_wr_ptr] <= data_A;       // pointer is used to store row number as indices
            A_received <= A_received+ 1'b1;
            if (A_wr_ptr == NR_A-1)
                A_wr_ptr <= 'b0;
            else
                A_wr_ptr <= A_wr_ptr + 1'b1;
        end

        if (state_reg == fetch && rd_valid_B && rd_ready_B)
        begin
            Mem_B [B_wr_ptr] <= data_B;     // pointer is used column number as indices
            B_received <= B_received+ 1'b1;
            if (B_wr_ptr == NC_B-1)
                B_wr_ptr <= 'b0;
            else
                B_wr_ptr <= B_wr_ptr + 1'b1;
        end      
      end
end

// Read logic in Delivery State
/*A_rd_pntr_width =  (NR_A = 1) ? 1 : $clog2(NR_A) ;  // Since we stored row wise, pntr should be on row
B_rd_pntr_width =  (NC_B = 1) ? 1 : $clog2(NC_B);   // since we stored column wise data, pntr should be on column
A_rd_pntr = [A_rd_pntr_width-1:0];
B_rd_pntr = [B_rd_pntr_width-1:0];   */

//Read Logic

always_comb
begin
       /* A_rd_pntr <= 'b0;
        B_rd_pntr <= 'b0;  */

        A_data_next  = '0;
        A_valid_next = '0;

        B_data_next  = '0;
        B_valid_next = '0;     

        if (state_reg == delivery)
        begin
            // Read A wave
            // since we have to read in 1 cycle from 2 different rows, so we need to keep this in for loop, so that in 1 cycle this runs for multiple times
            for(i=0 ;  i<NR_A ; i=i+1)
                if((read_cntr >=i) && ((read_cntr-i) < NC_A))
                begin
                  A_data_next[i*DW+:DW] <= Mem_A[i][(read_cntr-i)*DW+:DW];
                  A_valid_next[i] <= 1'b1; 
                end
            for(j=0 ;  j<NC_B ; j=j+1)
                if((read_cntr >=j) && ((read_cntr-j) < NR_B))
                begin
                  B_data_next[j*DW+:DW] = Mem_B[j][(read_cntr-j)*DW+:DW];
                  B_valid_next[j] <= 1'b1;
                end
        end  
end

always_ff @(posedge clk, negedge rst_n)
begin
    if (~rst_n)
    begin
    read_cntr <= 'b0;  ;
    data_A_out <= 'b0;
    data_A_vld <='b0;
    data_B_out <= 'b0;
    data_B_vld <= 'b0;
    end
    else
    begin
        if (state_reg == delivery)
        begin
            data_A_out <= A_data_next;
            data_A_vld <= A_valid_next;
            data_B_out <= B_data_next;
            data_B_vld <= B_valid_next;
            if (read_cntr < delivery_cycles-1)
            begin
                read_cntr <= read_cntr + 1'b1;
            end
            else
            begin
                read_cntr <= 'b0;
            end
        end
    end
end

endmodule
