# Stage 2N-A14.4-A: package the standalone A14 HBM lookup wrapper as a
# user-managed Vitis RTL kernel.
#
# This script creates only an XO, kernel.xml, and IP-packager metadata. It does
# not invoke v++, link an xclbin, bind a physical HBM bank, access a device,
# program an FPGA, or modify any RTL source.

set script_path [file normalize [info script]]
set script_dir [file dirname $script_path]
set root_dir [file normalize [file join $script_dir ..]]

set build_dir [file join $root_dir build stage2n_a14 xo_v1]
set project_dir [file join $build_dir vivado_project]
set ip_dir [file join $build_dir dlrm_f37x_stage2n_a14_ip_v1]
set top_name "dlrm_f37x_rtl_kernel_stage2n_a14_v1"
set target_part_name "xcvu37p-fsvh2892-2L-e"
set part_name $target_part_name
if {$argc > 1} {
    error "Usage: vivado -source package_stage2n_a14_rtl_kernel_v1.tcl ?packaging_part?"
}
if {$argc == 1} {
    set part_name [lindex $argv 0]
}
set target_part_used [expr {$part_name eq $target_part_name}]
set xo_path [file join $build_dir ${top_name}.xo]
set xml_path [file join $build_dir kernel.xml]

proc fail {message} {
    error $message
}

proc source_path {root_dir relative_path} {
    set resolved [file normalize [file join $root_dir $relative_path]]
    if {![file isfile $resolved]} {
        fail "Missing required RTL source: $relative_path"
    }
    return $resolved
}

proc require_bus_interface {core bus_name expected_mode} {
    set interfaces [ipx::get_bus_interfaces $bus_name -of_objects $core]
    if {[llength $interfaces] != 1} {
        fail "Expected one $bus_name interface, found [llength $interfaces]"
    }

    set interface [lindex $interfaces 0]
    set actual_mode [get_property interface_mode $interface]
    if {$actual_mode ne $expected_mode} {
        fail "$bus_name mode is $actual_mode, expected $expected_mode"
    }
    return $interface
}

proc add_control_register {address_block name offset access description} {
    ipx::add_register $name $address_block
    set reg [ipx::get_registers $name -of_objects $address_block]
    set_property address_offset $offset $reg
    set_property size 32 $reg
    set_property access $access $reg
    set_property description $description $reg
}

set rtl_files [list \
    [source_path $root_dir \
        rtl/hbm/dlrm_hbm_embedding_lookup_stage2n_a14_v1.sv] \
    [source_path $root_dir \
        rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a14_v1.sv] \
]

puts "============================================================"
puts "Stage 2N-A14.4-A F37X RTL-kernel XO packaging"
puts "ROOT=$root_dir"
puts "TARGET_PART=$target_part_name"
puts "PACKAGING_PART=$part_name"
puts "TARGET_PART_USED=$target_part_used"
puts "KERNEL=$top_name"
puts "CONTROL_INTERFACE=s_axi_control"
puts "MEMORY_INTERFACE=m_axi_gmem"
puts "M_AXI_DATA_WIDTH=128"
puts "M_AXI_OUTSTANDING_READS=1"
puts "M_AXI_BURST_OPTIMIZATION=0"
puts "XO=$xo_path"
puts "KERNEL_XML=$xml_path"
puts "NO_VPP_LINK=1"
puts "NO_XCLBIN=1"
puts "NO_PHYSICAL_HBM_BINDING=1"
puts "NO_FPGA_ACCESS=1"
puts "============================================================"

if {[llength [get_parts -quiet $part_name]] == 0} {
    fail "Vivado part is unavailable: $part_name"
}

if {[file exists $build_dir]} {
    fail "Refusing to overwrite existing A14 XO build directory: $build_dir"
}
file mkdir $build_dir

create_project dlrm_f37x_stage2n_a14_package_v1 $project_dir \
    -part $part_name -force
set_property target_language Verilog [current_project]
add_files -norecurse $rtl_files
set_property top $top_name [current_fileset]
update_compile_order -fileset sources_1

if {[get_property top [current_fileset]] ne $top_name} {
    fail "Unexpected project top after source import"
}

ipx::package_project \
    -root_dir $ip_dir \
    -vendor user.org \
    -library user \
    -taxonomy /UserIP \
    -import_files \
    -set_current true

set core [ipx::current_core]
set_property name $top_name $core
set_property display_name \
    {F37X A14 Single-Bank HBM Embedding Lookup RTL Kernel} $core
set_property description \
    {Stage 2N-A14 user-managed AXI4-Lite wrapper with one logical 128-bit m_axi_gmem read interface and a standalone embedding lookup IP} \
    $core
set_property version 2.14 $core

ipx::infer_bus_interface ap_clk xilinx.com:signal:clock_rtl:1.0 $core
ipx::infer_bus_interface ap_rst_n xilinx.com:signal:reset_rtl:1.0 $core

set s_axi_control [require_bus_interface $core s_axi_control slave]
set m_axi_gmem [require_bus_interface $core m_axi_gmem master]

ipx::associate_bus_interfaces \
    -busif s_axi_control -clock ap_clk $core
ipx::associate_bus_interfaces \
    -busif m_axi_gmem -clock ap_clk $core
ipx::associate_bus_interfaces \
    -clock ap_clk -reset ap_rst_n $core

set memory_maps [ipx::get_memory_maps s_axi_control -of_objects $core]
if {[llength $memory_maps] != 1} {
    fail "Expected one AXI4-Lite memory map, found [llength $memory_maps]"
}
set address_blocks [ipx::get_address_blocks \
    -of_objects [lindex $memory_maps 0]]
if {[llength $address_blocks] != 1} {
    fail "Expected one AXI4-Lite address block, found [llength $address_blocks]"
}
set address_block [lindex $address_blocks 0]

set register_specs {
    {CONTROL 0x000 read-write {Write START bit and read pending done idle ready and error status}}
    {LOOKUP_INDEX 0x010 read-write {Embedding row index}}
    {RESULT0 0x020 read-only {Embedding lanes 0 and 1}}
    {RESULT1 0x024 read-only {Embedding lanes 2 and 3}}
    {RESULT2 0x028 read-only {Embedding lanes 4 and 5}}
    {RESULT3 0x02C read-only {Embedding lanes 6 and 7}}
}

foreach spec $register_specs {
    lassign $spec name offset access description
    add_control_register \
        $address_block $name $offset $access $description
}

if {[llength $register_specs] != 6} {
    fail "Internal A14 register specification count is not six"
}

set_property sdx_kernel true $core
set_property sdx_kernel_type rtl $core
ipx::update_checksums $core
ipx::check_integrity -quiet $core
ipx::update_source_project_archive -component $core
ipx::save_core $core

package_xo \
    -force \
    -xo_path $xo_path \
    -kernel_name $top_name \
    -ctrl_protocol user_managed \
    -ip_directory $ip_dir \
    -output_kernel_xml $xml_path

if {![file isfile $xo_path] || [file size $xo_path] == 0} {
    fail "XO was not generated or is empty: $xo_path"
}
if {![file isfile $xml_path] || [file size $xml_path] == 0} {
    fail "kernel.xml was not generated or is empty: $xml_path"
}

set xml_file [open $xml_path r]
set xml_text [read $xml_file]
close $xml_file
if {[string first {name="s_axi_control"} $xml_text] < 0} {
    fail "kernel.xml does not contain s_axi_control"
}
if {[string first {name="m_axi_gmem"} $xml_text] < 0} {
    fail "kernel.xml does not contain m_axi_gmem"
}

puts "============================================================"
puts "STAGE2N_A14_4_A_XO_PACKAGE=PASS"
puts "KERNEL=$top_name"
puts "TARGET_PART=$target_part_name"
puts "PACKAGING_PART=$part_name"
puts "TARGET_PART_USED=$target_part_used"
puts "CONTROL_INTERFACE=s_axi_control"
puts "MEMORY_INTERFACE=m_axi_gmem"
puts "REGISTER_COUNT=6"
puts "XO=$xo_path"
puts "XO_SIZE_BYTES=[file size $xo_path]"
puts "KERNEL_XML=$xml_path"
puts "NO_VPP_LINK=1"
puts "NO_XCLBIN=1"
puts "NO_PHYSICAL_HBM_BINDING=1"
puts "NO_FPGA_ACCESS=1"
puts "============================================================"

close_project
