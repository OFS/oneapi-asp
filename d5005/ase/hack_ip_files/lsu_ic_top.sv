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


// This is the top level of token ring interconnect for global memory access.
// It has two modes: default (with data reordering block) and sw-dimm-partition (without data reordering; slow switch between banks).
`default_nettype none
module lsu_ic_top (
  clk,
  resetn,
  // from LSUs
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
  i_avm_write_ack, // Custom signal. This asserts once per writedata word, which is different from AVMM writeresponsevalid which asserts once per write burst.
  i_avm_readdata,
  i_avm_readdatavalid,
  // to MEM
  o_avm_byteenable,
  o_avm_address,
  o_avm_read,
  o_avm_write,
  o_avm_burstcount,
  o_avm_writedata,
  // to LSUs
  o_rd_waitrequest,
  o_wr_waitrequest,
  o_avm_readdata,
  o_avm_readdatavalid,
  o_avm_writeack,
  ecc_err_status
);


parameter  AWIDTH = 32;                        // memory address width. This is a byte address.
parameter  MWIDTH_BYTES = 64;                  // memory bus width
parameter  BURST_CNT_W = 5;                    // max burst number width
parameter  NUM_RD_PORT = 2;                    // number of read ports
parameter  NUM_WR_PORT = 2;                    // number of write ports
parameter  NUM_DIMM = 1;                       // number of root ports on the interconnect. This is the sum total of banks across all memory systems. For example, if we have 2 memory systems, comprised of 1 and 4 banks respectively, we'd use a value of 5 here.
parameter  RETURN_DATA_FIFO_DEPTH = 512;       // data reordering FIFO depth per bank. Must meet the minimum value required by lsu_token_ring.
parameter  HYPER_PIPELINE = 0;                 // 1 = optimized, highly pipelined mode, only sclrs (no aclrs) at the expense of area.
parameter  SYNCHRONIZE_RESET = 1;              // 1 = resetn is passed through a reset synchronizer before being consumed.
parameter  enable_ecc = "FALSE";               // Enable error correction coding
// parameter MAX_MEM_DELAY is used as Read ID/burstcount FIFO depth, to generate o_avm_readdatavalid
// Almost-full threshold is set to (MAX_MEM_DELAY - NUM_RD_PORT*2-5); stall is generated to read ring when the threshold is hit
// It selects (NUM_RD_PORT*2+6) as depth when this number is greater than 512, to gurantee a positive Almost-full threshold
parameter  MAX_MEM_DELAY = ((NUM_RD_PORT*2+6) > 512)? (NUM_RD_PORT*2+6) : 512;
parameter  DISABLE_ROOT_FIFO = 0;              // disable root fifo if token ring's root FIFO is merged in iface
// if set to 1, read-ring datapath is replaced with an N-to-1 mux. Arbitration is still a round-robin token, but the datapath uses fewer registers since there's no actual ring.
parameter  ENABLE_READ_FAST = HYPER_PIPELINE? (NUM_RD_PORT<4) : (NUM_RD_PORT<10);
parameter  ENABLE_DUAL_RING = 1;
parameter  ENABLE_MULTIPLE_WR_RING = 0;        // enable N write rings; N == number of banks
localparam NUM_ID = NUM_RD_PORT+NUM_WR_PORT;   // number of LSUs
parameter  ROOT_FIFO_DEPTH = 512;              // Must be at least 2*lsu_token_ring.WRITE_ROOT_FIFO_ALMOST_FULL_VALUE for maximum throughput.
parameter  NUM_REORDER = 1;                    // Number of reordering blocks for burst interleaved mode
parameter  ENABLE_LAST_WAIT = 0;               // A temperary fix for global const_cache, which needs avm_waitrequest == 0 to send load request in some cases
parameter  PIPELINE_RD_RETURN = 0;            // 1 = Route the read-return data to the LSUs in a pipelined vine (may help with performance). 0 = fan-out to all LSUs.
parameter  NUM_AVM_OUTPUT_PIPE_STAGES = 1;  // Minimum value 1. Length of pipeline stages between root FIFOs and CCB. This can be increased for performance (note that the agent-side
                                            // waitrequest allowance must be increased by the same amount as well). Only used when HYPER_PIPELINE=1
parameter  ENABLE_BSP_WAITREQUEST_ALLOWANCE = 0;  // Enables waitrequest-allowance on the AVMM interface. This param is passed down to lsu_token_ring so see comments in that module for more details.
parameter  ENABLE_BSP_AVMM_WRITE_ACK = 0;   // Enable use of i_avm_write_ack from the BSP rather than generate write-ack internally.
parameter  WRITE_ACK_FIFO_DEPTH = 1024;    // Used when ENABLE_BSP_AVMM_WRITE_ACK = 1. Sets the depth of the writeack response FIFO. This is approximately how many outstanding write words are allowed before we throttle write-requests. This amount needs to cover the round-trip latency to memory in order to maximize throughput.
parameter  AVM_WRITE_DATA_LATENESS = 0;        // fmax and area optimization - run the write data path this many clocks later than stall/valid
parameter  AVM_READ_DATA_LATENESS = 0;         // fmax and area optimization - o_avm_readdata is late by this many clocks compared to o_avm_readdatavalid
parameter  WIDE_DATA_SLICING = 0;              // for large MWIDTH_BYTES, a nonzero value indicate how wide to width-slice hld_fifo, also mux select signals are replicated based on width needed
parameter  ROOT_FIFO_STALL_IN_EARLINESS = 0;   // How much stall-in earliness should be expected for W/R root FIFOs when HYPER_PIPELINE=1
parameter  ROOT_WFIFO_VALID_IN_EARLINESS = 0;   // How much valid-in earliness should be expected for write root FIFO when HYPER_PIPELINE=1
parameter  ALLOW_HIGH_SPEED_FIFO_USAGE = 1;     // choice of hld_fifo style, 0 = mid speed fifo, 1 = high speed fifo
parameter  MAX_REQUESTS_PER_LSU = 4;            // See lsu_ic_token/lsu_n_fast for comments.

/*
  lsu_ic_top supports the concept of multiple memory systems (NUM_MEM_SYSTEMS).
  "Memory systems" are simply different and separate address spaces, each of which has its own characteristics (explained below).
  Each connected LSU can target any memory system at run time. The MSBs of the LSU's address indicate the memory system.
  Each memory system can have a different capacity. But the address width of the entire interconnect is determined by the memory system
  with the widest address bus. Therefore an access to a memory system with a smaller capacity does not use all of the address bits.
  Let's call the address bits that are actually used in a given access, the "relevant address bits".
  Each memory system can be comprised of multiple banks (NUM_BANKS_PER_MEM_SYSTEM, must be power of 2) and interleaving among these banks is possible.
  The bank selection is done using the MSBs of the relevant address bits. The position of these bits is specified by BANK_BIT_LSB_PER_MEM_SYSTEM.
  The interleaving chunk size is specified by PERMUTE_BIT_LSB_PER_MEM_SYSTEM.

  Example use case: these features were originally built to support Universal Shared Memory. There are 2 memory systems (host memory and device DDR). Device-DDR
  has 4 banks, across which interleaving is needed. But host-memory has only 1 bank.

  At this time, each element of NUM_BANKS_PER_MEM_SYSTEM be a power of 2. This is because interleaving is performed by simply re-arranging the address bits and
  there must be a power-of-2 number of banks for this to work.

  For example, the following are examples of valid configurations (i.e. valid values of NUM_BANKS_PER_MEM_SYSTEM, which is an array-based parameter).
  {1,4}
  {1,2}
  {4,4}
  {1,4,4}
  {1,2,2}
  {2,4,4}
*/

parameter int NUM_MEM_SYSTEMS = 1;
parameter [NUM_MEM_SYSTEMS-1:0][31:0] NUM_BANKS_PER_MEM_SYSTEM = {(NUM_MEM_SYSTEMS){32'd1}};  // index position [0] is in the right-most position.
parameter [NUM_MEM_SYSTEMS-1:0][31:0] NUM_BANKS_W_PER_MEM_SYSTEM = {(NUM_MEM_SYSTEMS){32'd1}};   // Bit-width of each NUM_BANKS
parameter [NUM_MEM_SYSTEMS-1:0][31:0] PERMUTE_BIT_LSB_PER_MEM_SYSTEM = {(NUM_MEM_SYSTEMS){32'd10}};  // Bit position that is moved during interleaving address permutation. This is ultimately specified in board_spec.xml ("num_interleaved_bytes"). See the comments further down in this file for the address_permuter module which show a diagram of how the bits are moved.
parameter [NUM_MEM_SYSTEMS-1:0][31:0] BANK_BIT_LSB_PER_MEM_SYSTEM = {(NUM_MEM_SYSTEMS){AWIDTH-32'd1}}; // Bit position of LSB of the bank bits for each memory system. If NUM_BANKS_PER_MEM_SYSTEM == 1 (at any position), BANK_BIT_LSB_PER_MEM_SYSTEM isn't used, but to avoid compilation errors, we can set it to AWIDTH-1.
parameter [NUM_MEM_SYSTEMS-1:0][31:0] ENABLE_BANK_INTERLEAVING = {(NUM_MEM_SYSTEMS){32'd1}};     // Interconnect will permute the AVMM addresses to stripe accesses across available banks. This can be controlled on each mem system.
parameter int ENABLE_SWDIMM = 0;    // SWDIMM is a poorly chosen, historical, label that refers to interleaving being disabled. This is a convenience/helper parameter. Technically if all the bits of ENABLE_BANK_INTERLEAVING are 0 then SWDIMM is enabled. But the following Verilog doesn't compile: "localparam ENABLE_SWDIMM = |ENABLE_BANK_INTERLEAVING."

parameter int LARGEST_NUM_BANKS = 1;  // Helper parameter
//parameter [NUM_MEM_SYSTEMS-1:0][LARGEST_NUM_BANKS-1:0][31:0] ROOT_PORT_MAP = {'0}; // Maps the combination of {mem system bits + bank bits} to interconnect root ports. Described in more detail in lsu_token_ring (where it's consumed)
parameter int ROOT_ARB_BALANCED_RW = 0; // Default behaviour is to prioritize writes over reads. This will balance reads and writes at the expense of a longer latency write-ack and a little bit of area.
localparam NUM_MEM_SYSTEMS_W = (NUM_MEM_SYSTEMS==1)? 1 : $clog2(NUM_MEM_SYSTEMS);
localparam RD_ROOT_FIFO_DEPTH = MAX_MEM_DELAY; // Read only root FIFO depth
localparam MWIDTH=8*MWIDTH_BYTES;
localparam ID_WIDTH = $clog2(NUM_ID);
localparam NUM_DIMM_W = $clog2(NUM_DIMM);
localparam P_NUM_DIMM_W = (NUM_DIMM_W > 0)? NUM_DIMM_W : 1;
localparam MAX_BURST = 2 ** (BURST_CNT_W-1);
localparam ROOT_FIFO_AW = (ROOT_FIFO_DEPTH >= (5+NUM_WR_PORT*2+MAX_BURST))? $clog2(ROOT_FIFO_DEPTH) : $clog2(5+NUM_WR_PORT*2+MAX_BURST);
localparam ROOT_RD_FIFO_AW = $clog2(RD_ROOT_FIFO_DEPTH);
localparam LOG2BYTES = $clog2(MWIDTH_BYTES);
localparam PAGE_ADDR_WIDTH = AWIDTH - LOG2BYTES; // Memory word address, where one word is MWIDTH_BYTES wide. In other words, this is the MWORD address width.

// avoid modelsim compile error
localparam P_NUM_RD_PORT   = (NUM_RD_PORT > 0)?   NUM_RD_PORT   : 1;
localparam P_NUM_WR_PORT   = (NUM_WR_PORT > 0)?   NUM_WR_PORT   : 1;

input wire  clk;
/* Synchronous if HYPER_PIPELINE==1, asynchronous otherwise.
   The ring nodes (lsu_ic_token and lsu_n_fast) assert waitrequest to their connected LSUs during reset.
   These blocks are held in reset longer than the rest of the interconnect to ensure that by the time they come out of reset
   and begin accepting requests from the LSUs, the rest of the interconnect is ready to accept the requests.
   resetn must be asserted for at least 30 cycles.
*/
input wire  resetn;
// from LSU
input wire  [MWIDTH_BYTES-1:0] i_rd_byteenable [P_NUM_RD_PORT];
input wire  [AWIDTH-1:0] i_rd_address [P_NUM_RD_PORT];
input wire  i_rd_request [P_NUM_RD_PORT];
input wire  [BURST_CNT_W-1:0] i_rd_burstcount [P_NUM_RD_PORT];
input wire  [MWIDTH_BYTES-1:0] i_wr_byteenable [P_NUM_WR_PORT];
input wire  [AWIDTH-1:0] i_wr_address [P_NUM_WR_PORT];
input wire  i_wr_request [P_NUM_WR_PORT];
input wire  [BURST_CNT_W-1:0] i_wr_burstcount [P_NUM_WR_PORT];
input wire  [MWIDTH-1:0] i_wr_writedata [P_NUM_WR_PORT];
// from MEM
input wire  i_avm_waitrequest [NUM_DIMM];
input wire  i_avm_write_ack [NUM_DIMM];
input wire  [MWIDTH-1:0] i_avm_readdata [NUM_DIMM];
input wire  i_avm_readdatavalid [NUM_DIMM];
// to MEM
output logic  [MWIDTH_BYTES-1:0] o_avm_byteenable [NUM_DIMM];
/* This is a byte address, including mem system bits (to identify the target system) and bank bits (to identify the target bank within this system).
   These bits combine to identify the root port to which a given request should be routed. Since o-avm_address is an array with one address per
   root port, it may seem unnecessary to carry these extra bits with the address (since the index into o_avm_address indicates the target root port).
    The challenge is that mem systems may have different effective address widths. But o_avm_address (and all of lsu_ic_top's internal address bus signals) are coded
    as an array, and therefore must share a single width. So to simplfiy things, lsu_ic_top just carries the full address width of the widest mem system, all the way through.
    It's up to the instantiator of lsu_ic_top to truncate the appropriate bits on a per-bank basis.

  However, in a single mem system application, we truncate the bank bits to stay consistent with how the interconnect has historically been.
*/
localparam O_AVM_ADDRESS_W = (NUM_MEM_SYSTEMS >  1)? AWIDTH : AWIDTH-NUM_DIMM_W;
output logic  [O_AVM_ADDRESS_W-1:0] o_avm_address [NUM_DIMM];
output logic  o_avm_read [NUM_DIMM];
output logic  o_avm_write [NUM_DIMM];
output logic  [BURST_CNT_W-1:0] o_avm_burstcount [NUM_DIMM];
output logic  [MWIDTH-1:0] o_avm_writedata [NUM_DIMM];
// to LSU
output logic  o_rd_waitrequest [P_NUM_RD_PORT];
output logic  o_wr_waitrequest [P_NUM_WR_PORT];
output logic  [MWIDTH-1:0] o_avm_readdata [P_NUM_RD_PORT];
output logic  o_avm_readdatavalid [P_NUM_RD_PORT];
output logic  o_avm_writeack [P_NUM_WR_PORT];
output logic  [1:0] ecc_err_status;  // ecc status signals

genvar z, g;

//////////////////////////////////////
//                                  //
//  Sanity check on the parameters  //
//                                  //
//////////////////////////////////////

initial /* synthesis enable_verilog_initial_construct */
begin

  // If interleaving is enabled on a mem system, the number of banks in that mem system must be a power of 2
  for (int z=0; z<NUM_MEM_SYSTEMS;z=z+1) begin
    if (ENABLE_BANK_INTERLEAVING[z]) begin
      if (2**($clog2(NUM_BANKS_PER_MEM_SYSTEM[z])) != NUM_BANKS_PER_MEM_SYSTEM[z]) begin
        $fatal(1, "lsu_ic_top ring interconnect: Memory System %0d has bank interleaving enabled, so it must have a power-of-2 number of banks. It has %0d banks.\n", z,  NUM_BANKS_PER_MEM_SYSTEM[z]);
      end
    end
  end

  // If interleaving is disabled on one multi-bank mem system, it must be disabled on all multi-bank mem systems.
  for (int z=0; z<NUM_MEM_SYSTEMS;z=z+1) begin
    if ((NUM_BANKS_PER_MEM_SYSTEM[z] > 1) && !ENABLE_BANK_INTERLEAVING[z]) begin // look for multi-bank mem systems with interleaving disabled
      for (int g=0; g<NUM_MEM_SYSTEMS;g=g+1) begin
        if ((NUM_BANKS_PER_MEM_SYSTEM[g] > 1) && ENABLE_BANK_INTERLEAVING[g]) begin // Check if any multi-bank mem system has interleaving ENabled (and then error out)
          $fatal(1, "lsu_ic_top ring interconnect: Memory System %0d has bank interleaving disabled. If one multi-bank mem system has interleaving disabled, all other multi-bank mem systems must also have it disabled. Found multi-bank mem system %0d with interleaving enabled.\n", z, g);
        end
      end
    end
  end

  // Similar check. if ENABLE_SWDIMM==1 then bank interleaving must be disabled on all mem systems
  for (int z=0; z<NUM_MEM_SYSTEMS;z=z+1) begin
    if (ENABLE_SWDIMM && ENABLE_BANK_INTERLEAVING[z]) begin
      $fatal(1, "lsu_ic_top ring interconnect: SWDIMM (non-interleaving) is enabled but memory system %0d is parameterized to have interleaving enabled. \n", z);
    end
  end

end

integer i, j;
wire [PAGE_ADDR_WIDTH-1:0] ci_avm_rd_addr [P_NUM_RD_PORT];
wire [PAGE_ADDR_WIDTH-1:0] ci_avm_wr_addr [P_NUM_WR_PORT];

localparam LSU_TOKEN_RING_O_ADDRESS_W = (NUM_MEM_SYSTEMS > 1)? PAGE_ADDR_WIDTH : PAGE_ADDR_WIDTH-NUM_DIMM_W;
wire [LSU_TOKEN_RING_O_ADDRESS_W-1:0] co_avm_address [NUM_DIMM]; // MWORD address, with mem system and bank bits.

// Permuted address, used when interleaving is enabled
logic [AWIDTH-1:0] read_address_permuted_per_mem_system_per_lsu [NUM_MEM_SYSTEMS][P_NUM_RD_PORT];
logic [AWIDTH-1:0] write_address_permuted_per_mem_system_per_lsu [NUM_MEM_SYSTEMS][P_NUM_WR_PORT];

// Mem system that each LSU is currently targeting (we simply look at the mem system bits)
logic [NUM_MEM_SYSTEMS_W-1:0] rd_lsu_current_mem_system_id [P_NUM_RD_PORT];
logic [NUM_MEM_SYSTEMS_W-1:0] wr_lsu_current_mem_system_id [P_NUM_WR_PORT];

/*
  lsu_ic_top contains a hierarchy of several sub-modules. All sub-modules consume the HYPER_PIPELINE parameter.
  When HYPER_PIPELINE=0, resets are consumed asynchronously. When HYPER_PIPELINE=1, resets are consumed synchronously.

  In addition to using the HYPER_PIPELINE parameter to select between aclrs and sclrs, *some* sub-modules use it to generate an
  entirely separate set of hyper-optimized code.

  To be clear, it is not possible to have HYPER_PIPELINE=1 and to have resets consumed asynchronously.

  Reset synchronization is taken care of in this module (the top level) and sub-modules
  do not synchronize again.
*/
localparam                    ASYNC_RESET = HYPER_PIPELINE? 0 : 1; // Use synchronous resets in hyper-pipeline mode.
localparam                    NUM_RESET_COPIES = 1;
localparam                    RESET_PIPE_DEPTH = 5;
logic                         aclrn;
logic [NUM_RESET_COPIES-1:0]  sclrn;
logic                         resetn_synchronized;

acl_reset_handler
#(
    .ASYNC_RESET            (ASYNC_RESET),
    .USE_SYNCHRONIZER       (SYNCHRONIZE_RESET),
    .SYNCHRONIZE_ACLRN      (SYNCHRONIZE_RESET),
    .PIPE_DEPTH             (RESET_PIPE_DEPTH),
    .NUM_COPIES             (NUM_RESET_COPIES)
)
acl_reset_handler_inst
(
    .clk                    (clk),
    .i_resetn               (resetn),
    .o_aclrn                (aclrn),
    .o_resetn_synchronized  (resetn_synchronized),
    .o_sclrn                (sclrn)
);


`ifdef DEBUG_AVMM

  // AVMM debug logic. Detect various error conditions that can be simulated or SignalTapped.
  // These could be turned into assertions.
(* noprune *)  logic [BURST_CNT_W-1:0] write_burst_counter [NUM_DIMM];
(* noprune *)  logic [AWIDTH-NUM_DIMM_W-1:0] output_address_reg [NUM_DIMM];
(* noprune *)  logic [BURST_CNT_W-1:0] expected_burst_count [NUM_DIMM];
(* noprune *)  logic [NUM_DIMM-1:0]write_burst_incomplete;
(* noprune *)  logic [NUM_DIMM-1:0]write_burst_incomplete_latched;
(* noprune *)  logic write_burst_incomplete_any_bank;
(* noprune *)  logic write_burst_incomplete_any_bank_latched;

(* noprune *)  logic [NUM_DIMM-1:0] avm_write_deasserted_mid_burst;
(* noprune *)  logic [NUM_DIMM-1:0] avm_write_deasserted_mid_burst_latched;
(* noprune *)  logic avm_write_deasserted_mid_burst_any_bank;
(* noprune *)  logic avm_write_deasserted_mid_burst_any_bank_latched;

(* noprune *)  logic [NUM_DIMM-1:0] avm_write_pause;
(* noprune *)  logic [NUM_DIMM-1:0] avm_read_asserted_during_write_pause;
(* noprune *)  logic [NUM_DIMM-1:0] avm_read_asserted_during_write_pause_latched;
(* noprune *)  logic                avm_read_asserted_during_write_pause_any_bank;
(* noprune *)  logic                avm_read_asserted_during_write_pause_any_bank_latched;

(* noprune *)  logic [NUM_DIMM-1:0] avm_read_write_same_time_latched;

  always @(posedge clk) begin
    if (!resetn_synchronized) begin
      for(i=0; i<NUM_DIMM; i=i+1) begin : GEN_RANDOM_BLOCK_NAME_R133
        write_burst_counter[i] <= 1;
        output_address_reg[i] <= 0;
        expected_burst_count[i] <= 0;
        write_burst_incomplete[i] <= 1'b0;
        write_burst_incomplete_latched[i] <= 1'b0;
        avm_write_deasserted_mid_burst[i] <= 1'b0;
        avm_write_deasserted_mid_burst_latched[i] <= 1'b0;
        avm_write_pause[i] <= 1'b0;
        avm_read_asserted_during_write_pause[i] <= 1'b0;
        avm_read_asserted_during_write_pause_latched[i] <= 1'b0;
        avm_read_write_same_time_latched[i] <= 1'b0;
      end
      write_burst_incomplete_any_bank <= 1'b0;
      write_burst_incomplete_any_bank_latched <= 1'b0;
      avm_write_deasserted_mid_burst_any_bank <= 1'b0;
      avm_write_deasserted_mid_burst_any_bank_latched <= 1'b0;
      avm_read_asserted_during_write_pause_any_bank <= 1'b0;
      avm_read_asserted_during_write_pause_any_bank_latched <= 1'b0;
    end else begin
      for(i=0; i<NUM_DIMM; i=i+1) begin : GEN_RANDOM_BLOCK_NAME_R134
        if(o_avm_write[i] && !i_avm_waitrequest[i]) begin
          write_burst_counter[i] <= (write_burst_counter[i] == o_avm_burstcount[i])? 1 : write_burst_counter[i] + 1;
          output_address_reg[i] <= o_avm_address[i];
          expected_burst_count[i] <= o_avm_burstcount[i];
          if(output_address_reg[i] != o_avm_address[i] & write_burst_counter[i] != 1) begin // write addr change, write count should be reset to 1
            write_burst_incomplete[i] <= 1'b1;
            write_burst_incomplete_latched[i] <= 1'b1;
          end
        end else begin
          write_burst_incomplete[i] <= 1'b0;
        end

        if (output_address_reg[i] == o_avm_address[i] && expected_burst_count[i] != 1 && write_burst_counter[i] != 1 && !o_avm_write[i] && !i_avm_waitrequest[i]) begin
          avm_write_deasserted_mid_burst[i] <= 1'b1;
          avm_write_deasserted_mid_burst_latched[i] <= 1'b1;
        end else begin
          avm_write_deasserted_mid_burst[i] <= 1'b0;
        end

        if (!avm_write_pause[i] && output_address_reg[i] == o_avm_address[i] && expected_burst_count[i] != 1 && write_burst_counter[i] != 1 && !o_avm_write[i] && !i_avm_waitrequest[i]) begin
          avm_write_pause[i] <= 1'b1;
        end else if (write_burst_counter[i] == expected_burst_count[i] && o_avm_write[i] && !i_avm_waitrequest[i]) begin
          avm_write_pause[i] <= 1'b0;
        end

        avm_read_asserted_during_write_pause[i] <= o_avm_read[i] && avm_write_pause[i];
        avm_read_asserted_during_write_pause_latched[i] <= avm_read_asserted_during_write_pause_latched[i] || avm_read_asserted_during_write_pause[i];

        avm_read_write_same_time_latched[i] <= avm_read_write_same_time_latched[i] || (o_avm_read[i] && o_avm_write[i]);

      end

      write_burst_incomplete_any_bank <= |write_burst_incomplete;
      if (!write_burst_incomplete_any_bank_latched) begin
        write_burst_incomplete_any_bank_latched <= |write_burst_incomplete;
      end

      avm_read_asserted_during_write_pause_any_bank <= |avm_read_asserted_during_write_pause;
      avm_read_asserted_during_write_pause_any_bank_latched <= avm_read_asserted_during_write_pause_any_bank_latched || (|avm_read_asserted_during_write_pause);

      avm_write_deasserted_mid_burst_any_bank <= |avm_write_deasserted_mid_burst;
      if (!avm_write_deasserted_mid_burst_any_bank_latched) begin
        avm_write_deasserted_mid_burst_any_bank_latched <= |avm_write_deasserted_mid_burst;
      end

    end
  end
`endif

`ifdef GEN_ACCESS_CNT
  // This part is used to trace the number of requests received from LSUs and sent to global memory
  // for simulation or signalTap mem access analysis
  // add /* synthesis syn_noprune syn_preserve = 1 */ for signalTap
  logic [31:0] i_receive_cnt [NUM_ID]; // num of requests received from LSUs
  logic [31:0] o_return_to_lsu_cnt [NUM_ID]; // returned to LSUs
  logic [8:0]  err_cnt_lsu [NUM_ID];
  logic [0:NUM_ID-1] err_lsu;
  logic [31:0] o_rd_to_mem_cnt, i_return_cnt;
  logic [8:0] err_cnt_global;
  logic [31:0] sum_receive [NUM_RD_PORT];
  logic [31:0] sum_return [NUM_RD_PORT];


  debug_io_cnt #(.WIDTH(6)) globl_mem_io_checker (
    .resetn(resetn_synchronized),
    .clk(clk),
    .i_0(((o_avm_read[0] & !i_avm_waitrequest[0])? o_avm_burstcount[0] : 0) + ((o_avm_read[1] & !i_avm_waitrequest[1])? o_avm_burstcount[1] : 0)),
    .i_1(i_avm_readdatavalid[0] + i_avm_readdatavalid[1] + 6'd0),
    .o_cnt_0(o_rd_to_mem_cnt),
    .o_cnt_1(i_return_cnt),
    .o_mismatch_cnt(err_cnt_global)
  );
  generate

    always @(posedge clk) begin
      for(i=0; i<NUM_ID; i=i+1) err_lsu[i] <= |err_cnt_lsu[i];
    end

    for(z=0; z<NUM_RD_PORT; z=z+1) begin : GEN_RD_LSU_IO_CNT
      assign sum_receive[z] = (z==0)? i_receive_cnt[0] : i_receive_cnt[z] + sum_receive[z-1];
      assign sum_return[z]  = (z==0)? o_return_to_lsu_cnt[0] : o_return_to_lsu_cnt[z] + sum_return[z-1];

      debug_io_cnt #(.WIDTH(6)) lsu_io_checker (
        .resetn(resetn_synchronized),
        .clk(clk),
        .i_0(((i_rd_request[z] & !o_rd_waitrequest[z])? i_rd_burstcount[z] : 0)),
        .i_1(o_avm_readdatavalid[z] + 0),
        .o_cnt_0(i_receive_cnt[z]),
        .o_cnt_1(o_return_to_lsu_cnt[z]),
        .o_mismatch_cnt(err_cnt_lsu[z])
      );
    end
    for(z=0; z<NUM_WR_PORT; z=z+1) begin : GEN_WR_LSU_IO_CNT
      debug_io_cnt #(.WIDTH(6)) lsu_io_checker (
        .resetn(resetn_synchronized),
        .clk(clk),
        .i_0((i_wr_request[z] & !o_wr_waitrequest[z]) + 6'd0),
        .i_1(o_avm_writeack[z] + 6'd0),
        .o_cnt_0(i_receive_cnt[z+NUM_RD_PORT]),
        .o_cnt_1(o_return_to_lsu_cnt[z+NUM_RD_PORT]),
        .o_mismatch_cnt(err_cnt_lsu[z+NUM_RD_PORT])
      );
    end
  endgenerate
`endif

generate

  /* Generate permuted addresses for each LSU to each mem system. Do this even if interleaving is disabled (for simplicity, the permuted addresses should get optimized away).
     Addresses from the LSUs are AWIDTH wide. The AVMM output address from lsu_ic_top is also AWIDTH wide. These are byte addresses.
     But the address width to the internal interconnect (lsu_token_ring) is PAGE_ADDR_WIDTH wide (narrower, memory word address, where a mem word is MWIDTH_BYTES wide).
     The permute bit is specified on the AWIDTH address.
     Feed the full AWIDTH address to the permuter. Then before feeding the permuted address to lsu_token_ring, chop off the LSBs (which will be all zeroes anyways).

     Note on how this is coded. The required address permutation at application runtime is not static. It depends on the memory system being targeted because each mem system
     may have different permute bit positions (the positions we need to move bits from) and bank bit positions (the positions we need to move them to).
     It turned out to be really tricky to write valid/compilable Verilog, that was also readable/maintainable, that could perform dynamic part selects into vectors
     where the part select position and width was determined using lookups into array-based module parameters (such PERMUTE_BIT_LSB_PER_MEM_SYSTEM and BANK_BIT_LSB_PER_MEM_SYSTEM).
     In general, it seems you can't do a lookup into a parameter using a lookup index that's determined at runtime. The lookup needs to be static at compile time.

     So instead, for each LSU, we generate a permuted address for each memory system, and at runtime, select the one we need based on the mem system bits.
  */
  for (z=0; z<NUM_MEM_SYSTEMS;z=z+1) begin :  GEN_ADDRESS_PERMUTERS
    // Load LSUs
    for (g=0;g<P_NUM_RD_PORT;g=g+1) begin : GEN_ADDRESS_PERMUTERS_READ
      address_permuter #(
        .NUM_MEM_SYSTEMS  (NUM_MEM_SYSTEMS),
        .AWIDTH           (AWIDTH),
        .BANK_BIT_LSB     (BANK_BIT_LSB_PER_MEM_SYSTEM[z]),
        .NUM_BANKS_W      (NUM_BANKS_W_PER_MEM_SYSTEM[z]),
        .PERMUTE_BIT_LSB  (PERMUTE_BIT_LSB_PER_MEM_SYSTEM[z])
      ) address_permuter_read_inst
      (
        .in_address     (i_rd_address[g]),
        .out_address    (read_address_permuted_per_mem_system_per_lsu[z][g])
      );
    end
    // Store LSUs
    for (g=0;g<P_NUM_WR_PORT;g=g+1) begin : GEN_ADDRESS_PERMUTERS_WRITE
      address_permuter #(
        .NUM_MEM_SYSTEMS  (NUM_MEM_SYSTEMS),
        .AWIDTH           (AWIDTH),
        .BANK_BIT_LSB     (BANK_BIT_LSB_PER_MEM_SYSTEM[z]),
        .NUM_BANKS_W      (NUM_BANKS_W_PER_MEM_SYSTEM[z]),
        .PERMUTE_BIT_LSB  (PERMUTE_BIT_LSB_PER_MEM_SYSTEM[z])
      ) address_permuter_write_inst
      (
        .in_address     (i_wr_address[g]),
        .out_address    (write_address_permuted_per_mem_system_per_lsu[z][g])
      );
    end
  end

  // Dynmically select the permutated address we need, based on the mem system being targeted

  for(g=0; g<P_NUM_RD_PORT; g=g+1) begin : GEN_SELECT_LSU_RD_ADDRESS
    // Look at the mem system bits
    assign rd_lsu_current_mem_system_id[g] = (NUM_MEM_SYSTEMS == 1)? 0 : i_rd_address[g][AWIDTH-1 -: NUM_MEM_SYSTEMS_W];
    // Select the corresponding permuted address. But if interleaving is disabled, select the original address. We also drop the LSBs since lsu_token_ring expects an MWORD address.
    assign ci_avm_rd_addr[g] = (ENABLE_BANK_INTERLEAVING[rd_lsu_current_mem_system_id[g]] && (NUM_BANKS_PER_MEM_SYSTEM[rd_lsu_current_mem_system_id[g]] > 1)) ? read_address_permuted_per_mem_system_per_lsu[rd_lsu_current_mem_system_id[g]][g][AWIDTH-1:LOG2BYTES] : i_rd_address[g][AWIDTH-1:LOG2BYTES];
  end

  // Same code as above, but for the store LSUs
  for(g=0; g<P_NUM_WR_PORT; g=g+1) begin : GEN_SELECT_LSU_WR_ADDRESS
    assign wr_lsu_current_mem_system_id[g] = (NUM_MEM_SYSTEMS == 1)? 0 : i_wr_address[g][AWIDTH-1 -: NUM_MEM_SYSTEMS_W]; // Grab the mem system ID from this LSU's current address
    assign ci_avm_wr_addr[g] = (ENABLE_BANK_INTERLEAVING[wr_lsu_current_mem_system_id[g]] && (NUM_BANKS_PER_MEM_SYSTEM[wr_lsu_current_mem_system_id[g]] > 1))? write_address_permuted_per_mem_system_per_lsu[wr_lsu_current_mem_system_id[g]][g][AWIDTH-1:LOG2BYTES] : i_wr_address[g][AWIDTH-1:LOG2BYTES];
  end

  // Take the output address from each root port of lsu_token_ring and put back the LSBs since lsu_ic_top is supposed to output a byte address.
  for(z=0; z<NUM_DIMM; z=z+1) begin : GEN_PAD_O_ADDR
    assign o_avm_address[z] = {co_avm_address[z], {LOG2BYTES{1'b0}}};
  end

  if(ENABLE_SWDIMM) begin : GEN_SW_DIMM
    /*  SWDIMM is synonymous with interleaving being disabled. The host application is supposed to control which bank
        each LSU shall access.
        lsu_swdimm_token_ring is a wrapper around lsu_token_ring that adds logic to block LSUs from switching banks
          if there are still responses that need to be received.
    */
    lsu_swdimm_token_ring #(
      .AWIDTH(PAGE_ADDR_WIDTH),
      .MWIDTH_BYTES(MWIDTH_BYTES),
      .BURST_CNT_W (BURST_CNT_W),
      .NUM_RD_PORT(NUM_RD_PORT),
      .NUM_WR_PORT(NUM_WR_PORT),
      .MAX_MEM_DELAY(MAX_MEM_DELAY),
      .DISABLE_ROOT_FIFO(DISABLE_ROOT_FIFO),
      .ENABLE_READ_FAST(ENABLE_READ_FAST),
      .NUM_DIMM(NUM_DIMM),
      .ROOT_FIFO_AW(ROOT_FIFO_AW),
      .RD_ROOT_FIFO_AW(ROOT_RD_FIFO_AW),
      .ENABLE_DATA_REORDER(0),  // Disable reordering in SWDIMM (no-interleaving mode)
      .ENABLE_LAST_WAIT(ENABLE_LAST_WAIT),
      .ENABLE_MULTIPLE_WR_RING(ENABLE_MULTIPLE_WR_RING),
      .ENABLE_DUAL_RING(1),
      .PIPELINE_RD_RETURN(PIPELINE_RD_RETURN),
      .HYPER_PIPELINE (HYPER_PIPELINE),
      .ENABLE_BSP_WAITREQUEST_ALLOWANCE(ENABLE_BSP_WAITREQUEST_ALLOWANCE),
      .ENABLE_BSP_AVMM_WRITE_ACK(ENABLE_BSP_AVMM_WRITE_ACK),
      .WRITE_ACK_FIFO_DEPTH(WRITE_ACK_FIFO_DEPTH),
      .AVM_WRITE_DATA_LATENESS(AVM_WRITE_DATA_LATENESS),
      .AVM_READ_DATA_LATENESS(AVM_READ_DATA_LATENESS),
      .WIDE_DATA_SLICING(WIDE_DATA_SLICING),
      .ROOT_FIFO_STALL_IN_EARLINESS(ROOT_FIFO_STALL_IN_EARLINESS),
      .ROOT_WFIFO_VALID_IN_EARLINESS(ROOT_WFIFO_VALID_IN_EARLINESS),
      .ALLOW_HIGH_SPEED_FIFO_USAGE(ALLOW_HIGH_SPEED_FIFO_USAGE),
      .NUM_AVM_OUTPUT_PIPE_STAGES(NUM_AVM_OUTPUT_PIPE_STAGES),
      .MAX_REQUESTS_PER_LSU(MAX_REQUESTS_PER_LSU),
      .enable_ecc(enable_ecc),
      .NUM_MEM_SYSTEMS             (NUM_MEM_SYSTEMS),
      .NUM_BANKS_PER_MEM_SYSTEM    (NUM_BANKS_PER_MEM_SYSTEM),
      .NUM_BANKS_W_PER_MEM_SYSTEM  (NUM_BANKS_W_PER_MEM_SYSTEM),
      .BANK_BIT_LSB_PER_MEM_SYSTEM (BANK_BIT_LSB_PER_MEM_SYSTEM),
      .ENABLE_BANK_INTERLEAVING    (ENABLE_BANK_INTERLEAVING),
      .LARGEST_NUM_BANKS           (LARGEST_NUM_BANKS),
      //.ROOT_PORT_MAP               (ROOT_PORT_MAP),
      .ROOT_ARB_BALANCED_RW        (ROOT_ARB_BALANCED_RW)
    )lsu_ic (
      .clk                (clk                ),
      .resetn             (resetn_synchronized ),
      .i_rd_byteenable    (i_rd_byteenable    ),
      .i_rd_address       (ci_avm_rd_addr     ),
      .i_rd_request       (i_rd_request       ),
      .i_rd_burstcount    (i_rd_burstcount    ),
      .i_wr_byteenable    (i_wr_byteenable    ),
      .i_wr_address       (ci_avm_wr_addr     ),
      .i_wr_request       (i_wr_request       ),
      .i_wr_burstcount    (i_wr_burstcount    ),
      .i_wr_writedata     (i_wr_writedata     ),
      .i_avm_waitrequest  (i_avm_waitrequest  ),
      .i_avm_write_ack    (i_avm_write_ack    ),
      .i_avm_readdata     (i_avm_readdata     ),
      .i_avm_return_valid (i_avm_readdatavalid),
      .o_id               (),
      .o_avm_byteenable   (o_avm_byteenable   ),
      .o_avm_address      (co_avm_address     ),
      .o_avm_read         (o_avm_read         ),
      .o_avm_write        (o_avm_write        ),
      .o_avm_burstcount   (o_avm_burstcount   ),
      .o_avm_writedata    (o_avm_writedata    ),
      .o_rd_waitrequest   (o_rd_waitrequest   ),
      .o_wr_waitrequest   (o_wr_waitrequest   ),
      .o_avm_readdata     (o_avm_readdata     ),
      .o_avm_readdatavalid(o_avm_readdatavalid),
      .o_avm_writeack     (o_avm_writeack     ),
      .ecc_err_status     (ecc_err_status     )
    );
  end
  else begin : GEN_SIMPLE
    lsu_token_ring #(
      .AWIDTH(PAGE_ADDR_WIDTH),
      .MWIDTH_BYTES(MWIDTH_BYTES),
      .BURST_CNT_W (BURST_CNT_W),
      .NUM_RD_PORT(NUM_RD_PORT),
      .NUM_WR_PORT(NUM_WR_PORT),
      .NUM_DIMM(NUM_DIMM),
      .RETURN_DATA_FIFO_DEPTH(RETURN_DATA_FIFO_DEPTH),
      .PIPELINE_RD_RETURN(PIPELINE_RD_RETURN),
      .MAX_MEM_DELAY(MAX_MEM_DELAY),
      .ENABLE_MULTIPLE_WR_RING(ENABLE_MULTIPLE_WR_RING),
      .ENABLE_READ_FAST(ENABLE_READ_FAST),
      .DISABLE_ROOT_FIFO(DISABLE_ROOT_FIFO),
      .ROOT_FIFO_AW(ROOT_FIFO_AW),
      .RD_ROOT_FIFO_AW(ROOT_RD_FIFO_AW),
      .ENABLE_DATA_REORDER(NUM_DIMM==1? 0 : 1), // If NUM_DIMM > 1, this means we either have 1 mem system with multiple banks, or 2+ mem systems. In both cases, we need reordering.
      .NUM_REORDER(NUM_REORDER > NUM_RD_PORT? NUM_RD_PORT : NUM_REORDER), // The maximum # of reorder units that makes sense is = # loads.
      .ENABLE_LAST_WAIT(ENABLE_LAST_WAIT),
      .ENABLE_DUAL_RING(1),
      .HYPER_PIPELINE (HYPER_PIPELINE),
      .ENABLE_BSP_WAITREQUEST_ALLOWANCE(ENABLE_BSP_WAITREQUEST_ALLOWANCE),
      .ENABLE_BSP_AVMM_WRITE_ACK(ENABLE_BSP_AVMM_WRITE_ACK),
      .WRITE_ACK_FIFO_DEPTH(WRITE_ACK_FIFO_DEPTH),
      .AVM_WRITE_DATA_LATENESS(AVM_WRITE_DATA_LATENESS),
      .AVM_READ_DATA_LATENESS(AVM_READ_DATA_LATENESS),
      .WIDE_DATA_SLICING(WIDE_DATA_SLICING),
      .ROOT_FIFO_STALL_IN_EARLINESS(ROOT_FIFO_STALL_IN_EARLINESS),
      .ROOT_WFIFO_VALID_IN_EARLINESS(ROOT_WFIFO_VALID_IN_EARLINESS),
      .ALLOW_HIGH_SPEED_FIFO_USAGE(ALLOW_HIGH_SPEED_FIFO_USAGE),
      .NUM_AVM_OUTPUT_PIPE_STAGES(NUM_AVM_OUTPUT_PIPE_STAGES),
      .MAX_REQUESTS_PER_LSU(MAX_REQUESTS_PER_LSU),
      .enable_ecc(enable_ecc),
      .NUM_MEM_SYSTEMS             (NUM_MEM_SYSTEMS),
      .NUM_BANKS_PER_MEM_SYSTEM    (NUM_BANKS_PER_MEM_SYSTEM),
      .NUM_BANKS_W_PER_MEM_SYSTEM  (NUM_BANKS_W_PER_MEM_SYSTEM),
      .BANK_BIT_LSB_PER_MEM_SYSTEM (BANK_BIT_LSB_PER_MEM_SYSTEM),
      .ENABLE_BANK_INTERLEAVING    (ENABLE_BANK_INTERLEAVING),
      .LARGEST_NUM_BANKS           (LARGEST_NUM_BANKS),
      //.ROOT_PORT_MAP               (ROOT_PORT_MAP),
      .ROOT_ARB_BALANCED_RW        (ROOT_ARB_BALANCED_RW)
    )lsu_ic (
      .clk                (clk                ),
      .resetn             (resetn_synchronized ),
      .i_rd_byteenable    (i_rd_byteenable    ),
      .i_rd_address       (ci_avm_rd_addr     ),
      .i_rd_request       (i_rd_request       ),
      .i_rd_burstcount    (i_rd_burstcount    ),
      .i_wr_byteenable    (i_wr_byteenable    ),
      .i_wr_address       (ci_avm_wr_addr     ),
      .i_wr_request       (i_wr_request       ),
      .i_wr_burstcount    (i_wr_burstcount    ),
      .i_wr_writedata     (i_wr_writedata     ),
      .i_avm_waitrequest  (i_avm_waitrequest  ),
      .i_avm_write_ack    (i_avm_write_ack    ),
      .i_avm_readdata     (i_avm_readdata     ),
      .i_avm_return_valid (i_avm_readdatavalid),
      .o_avm_byteenable   (o_avm_byteenable   ),
      .o_avm_address      (co_avm_address     ),
      .o_avm_read         (o_avm_read         ),
      .o_avm_write        (o_avm_write        ),
      .o_avm_burstcount   (o_avm_burstcount   ),
      .o_avm_writedata    (o_avm_writedata    ),
      .o_rd_waitrequest   (o_rd_waitrequest   ),
      .o_wr_waitrequest   (o_wr_waitrequest   ),
      .o_avm_readdata     (o_avm_readdata     ),
      .o_avm_readdatavalid(o_avm_readdatavalid),
      .o_avm_writeack     (o_avm_writeack     ),
      .ecc_err_status     (ecc_err_status     )
    );
  end
endgenerate
endmodule

module debug_io_cnt #(
  parameter WIDTH = 1
)(
  input wire resetn,
  input wire clk,
  input wire [WIDTH-1:0] i_0,
  input wire [WIDTH-1:0] i_1,
  output logic [31:0] o_cnt_0,
  output logic [31:0] o_cnt_1,
  output logic        o_mismatch,
  output logic [15:0] o_mismatch_cnt
);

// Debug module, uses aclrs, reset synchronization handled by parent.
always @(posedge clk or negedge resetn) begin
  if(!resetn) begin
    o_cnt_0        <= '0;
    o_cnt_1        <= '0;
    o_mismatch_cnt <= '0;
    o_mismatch <= '0;
  end
  else begin
    o_cnt_0    <= o_cnt_0 + i_0;
    o_cnt_1    <= o_cnt_1 + i_1;
    if(o_cnt_0 == o_cnt_1) o_mismatch_cnt <= '0;
    else if(!(&o_mismatch_cnt)) o_mismatch_cnt <= o_mismatch_cnt + 1;
    o_mismatch <= |o_mismatch_cnt;
  end
end
endmodule



// Intention is to instantate one permuter per mem system so that the part selects can use constants. (Variable part selects are not allowed in Verilog, which is what we'd need if the part-select is based on mem-system ID)
module address_permuter #(
    parameter integer NUM_MEM_SYSTEMS = 1,
    parameter integer AWIDTH = 32,
    parameter integer BANK_BIT_LSB = 16,
    parameter integer NUM_BANKS_W = 2,
    parameter integer PERMUTE_BIT_LSB = 10
)
(
    input  wire   [AWIDTH-1:0] in_address,
    output logic  [AWIDTH-1:0] out_address
);

  localparam P_NUM_BANKS_W = NUM_BANKS_W < 1? 1 : NUM_BANKS_W; // Floor the value to 1 because 0 can't be used with +: operator below.
  logic [AWIDTH-1:0] permuted_address;
  /*

    The concept is to take the permute bits and move them to the bank-bits position. Then squeeze together the remaining bits.
    This causes a linear sequence of input addresses to be spread across banks, with a per-bank chunk size equal to 2^PERMUTE_BIT_LSB bytes.

    Example.
    AWIDTH = 16
    BANK_BIT_LSB = 12
    NUM_BANKS_W = 2
    PERMUTE_BIT_LSB = 6

    Original in_address bit positions
    15 14 13 12 11 10  9  8  7  6  5  4  3  2  1  0
           |  |              |  |
           Bank bits         Permute bits

    out_address composition, expressed using in_address bit positions
    15 14  7  6 13 12 11 10  9  8  5  4  3  2  1  0

    Another example.
    AWIDTH = 16
    BANK_BIT_LSB = 14
    NUM_BANKS_W = 1
    PERMUTE_BIT_LSB = 10

    Original in_address bit positions
    15 14 13 12 11 10  9  8  7  6  5  4  3  2  1  0
        |           |
        Bank bit    Permute bit

    out_address composition, expressed using in_address bit positions
    15 10 14 13 12 11  9  8  7  6  5  4  3  2  1  0

  */

  generate
    if (NUM_MEM_SYSTEMS == 1) begin
      assign permuted_address =
        {
          in_address[PERMUTE_BIT_LSB +: P_NUM_BANKS_W],                           // Replace the bank bits with the permute bits
          in_address[BANK_BIT_LSB+P_NUM_BANKS_W-1 : P_NUM_BANKS_W+PERMUTE_BIT_LSB], // Grab the bits from the bank bits, down to, but excluding the permute bits
          in_address[PERMUTE_BIT_LSB-1:0]                                       // Grab the bits from after the permute bits, down to 0
        };
    end else begin
      assign permuted_address =
        {
          in_address[AWIDTH-1 : BANK_BIT_LSB+NUM_BANKS_W],                  // maintain the msbs all the way to, but excluding, the bank bits. Use NUM_BANKS_W instead of P_NUM_BANKS_W to avoid out of bounds access when there's only 1 bank (in which case this permuter is not even used so the results don't matter)
          in_address[PERMUTE_BIT_LSB +: P_NUM_BANKS_W],                           // Replace the bank bits with the permute bits
          in_address[BANK_BIT_LSB+P_NUM_BANKS_W-1 : P_NUM_BANKS_W+PERMUTE_BIT_LSB], // Grab the bits from the bank bits, down to, but excluding the permute bits
          in_address[PERMUTE_BIT_LSB-1:0]                                       // Grab the bits from after the permute bits, down to 0
        };
    end
  endgenerate

  assign out_address = permuted_address;

endmodule


`default_nettype wire
