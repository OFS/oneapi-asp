# Copyright 2020 Intel Corporation.
#
# THIS SOFTWARE MAY CONTAIN PREPRODUCTION CODE AND IS PROVIDED BY THE
# COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
# BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
# OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
# EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

#imports/links opencl compiler generated files into build directory

proc get_list_from_file {fname} {
    set f [open $fname r]
    set data [split [string trim [read $f]]]
    close $f
    return $data
}

set bsp_filelist [get_list_from_file ../bsp_dir_filelist.txt]

proc copy_dir {src_dir dst_dir} {
	#puts "copy_dir: $src_dir $dst_dir"
	set glob_src_path [file join $src_dir *]
	foreach i [glob -nocomplain $glob_src_path] {
		set dst_path [file join $dst_dir [file tail $i]]
		if [file isdirectory $dst_path] {
			copy_dir $i $dst_path
		} else {
			file copy -force $i $dst_path
		}
	}
}

foreach i [glob -nocomplain ../*] {
	set basefile [file tail $i]
	if {[lsearch -exact $bsp_filelist $basefile] == -1} {
		if [file isdirectory $i] {
			#puts "copy_dir $i $basefile"
			if { ![file exists $basefile] } {
				file mkdir $basefile
			}
			copy_dir $i $basefile
		} else {
			if {[file exists $basefile]} {
				file delete -force $basefile
			}
			
			file link -symbolic $basefile $i
		}
		#puts "importing: $i"
	}
}

