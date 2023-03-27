// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT

/**
 * \fpga_dma.h
 * \brief FPGA DMA BBB API Header
 *
 * Known Limitations
 * - Driver does not support Address Span Extender
 * - Implementation is not optimized for performance.
 *   User buffer data is copied into a DMA-able buffer before the transfer
 * - Supports only synchronous (blocking) transfers
 */

#ifndef AFU_BBB_UTIL_H__
#define AFU_BBB_UTIL_H__

#include <assert.h>
#include <opae/fpga.h>
#include <uuid/uuid.h>

#define DFH_FEATURE_EOL(dfh) (((dfh >> 40) & 1) == 1)
#define DFH_FEATURE(dfh) ((dfh >> 60) & 0xf)
#define DFH_FEATURE_IS_PRIVATE(dfh) (DFH_FEATURE(dfh) == 3)
#define DFH_FEATURE_IS_BBB(dfh) (DFH_FEATURE(dfh) == 2)
#define DFH_FEATURE_IS_AFU(dfh) (DFH_FEATURE(dfh) == 1)
#define DFH_FEATURE_NEXT(dfh) ((dfh >> 16) & 0xffffff)

static bool find_dfh_by_guid(fpga_handle afc_handle, uint64_t find_id_l,
                             uint64_t find_id_h, uint64_t *result_offset = NULL,
                             uint64_t *result_next_offset = NULL) {
  assert(find_id_l);
  assert(find_id_h);

  uint64_t offset = 0;
  if (result_offset) {
    offset = *result_offset;
  }
  uint64_t dfh = 0;

  // Limit the maximum number of DFH search iterations to avoid getting stuck
  // in an infinte loop in case the DFH_FEATURE_EOL is not found.  Limit of
  // 5000 is very conservaitve.  In practice search should terminate in 3 or
  // fewer iterations.
  int MAX_DFH_SEARCHES = 5000;
  int dfh_search_iterations = 0;

  do {
    fpgaReadMMIO64(afc_handle, 0, offset, &dfh);

    int is_bbb = DFH_FEATURE_IS_BBB(dfh);
    int is_afu = DFH_FEATURE_IS_AFU(dfh);

    if (is_afu || is_bbb) {
      uint64_t id_l = 0;
      uint64_t id_h = 0;
      fpgaReadMMIO64(afc_handle, 0, offset + 8, &id_l);
      fpgaReadMMIO64(afc_handle, 0, offset + 16, &id_h);

      if (find_id_l == id_l && find_id_h == id_h) {
        if (result_offset)
          *result_offset = offset;
        if (result_next_offset)
          *result_next_offset = DFH_FEATURE_NEXT(dfh);
        return true;
      }
    }
    offset += DFH_FEATURE_NEXT(dfh);

    dfh_search_iterations++;
    if (dfh_search_iterations > MAX_DFH_SEARCHES) {
      return false;
    }
  } while (!DFH_FEATURE_EOL(dfh));

  return false;
}

static bool find_dfh_by_guid(fpga_handle afc_handle, const char *guid_str,
                             uint64_t *result_offset = NULL,
                             uint64_t *result_next_offset = NULL) {
  fpga_guid guid;

  if (uuid_parse(guid_str, guid) < 0)
    return 0;

  uint32_t i;
  uint32_t s;

  uint64_t find_id_l = 0;
  uint64_t find_id_h = 0;

  // The API expects the MSB of the GUID at [0] and the LSB at [15].
  s = 64;
  for (i = 0; i < 8; ++i) {
    s -= 8;
    find_id_h = ((find_id_h << 8) | (0xff & guid[i]));
  }

  s = 64;
  for (i = 0; i < 8; ++i) {
    s -= 8;
    find_id_l = ((find_id_l << 8) | (0xff & guid[8 + i]));
  }

  return find_dfh_by_guid(afc_handle, find_id_l, find_id_h, result_offset,
                          result_next_offset);
}

#endif // AFU_BBB_UTIL_H__
