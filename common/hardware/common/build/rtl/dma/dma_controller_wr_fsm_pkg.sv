// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT
//

//DMA controller write-FSM state enumerations
package dma_controller_wr_fsm_pkg;

    typedef enum {  WIDLE,
                    WAIT_FOR_WRITE_BURST_DATA,
                    WRITE_COMPLETE_BURST,
					WAIT_TO_WRITE_MAGIC_NUM,
                    WRITE_MAGIC_NUM,
                    WXXX } wr_state_e;

endpackage
