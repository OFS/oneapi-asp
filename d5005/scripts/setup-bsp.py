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

    print("bsp_qsf_dir is %s\n" % bsp_qsf_dir)

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
    cmd_afu_synth_setup_platform_dst = os.path.join(bsp_dir,'pim')
    full_afu_synth_setup_cmd = (cmd_afu_synth_setup_opae_PATH_update + " " +
                                cmd_afu_synth_setup_opae_platform_db_path + " " +
                                cmd_afu_synth_setup_script + " " +
                                cmd_afu_synth_setup_filelist + " " +
                                cmd_afu_synth_setup_lib_arb + " " +
                                cmd_afu_synth_setup_force_arg + " " +
                                cmd_afu_synth_setup_platform_dst)
    print ("full afu_synth_setup cmd is %s" % full_afu_synth_setup_cmd)
    run_cmd(full_afu_synth_setup_cmd)

    #copy/move the pim folder into build/ to keep it common
    src_platform_dir = os.path.join(bsp_dir, 'pim')
    src = os.path.join(src_platform_dir,'*')
    dst = os.path.join(bsp_dir)
    #print("Ran the afu-synth-setup cmd; now use copy_glob to move/copy it to the proper place")
    #print ("src is %s" % src)
    #print ("dst is %s" % dst)

    copy_glob(src, dst, verbose)
    shutil.rmtree(src_platform_dir, ignore_errors=True)

    #move the release directory's syn_top files to hardware/<target>/build/
    dst_build_path=bsp_qsf_dir
    syn_top_dir_name="syn_top"
    src_syn_top_path=get_dir_path(syn_top_dir_name,bsp_qsf_dir)
    src_syn_top_files=os.path.join(src_syn_top_path, '*')
    #print("Moving the contents of syn_top from %s to %s " % (src_syn_top_files, dst_build_path) )
    copy_glob(src_syn_top_files,dst_build_path)
    #print("done copying the contents of syn_top into build/")
    shutil.rmtree(src_syn_top_path, ignore_errors=True)
    
    lib_src_path = (os.path.join(bsp_qsf_dir, 'src'))
    lib_ipss_path = (os.path.join(bsp_qsf_dir, 'ipss'))
    lib_ip_lib_path = (os.path.join(bsp_qsf_dir, 'ip_lib'))
    shutil.rmtree(lib_ip_lib_path, ignore_errors=True)
    os.mkdir(lib_ip_lib_path)
    copy_glob(lib_src_path,lib_ip_lib_path)
    copy_glob(lib_ipss_path,lib_ip_lib_path)
    #copy the ip_lib/ folder from work directory into build/../
    ip_lib_dir_name="ip_lib"
    src_ip_lib_path=get_dir_path(ip_lib_dir_name,bsp_qsf_dir)
    dst_ip_lib_path=(os.path.join(dst_build_path, '../'))
    #print("src_ip_lib_path is %s; dst_ip_lib_path is %s" % (src_ip_lib_path,dst_ip_lib_path) )
    copy_glob(src_ip_lib_path,dst_ip_lib_path)
    #print("done copying the contents of ip_lib into build/../")
    #shutil.rmtree(src_ip_lib_path, ignore_errors=True)
    
    # create quartus project revision for opencl kernel qsf
    kernel_qsf_path = os.path.join(bsp_dir, 'afu_opencl_kernel.qsf')
    #print ("kernel_qsf_path is %s\n" % kernel_qsf_path)

    iofs_pr_afu_qsf_file=os.path.join(bsp_qsf_dir, 'iofs_pr_afu.qsf')
    #print ("copy %s iofs_pr_afu_qsf_file to %s\n" % (bsp_qsf_dir, kernel_qsf_path))
    shutil.copy2(iofs_pr_afu_qsf_file, kernel_qsf_path)

    update_qsf_settings_for_opencl_kernel_qsf(kernel_qsf_path)
    #print ("update qsf setting for opencl-kernel-qsf")

    orig_qpf_file=os.path.join(bsp_qsf_dir, 'd5005.qpf')
    ocl_qpf_file=os.path.join(bsp_dir, 'd5005.qpf')
    #print ("copy %s  to %s" % (orig_qpf_file, ocl_qpf_file))
    shutil.copy2(orig_qpf_file, ocl_qpf_file)
    #print ("update qpf project for opencl flow of %s \n" % ocl_qpf_file)
    update_qpf_project_for_opencl_flow(ocl_qpf_file)

    # update quartus project files for opencl
    quartus_qpf_file=orig_qpf_file
    #print ("update qpf project for afu %s\n" % quartus_qpf_file)
    update_qpf_project_for_afu(quartus_qpf_file)
    
    #print ("update qsf settings for opencl afu %s \n" % iofs_pr_afu_qsf_file)
    update_qsf_settings_for_opencl_afu(iofs_pr_afu_qsf_file)

    #rename the iofs_pr_afu_qsf_file file to afu_flat.qsf. Up to this point we were using the iofs_pr_afu_qsf_file file from the platform build, now we need to move forward with appropriate OpenCL/HPR-naming
    afu_flat_qsf_path=os.path.join(bsp_qsf_dir, 'afu_flat.qsf')
    shutil.move(iofs_pr_afu_qsf_file,afu_flat_qsf_path)
    
    #write some stuff into afu_flat.qsf - this is to replace some lines in iofs_pr_afu_sources.tcl where the paths aren't correct
    with open(afu_flat_qsf_path, 'a') as f:
        f.write('set_global_assignment -name SEARCH_PATH "./platform"\n')
        f.write('set_global_assignment -name SOURCE_TCL_SCRIPT_FILE "./platform/ofs_plat_if/par/ofs_plat_if_addenda.qsf"\n')
        # Map FIM interfaces to the PIM
        f.write('set_global_assignment -name SYSTEMVERILOG_FILE "./src/port_gasket/stratix10/afu_main_pim/afu_main.sv"\n')

    #remove the hw folder; it isn't needed
    rel_template_hw_folder_path=os.path.join(bsp_qsf_dir, '../hw')
    shutil.rmtree(rel_template_hw_folder_path, ignore_errors=True)
    
    #remove the paths and files listed in the iofs_pr_afu_sources.tcl file
    iofs_pr_afu_source_tcl_file=os.path.join(bsp_qsf_dir, 'iofs_pr_afu_sources.tcl')
    #this still needs to be done in order to eliminate Quartus warnings
    replace_lines_in_file(iofs_pr_afu_source_tcl_file, 'set_global_assignment -name SOURCE_TCL_SCRIPT_FILE "../../', '#set_global_assignment -name SOURCE_TCL_SCRIPT_FILE "../../')
    #replace_lines_in_file(afu_flat_qsf_path, 'set_global_assignment -name SOURCE_TCL_SCRIPT_FILE ../setup/suppress_warning.tcl', '#set_global_assignment -name SOURCE_TCL_SCRIPT_FILE ../setup/suppress_warning.tcl')
    replace_lines_in_file(iofs_pr_afu_source_tcl_file, 'set FIM_SCRIPT_DIR "../setup"', 'set FIM_SCRIPT_DIR "./syn/setup"')
    #hierarchy is different
    replace_lines_in_file(iofs_pr_afu_source_tcl_file, '"../../..', '".')
    
    #update the build_env_db.txt file with the appropriate BUILD_ROOT_REL path
    build_env_db_path=os.path.join(bsp_qsf_dir, 'build_env_db.txt')
    remove_lines_in_file(build_env_db_path, 'BUILD_ROOT_REL=')
    with open(build_env_db_path, 'a') as f:
        f.write('BUILD_ROOT_REL=../build')
    #move the syn/*/setup/ folder
    config_env_file_path=get_file_path("config_env.tcl", bsp_qsf_dir)
    copy_glob(config_env_file_path,bsp_qsf_dir)
    
    replace_lines_in_file(afu_flat_qsf_path, 'set_global_assignment -name SOURCE_TCL_SCRIPT_FILE ../setup/config_env.tcl', 'set_global_assignment -name SOURCE_TCL_SCRIPT_FILE ./config_env.tcl')
    
    #remove user/kernel-clock constraints from d5005.out.sdc - use the constraints from user_clk.sdc
    FIM_sdc_file=os.path.join(bsp_qsf_dir, 'd5005.out.sdc')
    remove_lines_in_file(FIM_sdc_file,"create_generated_clock -name {afu_top|port_gasket|user_clock|qph_user_clk|qph_user_clk_iopll|iopll_0")
    
    # create manifest
    create_manifest(bsp_dir)


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


# replace search_text with replace_text in file
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
        f.write('PROJECT_REVISION = "d5005"\n')

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
        f.write('PROJECT_REVISION = "d5005"\n')

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
