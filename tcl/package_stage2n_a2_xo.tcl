# Stage 2N-A2: package the integrated MLP + feature-interaction top
# as a new user-managed Vitis RTL kernel.
#
# Existing Stage 2G/2M package scripts and top modules are not replaced.

set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]

set build_dir [file join $root_dir build stage2n_a2 package]
set project_dir [file join $build_dir vivado_project]
set ip_dir [file join $build_dir dlrm_f37x_stage2n_a2_ip]
set xo_path [file join $build_dir dlrm_f37x_rtl_kernel_stage2n_a2.xo]
set xml_path [file join $build_dir kernel.xml]

set part_name "xcvu37p-fsvh2892-2L-e"
set top_name "dlrm_f37x_rtl_kernel_stage2n_a2"

file delete -force $build_dir
file mkdir $build_dir

puts "============================================================"
puts "Stage 2N-A2 F37X integrated RTL-kernel packaging"
puts "Root : $root_dir"
puts "Part : $part_name"
puts "Top  : $top_name"
puts "XO   : $xo_path"
puts "============================================================"

if {[llength [get_parts -quiet $part_name]] == 0} {
    error "Vivado part is unavailable: $part_name"
}

create_project dlrm_f37x_stage2n_a2_package $project_dir \
    -part $part_name \
    -force

set_property target_language Verilog [current_project]

set rtl_files [list \
    [file join $root_dir rtl common rv_fifo.sv] \
    [file join $root_dir rtl common runtime_relu_quant.sv] \
    [file join $root_dir rtl compute mac_lane.sv] \
    [file join $root_dir rtl memory banked_activation_buffer.sv] \
    [file join $root_dir rtl memory local_weight_provider.sv] \
    [file join $root_dir rtl compute vector_dot_product_core.sv] \
    [file join $root_dir rtl compute dense_layer_engine.sv] \
    [file join $root_dir rtl control mlp_sequence_controller.sv] \
    [file join $root_dir rtl f37x dlrm_f37x_rtl_kernel.sv] \
    [file join $root_dir rtl interaction dlrm_feature_interaction_engine.sv] \
    [file join $root_dir rtl f37x dlrm_f37x_rtl_kernel_stage2n_a2.sv] \
]

foreach rtl_file $rtl_files {
    if {![file exists $rtl_file]} {
        error "Missing RTL source: $rtl_file"
    }
}

add_files -norecurse $rtl_files
set_property top $top_name [current_fileset]
update_compile_order -fileset sources_1

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
    {F37X DLRM MLP and Feature Interaction RTL Kernel} \
    $core
set_property description \
    {Stage 2N-A2 user-managed AXI4-Lite kernel preserving the verified MLP window and adding an independent DLRM feature-interaction engine} \
    $core
set_property version 2.2 $core

ipx::infer_bus_interface ap_clk \
    xilinx.com:signal:clock_rtl:1.0 $core

ipx::infer_bus_interface ap_rst_n \
    xilinx.com:signal:reset_rtl:1.0 $core

ipx::associate_bus_interfaces \
    -busif s_axi_control \
    -clock ap_clk \
    $core

ipx::associate_bus_interfaces \
    -clock ap_clk \
    -reset ap_rst_n \
    $core

set memory_map [
    ipx::get_memory_maps s_axi_control -of_objects $core
]

if {[llength $memory_map] == 0} {
    error "Cannot find AXI4-Lite memory map: s_axi_control"
}

set address_blocks [
    ipx::get_address_blocks -of_objects $memory_map
]

if {[llength $address_blocks] == 0} {
    error "Cannot find AXI4-Lite address block"
}

set address_block [lindex $address_blocks 0]

proc add_control_register {
    address_block name offset access description
} {
    ipx::add_register $name $address_block
    set reg [
        ipx::get_registers $name -of_objects $address_block
    ]
    set_property address_offset $offset $reg
    set_property size 32 $reg
    set_property access $access $reg
    set_property description $description $reg
}

# Preserved legacy MLP register window.
add_control_register $address_block CONTROL_STATUS 0x000 read-write \
    {Legacy MLP command and status register}
add_control_register $address_block VERSION 0x004 read-only \
    {Legacy MLP interface version}
add_control_register $address_block RESULT_COUNT 0x008 read-only \
    {Legacy MLP accepted-result count}
add_control_register $address_block LAYER_COUNT 0x010 read-write \
    {Legacy MLP layer count}
add_control_register $address_block INITIAL_BUFFER 0x014 read-write \
    {Legacy MLP initial activation-buffer selector}
add_control_register $address_block DESC_INDEX 0x020 read-write \
    {Legacy MLP descriptor index}
add_control_register $address_block DESC_WORD0 0x024 read-write \
    {Legacy MLP descriptor bits 31 to 0}
add_control_register $address_block DESC_WORD1 0x028 read-write \
    {Legacy MLP descriptor bits 63 to 32}
add_control_register $address_block DESC_WORD2 0x02C read-write \
    {Legacy MLP descriptor bits 95 to 64}
add_control_register $address_block ACT_BUFFER 0x040 read-write \
    {Legacy MLP activation-buffer selector}
add_control_register $address_block ACT_CHUNK_INDEX 0x044 read-write \
    {Legacy MLP activation chunk index}
add_control_register $address_block ACT_LANE_MASK 0x048 read-write \
    {Legacy MLP activation lane-valid mask}
add_control_register $address_block ACT_DATA0 0x050 read-write \
    {Legacy MLP activation payload 0}
add_control_register $address_block ACT_DATA1 0x054 read-write \
    {Legacy MLP activation payload 1}
add_control_register $address_block ACT_DATA2 0x058 read-write \
    {Legacy MLP activation payload 2}
add_control_register $address_block ACT_DATA3 0x05C read-write \
    {Legacy MLP activation payload 3}
add_control_register $address_block ACT_DATA4 0x060 read-write \
    {Legacy MLP activation payload 4}
add_control_register $address_block ACT_DATA5 0x064 read-write \
    {Legacy MLP activation payload 5}
add_control_register $address_block ACT_DATA6 0x068 read-write \
    {Legacy MLP activation payload 6}
add_control_register $address_block ACT_DATA7 0x06C read-write \
    {Legacy MLP activation payload 7}
add_control_register $address_block WEIGHT_ADDRESS 0x080 read-write \
    {Legacy MLP weight-memory address}
add_control_register $address_block WEIGHT_DATA 0x084 read-write \
    {Legacy MLP signed INT8 weight}
add_control_register $address_block BIAS_ADDRESS 0x090 read-write \
    {Legacy MLP bias-memory address}
add_control_register $address_block BIAS_DATA 0x094 read-write \
    {Legacy MLP signed INT24 bias}
add_control_register $address_block RESULT_DATA 0x0A0 read-only \
    {Legacy MLP sign-extended result}
add_control_register $address_block RESULT_INDEX 0x0A4 read-only \
    {Legacy MLP result index}
add_control_register $address_block RESULT_META 0x0A8 read-only \
    {Legacy MLP result metadata}

# New Stage 2N-A2 feature-interaction register window.
add_control_register $address_block INT_CONTROL_STATUS 0x100 read-write \
    {Feature-interaction command and status}
add_control_register $address_block INT_VERSION 0x104 read-only \
    {Stage 2N-A2 interaction interface version}
add_control_register $address_block INT_RESULT_COUNT 0x108 read-only \
    {Accepted feature-interaction result count}
add_control_register $address_block INT_SHIFT 0x10C read-write \
    {Feature-interaction output right shift}
add_control_register $address_block INT_VECTOR_INDEX 0x110 read-write \
    {Feature vector index from zero to four}
add_control_register $address_block INT_VECTOR_DATA0 0x114 read-write \
    {Signed INT16 vector elements zero and one}
add_control_register $address_block INT_VECTOR_DATA1 0x118 read-write \
    {Signed INT16 vector elements two and three}
add_control_register $address_block INT_VECTOR_DATA2 0x11C read-write \
    {Signed INT16 vector elements four and five}
add_control_register $address_block INT_VECTOR_DATA3 0x120 read-write \
    {Signed INT16 vector elements six and seven}
add_control_register $address_block INT_RESULT_DATA 0x124 read-only \
    {Sign-extended feature-interaction output}
add_control_register $address_block INT_RESULT_INDEX 0x128 read-only \
    {Feature-interaction output index from zero to seventeen}
add_control_register $address_block INT_RESULT_META 0x12C read-only \
    {Feature-interaction valid, last, and index metadata}
add_control_register $address_block INT_LOADED_MASK 0x130 read-only \
    {Loaded-vector mask for the five feature vectors}

set_property sdx_kernel true $core
set_property sdx_kernel_type rtl $core

ipx::update_source_project_archive -component $core
ipx::save_core $core

package_xo \
    -force \
    -xo_path $xo_path \
    -kernel_name $top_name \
    -ctrl_protocol user_managed \
    -ip_directory $ip_dir \
    -output_kernel_xml $xml_path

puts "============================================================"
puts "STAGE2N_A2_XO_PACKAGE_PASS"
puts "XO=$xo_path"
puts "KERNEL_XML=$xml_path"
puts "============================================================"

close_project
