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


# symlink function that accepts globs and can overlay existing directories
def symlink_glob(src, dst):
    for i in glob.glob(src):
        if os.path.isdir(i):
            dst_dir_path = os.path.join(dst, os.path.basename(i))
            if(not os.path.exists(dst_dir_path)):
                os.mkdir(dst_dir_path)
            symlink_glob(os.path.join(i, '*'), dst_dir_path)
            # '.' files(hidden files) are not included in '*'
            symlink_glob(os.path.join(i, '.*'), dst_dir_path)
        else:
            dst_link = os.path.join(dst, os.path.basename(i))
            if(os.path.exists(dst_link)):
                os.remove(dst_link)
            os.symlink(i, dst_link)
            #print ("create symlink src: %s    dest: %s   dest_link: %s" % (src, dst, dst_link))


# take a glob path and remove the files
def rm_glob(src, verbose=False):
    for i in glob.glob(src):
        os.remove(i)
        #print ("Removed: %s" % i)


# create a text file
def create_text_file(dst, lines):
    with open(dst, 'w') as f:
        for line in lines:
            f.write(line)


# main work function for setting up bsp
def setup_bsp(bsp_root, env_vars, bsp, verbose):

    libopae_c_root_dir = env_vars["LIBOPAE_C_ROOT"]
    packager_bin = get_packager_bin(libopae_c_root_dir)
    deliverable_dir = env_vars["OPAE_PLATFORM_ROOT"]
    deliverable_hw_dir = os.path.join(deliverable_dir, 'hw')
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
    filelist_path = os.path.join(bsp_qsf_dir, "filelist.txt")
    cmd_afu_synth_setup_filelist = ("--sources " + filelist_path)
    cmd_afu_synth_setup_lib_arb = ("--lib " + deliverable_hwlib_dir)
    cmd_afu_synth_setup_force_arg = "--force"
    cmd_afu_synth_setup_platform_dst = os.path.join(bsp_dir,'fim_platform')
    full_afu_synth_setup_cmd = (cmd_afu_synth_setup_opae_PATH_update + " " +
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
    ASP_BASE_DIR_ABS=bsp_dir
    
    QUARTUS_BUILD_DIR_RELATIVE_TO_ASP_BUILD_DIR=os.path.relpath(QUARTUS_SYN_DIR,bsp_qsf_dir)
    #print("QUARTUS_BUILD_DIR_RELATIVE_TO_ASP_BUILD_DIR %s" % (QUARTUS_BUILD_DIR_RELATIVE_TO_ASP_BUILD_DIR) )
    
    QUARTUS_BUILD_DIR_RELATIVE_TO_KERNEL_BUILD_DIR=os.path.relpath(QUARTUS_SYN_DIR,bsp_dir)
    #print("QUARTUS_BUILD_DIR_RELATIVE_TO_KERNEL_BUILD_DIR %s" % (QUARTUS_BUILD_DIR_RELATIVE_TO_KERNEL_BUILD_DIR) )
    
    ASP_BUILD_DIR_RELATIVE_TO_QUARTUS_BUILD_DIR=os.path.relpath(bsp_qsf_dir,QUARTUS_SYN_DIR)
    #print("ASP_BUILD_DIR_RELATIVE_TO_QUARTUS_BUILD_DIR %s" % (ASP_BUILD_DIR_RELATIVE_TO_QUARTUS_BUILD_DIR) )
    
    KERNEL_BUILD_DIR_RELATIVE_TO_QUARTUS_BUILD_DIR=os.path.relpath(bsp_dir,QUARTUS_SYN_DIR)
    #print("KERNEL_BUILD_DIR_RELATIVE_TO_QUARTUS_BUILD_DIR %s" % (KERNEL_BUILD_DIR_RELATIVE_TO_QUARTUS_BUILD_DIR) )
    
    #symlink the contents of bsp_dir/build into syn_top
    BSP_BUILD_DIR_FILES=os.path.join(bsp_qsf_dir, '*')
    #symlink_glob(BSP_BUILD_DIR_FILES,QUARTUS_SYN_DIR)
    ASP_BUILD_DIR_SYMLINK_CMD="cd " + QUARTUS_SYN_DIR + " && ln -s " + ASP_BUILD_DIR_RELATIVE_TO_QUARTUS_BUILD_DIR + "/* ."
    #ASP_BUILD_DIR_SYMLINK_CMD="ln -s " + ASP_BUILD_DIR_RELATIVE_TO_QUARTUS_BUILD_DIR + "/* " + QUARTUS_SYN_DIR + "/"
    run_cmd(ASP_BUILD_DIR_SYMLINK_CMD)
    
    #symlink the ofs_top.qpf and ofs_pr_afu.qsf file to bsp_dir
    rm_glob(os.path.join(bsp_dir, 'ofs_pr_afu.qsf'))
    OFS_PR_AFU_QSF_SYMLINK_CMD="cd " + bsp_dir + " && ln -s " + QUARTUS_BUILD_DIR_RELATIVE_TO_KERNEL_BUILD_DIR + "/ofs_pr_afu.qsf ."
    run_cmd(OFS_PR_AFU_QSF_SYMLINK_CMD)

    rm_glob(os.path.join(bsp_dir, 'ofs_top.qpf'))
    OFS_TOP_QPF_SYMLINK_CMD="cd " + bsp_dir + " && ln -s " + QUARTUS_BUILD_DIR_RELATIVE_TO_KERNEL_BUILD_DIR + "/ofs_top.qpf ."
    run_cmd(OFS_TOP_QPF_SYMLINK_CMD)
    

# create a file manifest for use in later copy-steps
def create_manifest(dst_dir):
    files = []
    for i in glob.glob(os.path.join(dst_dir, '*')):
        filename = os.path.basename(i)
        print ("create-manifest: filename is %s" % filename)
        files.append("%s\n" % filename)
    manifest_file = 'bsp_dir_filelist.txt'
    files.append("%s\n" % manifest_file)
    # add qdb so that it is not copied to build directory
    files.append('qdb\n')
    create_text_file(os.path.join(dst_dir, manifest_file), files)


# remove lines with search_text in file
def remove_lines_in_file(file_name, search_text):
    lines = []
    with open(file_name) as f:
        for line in f:
            if search_text in line:
                continue
            lines.append(line)

    with open(file_name, 'w') as f:
        for line in lines:
            f.write(line)


# replace a line containing search_text with replace_text in file
def replace_lines_in_file(file_name, search_text, replace_text):
    lines = []
    with open(file_name) as f:
        for line in f:
            if search_text in line:
                lines.append(line.replace(search_text, replace_text))
            else:
                lines.append(line)

    with open(file_name, 'w') as f:
        for line in lines:
            f.write(line)


# replace search_text with replace_text in file
def replace_text_in_file(file_name, search_text, replace_text):
    with open(file_name, 'r') as f:
        data = f.read()
        data = data.replace(search_text, replace_text)
    with open(file_name, 'w') as f:
        f.write(data)


# python equivalent of "chmod +w"
def chmod_plus_w(file_path):
    file_stats = os.stat(file_path)
    os.chmod(file_path, file_stats.st_mode | (stat.S_IWRITE))


# update quartus project for opencl flow
def update_qpf_project_for_opencl_flow(qpf_path):
    chmod_plus_w(qpf_path)

    # need to rewrite these lines so that opencl AOC qsys flow modifies the
    # correct project
    remove_lines_in_file(qpf_path, 'PROJECT_REVISION')

    with open(qpf_path, 'a') as f:
        f.write('\n')
        f.write('\n')
        f.write('#YOU MUST PUT SYNTH REVISION FIRST SO THAT '
                'AOC WILL DEFAULT TO THAT WITH qsys-script!\n')
        f.write('PROJECT_REVISION = "afu_opencl_kernel"\n')
        f.write('PROJECT_REVISION = "ofs_top"\n')

# update quartus project for afu compile flow
def update_qpf_project_for_afu(qpf_path):
    chmod_plus_w(qpf_path)

    # need to rewrite these lines so that opencl AOC qsys flow modifies the
    # correct project
    remove_lines_in_file(qpf_path, 'PROJECT_REVISION')

    with open(qpf_path, 'a') as f:
        f.write('\n')
        f.write('\n')
        f.write('PROJECT_REVISION = "afu_flat"\n')
        f.write('PROJECT_REVISION = "ofs_top"\n')

def update_qsf_settings_for_opencl_kernel_qsf(qsf_path):
    # create stripped down version of qsf for opencl qsys flow
    chmod_plus_w(qsf_path)

    remove_lines_in_file(qsf_path, 'user_clocks.sdc')
    remove_lines_in_file(qsf_path, 'SCJIO')

    remove_lines_in_file(qsf_path, '..')
    remove_lines_in_file(qsf_path, '.qsf')
    remove_lines_in_file(qsf_path, '.tcl')
    remove_lines_in_file(qsf_path, 'SOURCE')
    remove_lines_in_file(qsf_path, 'SEARCH_PATH')
    remove_lines_in_file(qsf_path, '_FILE ')

    with open(qsf_path, 'a') as f:
        f.write('\n')
        f.write('\n')
        f.write('##OPENCL_KERNEL_ASSIGNMENTS_START_HERE\n')
        f.write('\n')
        f.write('\n')


def update_qsf_settings_for_opencl_afu(qsf_path):
    chmod_plus_w(qsf_path)

    remove_lines_in_file(qsf_path, 'OPTIMIZATION_MODE')
    remove_lines_in_file(qsf_path, 'user_clocks.sdc')
    remove_lines_in_file(qsf_path, 'SCJIO')

    with open(qsf_path, 'a') as f:
        f.write('\n')
        #increase OPTIMIZATION_MODE effort level
        f.write("set_global_assignment -name OPTIMIZATION_MODE \"SUPERIOR PERFORMANCE WITH MAXIMUM PLACEMENT EFFORT\"\n")
        f.write('\n\n')
        f.write("# AFU  section - User AFU RTL goes here\n")
        f.write("# =============================================\n")
        f.write("#\n")
        f.write("# AFU + MPF IPs\n")
        f.write("source afu_ip.qsf\n")


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
