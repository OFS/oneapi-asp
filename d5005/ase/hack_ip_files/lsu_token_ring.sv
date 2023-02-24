// (c) 1992-2021 Intel Corporation.                            
// Intel, the Intel logo, Intel, MegaCore, NIOS II, Quartus and TalkBack words    
// and logos are trademarks of Intel Corporation or its subsidiaries in the U.S.  
// and/or other countries. Other marks and brands may be claimed as the property  
// of others. See Trademarks on intel.com for full list of Intel trademarks or    
// the Trademarks & Brands Names Database (if Intel) or See www.Intel.com/legal (if Altera) 
// Your use of Intel Corporation's design tools, logic functions and other        
// software and tools, and its AMPP partner logic functions, and any output       
// files any of the foregoing (including device programming or simulation         
// files), and any associated documentation or information are expressly subject  
// to the terms and conditions of the Altera Program License Subscription         
// Agreement, Intel MegaCore Function License Agreement, or other applicable      
// license agreement, including, without limitation, that your use is for the     
// sole purpose of programming logic devices manufactured by Intel and sold by    
// Intel or its authorized distributors.  Please refer to the applicable          
// agreement for further details.                                                 


// This module is a token ring that includes the following major sub-blocks
// [1] read ring / write ring, connected to LSUs
// [2] one root FIFO per bank; root FIFO buffers memory access requests and generate backpressure
// [3] data reordering block - optional
// The timing of reset is specific. lsu_ic_token and lsu_n_fast are held in reset longer than all other modules. This is done by setting the RESET_PIPE_DEPTH in those modules
// to be larger than the RESET_PIPE_DEPTH in this module. This relationship must be maintained if the reset_pipe_depth is changed.

`default_nettype none
module lsu_token_ring (
  clk,
  resetn,
  // from LSU
  i_rd_byteenable,
  i_rd_address,
  i_rd_request,
  i_rd_burstcount,
  i_wr_byteenable,
  i_wr_address,
  i_wr_request,
  i_wr_burstcount,
  i_wr_writedata,
  // from MEM
  i_avm_waitrequest,
  i_avm_write_ack,
  i_avm_readdata,
  i_avm_return_valid,
  // to MEM
  o_avm_byteenable,
  o_avm_address,
  o_avm_read,
  o_avm_write,
  o_avm_burstcount,
  o_avm_writedata,
  o_id, // Not used
  // to kernel
  o_rd_waitrequest,
  o_wr_waitrequest,
  o_avm_writeack,
  o_avm_readdata,
  o_avm_readdatavalid,
  // ECC status signal
  ecc_err_status
);


parameter AWIDTH = 32; // MWORD address. LSBs are truncated by lsu_ic_top.
parameter MWIDTH_BYTES = 64;
parameter BURST_CNT_W = 5;
parameter NUM_RD_PORT = 2;
parameter NUM_WR_PORT = 2;
parameter START_ID = 0;
parameter ENABLE_READ_FAST = 0;
parameter HYPER_PIPELINE = 0;  // 1 = optimized, highly pipelined, at the expense of area
parameter DISABLE_ROOT_FIFO = 0;
parameter ROOT_FIFO_AW = 8;               // Token root FIFO address width; FIFO depth = 2**ROOT_FIFO_AW. FIFO depth must be at least 2*WRITE_ROOT_FIFO_ALMOST_FULL_VALUE for maximum throughput.
parameter RD_ROOT_FIFO_AW = 7;
parameter ENABLE_LAST_WAIT = 0;
parameter MAX_MEM_DELAY = 128;
parameter RETURN_DATA_FIFO_DEPTH = 128;   // Read data reordering FIFO depth. Must be at least (MAX_BURST * (5+NUM_DATA_AF_COMPARE_STAGES))
parameter WRITE_ACK_FIFO_DEPTH = 1024;    // Used when ENABLE_BSP_AVMM_WRITE_ACK = 1. Sets the depth of the writeack response FIFO. This is approximately how many outstanding write words are allowed before we throttle write-requests. This amount needs to cover the round-trip latency to memory in order to maximize throughput.
parameter PIPELINE_RD_RETURN = 0;
parameter ENABLE_DATA_REORDER = 0;
parameter NUM_DIMM = 2;
parameter ENABLE_DUAL_RING = 0;
parameter ENABLE_MULTIPLE_WR_RING = 0;
parameter NUM_REORDER = 1;
/* If HYPER_PIPELINE==1, the AVMM agent to which this module connects must have a minimum waitrequest-allowance of at least (WAIT_REQUEST_INPUT_PIPE_DEPTH + 1 + ROOT_FIFO_STALL_IN_EARLINESS + NUM_AVM_OUTPUT_PIPE_STAGES).
    This number is the ring interconnect's "internal roundtrip latency" on its global memory AVMM interface.

    Explanation of the latency components:
    - WAIT_REQUEST_INPUT_PIPE_DEPTH because i_avm_waitrequest is purely pipelined by WAIT_REQUEST_INPUT_PIPE_DEPTH stages.
    - +1 because waitrequest is combined with other conditions to form a registered read-request to the root FIFO.
    - ROOT_FIFO_STALL_IN_EARLINESS because we support use of the stall-in-earliness feature of acl_high_speed_fifo, which means data will continue to be output for ROOT_FIFO_STALL_IN_EARLINESS cycles after the FIFO read-req de-asserts.
    - NUM_AVM_OUTPUT_PIPE_STAGES because the root FIFO output is pipelined by NUM_AVM_OUTPUT_PIPE_STAGES stages.

    If this waiterquest-allowance amount ever changes, the almost-full threshold in the BSP's clock crossing bridge must be correspondingly adjusted.

    If ENABLE_BSP_WAITREQUEST_ALLOWANCE=0 and HYPER_PIPELINE=1, the host-root-FIFO is instantiated to convert the BSP's non-waitrequest-allowance interface to the internal waiterquest-allownance interface used by the ring
*/
parameter NUM_AVM_OUTPUT_PIPE_STAGES = 1;  // Minimum value 1. Length of pipeline stages between root FIFOs and CCB. This can be increased for performance (note that the agent-side
                                            // waitrequest allowance must be increased by the same amount as well). Only used when HYPER_PIPELINE=1
parameter ENABLE_BSP_WAITREQUEST_ALLOWANCE = 0;
// Enable use of the writeack input from the AvalonMM interface to generate write-acks to store-LSUs. This is typically used when ordering between reads and writes is not guaranteed on the AVMM interface, for the particular BSP (which happens with high-bandwidth memory)
// This is a custom (non-standard) signal that asserts once per every writedata word. It's different from the standard AVMM writeresponsevalid, which asserts once per burst.
parameter ENABLE_BSP_AVMM_WRITE_ACK = 0;
parameter ROOT_FIFO_STALL_IN_EARLINESS = 0;  // How many cycles of lookahead to provide to the stall_in (ie. read_req) signal to the W/R root FIFOs. This is used as an area optimization. Used when HYPER_PIPELINE=1
parameter ROOT_WFIFO_VALID_IN_EARLINESS = 0; //Specify WRF valid-in earliness (does not affect RRF right now). Used when HYPER_PIPELINE=1
parameter AVM_WRITE_DATA_LATENESS = 0;  // fmax and area optimization - run the write data path this many clocks later than stall/valid
parameter AVM_READ_DATA_LATENESS = 0;   // fmax and area optimization - o_avm_readdata is late by this many clocks compared to o_avm_readdatavalid
parameter WIDE_DATA_SLICING = 0;        // for large MWIDTH_BYTES, a nonzero value indicate how wide to width-slice hld_fifo, also mux select signals are replicated based on width needed
parameter ALLOW_HIGH_SPEED_FIFO_USAGE = 1;  // choice of hld_fifo style, 0 = mid speed fifo, 1 = high speed fifo
parameter enable_ecc = "FALSE";            // Enable error correction coding
parameter MAX_REQUESTS_PER_LSU = 4;            // Max number of requests accepted per LSU before passing the token. Currently applies to reads only. See lsu_ic_token/lsu_n_fast.

parameter int NUM_MEM_SYSTEMS = 1;
parameter [NUM_MEM_SYSTEMS-1:0][31:0] NUM_BANKS_PER_MEM_SYSTEM  = {(NUM_MEM_SYSTEMS){32'd1}};  // index position [0] is in the right-most position.
parameter [NUM_MEM_SYSTEMS-1:0][31:0] NUM_BANKS_W_PER_MEM_SYSTEM  = {(NUM_MEM_SYSTEMS){32'd1}};   // Bit-width of each NUM_BANKS
parameter [NUM_MEM_SYSTEMS-1:0][31:0] BANK_BIT_LSB_PER_MEM_SYSTEM  = {(NUM_MEM_SYSTEMS){32'd30}};

parameter [NUM_MEM_SYSTEMS-1:0][31:0] ENABLE_BANK_INTERLEAVING  = {(NUM_MEM_SYSTEMS){32'd1}};     // Interconnect will permute the AVMM addresses to stripe accesses across available banks. This can be controlled on each mem system.
parameter int LARGEST_NUM_BANKS = 1;
/*  Within the LSU's address, the combination of {mem system + bank bits} uniquely identifies a target physical port.
    The mapping of these bits to physical ports is specified by the compiler using ROOT_PORT_MAP. An alternative approach
    could have been to simply interpret these bits as a binary number that specifies the root port number. But this requires
    the memory system whose mem system bits are zero to be connected to port 0. For Universal Shared Memory, it turns out
    System Integrator does not wire things up this way, hence the introduction of ROOT_PORT_MAP to give flexibility.
*/
parameter [NUM_MEM_SYSTEMS-1:0][LARGEST_NUM_BANKS-1:0][31:0] ROOT_PORT_MAP  = {1,0}; //'
parameter int ROOT_ARB_BALANCED_RW = 0;
localparam LARGEST_NUM_BANKS_W = $clog2(LARGEST_NUM_BANKS);
localparam DIMM_W = $clog2(NUM_DIMM);
// For multi mem systems we carry the full address through the interconnect and the instantiator of lsu_ic_top must truncate the bits appropriately.
// For single mem system, we truncate the bank bits to remain consistent with historical behaviour.
localparam O_AVM_ADDRESS_W = (NUM_MEM_SYSTEMS > 1)? AWIDTH : AWIDTH-DIMM_W;

localparam MWIDTH=8*MWIDTH_BYTES;
localparam NUM_ID = NUM_RD_PORT+NUM_WR_PORT;
localparam DISABLE_WR_RING = NUM_WR_PORT==0;
localparam ENABLE_MULTIPLE_WR_RING_INT = ENABLE_MULTIPLE_WR_RING & ENABLE_DUAL_RING & !DISABLE_WR_RING & NUM_DIMM > 1;
localparam WR_ENABLE = NUM_WR_PORT > 0;
localparam RD_ID_WIDTH = (NUM_RD_PORT==1)?  1 : $clog2(NUM_RD_PORT);
localparam WR_ID_WIDTH = (NUM_WR_PORT==1)?  1 : $clog2(NUM_WR_PORT);
localparam ID_WIDTH = (RD_ID_WIDTH > WR_ID_WIDTH)? RD_ID_WIDTH : WR_ID_WIDTH;
localparam WR_RING_ID_WIDTH = ENABLE_DUAL_RING? WR_ID_WIDTH : ID_WIDTH;
localparam P_DIMM_W = (DIMM_W == 0)? 1 : DIMM_W; // Used to workaround Modelsim compilation error when DIMM_W==0
localparam MAX_BURST = 2 ** (BURST_CNT_W-1);
/* Data width of the wr-root FIFO. The data written contains (MSB to LSB):
  - End-of-Burst flag (1+), only in HYPER_PIPELINE mode
  - Byte enable (MWIDTH_BYTES)
  - Address
  - Burstcount (BURST_CNT_W)
  - Write data (MWIDTH)
*/
localparam WRITE_ROOT_FIFO_WIDTH = (HYPER_PIPELINE? 1 : 0) + MWIDTH_BYTES + O_AVM_ADDRESS_W + BURST_CNT_W + MWIDTH ;
localparam ROOT_FIFO_DEPTH = 2 ** ROOT_FIFO_AW;
localparam RD_ROOT_FIFO_DEPTH = 2 ** RD_ROOT_FIFO_AW;
localparam NUM_REORDER_INT = (NUM_REORDER > NUM_RD_PORT)? NUM_RD_PORT : NUM_REORDER;
localparam PENDING_CNT_W = $clog2(RETURN_DATA_FIFO_DEPTH);
localparam RD_WIDTH = (NUM_REORDER_INT == 1)? 1 :$clog2(NUM_REORDER_INT+1);


// avoid modelsim compile error
localparam P_NUM_RD_PORT = (NUM_RD_PORT > 0)? NUM_RD_PORT : 1;
localparam P_NUM_WR_PORT = (NUM_WR_PORT > 0)? NUM_WR_PORT : 1;

localparam NUM_MEM_SYSTEMS_W = (NUM_MEM_SYSTEMS==1)? 1 : $clog2(NUM_MEM_SYSTEMS);
localparam MWORD_PAD = $clog2(MWIDTH_BYTES);

input wire clk;
input wire resetn; // reset is synchronous if HYPER_PIPELINE == 1, asynchronous otherwise
// from LSU
input wire [MWIDTH_BYTES-1:0] i_rd_byteenable [P_NUM_RD_PORT];
input wire [AWIDTH-1:0] i_rd_address [P_NUM_RD_PORT];   // MWORD addresses. The LSBs of the LSU's address are truncated by lsu_ic_top.
input wire i_rd_request [P_NUM_RD_PORT];
input wire  [BURST_CNT_W-1:0] i_rd_burstcount [P_NUM_RD_PORT];
input wire  [MWIDTH_BYTES-1:0] i_wr_byteenable [P_NUM_WR_PORT];
input wire  [AWIDTH-1:0] i_wr_address [P_NUM_WR_PORT];
input wire  i_wr_request [P_NUM_WR_PORT];
input wire  [BURST_CNT_W-1:0] i_wr_burstcount [P_NUM_WR_PORT];
input wire  [MWIDTH-1:0] i_wr_writedata [P_NUM_WR_PORT];
// from MEM
// Please see comment on ENABLE_BSP_WAITREQUEST_ALLOWANCE parameter for how much waitrequest-allowance is needed on i_avm_waitrequest.
input wire  i_avm_waitrequest [NUM_DIMM];
input wire  i_avm_write_ack [NUM_DIMM];
input wire  [MWIDTH-1:0] i_avm_readdata [NUM_DIMM];
input wire  i_avm_return_valid [NUM_DIMM];
// to MEM
/*
  This module's AVMM output can pause during a burst (ie. o_avm_write is asserted for a few cycles, then de-asserts, then asserts
  again to complete the burst). During the pause period (when o_avm_write==0), it is NOT guaranteed that o_avm_address/o_avm_burstcount will be held
  constant. This is because these outputs come from a FIFO whose output is indeterminate when empty.
  The AVMM spec includes a parameter called constantBurstBehaviour which indicates if an AVMM interface is expecting address/burstcount to be held
  during a burst. It doesn't explain what behaviour is expected during a pause.
  In general, none of this should be a problem because the inferred QSYS interconnect in the BSP seems to automatically get parameterized to latch address/burstcount on the first cycle of the burst
   -- but it's critical that this is true.
*/
output logic  [MWIDTH_BYTES-1:0] o_avm_byteenable [NUM_DIMM];
output logic  [O_AVM_ADDRESS_W-1:0] o_avm_address [NUM_DIMM]; // Output address is an MWORD address. Includes mem system and bank bits.
output logic  o_avm_read [NUM_DIMM];
output logic  o_avm_write [NUM_DIMM];
output logic  [BURST_CNT_W-1:0] o_avm_burstcount [NUM_DIMM];
output logic  [MWIDTH-1:0] o_avm_writedata [NUM_DIMM];
output logic  [ID_WIDTH-1:0] o_id [NUM_DIMM];
// to kernel
output logic  o_rd_waitrequest [P_NUM_RD_PORT];
output logic  o_wr_waitrequest [P_NUM_WR_PORT];
output logic  o_avm_writeack [P_NUM_WR_PORT];
output logic  [MWIDTH-1:0] o_avm_readdata [P_NUM_RD_PORT];
output logic  o_avm_readdatavalid [P_NUM_RD_PORT];

output logic  [1:0] ecc_err_status; // ecc status signals

logic reset;
assign reset = !resetn;  // Consumed when HYPER_PIPELINE=0.

genvar z, z0, g;

//////////////////////////////////////
//                                  //
//  Sanity check on the parameters  //
//                                  //
//////////////////////////////////////

// the checks are done in Quartus pro and Modelsim, it is disabled in Quartus standard because it results in a syntax error (parser is based on an older systemverilog standard)
// the workaround is to use synthesis translate to hide this from Quartus standard, ALTERA_RESERVED_QHD is only defined in Quartus pro, and Modelsim ignores the synthesis comment

`ifdef ALTERA_RESERVED_QHD
`else
//synthesis translate_off
`endif
generate

  if (ENABLE_BSP_AVMM_WRITE_ACK && !HYPER_PIPELINE) begin
      initial $fatal(1, "lsu_ic_top ring interconnect: HYPER_PIPELINE must be enabled when using BSP_AVMM_WRITE_ACK\n");
  end
  if (NUM_DIMM == 1 && ENABLE_MULTIPLE_WR_RING) begin
      initial $fatal(1, "lsu_ic_top ring interconnect: NUM_DIMM==1 (i.e. there's only 1 bank) but ENABLE_MULTIPLE_WR_RING==1. Multiple Write Rings are only supported if NUM_DIMM > 1.\n");
  end

  // If multi mem systems are used, HYPER_PIPELINE must be 1.
  if ((NUM_MEM_SYSTEMS>1) && (HYPER_PIPELINE==0)) begin
    $fatal(1, "lsu_ic_top ring interconnect: HYPER_PIPELINE==0 is not supported when NUM_MEM_SYSTEMS > 1\n");
  end

endgenerate
`ifdef ALTERA_RESERVED_QHD
`else
//synthesis translate_on
`endif

// Assign each load to a reorder unit. Round-robin assignment.
// In the future reorder_id_per_load could be specified by the compiler. For example, if the compiler knows that 2 particular loads require a lot of memory bandwidth it can place them
// on separate re-order units.
localparam NUM_REORDER_W = $clog2(NUM_REORDER_INT);
logic [P_NUM_RD_PORT-1:0][NUM_REORDER_W-1:0] reorder_id_per_load;
generate
  // For example, if there are 3 reorder units but 7 loads, load # 0 - 6 will be assigned reorder # 0,1,2,0,1,2,0
  for (z=0;z<NUM_RD_PORT;z++) begin : GEN_REORDER_ID_PER_LOAD
    assign reorder_id_per_load[z] = z % NUM_REORDER; // Quartus should implement this as a constant (i.e. no modulo hardware)
  end
endgenerate

generate
  if (HYPER_PIPELINE == 0) begin : GEN_HYPER_PIPELINE_0
    //TODO: pre-s10 ring does not support write data lateness, error out if we get here with that enabled
    `ifdef ALTERA_RESERVED_QHD
    `else
    //synthesis translate_off
    `endif
    if (AVM_WRITE_DATA_LATENESS) begin
        $fatal(1, "lsu_token_ring, AVM_WRITE_DATA_LATENESS is not supported with HYPER_PIPELINE == 0");
    end
    `ifdef ALTERA_RESERVED_QHD
    `else
    //synthesis translate_on
    `endif

    integer i, j;
    wire rd_o_token;
    wire [RD_ID_WIDTH-1:0] rd_o_id;
    wire [AWIDTH-1:0] rd_address;
    wire rd_request;
    wire rd_waitrequest [NUM_DIMM];
    wire rd_root_af [NUM_DIMM];
    wire [BURST_CNT_W-1:0] rd_burstcount;
    wire ic_read [P_NUM_WR_PORT];
    wire ic_write [P_NUM_RD_PORT];
    wire [MWIDTH_BYTES-1:0] wr_byteenable;
    wire [AWIDTH-1:0] wr_address;
    wire wr_read;
    wire wr_write;
    wire wr_request;
    wire [BURST_CNT_W-1:0] wr_burstcount;
    wire [WR_ID_WIDTH-1:0] wr_id;
    wire [MWIDTH-1:0] wr_writedata;
    wire [WRITE_ROOT_FIFO_WIDTH-1:0] wr_fin [NUM_DIMM];
    wire [WRITE_ROOT_FIFO_WIDTH-1:0] wr_fout [NUM_DIMM];
    wire wr_fifo_empty [NUM_DIMM];
    wire wr_root_af [NUM_DIMM];
    wire wr_wr_root_en [NUM_DIMM];
    wire rd_wr_root_en [NUM_DIMM];
    reg  wr_out_en [NUM_DIMM];
    wire rd_fifo_empty [NUM_DIMM];
    wire wr_rd_root_en [NUM_DIMM];
    wire rd_rd_root_en [NUM_DIMM];
    reg  rd_out_en [NUM_DIMM];
    wire [RD_ID_WIDTH-1:0] fout_id[NUM_DIMM];
    logic wr_dimm_en [NUM_DIMM];
    wire [AWIDTH-DIMM_W-1:0] top_rd_address [NUM_DIMM];
    wire [RD_ID_WIDTH-1:0] top_rd_o_id [NUM_DIMM];
    wire [BURST_CNT_W-1:0] top_rd_burstcount [NUM_DIMM];
    wire [RD_ID_WIDTH-1:0] fout_rd_id [NUM_DIMM];
    wire [0:NUM_DIMM-1] id_af;
    logic [NUM_REORDER-1:0][NUM_DIMM-1:0]rd_bank;
    logic [0:NUM_DIMM-1] data_af;
    wire [MWIDTH-1:0] rd_data [NUM_DIMM][P_NUM_RD_PORT];
    reg  [MWIDTH-1:0] R_avm_readdata [P_NUM_RD_PORT];
    reg  R_avm_readdatavalid [P_NUM_RD_PORT];
    wire rd_data_valid [NUM_DIMM][P_NUM_RD_PORT];
    wire [0:NUM_DIMM-1] v_rd_data_en [P_NUM_RD_PORT];
    wire [AWIDTH-DIMM_W-1:0] wr_ring_o_addr [NUM_DIMM];
    wire [BURST_CNT_W-1:0] wr_ring_o_burstcount [NUM_DIMM];
    wire [MWIDTH-1:0] wr_ring_o_writedata [NUM_DIMM];
    wire [MWIDTH_BYTES-1:0] wr_ring_o_byteenable [NUM_DIMM];
    reg  [PENDING_CNT_W-1:0] max_pending [NUM_DIMM];
    reg  [BURST_CNT_W-1:0] wr_cnt [NUM_DIMM];
    logic [0:NUM_DIMM-1] wr_done, wr_en, error_0, error_1;
    logic [0:NUM_DIMM-1] debug_bubble;
    logic [NUM_DIMM-1:0] input_avm_waitrequest_packed_per_bank_rd;
    logic [NUM_DIMM-1:0] input_avm_waitrequest_packed_per_bank_wr;

    //FIXME -- the parameters are set to match the behavior of before the reset handler was introduced
    localparam ASYNC_RESET = 1;
    localparam SYNCHRONIZE_RESET = 0;
    logic aclrn;
    logic sclrn;
    logic resetn_synchronized;

    acl_reset_handler
    #(
        .ASYNC_RESET            (ASYNC_RESET),
        .USE_SYNCHRONIZER       (SYNCHRONIZE_RESET),
        .SYNCHRONIZE_ACLRN      (SYNCHRONIZE_RESET),
        .PIPE_DEPTH             (1),
        .NUM_COPIES             (1)
    )
    acl_reset_handler_inst
    (
        .clk                    (clk),
        .i_resetn               (resetn),
        .o_aclrn                (aclrn),
        .o_resetn_synchronized  (resetn_synchronized),
        .o_sclrn                (sclrn)
    );

    assign wr_request = wr_read | wr_write;
    /* Apparently you can only use reduction operators on packed types, so this converts the unpacked signal
      i_avm_waitrequest to packed signal input_avm_waitrequest so we can later use the OR reduction operator.
    */
    for (z=0;z<NUM_DIMM;z++) begin : GEN_INPUT_AVM_WAIT_REQUEST
      assign input_avm_waitrequest_packed_per_bank_rd[z] = i_avm_waitrequest[z] && (i_rd_address[0][AWIDTH-1:AWIDTH-P_DIMM_W] == z);
      assign input_avm_waitrequest_packed_per_bank_wr[z] = i_avm_waitrequest[z] && (i_wr_address[0][AWIDTH-1:AWIDTH-P_DIMM_W] == z);
    end

    logic [1:0] ecc_err_status_port;
    if(NUM_ID == 1) begin : GEN_SINGLE_PORT
      for(z=0; z<NUM_DIMM; z=z+1) begin : GEN_
        assign o_avm_byteenable[z]    = (NUM_RD_PORT == 1)? '1 : i_wr_byteenable[0];
        assign o_avm_address[z]       = (NUM_RD_PORT == 1)? i_rd_address[0][AWIDTH-DIMM_W-1:0]  : i_wr_address[0][AWIDTH-DIMM_W-1:0];
        assign o_avm_burstcount[z]    = (NUM_RD_PORT == 1)? i_rd_burstcount[0] : i_wr_burstcount[0];
        assign o_avm_writedata[z]     = i_wr_writedata[0];
        assign o_id[z]                = START_ID;
        // If the LSU is being waitrequested, always de-assert o_avm_read. The LSU can be waitrequested if the AVMM interface is backpressuring or due to id_af asserting. In either case
        // we need to prevent read requests from mistkanely being sent out over the AVMM interface.
        assign o_avm_read[z]          = (NUM_RD_PORT == 1)? (i_rd_request[0] && !o_rd_waitrequest[0] && ((DIMM_W == 0)? 1'b1 : i_rd_address[0][AWIDTH-1:AWIDTH-P_DIMM_W] == z))
                                        : 1'b0;
        assign o_avm_write[z]         = (NUM_RD_PORT == 0)? (i_wr_request[0] && ((DIMM_W == 0)? 1'b1 : i_wr_address[0][AWIDTH-1:AWIDTH-P_DIMM_W] == z))
                                        : 1'b0;
      end

      // Backpressure the LSU if we get backpressure from the bank it is currently accessing.
      assign o_rd_waitrequest[0] = (|input_avm_waitrequest_packed_per_bank_rd) || (|id_af); // Load-LSUs must be additionally backpressured by the almost-full from lsu_rd_back's read-request FIFO (avm_read_req_fifo)
      assign o_wr_waitrequest[0] = |input_avm_waitrequest_packed_per_bank_wr;
      assign o_avm_writeack[0] = i_wr_request[0] && !o_wr_waitrequest[0];

      assign rd_burstcount = i_rd_burstcount[0];
      assign rd_o_id       = 1'b0;
      assign rd_request    = i_rd_request[0] && !o_rd_waitrequest[0];
      assign rd_address    = i_rd_address[0];
      assign ecc_err_status_port = 2'h0;
    end
    else begin : GEN_MULTIPLE_PORT
      for(z=0; z<NUM_WR_PORT; z=z+1) begin : GEN_WR_DUMMY
        assign ic_read[z] = 1'b0;
      end
      for(z=0; z<NUM_RD_PORT; z=z+1) begin : GEN_RD_DUMMY
        assign ic_write[z] = 1'b0;
      end

      logic [1:0] ecc_err_status_rd;
      if(NUM_RD_PORT > 0) begin : GEN_ENABLE_RD
        lsu_n_token #(
           .AWIDTH(AWIDTH),
           .MWIDTH_BYTES(MWIDTH_BYTES),
           .BURST_CNT_W(BURST_CNT_W),
           .NUM_PORT(NUM_RD_PORT),
           .START_ID(START_ID),
           .OPEN_RING(!DISABLE_WR_RING & !ENABLE_DUAL_RING),
           .SINGLE_STALL((DISABLE_WR_RING | ENABLE_DUAL_RING) & ENABLE_DATA_REORDER), // wr_root_af is from the single ID FIFO; sw-dimm-partion has N ID FIFOs
           .ENABLE_DATA_REORDER(ENABLE_DATA_REORDER),
           .START_ACTIVE(1),
           .ENABLE_FAST(ENABLE_READ_FAST),
           .NUM_DIMM(NUM_DIMM),
           .ENABLE_LAST_WAIT(ENABLE_LAST_WAIT),
           .READ(1),
           .HYPER_PIPELINE(HYPER_PIPELINE),
           .MAX_REQUESTS_PER_LSU (MAX_REQUESTS_PER_LSU)
         ) rd_ring (
          .clk              (clk),
          .resetn           (!reset),
          .i_ext_read       (1'b0),
          .i_avm_write      (ic_write),
          .i_token          (),
          .i_avm_address    (i_rd_address),
          .i_avm_read       (i_rd_request),
          .i_avm_burstcount (i_rd_burstcount),
          .i_avm_waitrequest(rd_waitrequest),
          .o_avm_waitrequest(o_rd_waitrequest),
          .o_avm_address    (rd_address),
          .o_avm_read       (rd_request),
          .o_avm_burstcount (rd_burstcount),
          .o_token          (rd_o_token),
          .o_id             (rd_o_id)
        );

        // There is very likely a bug here that needs to be fixed. A read request can be issued during a pause in a write-burst that's caused by the
        // write-root-FIFO going empty. Case:464548
        logic [1:0] ecc_err_status_for;
        logic [NUM_DIMM-1:0] ecc_err_status_for_0;
        logic [NUM_DIMM-1:0] ecc_err_status_for_1;
        assign ecc_err_status_for[0] = |ecc_err_status_for_0;
        assign ecc_err_status_for[1] = |ecc_err_status_for_1;
        for(z=0; z<NUM_DIMM; z=z+1) begin : GEN_RD_SET
          assign rd_rd_root_en[z] = !rd_out_en[z] | !i_avm_waitrequest[z] & !wr_en[z];
          assign o_avm_read[z] = rd_out_en[z] & !wr_en[z];

          if(NUM_DIMM > 1) assign wr_rd_root_en[z] = rd_request & rd_address[AWIDTH-1:AWIDTH-DIMM_W] == z;
          else assign wr_rd_root_en[z] = rd_request;

          always @(posedge clk or posedge reset) begin
            if(reset)  rd_out_en[z] <= 1'b0;
            else if(rd_rd_root_en[z]) rd_out_en[z] <= !rd_fifo_empty[z] & !data_af[z];
          end

          acl_scfifo_wrapped #(
            .add_ram_output_register ( "ON"),
            .lpm_numwords (RD_ROOT_FIFO_DEPTH),
            .lpm_showahead ( "OFF"),
            .lpm_type ( "scfifo"),
            .lpm_width (RD_ID_WIDTH+AWIDTH-DIMM_W+BURST_CNT_W),
            .lpm_widthu (RD_ROOT_FIFO_AW),
            .overflow_checking ( "OFF"),
            .underflow_checking ( "ON"),
            .use_eab ( "ON"),
            .almost_full_value(RD_ROOT_FIFO_DEPTH-5-NUM_RD_PORT*2),
            .enable_ecc (enable_ecc)
          ) rd_fifo (
            .clock (clk),
            .data ({rd_o_id, rd_address[AWIDTH-DIMM_W-1:0],rd_burstcount}),
            .wrreq (wr_rd_root_en[z]),
            .rdreq (rd_rd_root_en[z] & !data_af[z]),
            .empty (rd_fifo_empty[z]),
            .q ({top_rd_o_id[z], top_rd_address[z],top_rd_burstcount[z]}),
            .almost_full (rd_root_af[z]),
            .aclr (~aclrn),
            .sclr (~sclrn),
            .ecc_err_status({ecc_err_status_for_1[z], ecc_err_status_for_0[z]})
          );
         // wr_root_af to ring pipelined nodes
         assign rd_waitrequest[z] = id_af[z];
        end
        assign ecc_err_status_rd = ecc_err_status_for;
      end //end if(NUM_RD_PORT > 0) begin : GEN_ENABLE_RD
      else begin : GEN_DISABLE_RD
        for(z=0; z<NUM_DIMM; z=z+1) begin : GEN_DI
          assign o_avm_read[z] = 1'b0;
        end
        assign ecc_err_status_rd = 2'h0;
      end // end GEN_DISABLE_RD


      logic [1:0] ecc_err_status_wr;
      if(!DISABLE_WR_RING) begin : GEN_ENABLE_WRITE_RING
        logic [1:0] ecc_err_status_for;
        logic [NUM_DIMM-1:0] ecc_err_status_for_0;
        logic [NUM_DIMM-1:0] ecc_err_status_for_1;
        assign ecc_err_status_for[0] = |ecc_err_status_for_0;
        assign ecc_err_status_for[1] = |ecc_err_status_for_1;
        for(z=0; z<NUM_DIMM; z=z+1) begin : GEN_WR_ROOT_FIFOS
          assign o_avm_writedata[z] = wr_fout[z][MWIDTH-1:0];
          assign {o_avm_byteenable[z], o_avm_address[z], o_avm_burstcount[z]} = o_avm_write[z]? wr_fout[z][WRITE_ROOT_FIFO_WIDTH-1:MWIDTH] : {{MWIDTH_BYTES{1'b1}},top_rd_address[z], top_rd_burstcount[z]};
          assign o_avm_write[z] = wr_out_en[z] & wr_en[z];

          assign rd_wr_root_en[z] = !wr_out_en[z] | !i_avm_waitrequest[z] & wr_en[z];
          assign wr_done[z] = o_avm_write[z] & !i_avm_waitrequest[z] & wr_cnt[z] == wr_fout[z][MWIDTH+BURST_CNT_W-1:MWIDTH];

          `ifdef SIM_ONLY // check bubble or error
            reg  [AWIDTH-DIMM_W-1:0] R_addr;
            reg  not_wr_empty, not_rd_empty;
            reg  freeze_read, freeze_write;
            assign debug_bubble[z] = !i_avm_waitrequest[z] & (!o_avm_write[z] & not_wr_empty) & (!o_avm_read[z] & not_rd_empty); // check if there is switch bubble
            always @(posedge clk) begin
              if(o_avm_write[z]) R_addr <= o_avm_address[z];
              not_wr_empty <= !wr_fifo_empty[z];
              not_rd_empty <= !rd_fifo_empty[z];
              freeze_read <= i_avm_waitrequest[z] & o_avm_read[z];
              freeze_write <= i_avm_waitrequest[z] & o_avm_write[z];
              error_0[z] <= R_addr !== o_avm_address[z] & wr_cnt[z] < wr_fout[z][MWIDTH+BURST_CNT_W-1:MWIDTH] & wr_cnt[z] != 1 & (o_avm_read[z] | o_avm_write[z]) ; // switch to rd when wr has not finished
              error_1[z] <= freeze_read & !o_avm_read[z] | freeze_write & !o_avm_write[z] | o_avm_read[z] & o_avm_write[z];  // output request changes during i_avm_waitrequest
            end
          `endif

          always @(posedge clk or posedge reset) begin
            if(reset)  begin
              wr_out_en[z] <= 1'b0;
              wr_cnt[z] <= 1;
              wr_en[z] <= 1'b0;
            end
            else begin
              if(rd_wr_root_en[z]) wr_out_en[z] <= !wr_fifo_empty[z];
              if(o_avm_write[z] & !i_avm_waitrequest[z]) wr_cnt[z] <= (wr_cnt[z] == wr_fout[z][MWIDTH+BURST_CNT_W-1:MWIDTH])? 1 : wr_cnt[z] + 1'b1;
              if(wr_done[z]) wr_en[z] <= !wr_fifo_empty[z];
               else if((!wr_fifo_empty[z] | wr_out_en[z]) & !(i_avm_waitrequest[z] & o_avm_read[z])) wr_en[z] <= 1'b1;
            end
          end

          acl_scfifo_wrapped #(
            .add_ram_output_register ( "ON"),
            .lpm_numwords (ROOT_FIFO_DEPTH),
            .lpm_showahead ( "OFF"),
            .lpm_type ( "scfifo"),
            .lpm_width (WRITE_ROOT_FIFO_WIDTH),
            .lpm_widthu (ROOT_FIFO_AW),
            .overflow_checking ( "OFF"),
            .underflow_checking ( "ON"),
            .use_eab ( "ON"),
            .almost_full_value(ROOT_FIFO_DEPTH-5-NUM_WR_PORT*2),
            .enable_ecc (enable_ecc)
          ) wr_fifo (
            .clock (clk),
            .data (wr_fin[z]),
            .wrreq (wr_wr_root_en[z]),
            .rdreq (rd_wr_root_en[z]),
            .empty (wr_fifo_empty[z]),
            .q (wr_fout[z]),
            .almost_full (wr_root_af[z]),
            .aclr (~aclrn),
            .sclr (~sclrn),
            .ecc_err_status({ecc_err_status_for_1[z], ecc_err_status_for_0[z]})
          );
        end // end GEN_WR_ROOT_FIFOS z-loop

        if(ENABLE_MULTIPLE_WR_RING_INT) begin : GEN_MULTIPLE_WR_RING
          wire [AWIDTH-DIMM_W-1:0] wr_ring_i_addr [NUM_WR_PORT];
          wire wr_ring_i_write [NUM_DIMM] [NUM_WR_PORT];
          wire wr_ring_o_waitrequest [NUM_DIMM][NUM_WR_PORT];
          wire [0:NUM_DIMM-1] v_wr_stall [NUM_WR_PORT];
          wire [0:NUM_DIMM-1] wr_accept [NUM_WR_PORT];
          logic [WR_RING_ID_WIDTH-1:0] wr_o_id [NUM_DIMM];

          for(z0=0; z0<NUM_WR_PORT; z0=z0+1) begin : GEN_WR_STALL
            assign o_wr_waitrequest[z0] = |v_wr_stall[z0];
            assign wr_ring_i_addr[z0] = i_wr_address[z0][AWIDTH-DIMM_W-1:0];
          end
          for(z=0; z<NUM_DIMM; z=z+1) begin : GEN_
            wire wr_i_waitrequest [1];
            assign wr_i_waitrequest[0] = wr_root_af[z];
            for(z0=0; z0<NUM_WR_PORT; z0=z0+1) begin : GEN_WR_ENABLE
              assign wr_ring_i_write[z][z0] = i_wr_request[z0] & i_wr_address[z0][AWIDTH-1:AWIDTH-DIMM_W] == z;
              assign v_wr_stall[z0][z] = wr_ring_o_waitrequest[z][z0] & i_wr_address[z0][AWIDTH-1:AWIDTH-DIMM_W] == z;
              assign wr_accept[z0][z] = wr_dimm_en[z] & wr_o_id[z] == z0;
            end
            lsu_n_token #(
               .AWIDTH(AWIDTH - DIMM_W),
               .MWIDTH_BYTES(MWIDTH_BYTES),
               .BURST_CNT_W(BURST_CNT_W),
               .NUM_PORT(NUM_WR_PORT),
               .ID_WIDTH(WR_RING_ID_WIDTH),
               .ENABLE_DATA_REORDER(ENABLE_DATA_REORDER),
               .OPEN_RING(0),
               .START_ACTIVE(1),
               .NUM_DIMM(1),
               .ENABLE_LAST_WAIT(0),
               .START_ID(0),
               .READ(0),
               .HYPER_PIPELINE(HYPER_PIPELINE),
               .MAX_REQUESTS_PER_LSU (MAX_REQUESTS_PER_LSU)
             ) wr_ring (
              .clk              (clk),
              .resetn           (!reset),
              .i_token          (1'b0),
              .i_id             (),
              .i_ext_address    (),
              .i_ext_read       (1'b0),
              .i_ext_burstcount (),
              .o_ext_waitrequest(),
              .i_avm_byteenable (i_wr_byteenable),
              .i_avm_address    (wr_ring_i_addr),
              .i_avm_read       (ic_read),
              .i_avm_write      (wr_ring_i_write[z]),
              .i_avm_writedata  (i_wr_writedata),
              .i_avm_burstcount (i_wr_burstcount),
              .i_avm_waitrequest(wr_i_waitrequest),
              .o_avm_waitrequest(wr_ring_o_waitrequest[z]),
              .o_avm_byteenable (wr_ring_o_byteenable[z]),
              .o_avm_address    (wr_ring_o_addr[z]),
              .o_avm_read       (),
              .o_avm_write      (wr_dimm_en[z]),
              .o_avm_burstcount (wr_ring_o_burstcount[z]),
              .o_id             (wr_o_id[z]),
              .o_token          (),
              .o_avm_writedata  (wr_ring_o_writedata[z])
            );
            assign wr_fin[z] = {
              //wr_o_id[z],
              wr_ring_o_byteenable[z],
              wr_ring_o_addr[z],
              wr_ring_o_burstcount[z],
              wr_ring_o_writedata[z]
            };
            assign wr_wr_root_en[z] = wr_dimm_en[z];
          end
          // ------------------
          // Generate write ACK
          // ------------------
          always @(posedge clk or posedge reset) begin
            if(reset) begin
              for(i=0; i<NUM_WR_PORT; i=i+1) o_avm_writeack[i] <= 1'b0;
            end
            else begin
              for(i=0; i<NUM_WR_PORT; i=i+1) o_avm_writeack[i] <= |wr_accept[i];
            end
          end // end always
        end
        else begin : GEN_SINGLE_WR_RING
          lsu_n_token #(
             .AWIDTH(AWIDTH),
             .MWIDTH_BYTES(MWIDTH_BYTES),
             .BURST_CNT_W(BURST_CNT_W),
             .NUM_PORT(NUM_WR_PORT),
             .ID_WIDTH(WR_RING_ID_WIDTH),
             .ENABLE_DATA_REORDER(ENABLE_DATA_REORDER),
             .OPEN_RING(NUM_RD_PORT > 0 & !ENABLE_DUAL_RING),
             .START_ACTIVE(NUM_RD_PORT == 0 | ENABLE_DUAL_RING),
             .NUM_DIMM(NUM_DIMM),
             .ENABLE_LAST_WAIT(0),
             .START_ID(0),
             .READ(0),
             .HYPER_PIPELINE(HYPER_PIPELINE),
             .MAX_REQUESTS_PER_LSU (MAX_REQUESTS_PER_LSU)
           ) wr_ring (
            .clk              (clk),
            .resetn           (!reset),
            .i_token          (1'b0),
            .i_id             (),
            .i_ext_address    (),
            .i_ext_read       (1'b0),
            .i_ext_burstcount (rd_burstcount),
            .o_ext_waitrequest(),
            .i_avm_byteenable (i_wr_byteenable),
            .i_avm_address    (i_wr_address),
            .i_avm_read       (ic_read),
            .i_avm_write      (i_wr_request),
            .i_avm_writedata  (i_wr_writedata),
            .i_avm_burstcount (i_wr_burstcount),
            .i_avm_waitrequest(wr_root_af),
            .o_avm_waitrequest(o_wr_waitrequest),
            .o_avm_byteenable (wr_byteenable),
            .o_avm_address    (wr_address),
            .o_avm_read       (wr_read),
            .o_avm_write      (wr_write),
            .o_avm_burstcount (wr_burstcount),
            .o_id             (wr_id),
            .o_token          (),
            .o_avm_writedata  (wr_writedata)
          );
          for(z=0; z<NUM_DIMM; z=z+1) begin : GEN_
            assign wr_fin[z] = {
              //wr_id,
              wr_byteenable,
              wr_address[AWIDTH-DIMM_W-1:0],
              wr_burstcount,
              wr_writedata
            };
            if(NUM_DIMM > 1) assign wr_wr_root_en[z] = wr_request & wr_address[AWIDTH-1:AWIDTH-DIMM_W] == z;
            else assign wr_wr_root_en[z] = wr_request;
          end
          // ------------------
          // Generate write ACK
          // ------------------
          always @(posedge clk or posedge reset) begin
            if(reset) begin
              for(i=0; i<NUM_WR_PORT; i=i+1) o_avm_writeack[i] <= 1'b0;
            end
            else begin
              for(i=0; i<NUM_WR_PORT; i=i+1)  o_avm_writeack[i] <= wr_write & wr_id == i;
            end
          end // end GEN_SINGLE_WR_RING
        end
        assign ecc_err_status_wr = ecc_err_status_for;
      end // end GEN_ENABLE_WRITE_RING
      else begin
        for(z=0; z<NUM_DIMM; z=z+1) begin : GEN_
          assign o_avm_write[z] = 1'b0;
          assign wr_en[z] = 1'b0;
          assign {o_avm_byteenable[z], o_avm_address[z], o_avm_burstcount[z]} = {{MWIDTH_BYTES{1'b1}}, top_rd_address[z], top_rd_burstcount[z]};
        end
        assign ecc_err_status_wr = 2'h0;
      end
      assign ecc_err_status_port = ecc_err_status_rd | ecc_err_status_wr;
    end  // end MULTIPLE PORTS
    wire [DIMM_W:0] to_avm_port_num;
    if(NUM_DIMM > 1) assign to_avm_port_num = rd_address[AWIDTH-1:AWIDTH-DIMM_W];
    else assign to_avm_port_num = 1'b0;

    logic [1:0] ecc_err_status_lsu_rd_back;
    if(ENABLE_DATA_REORDER & NUM_RD_PORT > 0) begin : GEN_DATA_REORDER
      lsu_rd_back_n #(
        .NUM_DIMM (NUM_DIMM),
        .NUM_RD_PORT (NUM_RD_PORT),
        .NUM_REORDER(NUM_REORDER_INT),
        .BURST_CNT_W (BURST_CNT_W),
        .MWIDTH (MWIDTH),
        .DATA_FIFO_DEPTH(RETURN_DATA_FIFO_DEPTH),
        .MAX_MEM_DELAY (MAX_MEM_DELAY),
        .PIPELINE (PIPELINE_RD_RETURN),
        .HYPER_PIPELINE(HYPER_PIPELINE),
        .AVM_READ_DATA_LATENESS(AVM_READ_DATA_LATENESS),
        .WIDE_DATA_SLICING(WIDE_DATA_SLICING),
        .ALLOW_HIGH_SPEED_FIFO_USAGE(ALLOW_HIGH_SPEED_FIFO_USAGE),
        .enable_ecc(enable_ecc)
      ) lsu_rd_back (
        .clk                    (clk),
        .resetn                 (!reset),
        .i_to_avm_port_num      (to_avm_port_num),
        .i_to_avm_burstcount    (rd_burstcount),
        .i_to_avm_id            (rd_o_id),
        .i_to_avm_valid         (rd_request),
        .i_data                 (i_avm_readdata),
        .i_data_valid           (i_avm_return_valid),
        .i_reorder_id_per_load  (reorder_id_per_load),
        .o_data                 (o_avm_readdata),
        .o_data_valid           (o_avm_readdatavalid),
        .o_rd_bank              (rd_bank),
        .o_id_af                (id_af[0]),
        .ecc_err_status         (ecc_err_status_lsu_rd_back)
      );
      if(NUM_DIMM > 1) assign id_af[1:NUM_DIMM-1] = '0;

      logic [NUM_REORDER-1:0][NUM_DIMM-1:0][PENDING_CNT_W-1:0] pending_rd;
      reg  [0:NUM_DIMM-1] R_o_avm_read;
      reg  [BURST_CNT_W-1:0]  R_o_avm_burstcnt [NUM_DIMM];
      logic  [RD_ID_WIDTH-1:0] R_o_avm_lsu_id [NUM_DIMM];
      logic [NUM_DIMM-1:0][NUM_REORDER-1:0] read_request_throttle_per_reorder;
      always @(posedge clk) begin
        for(i=0; i<NUM_DIMM; i=i+1) begin : GEN_RANDOM_BLOCK_NAME_R192
          R_o_avm_burstcnt[i] <= o_avm_burstcount[i];
          R_o_avm_lsu_id[i]   <= top_rd_o_id[i]; // Grab the LSU ID of the read-request that's leaving the read root FIFO.
        end
      end
      always @(posedge clk or posedge reset) begin
        if(reset) begin
          for(i=0; i<NUM_DIMM; i=i+1) begin : GEN_RANDOM_BLOCK_NAME_R193
            for (int z=0;z<NUM_REORDER;z++) begin : GEN_RANDOM_BLOCK_NAME_R194
              pending_rd[z][i] <= '0;
              read_request_throttle_per_reorder[i][z] <= '0;
            end
            max_pending[i] <= '0;
            data_af[i] <= 1'b0;
            R_o_avm_read[i] <= 1'b0;

          end
        end
        else begin
          for(i=0; i<NUM_DIMM; i=i+1) begin : GEN_RANDOM_BLOCK_NAME_R195
            R_o_avm_read[i] <= o_avm_read[i] & !i_avm_waitrequest[i];

            for (int z=0;z<NUM_REORDER;z++) begin : GEN_RANDOM_BLOCK_NAME_R196
              // pending_rd is tracked per-reorder unit, per-bank. It decrements using rd_bank. It increments by the burstcount if a read request is actually leaving the RRF and the LSU ID of that request corresponds to the current (z'th) reorder unit.
              pending_rd[z][i] <= pending_rd[z][i] + (R_o_avm_burstcnt[i] & {BURST_CNT_W{R_o_avm_read[i]}} & {BURST_CNT_W{reorder_id_per_load[R_o_avm_lsu_id[i]]==z}}) - rd_bank[z][i];
              read_request_throttle_per_reorder[i][z] <= pending_rd[z][i] >= (RETURN_DATA_FIFO_DEPTH - MAX_BURST * 5); // The *5 multiplier is because it takes 4 cycles from o_avm_read asserting to data_af asserting. During this time, up to 4 MAX_BURSTS might be issued, so we need to accommodate the corresponding read data. +1 for margin.
            end

            //data_af[i] <= pending_rd[i] >= (RETURN_DATA_FIFO_DEPTH - MAX_BURST * 5);
            // Per-throttle signal. Throttle bank-i if any of the bank-i FIFOs, across all reorder units, is getting full.
            data_af[i] <= |read_request_throttle_per_reorder[i];
            `ifdef SIM_ONLY
              if(max_pending[i] < pending_rd[i]) max_pending[i] <= pending_rd[i];
            `endif
          end
        end
      end
    end
    else if(NUM_RD_PORT > 0) begin : GEN_DISABLE_DATA_REORDER
      for(z=0; z<NUM_RD_PORT; z=z+1) begin : GEN_RD_DOUT
        assign o_avm_readdata[z] = R_avm_readdata[z];
        assign o_avm_readdatavalid[z] = R_avm_readdatavalid[z];
      end
      always @(posedge clk) begin
        for(i=0; i<NUM_RD_PORT; i=i+1)  begin : GEN_RANDOM_BLOCK_NAME_R197
          for(j=0; j<NUM_DIMM; j=j+1) if(rd_data_valid[j][i]) R_avm_readdata[i] <= rd_data[j][0];
          R_avm_readdatavalid[i] <= |v_rd_data_en[i];
        end
      end

      logic [NUM_DIMM-1:0] ecc_err_status_for_0;
      logic [NUM_DIMM-1:0] ecc_err_status_for_1;
      assign ecc_err_status_lsu_rd_back[0] = |ecc_err_status_for_0;
      assign ecc_err_status_lsu_rd_back[1] = |ecc_err_status_for_1;
      for(z=0; z<NUM_DIMM; z=z+1) begin : GEN_DATA_VALID
        wire to_avm_valid;
        wire [MWIDTH-1:0] i_data [1];
        wire i_data_valid [1];
        assign data_af[z] = 1'b0;
        for(z0=0; z0<NUM_RD_PORT; z0=z0+1)  begin : GEN_
          assign v_rd_data_en[z0][z] = rd_data_valid[z][z0];
        end
        assign i_data[0] = i_avm_readdata[z];
        assign i_data_valid[0] = i_avm_return_valid[z];
        if(NUM_DIMM > 1) assign to_avm_valid = rd_request & rd_address[AWIDTH-1:AWIDTH-DIMM_W] == z;
        else assign to_avm_valid = rd_request;
        lsu_rd_back #(
          .NUM_DIMM (1), // NUM_DIMM == 1 : reordering is disabled, instantiate one lsu_rd_back per bank.
          .NUM_RD_PORT (NUM_RD_PORT),
          .BURST_CNT_W (BURST_CNT_W),
          .MWIDTH (MWIDTH),
          .MAX_MEM_DELAY(MAX_MEM_DELAY),
          .PIPELINE (0),
          .HYPER_PIPELINE(HYPER_PIPELINE),
          .AVM_READ_DATA_LATENESS(AVM_READ_DATA_LATENESS),
          .WIDE_DATA_SLICING(WIDE_DATA_SLICING),
          .ALLOW_HIGH_SPEED_FIFO_USAGE(ALLOW_HIGH_SPEED_FIFO_USAGE),
          .enable_ecc(enable_ecc)
        ) lsu_rd_back(
          .clk                (clk),
          .resetn             (!reset),
          .i_to_avm_port_num  (),
          .i_to_avm_burstcount(rd_burstcount),
          .i_to_avm_id        (rd_o_id),
          .i_to_avm_valid     (to_avm_valid),
          .i_data             (i_data),
          .i_data_valid       (i_data_valid),
          .o_id_af            (id_af[z]),
          .o_data             (rd_data[z]),
          .o_data_valid       (rd_data_valid[z]),
          .ecc_err_status({ecc_err_status_for_1[z], ecc_err_status_for_0[z]})
        );
      end
    end
    else begin
      assign ecc_err_status_lsu_rd_back = 2'h0;
    end
    assign ecc_err_status = ecc_err_status_port | ecc_err_status_lsu_rd_back;

  end else begin : GEN_HYPER_PIPELINE_1 // HYPER_PIPELINE==1
    /*********************************************************
      High-FMAX design.
    *********************************************************/
    /* The following code is highly optimized and agressively pipelined, for higher FMAX.
    */

    integer i, j;
    // Outputs from the read ring
    logic rd_o_token; // Token output from the read ring. Currently not used.
    logic [RD_ID_WIDTH-1:0] rd_o_id; // LSU ID
    logic [AWIDTH-1:0] rd_address;   // Address
    logic rd_request;
    logic rd_waitrequest [NUM_DIMM]; // Wait request into the read-ring, comes from lsu_rd_back's read-request FIFO's almost full.
    localparam NUM_RING_WAITREQUEST_PIPE_STAGES = 3;
    logic rd_ring_waitrequest_pipe[NUM_RING_WAITREQUEST_PIPE_STAGES:1][NUM_DIMM];
    logic wr_ring_waitrequest_pipe[NUM_RING_WAITREQUEST_PIPE_STAGES:1][NUM_DIMM];
    logic wr_ring_waitrequest [NUM_DIMM]; // Wait request into the write ring
    logic [BURST_CNT_W-1:0] rd_burstcount;

    logic rd_root_af [NUM_DIMM]; // read root FIFO almost_full
    // Tied off to zero, feeds unused inputs on the read/write rings
    logic ic_read [P_NUM_WR_PORT];
    logic ic_write [P_NUM_RD_PORT];

    // Outputs from write-ring
    logic [MWIDTH_BYTES-1:0] wr_byteenable;
    logic [AWIDTH-1:0] wr_address;
    logic wr_read;
    logic wr_write;
    logic wr_request;
    logic [BURST_CNT_W-1:0] wr_burstcount;
    logic [WR_ID_WIDTH-1:0] wr_id;
    logic [MWIDTH-1:0] wr_writedata;

    // Write root FIFO signals (single write ring)
    logic [WRITE_ROOT_FIFO_WIDTH-1:0] write_root_fifo_data_in[NUM_DIMM];
    logic [WRITE_ROOT_FIFO_WIDTH-1:0] write_root_fifo_data_out [NUM_DIMM];
    logic write_root_fifos_data_mismatch [NUM_DIMM];
    logic write_root_fifo_empty [NUM_DIMM];
    logic write_root_fifo_empty_lookahead_incr[NUM_DIMM];
    logic write_root_fifo_empty_lookahead_decr[NUM_DIMM];
    logic write_root_fifo_not_empty_lookahead [NUM_DIMM];
    logic write_root_fifo_empty_lookahead [NUM_DIMM];
    logic wr_root_af [NUM_DIMM];

    // Read root FIFO signals
    logic wr_rd_root_en [NUM_DIMM];
    logic rd_rd_root_en [NUM_DIMM];

    logic wr_dimm_en [NUM_DIMM];  // Write strobe, output from write-ring, used when there are multiple write rings

    logic [0:NUM_DIMM-1] id_af;      // Almost-full flags from lsu_rd_back internal FIFOs
    logic [NUM_REORDER-1:0][NUM_DIMM-1:0]rd_bank;  // Output from lsu_rd_back to indicate that the respective data FIFO is being read from. Used to generate pending_rd / read request throttling
    logic read_request_throttle [NUM_DIMM];

    // Read return data to the LSUs, from lsu_rd_back, and related signals
    logic [MWIDTH-1:0] rd_data [NUM_DIMM][P_NUM_RD_PORT];
    reg  [MWIDTH-1:0] R_avm_readdata [P_NUM_RD_PORT];
    reg  R_avm_readdatavalid [P_NUM_RD_PORT];
    logic rd_data_valid [NUM_DIMM][P_NUM_RD_PORT];
    logic [0:NUM_DIMM-1] v_rd_data_en [P_NUM_RD_PORT];

    // Write ring outputs (multiple write rings)
    logic [AWIDTH-1:0] wr_ring_o_addr [NUM_DIMM];
    logic [BURST_CNT_W-1:0] wr_ring_o_burstcount [NUM_DIMM];
    logic [MWIDTH-1:0] wr_ring_o_writedata [NUM_DIMM];
    logic [MWIDTH_BYTES-1:0] wr_ring_o_byteenable [NUM_DIMM];

    // Used for simulation debug
    reg  [PENDING_CNT_W-1:0] max_pending [NUM_DIMM];
    reg  [BURST_CNT_W-1:0] wr_cnt [NUM_DIMM];
    logic [0:NUM_DIMM-1] wr_done, wr_en, error_0, error_1;
    logic [0:NUM_DIMM-1] debug_bubble;

    localparam HOST_ROOT_FIFO_WIDTH = WRITE_ROOT_FIFO_WIDTH + 2; // +2 for read and write strobe
    logic [HOST_ROOT_FIFO_WIDTH-1:0] host_root_fifo_data_in[NUM_DIMM];
    logic [HOST_ROOT_FIFO_WIDTH-1:0] host_root_fifo_data_out[NUM_DIMM];
    logic host_root_fifo_wrreq[NUM_DIMM];
    logic host_root_fifo_rdreq[NUM_DIMM];
    logic host_root_fifo_empty[NUM_DIMM];
    logic host_root_fifo_almost_full[NUM_DIMM];
    logic host_root_fifo_in_write[NUM_DIMM];
    logic host_root_fifo_in_read[NUM_DIMM];

    // State machine for controlling reads from the root FIFOs
    enum logic [1:0]{
      STATE_READ_FROM_ROOT_FIFO_START = 2'b00,
      STATE_READ_FROM_ROOT_FIFO_RD    = 2'b01,
      STATE_READ_FROM_ROOT_FIFO_WR    = 2'b10
    } root_fifo_read_state[NUM_DIMM];

    /*  The normal FIFO read latency is 1, but when stall-in-earliness is used, the effective read latency increases by ROOT_FIFO_STALL_IN_EARLINESS.
    */
    localparam FIFO_READ_LATENCY = 1 + ROOT_FIFO_STALL_IN_EARLINESS;

    localparam FIFO_WRITE_LATENCY = (ALLOW_HIGH_SPEED_FIFO_USAGE) ? 5 : 3; // The FIFO's write-to-read latency, meaning when wrreq is asserted to an empty FIFO, how many cycles later will that data be available on the FIFO output.

    localparam MUX_DATA_SLICING_MULTIPLIER = 8; //WIDE_DATA_SLICING is intended to specify how wide each section of hld_fifo should be, e.g. 512, multiplexer data path needs to be cut smaller, e.g. 64
    localparam MUX_SELECT_BE_COPIES = (WIDE_DATA_SLICING==0) ? 1 : (MWIDTH_BYTES*MUX_DATA_SLICING_MULTIPLIER+WIDE_DATA_SLICING-1) / WIDE_DATA_SLICING;
    /*
      The root FIFO read-request signal is pipelined to match the read latency through the FIFO so we can track when the FIFO's output data
      is ready to be extracted.
    */
    logic read_root_fifo_rd_req_pipe [1:0][FIFO_READ_LATENCY:1][NUM_DIMM] /* synthesis dont_merge */; // 2 copies of this pipe, one goes to the FIFO another on the avm_output_pipe mux. This is to help decouple the two for better placement.
    logic read_root_fifo_rd_req_pipe_byteenable_copies [MUX_SELECT_BE_COPIES-1:0][FIFO_READ_LATENCY:1][NUM_DIMM] /* synthesis dont_merge */;  //a copy of above replicated for the wide byte enable signal
    logic read_root_fifo_rd_req_comb[NUM_DIMM];
    localparam READ_ROOT_FIFO_WIDTH = RD_ID_WIDTH + O_AVM_ADDRESS_W + BURST_CNT_W; // RRF stores LSU ID, read address, burstcount
    logic [READ_ROOT_FIFO_WIDTH-1:0] read_root_fifo_data_out[NUM_DIMM];
    logic read_root_fifo_empty [NUM_DIMM];

    logic write_root_fifo_rd_req_pipe [FIFO_READ_LATENCY:1][NUM_DIMM];
    logic write_root_fifo_rd_req_comb[NUM_DIMM];
    /*
      Index [0:the minimum] are lookahead on the write-req input to the FIFO.
      Index [1] is the actual write-req input to the FIFO.
      Index [FIFO_WRITE_LATENCY] indicates when write-data is available to be read.
    */
    localparam WRF_LOOKAHEAD_MIN_INDEX = (FIFO_WRITE_LATENCY - FIFO_READ_LATENCY > 0)? 0 : (FIFO_WRITE_LATENCY - FIFO_READ_LATENCY);
    logic write_root_fifo_wr_req_pipe [FIFO_WRITE_LATENCY:WRF_LOOKAHEAD_MIN_INDEX][NUM_DIMM];
    logic write_root_fifo_wr_req[NUM_DIMM];

    logic write_root_fifo_data_in_end_of_burst_pipe [FIFO_WRITE_LATENCY:WRF_LOOKAHEAD_MIN_INDEX][NUM_DIMM];
    logic [MAX_BURST:1] write_root_fifo_DataCount_onehot[NUM_DIMM];

    /*
      Length of the output pipe that feeds the global AvalonMM interface. This can be increased for performance. This will increase the amount of waitrequest-allowance required.
      However, outside this module, Avalon pipeline bridges are generally added for performance so increasing this may not be needed.
    */
    // Output pipeline to the avm interface (ie. the memory)
    logic  [MWIDTH_BYTES-1:0] avm_output_pipe_byteenable [NUM_AVM_OUTPUT_PIPE_STAGES:1][NUM_DIMM];
    logic  [O_AVM_ADDRESS_W-1:0] avm_output_pipe_address [NUM_AVM_OUTPUT_PIPE_STAGES:1][NUM_DIMM];
    logic  avm_output_pipe_read [NUM_AVM_OUTPUT_PIPE_STAGES:1][NUM_DIMM];
    logic  avm_output_pipe_write [NUM_AVM_OUTPUT_PIPE_STAGES:1][NUM_DIMM];
    logic  [BURST_CNT_W-1:0] avm_output_pipe_burstcount [NUM_AVM_OUTPUT_PIPE_STAGES:1][NUM_DIMM];
    logic  [MWIDTH-1:0] avm_output_pipe_writedata [NUM_AVM_OUTPUT_PIPE_STAGES:1][NUM_DIMM];

    logic write_root_fifo_output_end_of_burst[NUM_DIMM];
    logic write_root_fifo_output_end_of_burst_previous[NUM_DIMM];
    logic write_root_fifo_eob_mismatch[NUM_DIMM];
    logic write_root_fifo_eob_match[NUM_DIMM];

    // For the write-root-fifo early empty, we need FIFO_READ_LATENCY cycles of lookahead on the write-request signal.
    // So if FIFO_READ_LATENCY >= FIFO_WRITE_LATENCY, then we need extra pipelining before the write-root-fifo to get enough lookahead.
    // The # of stages required = FIFO_READ_LATENCY - FIFO_WRITE_LATENCY + 1.
    // Minimum value is 1 (mainly because the special case of 0 is not handled, but it could be).
    // Recall that FIFO_READ_LATENCY = 1 + ROOT_FIFO_STALL_IN_EARLINESS
    // And FIFO_WRITE_LATENCY = 5.
    // So for example, if FIFO_READ_LATENCY(FRL)=4, we need 1 stage. FRL = 5, need 1 stage, FRL=6, need 2 stages etc.
    // ** Do not modify this formula. If more stages are needed for FMAX, increase ROOT_FIFO_STALL_IN_EARLINESS or ROOT_WFIFO_VALID_IN_EARLINESS to make it happen.
    localparam NUM_WRITE_RING_OUTPUT_PIPE_STAGES = mymax(ROOT_WFIFO_VALID_IN_EARLINESS, mymax((FIFO_READ_LATENCY - FIFO_WRITE_LATENCY + 1), 1));
    localparam NUM_VIE_WRO_PIPE_STAGES_ADDED = mymax(0, ROOT_WFIFO_VALID_IN_EARLINESS - mymax((FIFO_READ_LATENCY - FIFO_WRITE_LATENCY + 1),1));

    /* These are combinational signals used to gather the ring outputs to then feed into the output pipeline.
     Ideally we'd just use index[0] of the pipeline registers for this purpose but Modelsim gives an
     error when assigning to the same array both continuously and procedurally, even if it's to different
     indexes into the array.
    */
    logic [MWIDTH_BYTES-1:0] write_ring_output_pipe_input_byteenable[NUM_DIMM];
    logic [AWIDTH-1:0] write_ring_output_pipe_input_address[NUM_DIMM];
    logic [BURST_CNT_W-1:0] write_ring_output_pipe_input_burstcount[NUM_DIMM];
    logic [MWIDTH-1:0] write_ring_output_pipe_input_writedata[NUM_DIMM];
    logic write_ring_output_pipe_input_write_request[NUM_DIMM];
    // Ring output pipeline. One per bank. If only one write-ring is used the only one bank's pipeline
    // is kept, the rest should be synthesized away.
    logic [MWIDTH_BYTES-1:0] write_ring_output_pipe_byteenable[NUM_WRITE_RING_OUTPUT_PIPE_STAGES:0][NUM_DIMM];
    logic [AWIDTH-1:0] write_ring_output_pipe_address[NUM_WRITE_RING_OUTPUT_PIPE_STAGES:0][NUM_DIMM];
    logic [BURST_CNT_W-1:0] write_ring_output_pipe_burstcount[NUM_WRITE_RING_OUTPUT_PIPE_STAGES:0][NUM_DIMM];
    logic [MWIDTH-1:0] write_ring_output_pipe_writedata[NUM_WRITE_RING_OUTPUT_PIPE_STAGES:0][NUM_DIMM];

    // Without balanced read/write at the root, we can prioritize writes over reads and generate the write-ack as the command exits the ring.
    // But if BSP write-ack is used, it doesn't matter, the write ack is coming from each bank in the BSP and we need to reorder.
    localparam ENABLE_LOW_LATENCY_WRITE_ACK = !ROOT_ARB_BALANCED_RW && !ENABLE_BSP_AVMM_WRITE_ACK;

    logic write_ring_output_pipe_write_request[NUM_WRITE_RING_OUTPUT_PIPE_STAGES:0][NUM_DIMM];
    logic write_ring_output_pipe_end_of_burst[NUM_WRITE_RING_OUTPUT_PIPE_STAGES:0][NUM_DIMM];
    logic write_root_fifo_most_recent_word_written_end_of_burst[NUM_DIMM]; // Flag to indicate that the most recent word that was written to the write-root-fifo was the end of a burst.

    logic [MAX_BURST+1:0] write_ring_output_burstcounter_onehot[2:1][NUM_DIMM];
    logic [MAX_BURST+1:0] write_ring_output_burstcounter_onehot_comb[NUM_DIMM];
    localparam WAIT_REQUEST_INPUT_PIPE_DEPTH = 0;
    logic wait_request_input_pipe[WAIT_REQUEST_INPUT_PIPE_DEPTH:1][NUM_DIMM];

    logic write_ack_router_backpressure;
    logic [1:0] ecc_err_status_write_ack_router;

    (* noprune *) logic [15:0] counter_rrf_has_data_while_wrf_empty [NUM_DIMM]; // Used in debug only, guarded by an ifdef, so should not be synthesized.

    logic [LARGEST_NUM_BANKS_W-1:0] bank_mask [NUM_MEM_SYSTEMS];



    /* The write root-FIFO's almost_full flag provides the back pressure to the write-ring. When asserted, the FIFO must have
      enough space to accommodate any requests that are already in the pipeline that feeds the FIFO's data input. This includes
      2 x the ring length (ie. NUM_WR_PORT*2) to account for the worst-case latency of the stall reaching the LSU at the end
      of the ring + a full ring's worth of write requests,
      the depth of the write-ring output pipeline which is NUM_WRITE_RING_OUTPUT_PIPE_STAGES, and the pipelining added
      to the ring waitrequest signal.
      the AVM_WRITE_DATA_LATENESS feature adds more latency to the round-trip path of almost full to write request
      -5 is for margin.
    */
    localparam WRITE_ROOT_FIFO_ALMOST_FULL_VALUE = ROOT_FIFO_DEPTH - 5 - (NUM_WR_PORT*2) - NUM_WRITE_RING_OUTPUT_PIPE_STAGES - NUM_RING_WAITREQUEST_PIPE_STAGES - AVM_WRITE_DATA_LATENESS;

    // One reset for each FIFO and its related logic (host root FIFO, read root FIFO, write root FIFO), and one for everything else.
    localparam  NUM_RESET_COPIES = 6;
    localparam  RESET_PIPE_DEPTH = 5;
    logic [NUM_RESET_COPIES-1:0]  sclrn;
    logic                         resetn_synchronized;

    if (NUM_AVM_OUTPUT_PIPE_STAGES < 1) begin
        initial $fatal(1, "lsu_token_ring: NUM_AVM_OUTPUT_PIPE_STAGES should be greater or equal to 1. Specified value: %d", NUM_AVM_OUTPUT_PIPE_STAGES);
    end

    // Here, HYPER_PIPELINE=1, so reset is synchronous and the synchronizer is instantiated by a parent of this module.
    acl_reset_handler
    #(
        .ASYNC_RESET            (0),
        .USE_SYNCHRONIZER       (0),
        .SYNCHRONIZE_ACLRN      (0),
        .PIPE_DEPTH             (RESET_PIPE_DEPTH),
        .NUM_COPIES             (NUM_RESET_COPIES)
    )
    acl_reset_handler_inst
    (
        .clk                    (clk),
        .i_resetn               (resetn),
        .o_aclrn                (), // aclrs are currently not supported when HYPER_PIPELINE==1
        .o_resetn_synchronized  (resetn_synchronized),
        .o_sclrn                (sclrn)
    );

    // Create a per-mem-system bit mask to help dynamically select the appropriate address bits
    for (g=0; g<NUM_MEM_SYSTEMS;g=g+1) begin : GEN_RANDOM_BLOCK_NAME_R192_0
      // Put zeroes in the bit positions that are not used for bank bits (not all mem systems may have the same # of bank bits0)
      if (LARGEST_NUM_BANKS > 1) begin // But only if there are bank bits at all
        assign bank_mask[g] = {LARGEST_NUM_BANKS_W{1'b1}} >> (LARGEST_NUM_BANKS_W - NUM_BANKS_W_PER_MEM_SYSTEM[g]);
      end
    end

    /********************************************************
      Host Root FIFO
    ********************************************************/
    /*
      This FIFO is a temporary stand-in for the lookahead waitrequest we will be getting from the Hyperflex-optimized
      Qsys interconnect. It buffers the output of avm_output_pipe and provides a lookahead stall using its almost_full flag.
      Tracked by Case:423801
    */
    logic [1:0] ecc_err_status_root;
    logic [NUM_DIMM-1:0] ecc_err_status_for_0;
    logic [NUM_DIMM-1:0] ecc_err_status_for_1;
    assign ecc_err_status_root[0] = |ecc_err_status_for_0;
    assign ecc_err_status_root[1] = |ecc_err_status_for_1;
    for (z=0;z<NUM_DIMM;z++) begin : GEN_HOST_ROOT_FIFO

      // Rest of the avm_output_pipe pipeline.
      for (g=2;g<=NUM_AVM_OUTPUT_PIPE_STAGES;g++) begin : GEN_REMAINING_AVM_OUTPUT_PIPE_STAGES
      always @(posedge clk) begin
          avm_output_pipe_read[g][z]        <= avm_output_pipe_read[g-1][z];
          avm_output_pipe_write[g][z]       <= avm_output_pipe_write[g-1][z];
          avm_output_pipe_byteenable[g][z]  <= avm_output_pipe_byteenable[g-1][z];
          avm_output_pipe_burstcount[g][z]  <= avm_output_pipe_burstcount[g-1][z];
          avm_output_pipe_address[g][z]     <= avm_output_pipe_address[g-1][z];
          avm_output_pipe_writedata[g][z]   <= avm_output_pipe_writedata[g-1][z];
        end
      end

      // Feed avm_output_pipe into the host root FIFO.
      // Not connecting end of burst flag (for writes)
      assign host_root_fifo_data_in[z][WRITE_ROOT_FIFO_WIDTH-1:0] = avm_output_pipe_write[NUM_AVM_OUTPUT_PIPE_STAGES][z]?

              {avm_output_pipe_byteenable[NUM_AVM_OUTPUT_PIPE_STAGES][z],avm_output_pipe_address[NUM_AVM_OUTPUT_PIPE_STAGES][z],
                avm_output_pipe_burstcount[NUM_AVM_OUTPUT_PIPE_STAGES][z],avm_output_pipe_writedata[NUM_AVM_OUTPUT_PIPE_STAGES][z]} :

              {{MWIDTH_BYTES{1'b1}},avm_output_pipe_address[NUM_AVM_OUTPUT_PIPE_STAGES][z],avm_output_pipe_burstcount[NUM_AVM_OUTPUT_PIPE_STAGES][z]};

      // By default we do not use the host root FIFO if HYPER_PIPELINE=1. This requires support for waitrequest allowance on the AvalonMM interface.
      if (ENABLE_BSP_WAITREQUEST_ALLOWANCE) begin : GEN_DISABLE_HOST_ROOT_FIFO

        assign o_avm_writedata[z]   = avm_output_pipe_writedata[NUM_AVM_OUTPUT_PIPE_STAGES][z];
        assign o_avm_byteenable[z]  = avm_output_pipe_byteenable[NUM_AVM_OUTPUT_PIPE_STAGES][z];
        assign o_avm_address[z]     = avm_output_pipe_address[NUM_AVM_OUTPUT_PIPE_STAGES][z];
        assign o_avm_burstcount[z]  = avm_output_pipe_burstcount[NUM_AVM_OUTPUT_PIPE_STAGES][z];
        assign o_avm_read[z]        = avm_output_pipe_read[NUM_AVM_OUTPUT_PIPE_STAGES][z];
        assign o_avm_write[z]       = avm_output_pipe_write[NUM_AVM_OUTPUT_PIPE_STAGES][z];

        // Pipeline the input waitrequest, for performance
        always @(posedge clk) begin
          wait_request_input_pipe[1][z]  <= i_avm_waitrequest[z];
          for (int i=2;i<=WAIT_REQUEST_INPUT_PIPE_DEPTH;i++) begin : GEN_RANDOM_BLOCK_NAME_R198
            wait_request_input_pipe[i][z]  <= wait_request_input_pipe[i-1][z];
          end
        end

        assign host_root_fifo_almost_full[z] = (WAIT_REQUEST_INPUT_PIPE_DEPTH>0)? wait_request_input_pipe[WAIT_REQUEST_INPUT_PIPE_DEPTH][z] : i_avm_waitrequest[z];
        assign ecc_err_status_for_0[z] = 1'h0;
        assign ecc_err_status_for_1[z] = 1'h0;
      end else begin : GEN_ENABLE_HOST_ROOT_FIFO

        hld_fifo #(
            .WIDTH                          (HOST_ROOT_FIFO_WIDTH),
            .MAX_SLICE_WIDTH                (WIDE_DATA_SLICING),
            .DEPTH                          (32),
            .ALMOST_FULL_CUTOFF             (32 - 22),
            .ASYNC_RESET                    (0),
            .SYNCHRONIZE_RESET              (0),
            .NEVER_OVERFLOWS                (0),
            .REGISTERED_DATA_OUT_COUNT      (2),
            .STYLE                          (ALLOW_HIGH_SPEED_FIFO_USAGE ? "hs" : "ms"),
            .RESET_EXTERNALLY_HELD          (0),
            .RAM_BLOCK_TYPE                 ("AUTO"),
            .enable_ecc                     (enable_ecc)
        ) host_root_fifo (
            .clock           (clk),
            .resetn          (resetn_synchronized),
            .i_valid         (host_root_fifo_wrreq[z]),
            // the REGISTERED_DATA_OUT_COUNT parameter requires the bits that need registers to be in the LSBs, so re-ordering them.
            .i_data          ({host_root_fifo_data_in[z][WRITE_ROOT_FIFO_WIDTH-1:0],
                               host_root_fifo_data_in[z][WRITE_ROOT_FIFO_WIDTH+1],
                               host_root_fifo_data_in[z][WRITE_ROOT_FIFO_WIDTH]}),
            .o_stall         (),
            .o_almost_full   (host_root_fifo_almost_full[z]),
            .o_valid         (),
            // Matching re-ordering on the output
            .o_data          ({host_root_fifo_data_out[z][WRITE_ROOT_FIFO_WIDTH-1:0],
                               host_root_fifo_data_out[z][WRITE_ROOT_FIFO_WIDTH+1],
                               host_root_fifo_data_out[z][WRITE_ROOT_FIFO_WIDTH]}),
            .i_stall         (!host_root_fifo_rdreq[z]),
            .o_almost_empty  (),
            .o_empty         (host_root_fifo_empty[z]),
            .ecc_err_status  ({ecc_err_status_for_1[z], ecc_err_status_for_0[z]})
        );

        assign host_root_fifo_wrreq[z]                = (avm_output_pipe_write[NUM_AVM_OUTPUT_PIPE_STAGES][z] || avm_output_pipe_read[NUM_AVM_OUTPUT_PIPE_STAGES][z]);
        assign host_root_fifo_data_in[z][WRITE_ROOT_FIFO_WIDTH]    = avm_output_pipe_read[NUM_AVM_OUTPUT_PIPE_STAGES][z];
        assign host_root_fifo_data_in[z][WRITE_ROOT_FIFO_WIDTH+1]  = avm_output_pipe_write[NUM_AVM_OUTPUT_PIPE_STAGES][z];

        assign o_avm_writedata[z] = host_root_fifo_data_out[z][MWIDTH-1:0];
        assign {o_avm_byteenable[z], o_avm_address[z], o_avm_burstcount[z]} = host_root_fifo_data_out[z][WRITE_ROOT_FIFO_WIDTH+1]?
          host_root_fifo_data_out[z][MWIDTH_BYTES + O_AVM_ADDRESS_W+ BURST_CNT_W + MWIDTH - 1 : MWIDTH] :
          {{MWIDTH_BYTES{1'b1}},host_root_fifo_data_out[z][O_AVM_ADDRESS_W+BURST_CNT_W-1:BURST_CNT_W],host_root_fifo_data_out[z][BURST_CNT_W-1:0]};

          assign o_avm_read[z] = host_root_fifo_data_out[z][WRITE_ROOT_FIFO_WIDTH] && !host_root_fifo_empty[z];
          assign o_avm_write[z] = host_root_fifo_data_out[z][WRITE_ROOT_FIFO_WIDTH+1] && !host_root_fifo_empty[z];

          assign host_root_fifo_rdreq[z] = !host_root_fifo_empty[z] && !i_avm_waitrequest[z];
      end
    end

    logic [NUM_DIMM-1:0] input_avm_waitrequest;

    assign wr_request = wr_read | wr_write;
    /* Apparently you can only use reduction operators on packed types, so this converts the unpacked signal
      i_avm_waitrequest to packed signal input_avm_waitrequest so we can later use the OR reduction operator.
      Placing this outside the IF statement because Quartus 16.1 gives an error otherwise.
    */
    for (z=0;z<NUM_DIMM;z++) begin : GEN_INPUT_AVM_WAIT_REQUEST
      assign input_avm_waitrequest[z]  = host_root_fifo_almost_full[z];
    end

    /* If there's only one LSU, we don't need the root-FIFOs and the single LSU can feed the output pipeline directly.
       Note that if ENABLE_BSP_WAITREQUEST_ALLOWANCE==1 we don't need to change anything here. The incoming waitrequest is pipelined
       and fed directly to the single LSU. The internal round-trip latency in this case (ie. from i_avm_waitrequest asserting to o_avm_read/write de-asserting)
       is less than internal round-trip latency where there are > 1 LSUs. So if the downstream AVMM interface's waitrequest-allowance supports more than 1 LSU it will also support
       exactly 1 LSU.
    */
    logic [1:0] ecc_err_status_port;
    if(NUM_ID == 1) begin : GEN_SINGLE_PORT
      //normally AVM_WRITE_DATA_LATENESS is handled in lsu_n_token, the write signal is delayed so that the data can catch up, this happens before writing into the write root fifo
      //in the case of a single write LSU, there is no write root fifo so we have to delay the write signal here
      //FIXME: need to reduce the almost full threshold from the ccb otherwise we can potentially overflow it, or we could add an extra fifo here
      //tracked by case:576733
      logic avm_output_pipe_write_orig    [NUM_DIMM];
      logic avm_output_pipe_write_delayed [AVM_WRITE_DATA_LATENESS:0][NUM_DIMM];
      always_comb begin
        for (int i=0; i<NUM_DIMM; i++) begin
          avm_output_pipe_write_delayed[0][i] = avm_output_pipe_write_orig[i];
        end
      end
      genvar z;
      for (z=1; z<=AVM_WRITE_DATA_LATENESS; z++) begin : GEN_WRITE_DELAY
        always @(posedge clk) begin
          for (int i=0; i<NUM_DIMM; i++) begin
            avm_output_pipe_write_delayed[z][i] <= avm_output_pipe_write_delayed[z-1][i];
          end
        end
      end
      always_comb begin
        for (int i=0; i<NUM_DIMM; i++) begin : GEN_RANDOM_BLOCK_NAME_R201
          avm_output_pipe_write[1][i] = avm_output_pipe_write_delayed[AVM_WRITE_DATA_LATENESS][i];
        end
      end

      // The following chunk of code grabs the mem system and bank bits from the address, then looks up the corresponding port in the root port map.
      logic [NUM_MEM_SYSTEMS_W-1:0] current_mem_system;
      logic [LARGEST_NUM_BANKS_W-1:0] current_bank_within_mem_system;

      if (NUM_RD_PORT == 1) begin
        if (NUM_MEM_SYSTEMS == 1) begin
          assign current_mem_system = 0;
        end else begin
          assign current_mem_system = i_rd_address[0][AWIDTH-1 -: NUM_MEM_SYSTEMS_W];
        end
        // Not all bank bits may be used in the current mem system, so zero out the unused bits with bank_mask.
        if (LARGEST_NUM_BANKS > 1) begin
          assign current_bank_within_mem_system = bank_mask[current_mem_system] & (i_rd_address[0][BANK_BIT_LSB_PER_MEM_SYSTEM[current_mem_system]-MWORD_PAD+LARGEST_NUM_BANKS_W-1 -: LARGEST_NUM_BANKS_W]);
        end else begin
          assign current_bank_within_mem_system = 0;
        end
      end else begin
        if (NUM_MEM_SYSTEMS == 1) begin
          assign current_mem_system = 0;
        end else begin
          assign current_mem_system = i_wr_address[0][AWIDTH-1 -: NUM_MEM_SYSTEMS_W];
        end
        // Not all bank bits may be used in the current mem system, so zero out the unused bits with bank_mask.
        if (LARGEST_NUM_BANKS > 1) begin
          assign current_bank_within_mem_system = bank_mask[current_mem_system] & (i_wr_address[0][BANK_BIT_LSB_PER_MEM_SYSTEM[current_mem_system]-MWORD_PAD+LARGEST_NUM_BANKS_W-1 -: LARGEST_NUM_BANKS_W]);
        end else begin
          assign current_bank_within_mem_system = 0;
        end
      end

      always @(posedge clk) begin
        for(int z=0; z<NUM_DIMM; z=z+1) begin : GEN_RANDOM_BLOCK_NAME_R202

          /* If NUM_RD_PORT != 1, then it must be zero. So in the case of no reads, set avm_output_pipe_read to zero.
            However, if we have one read, then assert avm_output_pipe_read to bank-z if the has a read-request to send
            AND the MSBs of the address correspond to bank-z. If there's only one bank (ie. DIMM_W==0), then assert
            avm_output_pipe_read irrespective of address.
          */

          if (NUM_RD_PORT == 1) begin
            // Read strobe
            if (DIMM_W == 0) begin  // If one-bank
              avm_output_pipe_read[1][z]        <= i_rd_request[0]&& !o_rd_waitrequest[0];
            end else begin  // If more than one bank
              avm_output_pipe_read[1][z]        <= i_rd_request[0] && !o_rd_waitrequest[0] && (ROOT_PORT_MAP[current_mem_system][current_bank_within_mem_system] == z);
            end
            // Write strobe
            avm_output_pipe_write_orig[z]       <= 1'b0;
          end else begin
            // Read strobe
            avm_output_pipe_read[1][z]          <= 1'b0;

            // Write strobe
            if (DIMM_W == 0) begin
              avm_output_pipe_write_orig[z]     <= i_wr_request[0] && !o_wr_waitrequest[0];
            end else begin
              avm_output_pipe_write_orig[z]     <= i_wr_request[0] && !o_wr_waitrequest[0] && (ROOT_PORT_MAP[current_mem_system][current_bank_within_mem_system] == z);
            end
          end

            avm_output_pipe_byteenable[1][z]  <= (NUM_RD_PORT == 1)? '1 : i_wr_byteenable[0];  // All bytes are enabled for reads
            avm_output_pipe_burstcount[1][z]  <= (NUM_RD_PORT == 1)? i_rd_burstcount[0] : i_wr_burstcount[0];
            avm_output_pipe_address[1][z]     <= (NUM_RD_PORT == 1)? i_rd_address[0][O_AVM_ADDRESS_W-1:0]  : i_wr_address[0][O_AVM_ADDRESS_W-1:0];
            avm_output_pipe_writedata[1][z]   <= i_wr_writedata[0];

        end

        // Mimic the backpressure behaviour of a full ring by stalling the LSU if any bank is stalling.
        o_rd_waitrequest[0] <= (|input_avm_waitrequest) || (|id_af); // Load-LSUs must be additionally backpressured by the almost-full from lsu_rd_back's read-request FIFO (avm_read_req_fifo)
        o_wr_waitrequest[0] <= |input_avm_waitrequest;
        o_avm_writeack[0] <= i_wr_request[0] && !o_wr_waitrequest[0];

        rd_burstcount <= i_rd_burstcount[0];
        rd_o_id       <= 1'b0;
        rd_request    <= i_rd_request[0] && !o_rd_waitrequest[0];  // A valid read request is issued only when unstalled
        rd_address    <= i_rd_address[0];
      end
      assign ecc_err_status_port = 2'h0;
    end
    else begin : GEN_MULTIPLE_PORT
      for(z=0; z<NUM_WR_PORT; z=z+1) begin : GEN_WR_DUMMY
        assign ic_read[z] = 1'b0;
      end
      for(z=0; z<NUM_RD_PORT; z=z+1) begin : GEN_RD_DUMMY
        assign ic_write[z] = 1'b0;
      end

      logic [NUM_DIMM-1:0] switch_to_wrf;
      logic [NUM_DIMM-1:0] switch_to_rrf;


      for(z=0; z<NUM_DIMM; z=z+1) begin : ROOT_FIFO_CONTROL_LOGIC
        /********************************************************************
          Root-FIFO Control Logic
        ********************************************************************/
        /* This state machine controls reads from the read and write root-FIFOs.
          A single read request
          is comprised of one word but it represents an entire burst's worth of return data. In contrast, a single write request consists of many words
          (up to a burstcount's worth of words). It appears that this is one of the reasons that priority is given to writes over reads,
          meaning that as soon as the write root-FIFO has a request,
          we interrupt the transmission of read requests in favour of transmitting the writes, since writes take "longer" to transmit (since they are comprised
          of more words).

          It appears a second reason that writes are given priority over reads is to support writeacks. When a store-LSU (AKA write-LSU) issues a write-request,
          the interconnect acknowledges reception of that request (in particular, the writeack to the LSU is asserted when the write request comes out of the
          write ring, NOT when the request is issued to the AvalonMM interface at the output of the interconnect). The interconnect is expected to ensure that once writeack is asserted correspondent
          to a particular write-request, no other write or read request, issued by ANY LSU to the same bank, can reach the global memory before it. The basic arbitration of the interconnect
          ensures that all subsequent write requests are guaranteed to come after. Giving writes priority over reads at the root guarantees that read requests also
          come after.

          The above is the default behaviour. If instead ROOT_ARB_BALANCED_RW=1, reads and writes are given 50/50 priority. In this case the write-ack must be generated from the root.

          The state-machine ensures bubble-free operation in the steady state when the root FIFOs contain lots of requests.
          This logic is pipelined, meaning that when the Avalon-MM (AVM) interface applies backpressure, it takes a few cycles
          for requests to stop being generated. As a result we require the use of waitrequest-allowance, which is the lookahead
          backpressure feature of the Hyperflex-optimized AVM interface. Similarly, when backpressure is removed, it takes a few cycles
          cycle before requests begin to be generated again, which seemingly creates bubbles (we can call them "start-up bubbles"). But in the steady state,
          when backpressure is asserted, we will generate additional requests equal to the # of start-up bubbles, so it evens out.
          Furthermore, it is expected that this module ultimately feeds a downstream FIFO and that FIFO provides the backpressure. The FIFO
          will therefore collapse these bubbles. As long as that downstream FIFO is deep enough and has enough data to cover the start-up delay,
          start-up bubbles should not effect overall throughput.

          For maximum throughput, we must switch between reading from the Read Root FIFO (RRF) and Write Root FIFO (WRF) without creating any bubbles.
          When the WRF goes empty we need to immediately extract data from the RRF. When the WRF has data (goes non-empty), we need to immediately stop extracting data from the RRF and
          begin extracting from the WRF again.
          To help with FMAX we also want the read-request signals into the FIFOs to be registered. This means we can't use WRF's empty signal to combinationally drive
          the read-req of RRF. This implies we need lookahead as to when WRF will go empty and non-empty so we can perfectly time the assertion/de-assertion of read-req to the RRF.
          Furthermore we want to support use of the stall-in-earliness feature of acl_high_speed_fifo since it significantly reduces area. Without this feature, the normal read latency through the FIFO
          is 1 (ie. when read-req is asserted, new data appears 1 cycle later). With stall-in-earliness set to STALL_IN_EARLINESS (nominally 3), the read latency effectively increases to
          (FIFO_READ_LATENCY = 1+STALL_IN_EARLINESS) cycles (nominally 4). This means when read-req is asserted, new data appears FIFO_READ_LATENCY cycles later.

          The FIFO uses read-showahead mode which can make the concept of "FIFO read latency" confusing. Read-showahead mode means that the current valid output data is left dangling on its output as soon
          as it's available to be read. So when read-req is asserted after being de-asserted for a while, this current data will disappear after STALL_IN_EARLINESS cycles.
          Said another way, if read-req has been de-asserted for a while, and is then asserted on cycle 1, the output data must be latched, at the latest, on cycle FIFO_READ_LATENCY.
          But when read-req is asserted continuously (ie. it's been asserted for at least a few cycles already), the output data must be latched exactly on cycle FIFO_READ_LATENCY.

          Similarly, when read-req is de-asserted, new data only stops appearing FIFO_READ_LATENCY cycles later.
          Therefore in order to perfectly time the assertion and deassertion of read-req to RRF, we need FIFO_READ_LATENCY cycles of lookahead on WRF's empty.
          The empty lookahead is implemented using acl_tessellated_incr_decr_threshold. This module effectively maintains a used-words count on the read-side of the FIFO, except we
          look ahead on the wr-req and rd-req signals by FIFO_READ_LATENCY cycles when incrementing and decrementing the count.

          We also cannot begin transmitting read requests to the AvalonMM interface if the current write-burst is incomplete. So in addition to looking ahead on the WRF empty, we check
          to make sure WRF goes empty coincident with the end of a burst.
        */

        /* Read from the read-root-fifo if reads are not being throttled due to lack of space in the return
          data FIFOs in lsu_rd_back and we are not stalled by waitrequest. We do not check
          read_root_fifo_empty (ie. we will allow reads from an empty read-root-FIFO, but we later check
          if the read was valid or not)
        */
        assign read_root_fifo_rd_req_comb[z] = !read_request_throttle[z] && !host_root_fifo_almost_full[z];

        /* The only thing that stops us from reading from the write-root FIFO is the waitrequest backpressure.
           There is also no need to read from the write-root FIFO if there is no write-ring, so tie off the read-req.
        */
        assign write_root_fifo_rd_req_comb[z] = !host_root_fifo_almost_full[z] && !DISABLE_WR_RING;

        // Grab the flag that indicates the burst boundary of write-requests. This is used to detect when to switch to reads. Used for debug only.
        assign write_root_fifo_output_end_of_burst[z] = write_root_fifo_data_out[z][1+MWIDTH_BYTES+O_AVM_ADDRESS_W+BURST_CNT_W+MWIDTH-1:MWIDTH_BYTES+O_AVM_ADDRESS_W+BURST_CNT_W+MWIDTH];

        // The threshold for the balanced read/write priority scheme is 4 bursts. This is a magic number for now but should be made into a compiler param (Case:14012278003)
        logic [1:0] read_req_counter;
        logic max_read_req_elapsed;
        logic [1:0] write_req_counter;
        logic max_write_req_elapsed;
        logic read_req_being_issued;
        logic write_req_being_issued;
        logic wrf_out_eob; // EOB = end of burst. Need to track burst-boundaries for writes.

        assign read_req_being_issued = read_root_fifo_rd_req_pipe[0][FIFO_READ_LATENCY][z] && !read_root_fifo_empty[z];
        assign write_req_being_issued = write_root_fifo_rd_req_pipe[FIFO_READ_LATENCY][z] && !write_root_fifo_empty[z];

        assign wrf_out_eob = write_root_fifo_data_out[z][WRITE_ROOT_FIFO_WIDTH-1];

        // Start reading from the Write Root FIFO if it has data and we've hit the # bursts threshold or if the if the Read Root FIFO is empty.
       assign switch_to_wrf[z] = (root_fifo_read_state[z] == STATE_READ_FROM_ROOT_FIFO_RD) && (!write_root_fifo_empty_lookahead[z]
                    && ( (ROOT_ARB_BALANCED_RW && ((read_req_counter == 3 && read_req_being_issued) || max_read_req_elapsed)) || read_root_fifo_empty[z])
                );

        // Start reading from the RRF if it has data and we've hit the # bursts threshold, but synchronize the switch to a burst boundary.
        assign switch_to_rrf[z] = (root_fifo_read_state[z] == STATE_READ_FROM_ROOT_FIFO_WR) && ( (write_root_fifo_empty_lookahead[z] && write_root_fifo_most_recent_word_written_end_of_burst[z]) || // If going empty, wait until EoB.
                   (ROOT_ARB_BALANCED_RW && (write_req_being_issued && wrf_out_eob && ((write_req_counter==3) ||  max_write_req_elapsed))) // If not going empty, but 4+ EoB's have been observed
                );


        always @(posedge clk) begin

          write_root_fifo_output_end_of_burst_previous[z] <= write_root_fifo_output_end_of_burst[z] && !write_root_fifo_empty[z]; // Used only for debug, will be synthesized away

          // State machine
          case (root_fifo_read_state[z])
            /* The purpose of the START state is to assert the read-req to the read-root-FIFO immediately
                after reset. This state-machine was originally written using SCFIFO instead of the high-speed FIFO.
                It's questionable if we could just assert read-req during reset (it's not clear in
                the SCFIFO user's guide if this is OK), so using a separate state to be safe.
            */
            STATE_READ_FROM_ROOT_FIFO_START: begin
              root_fifo_read_state[z]   <= STATE_READ_FROM_ROOT_FIFO_RD;
            end
            STATE_READ_FROM_ROOT_FIFO_RD: begin

              // Count the number of requests issue
              if (read_req_being_issued) begin
                read_req_counter <= read_req_counter + 1;
                if (read_req_counter == 3) begin
                  max_read_req_elapsed <= 1'b1;
                end
              end

              if (switch_to_wrf[z]) begin // When the write-root-fifo is about to have data, check if we should stop reading from the read-root-fifo
                // TODO (Case:14012282222) implement a RRF lookahead empty to eliminate the bubble that occurs when switching to WRF with less than 3 read reqs issued
                  root_fifo_read_state[z]   <= STATE_READ_FROM_ROOT_FIFO_WR;
                  for (i=0; i<2; i++) read_root_fifo_rd_req_pipe[i][1][z]  <= 1'b0; // stop reading from RRF
                  for (i=0; i<MUX_SELECT_BE_COPIES; i++) read_root_fifo_rd_req_pipe_byteenable_copies[i][1][z]  <= 1'b0;
                  write_req_counter <= 0;
                  max_write_req_elapsed <= 1'b0;
                  write_root_fifo_rd_req_pipe[1][z] <= write_root_fifo_rd_req_comb[z];
              end else begin
                for (i=0; i<2; i++) read_root_fifo_rd_req_pipe[i][1][z]  <= read_root_fifo_rd_req_comb[z];  // Read from the read-root-fifo as long as it's not being throttled
                for (i=0; i<MUX_SELECT_BE_COPIES; i++) read_root_fifo_rd_req_pipe_byteenable_copies[i][1][z]  <= read_root_fifo_rd_req_comb[z];
              end
            end
            STATE_READ_FROM_ROOT_FIFO_WR: begin

              // When an EoB is written into the WRF, increment here. That burst should get fully read out.
              if (write_req_being_issued && wrf_out_eob) begin
                write_req_counter <= write_req_counter + 1;
                if (write_req_counter == 3) begin
                  max_write_req_elapsed <= 1'b1;
                end
              end

              // Keep reading from the write-root-fifo until the FIFO goes empty, aligned with the end of a burst (ie. we must wait until the current write-burst is complete)
              // Only switch aligned to EoB. Switch if WRF is empty or 4+ requests have been issued.
              if ( switch_to_rrf[z]) begin
                write_root_fifo_eob_mismatch[z]   <= !write_root_fifo_output_end_of_burst_previous[z];  // Used for debug, will be synthesized away.
                root_fifo_read_state[z]           <= STATE_READ_FROM_ROOT_FIFO_RD;
                for (i=0; i<2; i++) read_root_fifo_rd_req_pipe[i][1][z]  <= read_root_fifo_rd_req_comb[z];
                for (i=0; i<MUX_SELECT_BE_COPIES; i++) read_root_fifo_rd_req_pipe_byteenable_copies[i][1][z]  <= read_root_fifo_rd_req_comb[z];
                read_req_counter <= 0;
                max_read_req_elapsed <= 1'b0;
                write_root_fifo_rd_req_pipe[1][z] <= 1'b0; // Stop reading from WRF
              end else begin
                write_root_fifo_rd_req_pipe[1][z] <= write_root_fifo_rd_req_comb[z];
              end
            end
          endcase

          if (!sclrn[4]) begin
            root_fifo_read_state[z]   <= STATE_READ_FROM_ROOT_FIFO_START;
            // Reset the first stage of the pipe and let it trickle through.
            for (i=0; i<2; i++) read_root_fifo_rd_req_pipe[i][1][z]  <= 1'b0;
            for (i=0; i<MUX_SELECT_BE_COPIES; i++) read_root_fifo_rd_req_pipe_byteenable_copies[i][1][z]  <= 1'b0;
            write_root_fifo_rd_req_pipe[1][z] <= 1'b0;
            read_req_counter <= 0;
            max_read_req_elapsed <= 1'b0;
            write_req_counter <= 0;
            max_write_req_elapsed <= 1'b0;
          end

          /*  Complete the root-fifo read-req pipes.
              The actual read-req signal fed to the FIFOs is tapped off this pipeline ROOT_FIFO_STALL_IN_EARLINESS stages before the end.
              The rd-req signal is pipelined to match the read latency through the FIFO so we know when to extract valid data from its output.
          */
          for (int j=2;j<=FIFO_READ_LATENCY;j++) begin : GEN_RANDOM_BLOCK_NAME_R203
            for (i=0; i<2; i++) read_root_fifo_rd_req_pipe[i][j][z]  <= read_root_fifo_rd_req_pipe[i][j-1][z];
            for (i=0; i<MUX_SELECT_BE_COPIES; i++) read_root_fifo_rd_req_pipe_byteenable_copies[i][j][z]  <= read_root_fifo_rd_req_pipe_byteenable_copies[i][j-1][z];
            write_root_fifo_rd_req_pipe[j][z] <= write_root_fifo_rd_req_pipe[j-1][z];
          end

          /*******************************************************
            Root-FIFO Output Pipeline
          *******************************************************/
          // Assert avm_read/write only if we successfully extract valid data from the FIFO
          avm_output_pipe_read[1][z]          <= read_root_fifo_rd_req_pipe[0][FIFO_READ_LATENCY][z] && !read_root_fifo_empty[z];
          avm_output_pipe_write[1][z]         <= write_root_fifo_rd_req_pipe[FIFO_READ_LATENCY][z] && !write_root_fifo_empty[z];
          if (read_root_fifo_rd_req_pipe[0][FIFO_READ_LATENCY][z]) begin  // Mux the data between the read and write root FIFOs.
            avm_output_pipe_burstcount[1][z]  <= read_root_fifo_data_out[z][BURST_CNT_W-1:0];
            avm_output_pipe_address[1][z]     <= read_root_fifo_data_out[z][O_AVM_ADDRESS_W+BURST_CNT_W-1:BURST_CNT_W];
          end else begin // Otherwise, stage-2 is fed by stage-1.
            avm_output_pipe_burstcount[1][z]  <= write_root_fifo_data_out[z][BURST_CNT_W+MWIDTH-1:MWIDTH];
            avm_output_pipe_address[1][z]     <= write_root_fifo_data_out[z][O_AVM_ADDRESS_W+BURST_CNT_W+MWIDTH-1:BURST_CNT_W+MWIDTH];
          end
          avm_output_pipe_writedata[1][z]     <= write_root_fifo_data_out[z][MWIDTH-1:0];
        end

        logic [MWIDTH_BYTES-1:0] write_root_fifo_data_out_byteenable;
        assign write_root_fifo_data_out_byteenable = write_root_fifo_data_out[z][MWIDTH_BYTES+O_AVM_ADDRESS_W+BURST_CNT_W+MWIDTH-1:O_AVM_ADDRESS_W+BURST_CNT_W+MWIDTH];

        for (g=0; g<MUX_SELECT_BE_COPIES; g++) begin : GEN_MUX_SELECT_BE_COPIES
          localparam BE_START = g * MWIDTH_BYTES / MUX_SELECT_BE_COPIES;
          localparam BE_END = (g+1) * MWIDTH_BYTES / MUX_SELECT_BE_COPIES;
          localparam BE_WIDTH = BE_END - BE_START;
          always @(posedge clk) begin
            avm_output_pipe_byteenable[1][z][BE_START +: BE_WIDTH] <= (read_root_fifo_rd_req_pipe_byteenable_copies[g][FIFO_READ_LATENCY][z]) ? {BE_WIDTH{1'b1}} : write_root_fifo_data_out_byteenable[BE_START +: BE_WIDTH];
          end
        end
          // The rest of the avm_output_pipe is implemented in another section.
        end

      /*******************************************************
        Generate Read Ring
      *******************************************************/
      logic [1:0] ecc_err_status_rd;
      if(NUM_RD_PORT > 0) begin : GEN_ENABLE_RD
        lsu_n_token #(
           .AWIDTH(AWIDTH),
           .MWIDTH_BYTES(MWIDTH_BYTES),
           .BURST_CNT_W(BURST_CNT_W),
           .NUM_PORT(NUM_RD_PORT),
           .START_ID(START_ID),
           .OPEN_RING(!DISABLE_WR_RING & !ENABLE_DUAL_RING),
           .SINGLE_STALL((DISABLE_WR_RING | ENABLE_DUAL_RING) & ENABLE_DATA_REORDER), // wr_root_af is from the single ID FIFO; sw-dimm-partion has N ID FIFOs
           .ENABLE_DATA_REORDER(ENABLE_DATA_REORDER),
           .START_ACTIVE(1),
           .ENABLE_FAST(ENABLE_READ_FAST),
           .NUM_DIMM(NUM_DIMM),
           .ENABLE_LAST_WAIT(ENABLE_LAST_WAIT),
           .READ(1),
           .HYPER_PIPELINE(HYPER_PIPELINE),
           .MAX_REQUESTS_PER_LSU (MAX_REQUESTS_PER_LSU)
         ) rd_ring (
          .clk              (clk),
          .resetn           (sclrn[0]), // Normally sub-modules are reset using resetn_synchronized, but here we want to ensure lsu_n_token comes out of reset AFTER this module.
          .i_ext_read       (1'b0),
          .i_avm_write      (ic_write),
          .i_token          (),
          .i_avm_address    (i_rd_address),
          .i_avm_read       (i_rd_request),
          .i_avm_burstcount (i_rd_burstcount),
          .i_avm_waitrequest(rd_waitrequest),
          .o_avm_waitrequest(o_rd_waitrequest),
          .o_avm_address    (rd_address),
          .o_avm_read       (rd_request),
          .o_avm_burstcount (rd_burstcount),
          .o_token          (rd_o_token),
          .o_id             (rd_o_id)
        );


        logic [1:0] ecc_err_status_for;
        logic [NUM_DIMM-1:0] ecc_err_status_for_0;
        logic [NUM_DIMM-1:0] ecc_err_status_for_1;
        assign ecc_err_status_for[0] = |ecc_err_status_for_0;
        assign ecc_err_status_for[1] = |ecc_err_status_for_1;
        for(z=0; z<NUM_DIMM; z=z+1) begin : GEN_RD_SET

          // Route the read request to the target output bank.
          logic [NUM_MEM_SYSTEMS_W-1:0] current_mem_system;
          logic [LARGEST_NUM_BANKS_W-1:0] current_bank_within_mem_system;

          if (NUM_DIMM == 1) begin
            assign wr_rd_root_en[z] = rd_request;
          end else begin // NUM_DIMM > 1
            if (NUM_MEM_SYSTEMS == 1) begin
              assign current_mem_system = 0;
            end else begin
              assign current_mem_system = rd_address[AWIDTH-1 -: NUM_MEM_SYSTEMS_W];
            end
            if (LARGEST_NUM_BANKS > 1) begin
              // Not all bank bits may be used in the current mem system, so zero out the unused bits with bank_mask.
              assign current_bank_within_mem_system = bank_mask[current_mem_system] & (rd_address[BANK_BIT_LSB_PER_MEM_SYSTEM[current_mem_system]-MWORD_PAD+LARGEST_NUM_BANKS_W-1 -: LARGEST_NUM_BANKS_W]);
            end else begin
              assign current_bank_within_mem_system = 0;
            end
            assign wr_rd_root_en[z] = rd_request & (ROOT_PORT_MAP[current_mem_system][current_bank_within_mem_system] == z);
          end

          hld_fifo #(
              .WIDTH                          (READ_ROOT_FIFO_WIDTH),
              .MAX_SLICE_WIDTH                (WIDE_DATA_SLICING),
              .DEPTH                          (RD_ROOT_FIFO_DEPTH),
              .ALMOST_FULL_CUTOFF             (5 + NUM_RD_PORT*2),
              .ASYNC_RESET                    (0),
              .SYNCHRONIZE_RESET              (0),
              .NEVER_OVERFLOWS                (1),
              .STALL_IN_EARLINESS             (ROOT_FIFO_STALL_IN_EARLINESS),
              // Registering the full FIFO output since some of the data output feeds combinational logic (muxes into the output pipeline). The data width of this FIFO is small so this does not appear to impact performance.
              .REGISTERED_DATA_OUT_COUNT      (READ_ROOT_FIFO_WIDTH),
              .STYLE                          (ALLOW_HIGH_SPEED_FIFO_USAGE ? "hs" : "ms"),
              .RESET_EXTERNALLY_HELD          (0),
              .RAM_BLOCK_TYPE                 ("AUTO"),
              .enable_ecc                     (enable_ecc)
          ) read_root_fifo (
              .clock           (clk),
              .resetn          (resetn_synchronized),
              .i_valid         (wr_rd_root_en[z]),
              .i_data          ({rd_o_id, rd_address[O_AVM_ADDRESS_W-1:0],rd_burstcount}),
              .o_stall         (),
              .o_almost_full   (rd_root_af[z]),
              .o_valid         (),
              .o_data          (read_root_fifo_data_out[z]),
              .i_stall         (!read_root_fifo_rd_req_pipe[1][FIFO_READ_LATENCY - ROOT_FIFO_STALL_IN_EARLINESS][z]),
              .o_almost_empty  (),
              .o_empty         (read_root_fifo_empty[z]),
              .ecc_err_status  ({ecc_err_status_for_1[z], ecc_err_status_for_0[z]})
          );

          `ifdef DEBUG_AVMM
          // RRF has data, we are not reading it, and WRF is empty too. Count how long we're stuck for.
          always @(posedge clk) begin
            if (!read_root_fifo_empty[z] && !read_root_fifo_rd_req_pipe[1][FIFO_READ_LATENCY - ROOT_FIFO_STALL_IN_EARLINESS][z] && write_root_fifo_empty[z]) begin
              counter_rrf_has_data_while_wrf_empty[z] <= counter_rrf_has_data_while_wrf_empty[z] + 1;
            end else begin
              counter_rrf_has_data_while_wrf_empty[z] <= 0;
            end

            if (!sclrn[2]) begin
              counter_rrf_has_data_while_wrf_empty[z] <= 0;
            end
          end
          `endif

          /* The read-ring back pressure comes from lsu_rd_back's internal FIFO that buffers read-requests. It tracks the
              read-requests that are issued so that it knows to which LSU the returned data should be routed. This FIFO's capacity
              is ultimately what limits how many outstanding read requests there can be since this FIFO can't overflow.
              One might wonder why we don't use the read-root-fifo's almost-full to provide the backpressure to the read ring
              just like we use the write-root-fifo's almost-full to provide backpressure to the write ring. It's simply because the
              read-root-FIFO is read before lsu_rd_back's FIFO is read. We read from the read_root_fifo to issue the requests
              to the AvalonMM interface, but we only read from lsu_rd_back's FIFO when the data returns -- so this FIFO is the ultimate
              limitation.
              The backpressure to the read ring should not be confused with the read_request_throttle signal that's generated using
              the pending_rd count. The read-request-throttle is used in multi-bank mode, and it controls the issuing of read
              requests on a *per bank* basis, as dictated by the available capacity of lsu_rd_back's internal data FIFOs. These FIFOs
              cannot overflow so their almost_full is used to control the throttling of read-requests being pulled out of the respective
              bank's read_root_fifo. But the absolute overall number of read-requests
              (to any bank) that the read-ring is allowed to have outstanding is limited by the capacity of lsu_rd_back's internal read-request
              FIFO.
          */
          always @(posedge clk) begin
            rd_ring_waitrequest_pipe[1][z] <= id_af[z];
            for (int i=2;i<=NUM_RING_WAITREQUEST_PIPE_STAGES;i++) begin : GEN_RANDOM_BLOCK_NAME_R204
              rd_ring_waitrequest_pipe[i][z] <= rd_ring_waitrequest_pipe[i-1][z];
            end
          end
          assign rd_waitrequest[z] = rd_ring_waitrequest_pipe[NUM_RING_WAITREQUEST_PIPE_STAGES][z];
        end
        assign ecc_err_status_rd = ecc_err_status_for;
      end //end if(NUM_RD_PORT > 0) begin : GEN_ENABLE_RD
      else begin : GEN_DISABLE_RD
        // If there's no read ring, and therefore no read root FIFO, hook up the read root FIFO output signals
        // as though there are never any read requests from the read-ring.
        for(z=0; z<NUM_DIMM; z=z+1) begin : GEN_DISABLE_RD_ROOT_FIFO_CONNECTIONS
          always @(posedge clk) begin
            read_root_fifo_empty[z] <= 1'b1;
          end
        end
        assign ecc_err_status_rd = 2'h0;
      end // end GEN_DISABLE_RD

      /*******************************************************
        Generate Write Ring
      *******************************************************/
      logic [1:0] ecc_err_status_wr;
      if(!DISABLE_WR_RING) begin : GEN_ENABLE_WRITE_RING

        logic [AWIDTH-1:0] wr_ring_i_addr [NUM_WR_PORT];
        logic wr_ring_i_write [NUM_DIMM] [NUM_WR_PORT];
        logic wr_ring_o_waitrequest [NUM_DIMM][NUM_WR_PORT];
        logic [0:NUM_DIMM-1] v_wr_stall [NUM_WR_PORT];
        logic [0:NUM_DIMM-1] wr_accept [NUM_WR_PORT];
        logic [WR_RING_ID_WIDTH-1:0] wr_o_id [NUM_DIMM];

        logic [NUM_MEM_SYSTEMS_W-1:0] current_mem_system_wr[NUM_WR_PORT];
        logic [LARGEST_NUM_BANKS_W-1:0] current_bank_within_mem_system_wr[NUM_WR_PORT]; // TODO: Assumes the widest bank ID width comes from NUM_BANKS_W_PER_MEM_SYSTEM[0]. Fine for now since this is enforced. But clean this up later.

        if(ENABLE_MULTIPLE_WR_RING_INT) begin : GEN_MULTIPLE_WR_RING
          //TODO: with multiple write rings, we need to peek at the address in order to figure out which ring a given transaction will go to
          //with a single write ring, the ring does not need to consume the address so it is fine for it to run late
          //to fix this, whatever bits of the address is needed (e.g. if we interleave between 2 rings on 1 KB boundaries, then use bit 10 of address), those bits need to run on-time coming out of the LSUs
          `ifdef ALTERA_RESERVED_QHD
          `else
          //synthesis translate_off
          `endif
          if (AVM_WRITE_DATA_LATENESS) begin
              $fatal(1, "lsu_token_ring, AVM_WRITE_DATA_LATENESS is not supported with HYPER_PIPELINE == 1 and multiple write rings");
          end
          `ifdef ALTERA_RESERVED_QHD
          `else
          //synthesis translate_on
          `endif

          for(z0=0; z0<NUM_WR_PORT; z0=z0+1) begin : GEN_WR_STALL_AND_CURRENT_MEM_SYSTEM_LOOKUP
            assign o_wr_waitrequest[z0] = |v_wr_stall[z0];  // Stall LSU z0 if any bank is stalling LSU z0.

            assign wr_ring_i_addr[z0] = i_wr_address[z0][AWIDTH-1:0];

            // Determine the target root port
            if (NUM_MEM_SYSTEMS == 1) begin
              assign current_mem_system_wr[z0] = 0;
            end else begin
              assign current_mem_system_wr[z0] = i_wr_address[z0][AWIDTH-1 -: NUM_MEM_SYSTEMS_W];
            end
            if (LARGEST_NUM_BANKS > 1) begin
              assign current_bank_within_mem_system_wr[z0] = bank_mask[current_mem_system_wr[z0]] & (i_wr_address[z0][BANK_BIT_LSB_PER_MEM_SYSTEM[current_mem_system_wr[z0]]-MWORD_PAD+LARGEST_NUM_BANKS_W-1 -: LARGEST_NUM_BANKS_W]);
            end else begin
              assign current_bank_within_mem_system_wr[z0] = 0;
            end

          end
          for(z=0; z<NUM_DIMM; z=z+1) begin : GEN_
            logic wr_i_waitrequest [1];

            assign wr_i_waitrequest[0] = wr_root_af[z];

            // Write request routing
            for(z0=0; z0<NUM_WR_PORT; z0=z0+1) begin : GEN_WR_ENABLE
              // Actual write request routing
              assign wr_ring_i_write[z][z0] = i_wr_request[z0] & (ROOT_PORT_MAP[current_mem_system_wr[z0]][current_bank_within_mem_system_wr[z0]] == z);

              // Take the waitrequest to the z0 LSU (from the ring), but only forward it if that LSU is writing to
              // the specified bank.
              assign v_wr_stall[z0][z] = wr_ring_o_waitrequest[z][z0] & (ROOT_PORT_MAP[current_mem_system_wr[z0]][current_bank_within_mem_system_wr[z0]] == z);
              assign wr_accept[z0][z] = wr_dimm_en[z] & wr_o_id[z] == z0;    // Used for write-ack as the request comes out of the ring. wr_dimm_en is the wr_request strobe output from the write-ring.
            end

            lsu_n_token #(
               .AWIDTH(AWIDTH),
               .MWIDTH_BYTES(MWIDTH_BYTES),
               .BURST_CNT_W(BURST_CNT_W),
               .NUM_PORT(NUM_WR_PORT),
               .ID_WIDTH(WR_RING_ID_WIDTH),
               .ENABLE_DATA_REORDER(ENABLE_DATA_REORDER),
               .OPEN_RING(0),
               .START_ACTIVE(1),
               .NUM_DIMM(1),
               .ENABLE_LAST_WAIT(0),
               .START_ID(0),
               .READ(0),
               .HYPER_PIPELINE(HYPER_PIPELINE),
               .MAX_REQUESTS_PER_LSU (MAX_REQUESTS_PER_LSU)
             ) wr_ring_multiple (
              .clk              (clk),
              .resetn           (sclrn[0]),    // Normally sub-modules are reset using resetn_synchronized, but here we want to ensure lsu_n_token comes out of reset AFTER this module.
              .i_token          (1'b0),
              .i_id             (),
              .i_ext_address    (),
              .i_ext_read       (1'b0),
              .i_ext_burstcount (),
              .o_ext_waitrequest(),
              .i_avm_byteenable (i_wr_byteenable),
              .i_avm_address    (wr_ring_i_addr),
              .i_avm_read       (ic_read),
              .i_avm_write      (wr_ring_i_write[z]),
              .i_avm_writedata  (i_wr_writedata),
              .i_avm_burstcount (i_wr_burstcount),
              .i_avm_waitrequest(wr_i_waitrequest),
              .o_avm_waitrequest(wr_ring_o_waitrequest[z]),
              .o_avm_byteenable (wr_ring_o_byteenable[z]),
              .o_avm_address    (wr_ring_o_addr[z]),
              .o_avm_read       (),
              .o_avm_write      (wr_dimm_en[z]),
              .o_avm_burstcount (wr_ring_o_burstcount[z]),
              .o_id             (wr_o_id[z]),
              .o_token          (),
              .o_avm_writedata  (wr_ring_o_writedata[z])
            );

            assign write_ring_output_pipe_input_byteenable[z]    = wr_ring_o_byteenable[z];
            assign write_ring_output_pipe_input_address[z]       = wr_ring_o_addr[z];
            assign write_ring_output_pipe_input_burstcount[z]    = wr_ring_o_burstcount[z];
            assign write_ring_output_pipe_input_writedata[z]     = wr_ring_o_writedata[z];
            assign write_ring_output_pipe_input_write_request[z] = wr_dimm_en[z];
          end
        end
        else begin : GEN_SINGLE_WR_RING
          lsu_n_token #(
             .AWIDTH(AWIDTH),
             .MWIDTH_BYTES(MWIDTH_BYTES),
             .BURST_CNT_W(BURST_CNT_W),
             .NUM_PORT(NUM_WR_PORT),
             .ID_WIDTH(WR_RING_ID_WIDTH),
             .ENABLE_DATA_REORDER(ENABLE_DATA_REORDER),
             .OPEN_RING(NUM_RD_PORT > 0 & !ENABLE_DUAL_RING),
             .START_ACTIVE(NUM_RD_PORT == 0 | ENABLE_DUAL_RING),
             .NUM_DIMM(NUM_DIMM),
             .ENABLE_LAST_WAIT(0),
             .START_ID(0),
             .READ(0),
             .AVM_WRITE_DATA_LATENESS(AVM_WRITE_DATA_LATENESS),
             .WIDE_DATA_SLICING(WIDE_DATA_SLICING),
             .HYPER_PIPELINE(HYPER_PIPELINE),
             .MAX_REQUESTS_PER_LSU (MAX_REQUESTS_PER_LSU)
           ) wr_ring (
            .clk              (clk),
            .resetn           (sclrn[0]),    // Normally sub-modules are reset using resetn_synchronized, but here we want to ensure lsu_n_token comes out of reset AFTER this module.
            .i_token          (1'b0),
            .i_id             (),
            .i_ext_address    (),
            .i_ext_read       (1'b0),
            .i_ext_burstcount (rd_burstcount),
            .o_ext_waitrequest(),
            .i_avm_byteenable (i_wr_byteenable),
            .i_avm_address    (i_wr_address),
            .i_avm_read       (ic_read),
            .i_avm_write      (i_wr_request),
            .i_avm_writedata  (i_wr_writedata),
            .i_avm_burstcount (i_wr_burstcount),
            .i_avm_waitrequest(wr_ring_waitrequest),
            .o_avm_waitrequest(o_wr_waitrequest),
            .o_avm_byteenable (wr_byteenable),
            .o_avm_address    (wr_address),
            .o_avm_read       (wr_read), // ??
            .o_avm_write      (wr_write),
            .o_avm_burstcount (wr_burstcount),
            .o_id             (wr_id),
            .o_token          (),
            .o_avm_writedata  (wr_writedata)
          );

          // Route the request to the target root port
          if (NUM_MEM_SYSTEMS == 1) begin
            assign current_mem_system_wr[0] = 0;
          end else begin
            assign current_mem_system_wr[0] = wr_address[AWIDTH-1 -: NUM_MEM_SYSTEMS_W];
          end
          // Not all bank bits may be used in the current mem system, so zero out the unused bits with bank_mask.
          if (LARGEST_NUM_BANKS > 1) begin
            assign current_bank_within_mem_system_wr[0] = bank_mask[current_mem_system_wr[0]] & (wr_address[BANK_BIT_LSB_PER_MEM_SYSTEM[current_mem_system_wr[0]]-MWORD_PAD+LARGEST_NUM_BANKS_W-1 -: LARGEST_NUM_BANKS_W]);
          end else begin
            assign current_bank_within_mem_system_wr[0] = 0;
          end

          for(z=0; z<NUM_DIMM; z=z+1) begin : SINGLE_WR_RING_OUTPUT_PIPE_INPUT_ASSIGNMENT

            /*
              The write ring is backpressured by the write-root-fifo (WRF) almost full and the write-ack-router backpressure.
              It may not be clear why we OR these signals together as opposed to just using one.

              The WRF must not be allowed to overflow. It is a wide FIFO (> MWIDTH wide) and only needs to be as deep as is necessary
              to ensure it never goes empty once the top-level AVMM interface de-asserts backpressure. This depth is dictated by the
              latency through the FIFO as well as the latency from the LSU to the FIFO. A depth of 512 is usually more than enough.

              But the narrow avm_read_req_fifo inside the write-ack-router (lsu_rd_back) also must not overflow. The difference is that it needs
              to be deep enough to ensure we allow enough pending write requests to cover the round-trip latency to memory.

              In steady state, if the write-ack-router is deep enough, it will rarely backpressure.
            */
            // Pipeline the waitrequest going into the ring, for performance
            always @(posedge clk) begin
              wr_ring_waitrequest_pipe[1][z] <= wr_root_af[z] || write_ack_router_backpressure;
              for (int i=2;i<=NUM_RING_WAITREQUEST_PIPE_STAGES;i++) begin : GEN_RANDOM_BLOCK_NAME_R205
                wr_ring_waitrequest_pipe[i][z] <= wr_ring_waitrequest_pipe[i-1][z];
              end
            end
            assign wr_ring_waitrequest[z] = wr_ring_waitrequest_pipe[NUM_RING_WAITREQUEST_PIPE_STAGES][z];

            assign write_ring_output_pipe_input_byteenable[z]    = wr_byteenable;
            assign write_ring_output_pipe_input_address[z]       = wr_address;
            assign write_ring_output_pipe_input_burstcount[z]    = wr_burstcount;
            assign write_ring_output_pipe_input_writedata[z]     = wr_writedata;

            // Not sure why wr_request is used instead of wr_write
            if (NUM_DIMM == 1) begin
              assign write_ring_output_pipe_input_write_request[z] = wr_request;
            end else begin // NUM_DIMM > 1
              assign write_ring_output_pipe_input_write_request[z] = wr_request & (ROOT_PORT_MAP[current_mem_system_wr[0]][current_bank_within_mem_system_wr[0]] == z);
            end
          end

        end // end single ring vs multi ring

        // ------------------
        // Generate and re-order write ACK
        // ------------------

        /*
          In a multi-bank system with interleaving, write responses (write acks) must be re-ordered just like read data.
          This block of code generates the write ack and handles the reordering, very similar to how read data reordering is handled.

          There are 3 variables that control write-ack generation
          ENABLE_MULTIPLE_WR_RING_INT
          ENABLE_BSP_AVMM_WRITE_ACK
          ROOT_ARB_BALANCED_RW

          If ENABLE_MULTIPLE_WR_RING_INT=1, then we parameterize the write-ack router to accept parallel commands since
            we have multiple write command rings.
          If ENABLE_BSP_AVMM_WRITE_ACK=1, the write-ack is sourced from the BSP (and is an input to this module).
          If ROOT_ARB_BALANCED_RW=1, we internally generate the write-ack as the write-request is leaving the root. This is the earliest point
            in the interconnect where it's guaranteed that writes and reads stay in-order.

          Future enhancement: if ENABLE_MULTIPLE_WR_RING_INT=0 and ENABLE_BSP_AVMM_WRITE_ACK=0 and ROOT_ARB_BALANCED_RW=1, technically we can forgo the write-ack
            reordering logic and simply internally generate the write-ack at the root. This requires carrying the LSU ID all the way to the root. The area
            savings will be small though.
        */

        /*  Track write-requests as they exit the write-ring using lsu_rd_back_n.
            This module performs response routing and re-ordering (for multi-bank systems).
            In the case of write-ack, there is no data associated with the response so the lsu_rd_back datapath is disconnected.
            i_avm_write_ack is assumed to assert once for every write-data word.
            If SWDIMM is used we technically do not need to re-order the write-acks. This is constrast
            to how we handle SWDIMM on readdata, in which rather
            than instantiate a single lsu_rd_back with re-ordering enabled (this will use wide FIFOs for reordering), we instead instantiate
            NUM_DIMM lsu_rd_backs with reorderding disabled (no wide FIFOs are used) and each only performs routing. We could do the same
            here but the area savings is not expected to be large since the datapath is disconnected. But we technically could save a few
            M20Ks by getting rid of the 1-bit wide reordering FIFOs. If we do this we'll need to enhance lsu_swdimm_token_ring to block
            write-LSUs from switching banks (which it already does for reads).
        */

        if (ENABLE_LOW_LATENCY_WRITE_ACK) begin : GEN_INTERNAL_WRITE_ACK_LOW_LATENCY// Writes are prioritized over reads and we need to generate the writeack internally. Therefore we can generate the write-ack as the request leaves the ring. This is the earliest we can do it.
          always @(posedge clk) begin
            // Generate the write-ack as the request exits the ring
            if (ENABLE_MULTIPLE_WR_RING_INT) begin // Gather the writes from multiple rings. They are combined into wr_accept
              for(i=0; i<NUM_WR_PORT; i=i+1) o_avm_writeack[i] <= |wr_accept[i];
            end else begin // Gather the writes from the output of the one ring
              for(i=0; i<NUM_WR_PORT; i=i+1) o_avm_writeack[i] <= wr_write & wr_id == i;
            end
          end
          assign write_ack_router_backpressure = 1'b0;
        end else begin : GEN_WRITE_ACK_ROUTER // Write-ack reordering is needed because the write-ack comes from the root (either internally or from the BSP).

          /* In the case where the writeack is generated from the root, we need to ensure its sufficiently delayed
              to allow time for the write command to propagate within the reordering unit. The command exits the ring
              and goes to 2 places:
              1. through the WRF to the root
              2. to the write-ack reordering unit

              #2 contains a FIFO therefore the latency in paths #1 (which also contains a FIFO, the WRF) and #2 is very similar
              so there can be a race condition. To alleviate this, simply delay the write-ack.

              We can calculate the latencies on 1 and 2 and then figure out much to add.
          */
          // Shortest possible latency from write ring output to root output.
          localparam WRITE_COMMAND_LATENCY_TO_ROOT = NUM_WRITE_RING_OUTPUT_PIPE_STAGES + FIFO_WRITE_LATENCY + NUM_AVM_OUTPUT_PIPE_STAGES;

          // Latency from write ring output to the command having fully propagated through the write-ack reorder unit's internals.
          // Tried specifying latency as a localparam within lsu_rd_back_n and querying it from here, but Quartus displays a compilation error.
          // 1 input stage in lsu_rd_back_n before the L2, 1 input stage inside the L2, FIFO latency, skid buffer latency of 1.
          localparam WRITE_COMMAND_LATENCY_THROUGH_WRITE_ACK_REORDERER = 1 + 1 + FIFO_WRITE_LATENCY + 1;

          // No matter what, pipe by at least 3 (using 3 for some margin, we just need it to be longer, so a value of 1 theoretically could be used).
          // If latency to the root is shorter, we need to also match the latency through the reorderer.
          // If latency to the root is already longer, no need to add any more stages.
          localparam WRITE_ACK_PIPE_DEPTH = mymax(WRITE_COMMAND_LATENCY_THROUGH_WRITE_ACK_REORDERER - WRITE_COMMAND_LATENCY_TO_ROOT,0) + 3;

          logic write_ack_pipe [WRITE_ACK_PIPE_DEPTH:1][NUM_DIMM];

          localparam NUM_WRITE_ACK_COMMAND_INPUTS = ENABLE_MULTIPLE_WR_RING_INT? NUM_WR_PORT : 1; // If using parallel commands, we have one command bus per mastter
          logic [DIMM_W-1:0]      write_ack_avm_port_num        [NUM_WRITE_ACK_COMMAND_INPUTS];
          logic [BURST_CNT_W-1:0] write_ack_router_i_burstcount [NUM_WRITE_ACK_COMMAND_INPUTS];
          logic [WR_ID_WIDTH-1:0] write_ack_router_i_lsu_id     [NUM_WRITE_ACK_COMMAND_INPUTS];
          logic                   write_ack_router_i_valid      [NUM_WRITE_ACK_COMMAND_INPUTS];
          logic [BURST_CNT_W-1:0] write_ack_router_i_agent_avm_burstcount [NUM_DIMM];
          logic                   write_ack_router_i_write_ack            [NUM_DIMM];

          // Write-ack generation
          if (ENABLE_BSP_AVMM_WRITE_ACK) begin : GEN_BSP_WRITE_ACK // BSP writeack
            assign write_ack_router_i_write_ack = i_avm_write_ack;
          end else begin : GEN_INTERNAL_WRITE_ACK // Internally generated write-ack
            always @(posedge clk) begin
              // Generate writeack as the request leaves the root
              for(i=0; i<NUM_DIMM; i=i+1) write_ack_pipe[1][i] <= o_avm_write[i] && (ENABLE_BSP_WAITREQUEST_ALLOWANCE || !i_avm_waitrequest[i]);

              for (int i=2;i<=WRITE_ACK_PIPE_DEPTH;i=i+1) begin
                write_ack_pipe[i] <= write_ack_pipe[i-1];
              end

              // synchronous reset (these assignments override the assignments above if reset is asserted)
              if(!sclrn[0]) begin
                for(i=0; i<NUM_DIMM; i=i+1) write_ack_pipe[1][i]  <= '0;
              end
            end
            for(z=0; z<NUM_DIMM; z++) begin : GEN_RANDOM_BLOCK_NAME_R192_1 // Grab from the end of the pipe
              assign write_ack_router_i_write_ack[z] = write_ack_pipe[WRITE_ACK_PIPE_DEPTH][z];
            end
          end

          // Select between parallel vs serial command tracking
          if (ENABLE_MULTIPLE_WR_RING_INT) begin : GEN_WRITE_ACK_PARALLEL_COMMANDS
            // Grab the write commands directly from the LSUs
            for (z=0; z<NUM_WRITE_ACK_COMMAND_INPUTS;z=z+1) begin : GEN_RANDOM_BLOCK_NAME_R192_2
              assign write_ack_avm_port_num[z]        = ROOT_PORT_MAP[current_mem_system_wr[z]][current_bank_within_mem_system_wr[z]]; // Target agent #
              assign write_ack_router_i_burstcount[z] = 1;
              assign write_ack_router_i_lsu_id[z]     = z;
              assign write_ack_router_i_valid[z]      = i_wr_request[z] && !o_wr_waitrequest[z];
            end
          end else begin : GEN_WRITE_ACK_SERIALIZED_COMMANDS
            // Grab the write commands from the output of the single write ring
            //if(NUM_DIMM > 1) assign write_ack_avm_port_num = wr_address[AWIDTH-1:AWIDTH-DIMM_W];
            if(NUM_DIMM > 1) assign write_ack_avm_port_num[0] = ROOT_PORT_MAP[current_mem_system_wr[0]][current_bank_within_mem_system_wr[0]];
            else assign write_ack_avm_port_num[0] = 1'b0;

            assign write_ack_router_i_lsu_id[0] = wr_id;
            assign write_ack_router_i_valid[0] = wr_request;
            assign write_ack_router_i_burstcount[0] = 1;
          end

          for (z=0; z<NUM_DIMM; z=z+1) begin : GEN_RANDOM_BLOCK_NAME_R192_3
            assign write_ack_router_i_agent_avm_burstcount[z] = 1;
          end

          lsu_rd_back_n #(
            .NUM_DIMM (NUM_DIMM),
            .NUM_RD_PORT (NUM_WR_PORT),    // # of downstream LSUs
            .BURST_CNT_W (BURST_CNT_W),
            .MWIDTH (MWIDTH),
            .MAX_MEM_DELAY(WRITE_ACK_FIFO_DEPTH),   // MAX_MEM_DELAY sets the depth of the avm_read_req, which tracks every piece of write-data.
            .PIPELINE (1),                // enable pipelined vine rather than fanout
            .NUM_REORDER(1),
            .HYPER_PIPELINE(HYPER_PIPELINE),
            .DATA_FIFO_DEPTH(WRITE_ACK_FIFO_DEPTH), // DATA_FIFO_DEPTH sets the depth of the reordering FIFOs.
            .ID_AF_EXTERNAL_LATENCY(NUM_RING_WAITREQUEST_PIPE_STAGES),    // // The amount of latency from write_ack_router_backpressure asserting to wait-request to the write-ring asserting.
            .ALLOW_HIGH_SPEED_FIFO_USAGE(ALLOW_HIGH_SPEED_FIFO_USAGE),
            .ENABLE_PARALLEL_COMMANDS(ENABLE_MULTIPLE_WR_RING_INT),
            .enable_ecc(enable_ecc)
          ) write_ack_router(
            .clk                (clk),
            .resetn             (resetn_synchronized),

            .i_to_avm_port_num  (write_ack_avm_port_num),
            .i_to_avm_burstcount(write_ack_router_i_burstcount), // For simplicity, we track every piece of writedata as it goes out, not every burst. So set the burstcount to 1. Future optimization can be to track only bursts (ie. record the real burstcount). This will make the avm_read_req FIFO shallower.
            .i_to_avm_id        (write_ack_router_i_lsu_id),
            .i_to_avm_valid     (write_ack_router_i_valid),

            .i_agent_avm_burstcount (write_ack_router_i_agent_avm_burstcount),
            .i_agent_host_id      (wr_o_id),
            .i_agent_valid          (wr_dimm_en),

            .i_data             (),     // No data associated with write-ack
            .i_data_valid       (write_ack_router_i_write_ack),
            .o_id_af            (write_ack_router_backpressure),
            .o_data             (),     // No data associated with write-ack
            .o_data_valid       (o_avm_writeack), // The write-ack routed to the correct LSU
            .ecc_err_status     (ecc_err_status_write_ack_router)
          );
        end

        /********************************************
          Write Root FIFOs
        ********************************************/
        // Write-ring output pipeline, end-of-burst precomputation, and root FIFOs.
        // When using multiple write rings, there is one pipeline per bank.
        // With only one write ring, there is only one pipeline in total and the others should be synthesized away
        logic [1:0] ecc_err_status_for;
        logic [NUM_DIMM-1:0] ecc_err_status_for_0;
        logic [NUM_DIMM-1:0] ecc_err_status_for_1;
        assign ecc_err_status_for[0] = |ecc_err_status_for_0;
        assign ecc_err_status_for[1] = |ecc_err_status_for_1;
        for(z=0; z<NUM_DIMM; z=z+1) begin : GEN_WR_ROOT_FIFOS
          logic i_valid_local;
          /*
              Use a one-hot counter, which can be thought of as counting down.
              The count value reflects the word number in stage-1 (though it's counting down)
              Load the one-hot counter with the new one-hot burstcount when the counter is rolling over
              (ie. when index[1] == 1). Otherwise shift the counter to the right (towards the LSB)
              The write-ring output is pipelined.
              This code flags the of end of the burst. The logic that reads from the write-root-fifo needs to know
              when the write-root-FIFO goes empty coincident with the end of a burst so it can begin reading from the read-root-FIFO.
              See that code for more detailed comments.
          */

          // This is the next-stage logic for the one-hot counter. It's written this way so we can peak at these signals for lookahead on the end-of-burst flag.
          always_comb begin
            for (int i=0;i<=MAX_BURST+1;i++) begin : ONE_HOT_COUNTER
              if (i == MAX_BURST + 1) begin
                write_ring_output_burstcounter_onehot_comb[z][i] = 1'b0;  // Shift zero into the MSB of the counter
              end else begin
                /* If a new input word is here and the word in stage-1 is the EoB or the EoB has happened already,
                  we need to reload the counter.
                */
                if  ( write_ring_output_pipe_input_write_request[z] &&
                      ( (write_ring_output_burstcounter_onehot[1][z][1] && write_ring_output_pipe_write_request[1][z])
                        || write_ring_output_burstcounter_onehot[1][z][0]
                      )
                    ) begin
                    // Load the counter with the one-hot starting value.
                    // Convert the binary burstcount to one-hot.
                    // Index [0] will be set to 0 since wr_burstcount is assumed to be > 0
                    // [1][0][g] = [pipe stage 1][g'th bit]
                    write_ring_output_burstcounter_onehot_comb[z][i] = (i == write_ring_output_pipe_input_burstcount[z])? 1'b1 : 1'b0;

                // Otherwise shift the counter whenever a valid word is in stage-1
                end else if (write_ring_output_pipe_write_request[1][z]) begin
                  write_ring_output_burstcounter_onehot_comb[z][i] = write_ring_output_burstcounter_onehot[1][z][i+1]; // Zero is shifted into the MSB (see above)
                end else begin
                  write_ring_output_burstcounter_onehot_comb[z][i] = write_ring_output_burstcounter_onehot[1][z][i];
                end
                end
              end
              end

          // Write ring output pipeline. Write-request handled separately.
          always @(posedge clk) begin
              // Stage-1
              write_ring_output_pipe_byteenable[1][z]    <= write_ring_output_pipe_input_byteenable[z];
              write_ring_output_pipe_address[1][z]       <= write_ring_output_pipe_input_address[z];
              write_ring_output_pipe_burstcount[1][z]    <= write_ring_output_pipe_input_burstcount[z];
              write_ring_output_pipe_writedata[1][z]     <= write_ring_output_pipe_input_writedata[z];

              write_ring_output_burstcounter_onehot[1][z] <= write_ring_output_burstcounter_onehot_comb[z];

              // Remaining pipe stages
              for (int i=2;i<=NUM_WRITE_RING_OUTPUT_PIPE_STAGES;i++) begin : GEN_RANDOM_BLOCK_NAME_R207
                write_ring_output_pipe_byteenable[i][z]    <= write_ring_output_pipe_byteenable[i-1][z];
                write_ring_output_pipe_address[i][z]       <= write_ring_output_pipe_address[i-1][z];
                write_ring_output_pipe_burstcount[i][z]    <= write_ring_output_pipe_burstcount[i-1][z];
                write_ring_output_pipe_writedata[i][z]     <= write_ring_output_pipe_writedata[i-1][z];
              end

              if (!sclrn[2]) begin
                write_ring_output_burstcounter_onehot[1][z][0] <= 1'b1;  // Ensures counter is loaded when first word arrives after reset
              end
          end

          // Pipeline for write-request
          for (z0=0;z0<=NUM_WRITE_RING_OUTPUT_PIPE_STAGES;z0++) begin : GEN_RANDOM_BLOCK_NAME_R208
            if (z0==0) begin
              assign write_ring_output_pipe_write_request[0][z] = write_ring_output_pipe_input_write_request[z];
            end else begin // i>= 1
              always @(posedge clk) begin
                 write_ring_output_pipe_write_request[z0][z] <=  write_ring_output_pipe_write_request[z0-1][z];
          end
            end
          end

          // Pipeline for end-of-burst flag
          for (z0=0;z0<=NUM_WRITE_RING_OUTPUT_PIPE_STAGES;z0++) begin : GEN_RANDOM_BLOCK_NAME_R209
            if (z0 == 0) begin
              assign write_ring_output_pipe_end_of_burst[0][z] = write_ring_output_burstcounter_onehot_comb[z][1];
            end else if (z0 == 1) begin
            assign write_ring_output_pipe_end_of_burst[1][z] = write_ring_output_burstcounter_onehot[1][z][1];
            end else begin
            always @(posedge clk) begin
                write_ring_output_pipe_end_of_burst[z0][z] <= write_ring_output_pipe_end_of_burst[z0-1][z];
              end
            end
          end

          // Cleanly grab the finalpipe outputs
          assign write_root_fifo_data_in[z] = {
            write_ring_output_pipe_end_of_burst[NUM_WRITE_RING_OUTPUT_PIPE_STAGES][z],
            write_ring_output_pipe_byteenable[NUM_WRITE_RING_OUTPUT_PIPE_STAGES][z],
            write_ring_output_pipe_address[NUM_WRITE_RING_OUTPUT_PIPE_STAGES][z][O_AVM_ADDRESS_W-1:0], // This is where the address is truncated in single-mem-system.
            write_ring_output_pipe_burstcount[NUM_WRITE_RING_OUTPUT_PIPE_STAGES][z],
            write_ring_output_pipe_writedata[NUM_WRITE_RING_OUTPUT_PIPE_STAGES][z]
          };
          assign write_root_fifo_wr_req[z] = write_ring_output_pipe_write_request[NUM_WRITE_RING_OUTPUT_PIPE_STAGES][z];
          assign i_valid_local = write_ring_output_pipe_write_request[NUM_WRITE_RING_OUTPUT_PIPE_STAGES - ROOT_WFIFO_VALID_IN_EARLINESS][z];

         `ifdef SIM_ONLY // check bubble or error
            reg  [AWIDTH-DIMM_W-1:0] R_addr;
            reg  not_wr_empty, not_rd_empty;
            reg  freeze_read, freeze_write;
            localparam BUBBLE_COUNTER_WIDTH = 64;
            logic [NUM_DIMM-1:0][BUBBLE_COUNTER_WIDTH-1:0]count_unstalled_cycles_with_data_to_output;
            logic [NUM_DIMM-1:0][BUBBLE_COUNTER_WIDTH-1:0]count_data_output_cycles;
            logic [NUM_DIMM-1:0][BUBBLE_COUNTER_WIDTH-1:0]num_bubbles;

            //assign debug_bubble[z] = !i_avm_waitrequest[z] & (!o_avm_write[z] & not_wr_empty) & (!o_avm_read[z] & not_rd_empty); // check if there is switch bubble
            assign debug_bubble[z] = !host_root_fifo_almost_full[z] & (!o_avm_write[z] & not_wr_empty) & (!o_avm_read[z] & not_rd_empty); // check if there is switch bubble
            always @(posedge clk) begin
              if(o_avm_write[z]) R_addr <= o_avm_address[z];
              if(o_avm_write[z]) R_addr <= o_avm_address[z];
              not_wr_empty <= !write_root_fifo_empty[z];
              not_rd_empty <= !read_root_fifo_empty[z];
              freeze_read <= i_avm_waitrequest[z] & o_avm_read[z];
              freeze_write <= i_avm_waitrequest[z] & o_avm_write[z];
              error_0[z] <= R_addr !== o_avm_address[z] & wr_cnt[z] < write_root_fifo_data_out[z][MWIDTH+BURST_CNT_W-1:MWIDTH] & wr_cnt[z] != 1 & (o_avm_read[z] | o_avm_write[z]) ; // switch to rd when wr has not finished
              error_1[z] <= freeze_read & !o_avm_read[z] | freeze_write & !o_avm_write[z] | o_avm_read[z] & o_avm_write[z];  // output request changes during i_avm_waitrequest

              for (int z=0;z<NUM_DIMM;z++) begin : GEN_RANDOM_BLOCK_NAME_R210
                // Track how many cycles in which we're not being stalled and either of the root FIFOs has data to send
                if (!host_root_fifo_almost_full[z] && (!write_root_fifo_empty[z] || !read_root_fifo_empty[z])) begin
                  count_unstalled_cycles_with_data_to_output[z] <= count_unstalled_cycles_with_data_to_output[z] + 1;
                end
                // Count how many cycles we spend sending data
                if (avm_output_pipe_read[NUM_AVM_OUTPUT_PIPE_STAGES][z] || avm_output_pipe_write[NUM_AVM_OUTPUT_PIPE_STAGES][z]) begin
                  count_data_output_cycles[z]  <= count_data_output_cycles[z] + 1;
                end
                num_bubbles[z] <= count_unstalled_cycles_with_data_to_output[z] - count_data_output_cycles[z];
              end

              if (!sclrn[0]) begin
                count_unstalled_cycles_with_data_to_output <= '0;
                count_data_output_cycles <= '0;
                num_bubbles <= '0;
              end
            end
          `endif

          hld_fifo #(
              .WIDTH                          (WRITE_ROOT_FIFO_WIDTH),
              .MAX_SLICE_WIDTH                (WIDE_DATA_SLICING),
              .DEPTH                          (ROOT_FIFO_DEPTH),
              .ALMOST_FULL_CUTOFF             (ROOT_FIFO_DEPTH - WRITE_ROOT_FIFO_ALMOST_FULL_VALUE),
              .ASYNC_RESET                    (0),
              .SYNCHRONIZE_RESET              (0),
              .NEVER_OVERFLOWS                (1),
              .VALID_IN_EARLINESS             (ROOT_WFIFO_VALID_IN_EARLINESS),
              .STALL_IN_EARLINESS             (ROOT_FIFO_STALL_IN_EARLINESS),
              // Registering the full FIFO output since some of the data output feeds combinational logic (muxes into the output pipeline). The data width of this FIFO is small so this does not appear to impact performance.
              .REGISTERED_DATA_OUT_COUNT      (1),
              .STYLE                          (ALLOW_HIGH_SPEED_FIFO_USAGE ? "hs" : "ms"),
              .RESET_EXTERNALLY_HELD          (0),
              .RAM_BLOCK_TYPE                 ("AUTO"),
              .enable_ecc                     (enable_ecc)
          ) write_root_fifo (
              .clock           (clk),
              .resetn          (resetn_synchronized),
              .i_valid         (i_valid_local),
              .i_data          ({write_root_fifo_data_in[z][WRITE_ROOT_FIFO_WIDTH-2:0],
                                 write_root_fifo_data_in[z][WRITE_ROOT_FIFO_WIDTH-1]}),
              .o_stall         (),
              .o_almost_full   (wr_root_af[z]),
              .o_valid         (),
              .o_data          ({write_root_fifo_data_out[z][WRITE_ROOT_FIFO_WIDTH-2:0],
                                 write_root_fifo_data_out[z][WRITE_ROOT_FIFO_WIDTH-1]}),
              .i_stall         (!write_root_fifo_rd_req_pipe[FIFO_READ_LATENCY - ROOT_FIFO_STALL_IN_EARLINESS][z]),
              .o_almost_empty  (),
              .o_empty         (write_root_fifo_empty[z]),
              .ecc_err_status  ({ecc_err_status_for_1[z], ecc_err_status_for_0[z]})
          );

          /*
            Pipeline the write-request signal going into the write-root-FIFO to match its write-to-read latency.
            This is used to track when data that is written into the FIFO is available to be read.
            write_root_fifo_wr_req_pipe[1] is equivalent to the i_valid on write_root_fifo. Index [0:WRF_LOOKAHEAD_MIN_INDEX] are early versions of this signal.
          */
          for (z0=WRF_LOOKAHEAD_MIN_INDEX;z0<=FIFO_WRITE_LATENCY;z0++) begin : GEN_
            if (z0 == WRF_LOOKAHEAD_MIN_INDEX) begin
              assign write_root_fifo_wr_req_pipe[WRF_LOOKAHEAD_MIN_INDEX][z] = write_ring_output_pipe_write_request[NUM_VIE_WRO_PIPE_STAGES_ADDED][z];
              assign write_root_fifo_data_in_end_of_burst_pipe[WRF_LOOKAHEAD_MIN_INDEX][z] = write_ring_output_pipe_end_of_burst[NUM_VIE_WRO_PIPE_STAGES_ADDED][z];
            end else begin
              always @(posedge clk) begin
                write_root_fifo_wr_req_pipe[z0][z] <= write_root_fifo_wr_req_pipe[z0-1][z];
                write_root_fifo_data_in_end_of_burst_pipe[z0][z] <= write_root_fifo_data_in_end_of_burst_pipe[z0-1][z];
              end
            end
          end

          /*
            Lookahead on the write-root-fifo's empty signal. This is used by the root-fifo control logic to know when to switch between reading from the write and read root FIFOs.
            The amount of lookahead needed is FIFO_READ_LATENCY, which is why we look at the write-request and read-request signals from FIFO_READ_LATENCY cycles ago.
          */
          assign write_root_fifo_empty_lookahead_incr[z] = write_root_fifo_wr_req_pipe[FIFO_WRITE_LATENCY - FIFO_READ_LATENCY][z];
          // write_root_fifo_rd_req_pipe is sized [FIFO_READ_LATENCY:1] which is why we look at write_root_fifo_rd_req_comb, which feeds index [1]. We also guard against underflow -- a read is only valid if there is data.
          assign write_root_fifo_empty_lookahead_decr[z] = write_root_fifo_rd_req_comb[z] && ( (root_fifo_read_state[z] == STATE_READ_FROM_ROOT_FIFO_WR && !switch_to_rrf[z]) || switch_to_wrf[z])
                                                          && !write_root_fifo_empty_lookahead[z];
          acl_tessellated_incr_decr_threshold #(
              .CAPACITY                   (ROOT_FIFO_DEPTH),
              .THRESHOLD                  (1),
              .THRESHOLD_REACHED_AT_RESET (0),
              .ASYNC_RESET                (0)
          )
          write_root_fifo_empty_lookahead_gen
          (
              .clock                      (clk),
              .resetn                     (sclrn[2]),
              .incr_no_overflow           (write_root_fifo_empty_lookahead_incr[z]),
              .incr_raw                   (write_root_fifo_empty_lookahead_incr[z]),
              .decr_no_underflow          (write_root_fifo_empty_lookahead_decr[z]),
              .decr_raw                   (write_root_fifo_empty_lookahead_decr[z]),
              .threshold_reached          (write_root_fifo_not_empty_lookahead[z])
          );
          assign write_root_fifo_empty_lookahead[z] = !write_root_fifo_not_empty_lookahead[z];

          always @(posedge clk) begin
            if (write_root_fifo_empty_lookahead_incr[z]) begin // When a word is written in, track if it was the EoB.
              write_root_fifo_most_recent_word_written_end_of_burst[z] <= write_root_fifo_data_in_end_of_burst_pipe[FIFO_WRITE_LATENCY - FIFO_READ_LATENCY][z];
            end
            if (!sclrn[2]) begin
              write_root_fifo_most_recent_word_written_end_of_burst[z] <= 1'b0;
            end
          end

        end // end GEN_WR_ROOT_FIFOS z-loop
        assign ecc_err_status_wr = ecc_err_status_for;
      end // end GEN_ENABLE_WRITE_RING
      else begin : GEN_DISABLE_WRITE_RING
        // If there's no write ring, and therefore no write root FIFO, hook up the write root FIFO output signals
        // as though there are never any write requests from the write-ring.
        for(z=0; z<NUM_DIMM; z=z+1) begin : GEN_DISABLE_WR_ROOT_FIFO_CONNECTIONS
          always @(posedge clk) begin
            write_root_fifo_empty[z] <= 1'b1;
            wr_root_af[z] <= 1'b0;
            write_root_fifo_empty_lookahead[z] <= 1'b1; // Say WRF is always empty
            write_root_fifo_most_recent_word_written_end_of_burst[z] <= 1'b0;
          end
        end
        assign ecc_err_status_wr = 2'h0;
      end
      assign ecc_err_status_port = ecc_err_status_rd | ecc_err_status_wr;
    end  // end MULTIPLE PORTS
    logic [DIMM_W:0] to_avm_port_num;

    // Track the output root port that the read request is targeting.
    logic [NUM_MEM_SYSTEMS_W-1:0] current_mem_system;
    logic [LARGEST_NUM_BANKS_W-1:0] current_bank_within_mem_system;

    if (NUM_DIMM == 1) begin
      assign to_avm_port_num = 1'b0;
    end else begin // NUM_DIMM > 1
      if (NUM_MEM_SYSTEMS == 1) begin
        assign current_mem_system = 0;
      end else begin
        assign current_mem_system = rd_address[AWIDTH-1 -: NUM_MEM_SYSTEMS_W];
      end
      if (LARGEST_NUM_BANKS > 1) begin
        // Not all bank bits may be used in the current mem system, so zero out the unused bits with bank_mask.
        assign current_bank_within_mem_system = bank_mask[current_mem_system] & (rd_address[BANK_BIT_LSB_PER_MEM_SYSTEM[current_mem_system]-MWORD_PAD+LARGEST_NUM_BANKS_W-1 -: LARGEST_NUM_BANKS_W]);
      end else begin
        assign current_bank_within_mem_system = 0;
      end
      assign to_avm_port_num = ROOT_PORT_MAP[current_mem_system][current_bank_within_mem_system];
    end

    logic [DIMM_W-1:0]       lsu_rd_back_i_to_avm_port_num   [1];
    logic [BURST_CNT_W-1:0]  lsu_rd_back_i_to_avm_burstcount [1];
    logic [RD_ID_WIDTH-1:0]  lsu_rd_back_i_to_avm_id         [1];  // LSU ID, used when NUM_HOST_COMMAND_INPUTS == 1. Otherwise the index simply indicates the host ID.
    logic                    lsu_rd_back_i_to_avm_valid      [1];

    assign lsu_rd_back_i_to_avm_port_num[0]    = to_avm_port_num;
    assign lsu_rd_back_i_to_avm_burstcount[0]  = rd_burstcount;
    assign lsu_rd_back_i_to_avm_id[0]          = rd_o_id;
    assign lsu_rd_back_i_to_avm_valid[0]       = rd_request;

    logic [1:0] ecc_err_status_lsu_rd_back;
    /*******************************************************
      Generate Read Return Data Reordering
    *******************************************************/
    if(ENABLE_DATA_REORDER & NUM_RD_PORT > 0) begin : GEN_DATA_REORDER
      lsu_rd_back_n #(
        .NUM_DIMM (NUM_DIMM),
        .NUM_RD_PORT (NUM_RD_PORT),
        .NUM_REORDER(NUM_REORDER_INT),
        .BURST_CNT_W (BURST_CNT_W),
        .MWIDTH (MWIDTH),
        .DATA_FIFO_DEPTH(RETURN_DATA_FIFO_DEPTH),
        .MAX_MEM_DELAY (MAX_MEM_DELAY),
        .PIPELINE (PIPELINE_RD_RETURN),
        .HYPER_PIPELINE(HYPER_PIPELINE),
        .AVM_READ_DATA_LATENESS(AVM_READ_DATA_LATENESS),
        .WIDE_DATA_SLICING(WIDE_DATA_SLICING),
        .ID_AF_EXTERNAL_LATENCY(NUM_RING_WAITREQUEST_PIPE_STAGES), //id_af is pipelined by this amount before backpressuring the read ring.
        .ALLOW_HIGH_SPEED_FIFO_USAGE(ALLOW_HIGH_SPEED_FIFO_USAGE),
        .enable_ecc(enable_ecc),
        .ENABLE_PARALLEL_COMMANDS(0)
      ) lsu_rd_back_n (
        .clk                    (clk),
        .resetn                 (resetn_synchronized),

        .i_to_avm_port_num      (lsu_rd_back_i_to_avm_port_num  ),
        .i_to_avm_burstcount    (lsu_rd_back_i_to_avm_burstcount),
        .i_to_avm_id            (lsu_rd_back_i_to_avm_id        ),
        .i_to_avm_valid         (lsu_rd_back_i_to_avm_valid     ),

        .i_data                 (i_avm_readdata),
        .i_data_valid           (i_avm_return_valid),
        .i_reorder_id_per_load  (reorder_id_per_load),
        .o_data                 (o_avm_readdata),
        .o_data_valid           (o_avm_readdatavalid),
        .o_rd_bank              (rd_bank),
        .o_id_af                (id_af[0]),
        .ecc_err_status         (ecc_err_status_lsu_rd_back)
      );
      if(NUM_DIMM > 1) assign id_af[1:NUM_DIMM-1] = '0;
      logic [NUM_REORDER-1:0][NUM_DIMM-1:0][PENDING_CNT_W-1:0] pending_rd;
      logic  [0:NUM_DIMM-1] R_o_avm_read;
      logic  [BURST_CNT_W-1:0]  R_o_avm_burstcnt [NUM_DIMM];
      logic  [RD_ID_WIDTH-1:0] R_o_avm_lsu_id [NUM_DIMM]; // LSU ID
      logic  [RD_ID_WIDTH-1:0] R_o_avm_lsu_id_stage_2 [NUM_DIMM]; // LSU ID
      logic  R_rd_bank[NUM_REORDER][NUM_DIMM];
      logic  [PENDING_CNT_W-1:0]  burstcount_minus_rd_bank [NUM_REORDER][NUM_DIMM];
      logic  [PENDING_CNT_W-1:0]  minus_rd_bank [NUM_REORDER][NUM_DIMM];
      logic  valid_avm_read[NUM_DIMM];
      logic  [PENDING_CNT_W-1:0] pending_rd_increment_value [NUM_REORDER][NUM_DIMM];
      localparam NUM_DATA_AF_COMPARE_STAGES = 2;
      logic [NUM_DIMM-1:0][NUM_REORDER-1:0] read_request_throttle_per_reorder;

      always @(posedge clk) begin
        /***********************************************
          Read Request Throttling
        ***********************************************/
        for(i=0; i<NUM_DIMM; i=i+1) begin : GEN_RANDOM_BLOCK_NAME_R211
          /* We must ensure the FIFOs inside lsu_rd_back can accommodate the return data from the requests that
            are issued.
            For a given bank [i], pending_rd is a count of the number of outstanding read words from bank [i]
            not yet returned to the corresponding LSU. Said another way, it's the # of spaces that have been reserved
            in the read return data FIFOs. pending_rd is used to throttle the issuing of further read requests
            to a given bank.

            pending_rd is maintained as a per-bank per-reorder unit counter.
            We may use multiple reordering units as a way to increase read bandwidth in a multi-bank system.
            Each reordering unit has one FIFO per bank, therefore the total number of return data FIFOs
            per bank is NUM_REORDER. This increases our total capacity for catching read data which means
            we can issue more read requests to a given bank.

            pending_rd is calculated by accumulating the burstcounts of read requests as they go out to the memory
            and decrementing the count as words are read out of the return data FIFOs.

            The calculation is pipelined with pre-computation to reduce the loop size.
            pending_rd is accumulated in every cycle (there is no clken). The increment value is pre-computed
            as follows.

            R_o_avm_read    | pending_rd_increment_value
            ---------------------------------------------------
                          0 | -rd_bank
                          1 | burstcount - rd_bank

            So if rd_bank == 0, then we are simply incrementing pending_rd by a value of burstcount.
          */

          // Stage-1 Register the inputs to the computation
          R_o_avm_read[i]       <= read_root_fifo_rd_req_pipe[1][FIFO_READ_LATENCY][i] && !read_root_fifo_empty[i]; // Check if a valid read request was sent out to the global AVMM interface (by checking if a word was read from the read-root-FIFO)

          R_o_avm_burstcnt[i]   <= read_root_fifo_data_out[i][BURST_CNT_W-1:0];   // Capture the burstcount for that request
          R_o_avm_lsu_id[i]     <= read_root_fifo_data_out[i][READ_ROOT_FIFO_WIDTH-1 -: RD_ID_WIDTH]; // Capture the LSU ID for that request.

          for (int z=0;z<NUM_REORDER;z++) begin : GEN_RANDOM_BLOCK_NAME_R212
            R_rd_bank[z][i]     <= rd_bank[z][i];  // rd_bank asserts when a word is read out of the given return data FIFO. Capture this 2D vector here for use in later stages.
          end


          // Stage 2. Compute the difference
          valid_avm_read[i]               <= R_o_avm_read[i];   // Pass through stage 2
          R_o_avm_lsu_id_stage_2[i]       <= R_o_avm_lsu_id[i]; // Pass through stage 2
          for (int z=0;z<NUM_REORDER;z++) begin : GEN_RANDOM_BLOCK_NAME_R213
            // Stage 2.
            burstcount_minus_rd_bank[z][i] <= R_o_avm_burstcnt[i] - R_rd_bank[z][i];  // Compute the difference. This assumes the current outgoing read request corresponds to the z'th reorder unit (may not be true, will be handled below).
            minus_rd_bank[z][i]            <= -R_rd_bank[z][i]; // Compute the negative

            // Stage 3. Select the increment value from the two possibilities. Select burstcount_minus_rd_bank if the read request is leaving the root
            // and it corresponds to the z'th reorder unit.
            pending_rd_increment_value[z][i] <= (valid_avm_read[i] && reorder_id_per_load[R_o_avm_lsu_id_stage_2[i]]==z)? burstcount_minus_rd_bank[z][i] :  minus_rd_bank[z][i];

            // Stage 4. Perform the addition
            pending_rd[z][i] <= pending_rd[z][i] + pending_rd_increment_value[z][i];
          end

          /* Throttle if the # of outstanding read words exceeds the following threshold.
            The threshold must account for the latency through this computation pipeline and the latency
            to when read_request_throttle actually results in the stoppage of read requests. It takes 4 cycles to compute pending_rd (see the 4 stages above),
            2 more cycles until read_request_throttle asserts, and FIFO_READ_LATENCY cycles for read_request_throttle to halt the issuing
            of reads. Hence we set the threshold such that the return data FIFO can accommodate up to
            MAX_BURST*(4+2+FIFO_READ_LATENCY) words. This is the worst case # of words that could be returned
            if every request in this pipeline had a maximum burst count. The -5 is for margin.
            This may seem like a lot of potential wasted space in the return data FIFO. But the nominal FIFO depth is 512 which is the depth of a single M20K anyways so even if we
            reduced the almost_full threshold somehow, we would not save any M20Ks. Furthermore, as long as the return data FIFOs do not go empty there should be no throughput
            degradation. The FIFO occupancy must be able to cover the round trip latency to global memory. Here are some rough, but realistic, numbers to put this in perspective:
            MAX_BURST = 16
            NUM_DATA_AF_COMPARE_STAGES = 2
            FIFO_READ_LATENCY = 4
            So this results in an almost_full threshold of about: 512 - (16 * 10) = 352.
            As long as the round-trip global mem latency is less than 352 cycles, the FIFOs will not go empty. At 600 MHz, this is 587ns.
          */

          for (int z=0;z<NUM_REORDER;z++) begin : GEN_RANDOM_BLOCK_NAME_R214
            // read_request_throttle_per_reorder[NUM_DIMM][NUM_REORDER]
            // read_request_throttle represents a per-bank per-reorder-unit throttle signal.
            read_request_throttle_per_reorder[i][z]    <= pending_rd[z][i] >= (RETURN_DATA_FIFO_DEPTH - (MAX_BURST * (4+2+FIFO_READ_LATENCY)) - 5);
          end
          // For a given bank, OR the throttle signals from the multiple reorder units. This means each bank will get stalled if any of the per-bank
          // FIFOs across the multiple reorder units is getting full. As long as accesses are evenly distributed across LSUs then the FIFOs should
          // have roughly the same occupancy and should approach fullness around the same time. OR'ing the throttle signals into a single per-bank throttle allows
          // it to be pipelined into the read-root-fifo (RRF) read-request. If we instead had per-bank per-reorder throttle signals then the read-req to the RRF
          // would have to be combinational because we'd have to gate the read request if the LSU ID of the next request corresponds to a reorder unit that's
          // throttling.
          read_request_throttle[i] <= |read_request_throttle_per_reorder[i];

          `ifdef SIM_ONLY
            if(max_pending[i] < pending_rd[i]) max_pending[i] <= pending_rd[i];
          `endif
        end

        // synchronous reset (these assignments override the assignments above if reset is asserted)
        if(!sclrn[5]) begin
          for(i=0; i<NUM_DIMM; i=i+1) begin : GEN_RANDOM_BLOCK_NAME_R215
            for (int j=0;j<NUM_REORDER;j++) begin : GEN_RANDOM_BLOCK_NAME_R216
              pending_rd[j][i] <= '0;
              read_request_throttle_per_reorder[i][j] <= '0;
            end
            max_pending[i] <= '0;
            read_request_throttle[i] <= 1'b0;
            R_o_avm_read[i] <= 1'b0;
          end
        end
      end
    end
    else if(NUM_RD_PORT > 0) begin : GEN_DISABLE_DATA_REORDER
      for(z=0; z<NUM_RD_PORT; z=z+1) begin : GEN_RD_DOUT
        assign o_avm_readdata[z] = R_avm_readdata[z];
        assign o_avm_readdatavalid[z] = R_avm_readdatavalid[z];
      end
      always @(posedge clk) begin
        for(int i=0; i<NUM_RD_PORT; i=i+1)  begin : GEN_RANDOM_BLOCK_NAME_R217
          for(int j=0; j<NUM_DIMM; j=j+1)
            /* This appears to mux the data from the multiple banks down to each LSU.
              It appears to assume that only one bank will be routing to a given LSU at a time.
            */

            // If there's only one bank, then feed the data straight through with no clock enable (feed forward)
            if (NUM_DIMM == 1) begin
              R_avm_readdata[i] <= rd_data[0][0]; // Then to the i'th LSU data bus, forward data-0.
            // If multi-bank, then feed the j'th bank's data to the i'th LSU
            end else if (rd_data_valid[j][i]) begin
              R_avm_readdata[i] <= rd_data[j][0];
            end

            // For the i'th LSU, assert valid if we have a valid from any of the banks for that LSU
            // This appears to assume only one bank at a time will be returning data to a given LSU (ie.
            // no contention)
            R_avm_readdatavalid[i] <= |v_rd_data_en[i];
        end
      end

      logic [NUM_DIMM-1:0] ecc_err_status_for_0;
      logic [NUM_DIMM-1:0] ecc_err_status_for_1;
      assign ecc_err_status_lsu_rd_back[0] = |ecc_err_status_for_0;
      assign ecc_err_status_lsu_rd_back[1] = |ecc_err_status_for_1;
      for(z=0; z<NUM_DIMM; z=z+1) begin : GEN_DATA_VALID
        logic to_avm_valid;
        logic [MWIDTH-1:0] i_data [1];
        logic i_data_valid [1];
        assign read_request_throttle[z] = 1'b0;
        for(z0=0; z0<NUM_RD_PORT; z0=z0+1)  begin : GEN_
          assign v_rd_data_en[z0][z] = rd_data_valid[z][z0]; // This looks like a transpose so a reduction OR can be done easily above
        end
        assign i_data[0] = i_avm_readdata[z];
        assign i_data_valid[0] = i_avm_return_valid[z];

        // Determine the root port being targeted by the read request
        logic [NUM_MEM_SYSTEMS_W-1:0] current_mem_system;
        logic [LARGEST_NUM_BANKS_W-1:0] current_bank_within_mem_system;

        if (NUM_MEM_SYSTEMS == 1) begin
          assign current_mem_system = 0;
        end else begin
          assign current_mem_system = rd_address[AWIDTH-1 -: NUM_MEM_SYSTEMS_W];
        end
        if (LARGEST_NUM_BANKS > 1) begin
          // Not all bank bits may be used in the current mem system, so zero out the unused bits with bank_mask.
          assign current_bank_within_mem_system = bank_mask[current_mem_system] & (rd_address[BANK_BIT_LSB_PER_MEM_SYSTEM[current_mem_system]-MWORD_PAD+LARGEST_NUM_BANKS_W-1 -: LARGEST_NUM_BANKS_W]);
        end else begin
          assign current_bank_within_mem_system = 0;
        end

        if(NUM_DIMM > 1) assign to_avm_valid = rd_request & (ROOT_PORT_MAP[current_mem_system][current_bank_within_mem_system] == z);
        else assign to_avm_valid = rd_request;

        lsu_rd_back #(
          .NUM_DIMM (1), // NUM_DIMM == 1 : reordering is disabled
          .NUM_RD_PORT (NUM_RD_PORT),
          .BURST_CNT_W (BURST_CNT_W),
          .MWIDTH (MWIDTH),
          .MAX_MEM_DELAY(MAX_MEM_DELAY),
          .PIPELINE (PIPELINE_RD_RETURN),
          .HYPER_PIPELINE(HYPER_PIPELINE),
          .AVM_READ_DATA_LATENESS(AVM_READ_DATA_LATENESS),
          .WIDE_DATA_SLICING(WIDE_DATA_SLICING),
          .ID_AF_EXTERNAL_LATENCY(NUM_RING_WAITREQUEST_PIPE_STAGES),
          .ALLOW_HIGH_SPEED_FIFO_USAGE(ALLOW_HIGH_SPEED_FIFO_USAGE),
          .enable_ecc(enable_ecc)
        ) lsu_rd_back(
          .clk                (clk),
          .resetn             (resetn_synchronized),
          .i_to_avm_port_num  (1'b0),
          .i_to_avm_burstcount(rd_burstcount),
          .i_to_avm_id        (rd_o_id),
          .i_to_avm_valid     (to_avm_valid),
          .i_data             (i_data),
          .i_data_valid       (i_data_valid),
          .o_id_af            (id_af[z]),
          .o_data             (rd_data[z]),
          .o_data_valid       (rd_data_valid[z])  ,
          .ecc_err_status({ecc_err_status_for_1[z], ecc_err_status_for_0[z]})
        );
      end
    end
    else begin
      assign ecc_err_status_lsu_rd_back = 2'h0;
    end

    assign ecc_err_status = ecc_err_status_root | ecc_err_status_port | ecc_err_status_lsu_rd_back | ecc_err_status_write_ack_router;
end
endgenerate

function int mymax(int a, int b);
    automatic int max_val = (a > b) ? a : b;
    return max_val;
endfunction

endmodule
`default_nettype wire
