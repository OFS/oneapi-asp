// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT

#ifndef MMD_H
#define MMD_H

/** Directly programs aocx file data to a device bypassing the typical
    OpenCL function calls.  Used because the aoc runtime needs
    to interface with the ASP, that is not possible if the ASP is
    not loaded yet.  This function bypasses the aoc runtime and directly
    loads the aocx using OPAE.  Note that the function is not thread-safe
    and will not have aoc locking.  It should *not* be used in conjunction
    with OpenCL API calls.
*/
int mmd_device_reprogram(const char *device_name, void *data,
                              size_t data_size);
extern bool diagnose;
#define DEBUG_LOG(...) fprintf(stderr, __VA_ARGS__)
#endif // MMD_H
