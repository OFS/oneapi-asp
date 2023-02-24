// Copyright 2020 Intel Corporation.
//
// THIS SOFTWARE MAY CONTAIN PREPRODUCTION CODE AND IS PROVIDED BY THE
// COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
// WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
// BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
// WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
// OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
// EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

//defining OpenCL kernel/cra connections
interface opencl_kernel_control_intf #(
    parameter CRA_RDDATA_WIDTH  = 64,
    parameter CRA_WRDATA_WIDTH  = 64,
    parameter CRA_ADDR_WIDTH    = 30,
    parameter CRA_BYTE_EN_WIDTH = 8
);

    logic kernel_reset_n;
    logic kernel_irq;

    logic                           kernel_cra_waitrequest;
    logic [CRA_RDDATA_WIDTH-1:0]    kernel_cra_readdata;
    logic                           kernel_cra_readdatavalid;
    logic                           kernel_cra_burstcount;
    logic [CRA_WRDATA_WIDTH-1:0]    kernel_cra_writedata;
    logic [CRA_ADDR_WIDTH-1:0]      kernel_cra_address;
    logic                           kernel_cra_write;
    logic                           kernel_cra_read;
    logic [CRA_BYTE_EN_WIDTH-1:0]   kernel_cra_byteenable;
    logic                           kernel_cra_debugaccess;


    //kernel_wrapper module
    modport kw (
        input   kernel_reset_n, kernel_cra_burstcount, kernel_cra_writedata, 
                kernel_cra_address, kernel_cra_write, kernel_cra_read, kernel_cra_debugaccess,
                kernel_cra_byteenable,
        output  kernel_irq, kernel_cra_waitrequest, kernel_cra_readdata,
                kernel_cra_readdatavalid
    );
    
    //bsp_interface module
    modport bsp (
        input   kernel_irq, kernel_cra_waitrequest, kernel_cra_readdata,
                kernel_cra_readdatavalid,
        output  kernel_reset_n, kernel_cra_burstcount, kernel_cra_writedata, 
                kernel_cra_address, kernel_cra_write, kernel_cra_read, kernel_cra_debugaccess,
                kernel_cra_byteenable
    );

endinterface : opencl_kernel_control_intf

interface kernel_mem_intf #(
    parameter ADDR_WIDTH        = dc_bsp_pkg::OPENCL_QSYS_ADDR_WIDTH,
    parameter DATA_WIDTH        = dc_bsp_pkg::OPENCL_BSP_KERNEL_DATA_WIDTH,
    parameter BURSTCOUNT_WIDTH  = dc_bsp_pkg::OPENCL_BSP_KERNEL_BURSTCOUNT_WIDTH,
    parameter BYTEENABLE_WIDTH  = dc_bsp_pkg::OPENCL_BSP_KERNEL_BYTEENABLE_WIDTH
);
    logic                           waitrequest;
    logic [DATA_WIDTH-1:0]          readdata;
    logic                           readdatavalid;
    
    logic [BURSTCOUNT_WIDTH-1:0]    burstcount;
    logic [DATA_WIDTH-1:0]          writedata;
    logic [ADDR_WIDTH-1:0]          address;
    logic                           write;
    logic                           read;
    logic [BYTEENABLE_WIDTH-1:0]    byteenable;
    logic                           writeack;
    
    modport bsp (
        input  read, write, writedata, address, burstcount,
               byteenable,
        output readdata, readdatavalid, waitrequest, writeack
    );
    modport ker (
        input  readdata, readdatavalid, waitrequest, writeack,
        output read, write, writedata, address, burstcount,
               byteenable
    );
endinterface : kernel_mem_intf

