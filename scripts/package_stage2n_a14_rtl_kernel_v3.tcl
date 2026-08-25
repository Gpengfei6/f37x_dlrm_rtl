# Stage 2N-A14.5: package the runtime-table-base wrapper as a user-managed
# Vitis RTL kernel.  TABLE_BASE is a 64-bit global-memory argument associated
# with m_axi_gmem; this is the reviewed ABI needed for a future XRT BO address.
#
# This script packages XO metadata only.  It does not invoke v++, bind HBM,
# generate an xclbin, access a device, program an FPGA, or overwrite A14 v1/v2
# build artifacts.

set script_path [file normalize [info script]]
set script_dir [file dirname $script_path]
set root_dir [file normalize [file join $script_dir ..]]

set build_dir [file join $root_dir build stage2n_a14 xo_v2]
set project_dir [file join $build_dir vivado_project]
set ip_dir [file join $build_dir dlrm_f37x_stage2n_a14_ip_v2]
set top_name "dlrm_f37x_rtl_kernel_stage2n_a14_v2"
set target_part_name "xcvu37p-fsvh2892-2L-e"
set part_name $target_part_name
if {$argc > 1} {
    error "Usage: vivado -source package_stage2n_a14_rtl_kernel_v3.tcl ?packaging_part?"
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

proc set_required_bus_parameter {interface name expected_value} {
    set parameters [ipx::get_bus_parameters $name -of_objects $interface]
    if {[llength $parameters] == 0} {
        ipx::add_bus_parameter $name $interface
        set parameters [ipx::get_bus_parameters $name -of_objects $interface]
    }
    if {[llength $parameters] != 1} {
        fail "Expected one $name bus parameter, found [llength $parameters]"
    }

    set parameter [lindex $parameters 0]
    set_property value $expected_value $parameter
    set actual_value [get_property value $parameter]
    if {$actual_value ne $expected_value} {
        fail "$name bus parameter is $actual_value, expected $expected_value"
    }
}

proc add_control_register {
    address_block name offset size access description
} {
    ipx::add_register $name $address_block
    set reg [ipx::get_registers $name -of_objects $address_block]
    set_property address_offset $offset $reg
    set_property size $size $reg
    set_property access $access $reg
    set_property description $description $reg
    return $reg
}

proc associate_register_with_bus {reg bus_name} {
    set parameters [ipx::get_register_parameters ASSOCIATED_BUSIF \
        -of_objects $reg]
    if {[llength $parameters] == 0} {
        ipx::add_register_parameter ASSOCIATED_BUSIF $reg
        set parameters [ipx::get_register_parameters ASSOCIATED_BUSIF \
            -of_objects $reg]
    }
    if {[llength $parameters] != 1} {
        fail "Expected one ASSOCIATED_BUSIF register parameter"
    }
    set parameter [lindex $parameters 0]
    set_property value $bus_name $parameter
    if {[get_property value $parameter] ne $bus_name} {
        fail "TABLE_BASE is not associated with $bus_name"
    }
}

set rtl_files [list \
    [source_path $root_dir \
        rtl/hbm/dlrm_hbm_embedding_lookup_stage2n_a14_v2.sv] \
    [source_path $root_dir \
        rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a14_v2.sv] \
]

puts "============================================================"
puts "Stage 2N-A14.5 F37X runtime-table-base XO packaging"
puts "ROOT=$root_dir"
puts "TARGET_PART=$target_part_name"
puts "PACKAGING_PART=$part_name"
puts "TARGET_PART_USED=$target_part_used"
puts "KERNEL=$top_name"
puts "CONTROL_INTERFACE=s_axi_control"
puts "MEMORY_INTERFACE=m_axi_gmem"
puts "M_AXI_DATA_WIDTH=128"
puts "M_AXI_ADDR_WIDTH=64"
puts "TABLE_BASE_OFFSET=0x018"
puts "TABLE_BASE_WIDTH=64"
puts "TABLE_BASE_ASSOCIATED_BUSIF=m_axi_gmem"
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
    fail "Refusing to overwrite existing A14.5 XO build directory: $build_dir"
}
file mkdir $build_dir

create_project dlrm_f37x_stage2n_a14_package_v3 $project_dir \
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
    {F37X A14.5 HBM Embedding Lookup RTL Kernel with Runtime Table Base} \
    $core
set_property description \
    {Stage 2N-A14.5 user-managed wrapper with a 64-bit TABLE_BASE global-memory argument and one logical 128-bit m_axi_gmem read interface} \
    $core
set_property version 2.15 $core

ipx::infer_bus_interface ap_clk xilinx.com:signal:clock_rtl:1.0 $core
ipx::infer_bus_interface ap_rst_n xilinx.com:signal:reset_rtl:1.0 $core

set s_axi_control [require_bus_interface $core s_axi_control slave]
set m_axi_gmem [require_bus_interface $core m_axi_gmem master]

set_required_bus_parameter $m_axi_gmem DATA_WIDTH 128
set_required_bus_parameter $m_axi_gmem ADDR_WIDTH 64

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
    {CONTROL 0x000 32 read-write {Write START bit and read pending done idle ready and error status}}
    {LOOKUP_INDEX 0x010 32 read-write {Embedding row index}}
    {TABLE_BASE 0x018 64 read-write {64-bit byte address of the first embedding-table row}}
    {RESULT0 0x020 32 read-only {Embedding lanes 0 and 1}}
    {RESULT1 0x024 32 read-only {Embedding lanes 2 and 3}}
    {RESULT2 0x028 32 read-only {Embedding lanes 4 and 5}}
    {RESULT3 0x02C 32 read-only {Embedding lanes 6 and 7}}
}

set table_base_register ""
foreach spec $register_specs {
    lassign $spec name offset size access description
    set reg [add_control_register \
        $address_block $name $offset $size $access $description]
    if {$name eq "TABLE_BASE"} {
        set table_base_register $reg
    }
}

if {[llength $register_specs] != 7} {
    fail "Internal A14.5 register specification count is not seven"
}
if {$table_base_register eq ""} {
    fail "TABLE_BASE register was not created"
}
associate_register_with_bus $table_base_register m_axi_gmem

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
foreach required_fragment [list \
    {name="s_axi_control"} \
    {name="m_axi_gmem"} \
    {dataWidth="128"} \
    {name="TABLE_BASE"} \
    {addressQualifier="1"} \
    {port="m_axi_gmem"} \
    {size="0x8"} \
    {offset="0x18"} \
] {
    if {[string first $required_fragment $xml_text] < 0} {
        fail "kernel.xml does not contain required fragment: $required_fragment"
    }
}
if {[string first {range="0xFFFFFFFFFFFFFFFF"} $xml_text] < 0 &&
    [string first {range="0xffffffffffffffff"} $xml_text] < 0} {
    fail "kernel.xml does not record the 64-bit AXI master address range"
}

puts "============================================================"
puts "STAGE2N_A14_5_TABLE_BASE_XO_PACKAGE=PASS"
puts "KERNEL=$top_name"
puts "TARGET_PART=$target_part_name"
puts "PACKAGING_PART=$part_name"
puts "TARGET_PART_USED=$target_part_used"
puts "CONTROL_INTERFACE=s_axi_control"
puts "MEMORY_INTERFACE=m_axi_gmem"
puts "M_AXI_DATA_WIDTH=128"
puts "M_AXI_ADDR_WIDTH=64"
puts "TABLE_BASE_OFFSET=0x018"
puts "TABLE_BASE_WIDTH=64"
puts "TABLE_BASE_ADDRESS_QUALIFIER=1"
puts "TABLE_BASE_ASSOCIATED_BUSIF=m_axi_gmem"
puts "REGISTER_COUNT=7"
puts "XO=$xo_path"
puts "XO_SIZE_BYTES=[file size $xo_path]"
puts "KERNEL_XML=$xml_path"
puts "NO_VPP_LINK=1"
puts "NO_XCLBIN=1"
puts "NO_PHYSICAL_HBM_BINDING=1"
puts "NO_FPGA_ACCESS=1"
puts "============================================================"

close_project
