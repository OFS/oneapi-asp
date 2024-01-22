#!/usr/bin/env python3

## Copyright 2022 Intel Corporation
## SPDX-License-Identifier: MIT

# setup_bsp.py
# description:
#   This script imports the out-of-tree build template from a base FIM
#   build.

import argparse
import glob
import os
import shutil
import stat
import subprocess
import sys
import tarfile
import platform

def get_packager_bin(libopae_c_root_dir):
    packager_bin = os.path.join(libopae_c_root_dir, 'bin',
                                'packager')
    if(not os.path.exists(packager_bin)):
        print ("ERROR: %s path not found" % packager_bin)
        sys.exit(1)
    return packager_bin

def get_dir_path(search_dir_name,search_start_path):
    res="none"
    for root, dirs, files in os.walk(search_start_path):
        if search_dir_name in dirs:
            res = os.path.join(root,search_dir_name)
    if res == "none":
        print("Couldn't find the directory %s when searching from %s. Quitting." % (search_dir_name, search_start_path))
        sys.exit(1)
    return res
    
def get_file_path(search_file_name,search_start_path):
    res="none"
    for root, dirs, files in os.walk(search_start_path):
        if search_file_name in files:
            res = os.path.join(root,search_file_name)
    if res == "none":
        print("Couldn't find the file %s when searching from %s. Quitting." % (search_file_name, search_start_path))
        sys.exit(1)
    return res

# run command
def run_cmd(cmd, path=None):
    if(path):
        old_cwd = os.getcwd()
        os.chdir(path)
    #print ("run_cmd cmd is %s" % cmd)
    process = subprocess.Popen(cmd,
                               stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE,
                               stdin=subprocess.PIPE,
                               shell=True)
    out, _err = process.communicate()
    exitcode = process.poll()
    if(path):
        os.chdir(old_cwd)
    if exitcode == 0:
        return str(out).rstrip()
    else:
        print ("ERROR: command '%s' failed" % cmd)
        sys.exit(1)


# delete directory and create empty directory in its place
def delete_and_mkdir(dir_path):
    shutil.rmtree(dir_path, ignore_errors=True)
    os.mkdir(dir_path)
    #print ("delete and remake %s" % dir_path)


# copy function that accepts globs and can overlay existing directories
def copy_glob(src, dst, verbose=False):
    for i in glob.glob(src):
        if os.path.isdir(i):
            dst_dir_path = os.path.join(dst, os.path.basename(i))
            if(not os.path.exists(dst_dir_path)):
                os.mkdir(dst_dir_path)
            copy_glob(os.path.join(i, '*'), dst_dir_path, verbose)
            # '.' files(hidden files) are not included in '*'
            copy_glob(os.path.join(i, '.*'), dst_dir_path, verbose)
        else:
            if verbose:
                print ("copy_glob: src is %s; dst is %s" % (i, dst))
            basefilename = (os.path.basename(i))
            #print ("basefilename is %s" % basefilename)
            full_dst = os.path.join(dst,basefilename)
            #print ("full_dst is %s" % full_dst)
            if(os.path.exists(full_dst)):
                #print ("%s exists already, deleting it first" % full_dst)
                rm_glob(full_dst)
            shutil.copy2(i, dst)

            
# take a glob path and remove the files
def rm_glob(src, verbose=False):
    for i in glob.glob(src):
        os.remove(i)
        #print ("Removed: %s" % i)

        
# main work function for setting up bsp
def setup_bsp(bsp_root, env_vars, bsp, verbose):

    libopae_c_root_dir = env_vars["LIBOPAE_C_ROOT"]
    packager_bin = get_packager_bin(libopae_c_root_dir)
    deliverable_dir = env_vars["OPAE_PLATFORM_ROOT"].rstrip("/")
    deliverable_hw_dir = os.path.join(deliverable_dir, 'hw')
    deliverable_bluebits_dir = os.path.join(deliverable_hw_dir, 'blue_bits')
    deliverable_hwlib_dir = os.path.join(deliverable_hw_dir, 'lib')
    intel_fpga_bbb_dir = env_vars["INTEL_FPGA_BBB"]

    print ("packager_bin: %s" % packager_bin)
    print ("deliverable_dir: %s" % deliverable_dir)
    print ("deliverable_hw_dir: %s" % deliverable_hw_dir)
    print ("deliverable_hwlib_dir: %s" % deliverable_hwlib_dir)
    print ("intel_fpga_bbb_dir: %s" % intel_fpga_bbb_dir)

    bsp_dir = os.path.join(bsp_root,"hardware",bsp)
    bsp_qsf_dir = os.path.join(bsp_dir, 'build')

    print("bsp_dir is %s\n" % bsp_dir)
    
    #preserve the pr-build-template folder
    delete_and_mkdir(os.path.join(bsp_dir, '../../pr_build_template'))
    copy_glob(deliverable_dir, os.path.join(bsp_dir, '../../'),verbose)
    
    #preserve the blue_bits folder from $OPAE_PLATFORM_ROOT/hw/
    delete_and_mkdir(os.path.join(bsp_dir, 'blue_bits'))
    copy_glob(deliverable_bluebits_dir, bsp_dir, verbose)
    
    # copy the FIM FME information text files
    copy_glob(os.path.join(deliverable_hwlib_dir, 'fme*.txt'), bsp_qsf_dir, verbose)
    
    # copy the required IP files from the intel-fpga-bbb repo (for use in VTP/MPF)
    bsp_ip_dir = os.path.join(bsp_qsf_dir, 'ip')
    copy_glob(os.path.join(intel_fpga_bbb_dir,"BBB_mpf_vtp"), bsp_ip_dir, verbose)
    copy_glob(os.path.join(intel_fpga_bbb_dir,"BBB_cci_mpf"), bsp_ip_dir, verbose)

    # add packager to opencl bsp to make bsp easier to use
    bsp_tools_dir = os.path.join(bsp_qsf_dir, 'tools')
    delete_and_mkdir(bsp_tools_dir)
    shutil.copy2(packager_bin, bsp_tools_dir)

    # run the opae script 'afu-synth-setup' to create the PIM
    cmd_afu_synth_setup_opae_PATH_update = ("PATH=" + env_vars["LIBOPAE_C_ROOT"] + "/bin:${PATH}")
    if "OPAE_PLATFORM_DB_PATH" not in os.environ:
        cmd_afu_synth_setup_opae_platform_db_path = "OPAE_PLATFORM_DB_PATH=${OPAE_PLATFORM_ROOT}/hw/lib/platform/platform_db"
    else:
        cmd_afu_synth_setup_opae_platform_db_path = ""
    cmd_afu_synth_setup_script = "${LIBOPAE_C_ROOT}/bin/afu_synth_setup"
    filelist_path = "filelist.txt"
    cmd_afu_synth_setup_filelist = ("--sources " + filelist_path)
    cmd_afu_synth_setup_lib_arb = ("--lib " + deliverable_hwlib_dir)
    cmd_afu_synth_setup_force_arg = "--force"
    cmd_afu_synth_setup_platform_dst = os.path.join(bsp_dir,'fim_platform')
    full_afu_synth_setup_cmd = ("cd " + bsp_qsf_dir + " && " +  
                                cmd_afu_synth_setup_opae_PATH_update + " " +
                                cmd_afu_synth_setup_opae_platform_db_path + " " +
                                cmd_afu_synth_setup_script + " " +
                                cmd_afu_synth_setup_filelist + " " +
                                cmd_afu_synth_setup_lib_arb + " " +
                                cmd_afu_synth_setup_force_arg + " " +
                                cmd_afu_synth_setup_platform_dst)
    print ("full afu_synth_setup cmd is %s" % full_afu_synth_setup_cmd)
    run_cmd(full_afu_synth_setup_cmd)

    #find the Quartus-build folder expected by the FIM
    #use syn_top for now, but it might change depending on FIM board/variant/etc
    QUARTUS_SYN_DIR=get_dir_path("syn_top",bsp_dir)
    if verbose:
        print("QUARTUS_SYN_DIR is %s" % (QUARTUS_SYN_DIR))
    ASP_BASE_DIR_ABS=bsp_dir
    
    QUARTUS_BUILD_DIR_RELATIVE_TO_ASP_BUILD_DIR=os.path.relpath(QUARTUS_SYN_DIR,bsp_qsf_dir)
    if verbose:
        print("QUARTUS_BUILD_DIR_RELATIVE_TO_ASP_BUILD_DIR %s" % (QUARTUS_BUILD_DIR_RELATIVE_TO_ASP_BUILD_DIR) )
    
    QUARTUS_BUILD_DIR_RELATIVE_TO_KERNEL_BUILD_DIR=os.path.relpath(QUARTUS_SYN_DIR,bsp_dir)
    if verbose:
        print("QUARTUS_BUILD_DIR_RELATIVE_TO_KERNEL_BUILD_DIR %s" % (QUARTUS_BUILD_DIR_RELATIVE_TO_KERNEL_BUILD_DIR) )
    
    ASP_BUILD_DIR_RELATIVE_TO_QUARTUS_BUILD_DIR=os.path.relpath(bsp_qsf_dir,QUARTUS_SYN_DIR)
    if verbose:
        print("ASP_BUILD_DIR_RELATIVE_TO_QUARTUS_BUILD_DIR %s" % (ASP_BUILD_DIR_RELATIVE_TO_QUARTUS_BUILD_DIR) )
    
    KERNEL_BUILD_DIR_RELATIVE_TO_QUARTUS_BUILD_DIR=os.path.relpath(bsp_dir,QUARTUS_SYN_DIR)
    if verbose:
        print("KERNEL_BUILD_DIR_RELATIVE_TO_QUARTUS_BUILD_DIR %s" % (KERNEL_BUILD_DIR_RELATIVE_TO_QUARTUS_BUILD_DIR) )
    
    BUILD_SCRIPTS_DIR=os.path.join(bsp_qsf_dir,'scripts')
    SYNTOP_TCL_POINTER=os.path.join(BUILD_SCRIPTS_DIR,'syn_top_relpath.tcl')
    SYNTOP_FILE_LINES = []
    SYNTOP_FILE_LINES.append("#Generated by setup-bsp.py, used in entry.tcl.\n")
    SYNTOP_FILE_LINES.append("global SYN_TOP_RELPATH\n")
    SYNTOP_FILE_LINES.append("set SYN_TOP_RELPATH %s\n" % QUARTUS_BUILD_DIR_RELATIVE_TO_KERNEL_BUILD_DIR)
    create_text_file(SYNTOP_TCL_POINTER, SYNTOP_FILE_LINES)
    
    #symlink the contents of bsp_dir/build into syn_top
    BSP_BUILD_DIR_FILES=os.path.join(bsp_qsf_dir, '*')
    ASP_BUILD_DIR_SYMLINK_CMD="cd " + QUARTUS_SYN_DIR + " && ln -sf " + ASP_BUILD_DIR_RELATIVE_TO_QUARTUS_BUILD_DIR + "/* ."
    run_cmd(ASP_BUILD_DIR_SYMLINK_CMD)
    
    PR_AFU_QPF_FILENAME=os.path.basename(glob.glob(QUARTUS_SYN_DIR + "/*.qpf")[0])
    PR_AFU_QSF_FILENAME=os.path.basename(glob.glob(QUARTUS_SYN_DIR + "/*pr_afu.qsf")[0])
    if verbose:
        print("PR_AFU_QPF_FILENAME is %s" % PR_AFU_QPF_FILENAME)
    if verbose:
        print("PR_AFU_QSF_FILENAME is %s" % PR_AFU_QSF_FILENAME)
    
    rm_glob(os.path.join(bsp_dir, PR_AFU_QSF_FILENAME)) 
    OFS_PR_AFU_QSF_SYMLINK_CMD="cd " + bsp_dir + " && ln -sf " + QUARTUS_BUILD_DIR_RELATIVE_TO_KERNEL_BUILD_DIR + "/" + PR_AFU_QSF_FILENAME + " ."
    run_cmd(OFS_PR_AFU_QSF_SYMLINK_CMD)

    rm_glob(os.path.join(bsp_dir, PR_AFU_QPF_FILENAME))
    OFS_TOP_QPF_SYMLINK_CMD="cd " + bsp_dir + " && ln -sf " + QUARTUS_BUILD_DIR_RELATIVE_TO_KERNEL_BUILD_DIR + "/" + PR_AFU_QPF_FILENAME + " ."
    run_cmd(OFS_TOP_QPF_SYMLINK_CMD)
    
    print("\nsetup-bsp.py completed successfully for variant %s\n" % bsp)


# Read environment variables required for script operations
# TODO: see if these can be converted to command line arguments. Keeping
# as env vars for now because some of the dependent scripts may use them
def get_required_env_vars():
    env_vars = {}
    env_vars_list = ["OPAE_PLATFORM_ROOT","LIBOPAE_C_ROOT","INTEL_FPGA_BBB"]
    for var_name in env_vars_list:
        var = os.environ.get(var_name)
        if var:
            env_vars[var_name] = var
        else:
            print("Error must set environment variable: {}".format(var_name))
            sys.exit(-1)
    return env_vars

# create a text file
def create_text_file(dst, lines):
    with open(dst, 'w') as f:
        for line in lines:
            f.write(line)
    

# process command line and setup bsp flow
def main():
    parser = argparse.ArgumentParser(description="Generate board variant")
    parser.add_argument("board_name", help="Name of board to configure")
    parser.add_argument('--verbose', required=False, default=False,
                        action='store_true', help='verbose output')
    args = parser.parse_args()

    env_vars = get_required_env_vars()
    bsp_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    setup_bsp(bsp_root, env_vars, args.board_name, args.verbose)

if __name__ == '__main__':
    main()
