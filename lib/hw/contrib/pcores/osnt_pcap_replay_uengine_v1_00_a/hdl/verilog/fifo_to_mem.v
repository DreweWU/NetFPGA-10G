/*******************************************************************************
 *
 *  NetFPGA-10G http://www.netfpga.org
 *
 *  File:
 *        fifo_to_mem.v
 *
 *  Library:
 *        hw/osnt/pcores/nf10_pcap_replay_uengine_v1_00_a
 *
 *  Module:
 *        fifo_to_mem
 *
 *  Author:
 *        Yilong Geng
 *
 *  Description:
 *
 *
 *  Copyright notice:
 *        Copyright (C) 2010, 2011 The Board of Trustees of The Leland Stanford
 *                                 Junior University
 *
 *  Licence:
 *        This file is part of the NetFPGA 10G development base package.
 *
 *        This file is free code: you can redistribute it and/or modify it under
 *        the terms of the GNU Lesser General Public License version 2.1 as
 *        published by the Free Software Foundation.
 *
 *        This package is distributed in the hope that it will be useful, but
 *        WITHOUT ANY WARRANTY; without even the implied warranty of
 *        MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 *        Lesser General Public License for more details.
 *
 *        You should have received a copy of the GNU Lesser General Public
 *        License along with the NetFPGA source package.  If not, see
 *        http://www.gnu.org/licenses/.
 *
 */

// NOTE:
// (1) The burst of 4 is inherently covered with AXIS data wigth 256. The QID won't change
//     until the burst is complete. 

module fifo_to_mem
#(
    parameter NUM_QUEUES            = 4,
    parameter NUM_QUEUES_BITS      = log2(NUM_QUEUES),
    parameter FIFO_DATA_WIDTH      = 144,
    parameter MEM_ADDR_WIDTH       = 19,
    parameter MEM_DATA_WIDTH       = 36,
    parameter MEM_BW_WIDTH         = 4,
    parameter MEM_BURST_LENGTH     = 4,
    parameter MEM_ADDR_LOW         = 0,
    parameter MEM_ADDR_HIGH        = MEM_ADDR_LOW+(2**MEM_ADDR_WIDTH)
)
(
    output reg [31:0]                 drop_count_0,
    output reg [31:0]                 drop_count_1,
    output reg [31:0]                 drop_count_2,
    output reg [31:0]                 drop_count_3,

    // Global Ports
    input                             clk,
    input                             rst,
    
    // FIFO Ports
    output reg                        fifo_rd_en,
    input [FIFO_DATA_WIDTH-1:0]       fifo_data,
    input [NUM_QUEUES_BITS-1:0]       fifo_qid,
    input                             fifo_empty,
    
    // Memory Ports
    output reg                        mem_ad_w_n,
  input                              mem_wr_full,
    output reg [MEM_ADDR_WIDTH-1:0]    mem_ad_wr,
    
    output reg                         mem_d_w_n,
    output [MEM_BW_WIDTH-1:0]          mem_bwh_n,
    output [MEM_BW_WIDTH-1:0]          mem_bwl_n,
    output reg [MEM_DATA_WIDTH-1:0]    mem_dwl,
    output reg [MEM_DATA_WIDTH-1:0]    mem_dwh,

    // Misc

    input [MEM_ADDR_WIDTH-3:0]        q0_addr_head,
    output [MEM_ADDR_WIDTH-3:0]        q0_addr_tail,
    input [MEM_ADDR_WIDTH-3:0]        q1_addr_head,
    output [MEM_ADDR_WIDTH-3:0]        q1_addr_tail,
    input [MEM_ADDR_WIDTH-3:0]        q2_addr_head,
    output [MEM_ADDR_WIDTH-3:0]        q2_addr_tail,
    input [MEM_ADDR_WIDTH-3:0]        q3_addr_head,
    output [MEM_ADDR_WIDTH-3:0]        q3_addr_tail,
    
    input                  cal_done
);

  // -- Local Functions
  function integer log2;
    input integer number;
    begin
       log2=0;
       while(2**log2<number) begin
          log2=log2+1;
       end
    end
  endfunction

  // -- Internal Parameters
  localparam IDLE     = 0;
  localparam WR_PKT_0   = 1;
  localparam WR_PKT_1   = 2;
  localparam WR_PKT_2   = 3;
  localparam WR_PKT_3   = 4;
  localparam DROP     = 5;

  // -- Signals

  reg [2:0]            state, state_next;
  reg [1:0]            cur_queue, cur_queue_next;

  reg [FIFO_DATA_WIDTH-1:0]    fifo_data_r;
  reg [NUM_QUEUES_BITS-1:0]    fifo_qid_r;

  reg [MEM_DATA_WIDTH-1:0]    mem_dwl_next, mem_dwh_next;

  wire [(MEM_ADDR_WIDTH-2)*4-1:0] addr_tail_0;
  reg [(MEM_ADDR_WIDTH-2)*4-1:0]  addr_tail_1;
  reg [(MEM_ADDR_WIDTH-2)*4-1:0]  addr_tail_2;
  reg [(MEM_ADDR_WIDTH-2)*4-1:0]  addr_tail_3;
  reg [(MEM_ADDR_WIDTH-2)*4-1:0]  addr_tail_4;
  reg [(MEM_ADDR_WIDTH-2)*4-1:0]  addr_tail_5;
  reg [(MEM_ADDR_WIDTH-2)*4-1:0]  addr_tail_6;
  reg [(MEM_ADDR_WIDTH-2)*4-1:0]  addr_tail_7;

  
  reg [MEM_ADDR_WIDTH-2:0]     mem_ad_wr_r0, mem_ad_wr_r0_next;
  reg [MEM_ADDR_WIDTH-2:0]     mem_ad_wr_r1, mem_ad_wr_r1_next;
  reg [MEM_ADDR_WIDTH-2:0]     mem_ad_wr_r2, mem_ad_wr_r2_next;
  reg [MEM_ADDR_WIDTH-2:0]     mem_ad_wr_r3, mem_ad_wr_r3_next;

  wire [MEM_ADDR_WIDTH-2:0]    mem_ad_wr_r0_plus1;
  wire [MEM_ADDR_WIDTH-2:0]    mem_ad_wr_r1_plus1;
  wire [MEM_ADDR_WIDTH-2:0]    mem_ad_wr_r2_plus1;
  wire [MEM_ADDR_WIDTH-2:0]    mem_ad_wr_r3_plus1;

  reg [MEM_ADDR_WIDTH-1:0]     mem_ad_wr_next;

  wire                 mem_full_q0;
  wire                 mem_full_q1;
  wire                 mem_full_q2;
  wire                 mem_full_q3;
  
  reg                         mem_wr_n_c;

  reg [31:0]           drop_count_0_next;
  reg [31:0]           drop_count_1_next;
  reg [31:0]           drop_count_2_next;
  reg [31:0]           drop_count_3_next;
  
  // -- Assignments
  
  assign mem_bwh_n = {MEM_BW_WIDTH{1'b0}};
  assign mem_bwl_n = {MEM_BW_WIDTH{1'b0}};

  assign mem_ad_wr_r0_plus1 = mem_ad_wr_r0 + 1;
  assign mem_ad_wr_r1_plus1 = mem_ad_wr_r1 + 1;
  assign mem_ad_wr_r2_plus1 = mem_ad_wr_r2 + 1;
  assign mem_ad_wr_r3_plus1 = mem_ad_wr_r3 + 1;

  assign {q3_addr_tail, q2_addr_tail, q1_addr_tail, q0_addr_tail} = addr_tail_7;
  assign addr_tail_0 = {mem_ad_wr_r3[MEM_ADDR_WIDTH-2:1], mem_ad_wr_r2[MEM_ADDR_WIDTH-2:1], mem_ad_wr_r1[MEM_ADDR_WIDTH-2:1], mem_ad_wr_r0[MEM_ADDR_WIDTH-2:1]};

  // always ensure there are at least 64 words left in the queue to contain the packet
  assign mem_full_q0 = (mem_ad_wr_r0[MEM_ADDR_WIDTH-2:1] - q0_addr_head) >= 17'h1ffc0;
  assign mem_full_q1 = (mem_ad_wr_r1[MEM_ADDR_WIDTH-2:1] - q1_addr_head) >= 17'h1ffc0;
  assign mem_full_q2 = (mem_ad_wr_r2[MEM_ADDR_WIDTH-2:1] - q2_addr_head) >= 17'h1ffc0;
  assign mem_full_q3 = (mem_ad_wr_r3[MEM_ADDR_WIDTH-2:1] - q3_addr_head) >= 17'h1ffc0;

  // -- Modules and Logic

  always @(posedge clk) begin
    if(fifo_rd_en) begin
      fifo_data_r <= fifo_data;
      fifo_qid_r <= fifo_qid;
    end
  end
  
  always @ * begin
  	state_next = state;
  	cur_queue_next = cur_queue;

  	mem_ad_wr_r0_next = mem_ad_wr_r0;
  	mem_ad_wr_r1_next = mem_ad_wr_r1;
  	mem_ad_wr_r2_next = mem_ad_wr_r2;
  	mem_ad_wr_r3_next = mem_ad_wr_r3;

  	mem_ad_wr_next = mem_ad_wr;

    fifo_rd_en = 0;
    mem_wr_n_c = 1;

    mem_dwl_next = 0;
    mem_dwh_next = 0;

    drop_count_0_next = drop_count_0;
    drop_count_1_next = drop_count_1;
    drop_count_2_next = drop_count_2;
    drop_count_3_next = drop_count_3;

    case(state)
      IDLE: begin
        //if (~rst) begin
          if(!fifo_empty) begin
            cur_queue_next = fifo_qid;
            case(fifo_qid)
              2'd0: begin
                if(!mem_full_q0) begin
                  state_next = WR_PKT_0;
                end
                else begin
                  drop_count_0_next = drop_count_0 + 1;
                  state_next = DROP;
                end
              end
              2'd1: begin
                if(!mem_full_q1) begin
                  state_next = WR_PKT_0;
                end
                else begin
                  drop_count_1_next = drop_count_1 + 1;
                  state_next = DROP;
                end
              end
              2'd2: begin
                if(!mem_full_q2) begin
                  state_next = WR_PKT_0;
                end
                else begin
                  drop_count_2_next = drop_count_2 + 1;
                  state_next = DROP;
                end
              end
              2'd3: begin
                if(!mem_full_q3) begin
                  state_next = WR_PKT_0;
                end
                else begin
                  drop_count_3_next = drop_count_3 + 1;
                  state_next = DROP;
                end
              end
            endcase
          end
        //end
      end

      // seperate fifo_rd_en from mem_full to improve timing
      WR_PKT_0: begin
        fifo_rd_en = 1;
        state_next = WR_PKT_1;
      end

      WR_PKT_1: begin

        if (!fifo_empty && !mem_wr_full && cal_done) begin
          mem_dwl_next = fifo_data_r[FIFO_DATA_WIDTH/2-1:0];
          mem_dwh_next = fifo_data_r[FIFO_DATA_WIDTH-1:FIFO_DATA_WIDTH/2];

          mem_wr_n_c = 0;

          case (cur_queue)
            2'd0: begin
              mem_ad_wr_r0_next = mem_ad_wr_r0_plus1;
              mem_ad_wr_next = {2'b00, mem_ad_wr_r0[MEM_ADDR_WIDTH-2:1]};
            end
            2'd1: begin
              mem_ad_wr_r1_next = mem_ad_wr_r1_plus1;
              mem_ad_wr_next = {2'b01, mem_ad_wr_r1[MEM_ADDR_WIDTH-2:1]};
            end
            2'd2: begin
              mem_ad_wr_r2_next = mem_ad_wr_r2_plus1;
              mem_ad_wr_next = {2'b10, mem_ad_wr_r2[MEM_ADDR_WIDTH-2:1]};
            end
            2'd3: begin
              mem_ad_wr_r3_next = mem_ad_wr_r3_plus1;
              mem_ad_wr_next = {2'b11, mem_ad_wr_r3[MEM_ADDR_WIDTH-2:1]};
            end
          endcase

          state_next = WR_PKT_2;
        end

      end

      WR_PKT_2: begin
        fifo_rd_en = 1;

        mem_dwl_next = fifo_data[FIFO_DATA_WIDTH/2-1:0];
        mem_dwh_next = fifo_data[FIFO_DATA_WIDTH-1:FIFO_DATA_WIDTH/2];

        case (cur_queue)
          2'd0: begin
            mem_ad_wr_r0_next = mem_ad_wr_r0_plus1;
            mem_ad_wr_next = {2'b00, mem_ad_wr_r0[MEM_ADDR_WIDTH-2:1]};
          end
          2'd1: begin
            mem_ad_wr_r1_next = mem_ad_wr_r1_plus1;
            mem_ad_wr_next = {2'b01, mem_ad_wr_r1[MEM_ADDR_WIDTH-2:1]};
          end
          2'd2: begin
            mem_ad_wr_r2_next = mem_ad_wr_r2_plus1;
            mem_ad_wr_next = {2'b10, mem_ad_wr_r2[MEM_ADDR_WIDTH-2:1]};
          end
          2'd3: begin
            mem_ad_wr_r3_next = mem_ad_wr_r3_plus1;
            mem_ad_wr_next = {2'b11, mem_ad_wr_r3[MEM_ADDR_WIDTH-2:1]};
          end
        endcase

        if (fifo_qid != cur_queue) begin
          state_next = IDLE;
        end
        else begin
          state_next = WR_PKT_3;
        end
      end

      WR_PKT_3: begin
        if (!fifo_empty) begin
          fifo_rd_en = 1;
          state_next = WR_PKT_1;
        end
      end

      DROP: begin
        if (!fifo_empty) begin
          fifo_rd_en = 1;
          if (fifo_qid != cur_queue) begin
            state_next = IDLE;
          end
        end
      end
    endcase

  end
  
  always @ (posedge clk) begin
    if(rst) begin
      state <= IDLE;
      cur_queue <= 0;

      mem_ad_w_n   <= 1;
      mem_d_w_n    <= 1;
      mem_dwl      <= 0;
      mem_dwh      <= 0;
      mem_ad_wr    <= 0;

      mem_ad_wr_r0 <= 0;
      mem_ad_wr_r1 <= 0;
      mem_ad_wr_r2 <= 0;
      mem_ad_wr_r3 <= 0;

      drop_count_0 <= 0;
      drop_count_1 <= 0;
      drop_count_2 <= 0;
      drop_count_3 <= 0;



      addr_tail_1 <= 0;
      addr_tail_2 <= 0;
      addr_tail_3 <= 0;
      addr_tail_4 <= 0;
      addr_tail_5 <= 0;
      addr_tail_6 <= 0;
      addr_tail_7 <= 0;

    end
    else begin
      state <= state_next;
      cur_queue <= cur_queue_next;

      mem_ad_w_n <= mem_wr_n_c;
      mem_d_w_n  <= mem_wr_n_c;
      mem_dwl    <= mem_dwl_next;
      mem_dwh    <= mem_dwh_next;
      
      mem_ad_wr_r0 <= mem_ad_wr_r0_next;
      mem_ad_wr_r1 <= mem_ad_wr_r1_next;
      mem_ad_wr_r2 <= mem_ad_wr_r2_next;
      mem_ad_wr_r3 <= mem_ad_wr_r3_next;
      
      mem_ad_wr <= mem_ad_wr_next;

      drop_count_0 <= drop_count_0_next;
      drop_count_1 <= drop_count_1_next;
      drop_count_2 <= drop_count_2_next;
      drop_count_3 <= drop_count_3_next;

      addr_tail_1 <= addr_tail_0;
      addr_tail_2 <= addr_tail_1;
      addr_tail_3 <= addr_tail_2;
      addr_tail_4 <= addr_tail_3;
      addr_tail_5 <= addr_tail_4;
      addr_tail_6 <= addr_tail_5;
      addr_tail_7 <= addr_tail_6;
    end
  end
  
endmodule

