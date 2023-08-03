// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT
//

//DMA controller read-FSM state enumerations
package dma_controller_rd_fsm_pkg;

    typedef enum {  IDLE,
                    READ,
                    PAUSE_READ,
                    WAIT_FOR_RX_DATA,
                    MAKE_RD_XFERS_EVEN,
                    FLUSH_RD_DATA_PIPE,
                    XXX } rd_state_e;

endpackage
