# Stage 2N-A13: package the cycle-counter automatic DLRM pipeline as a
# user-managed Vitis RTL kernel for the Inspur F37X platform.
#
# This script creates only an XO and generated kernel.xml. It does not link an
# xclbin, run implementation, access a device, program an FPGA, or reset one.

set script_path [file normalize [info script]]
set script_dir [file dirname $script_path]
set root_dir [file normalize [file join $script_dir ..]]

set build_dir [file join $root_dir build stage2n_a13 xo_v1]
set project_dir [file join $build_dir vivado_project]
set ip_dir [file join $build_dir dlrm_f37x_stage2n_a13_ip_v1]
set top_name "dlrm_f37x_rtl_kernel_stage2n_a13_v1"
set part_name "xcvu37p-fsvh2892-2L-e"
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

set rtl_files [list \
    [source_path $root_dir rtl/common/rv_fifo.sv] \
    [source_path $root_dir rtl/common/runtime_relu_quant.sv] \
    [source_path $root_dir rtl/compute/mac_lane.sv] \
    [source_path $root_dir rtl/memory/banked_activation_buffer.sv] \
    [source_path $root_dir rtl/memory/local_weight_provider.sv] \
    [source_path $root_dir rtl/compute/vector_dot_product_core.sv] \
    [source_path $root_dir rtl/compute/dense_layer_engine.sv] \
    [source_path $root_dir rtl/control/mlp_sequence_controller.sv] \
    [source_path $root_dir rtl/top/dlrm_f37x_rtl_kernel.sv] \
    [source_path $root_dir rtl/interaction/dlrm_feature_interaction_engine.sv] \
    [source_path $root_dir rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a2.sv] \
    [source_path $root_dir rtl/control/mlp_sequence_controller_segmented.sv] \
    [source_path $root_dir rtl/pipeline/dlrm_internal_pipeline_controller.sv] \
    [source_path $root_dir rtl/pipeline/dlrm_internal_pipeline_controller_stage2n_a13_v1.sv] \
    [source_path $root_dir rtl/f37x/dlrm_internal_pipeline_axi_lite_adapter_stage2n_a13_v1.sv] \
    [source_path $root_dir rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a13_v1.sv] \
]

if {[file exists $build_dir]} {
    fail "Refusing to overwrite existing A13 XO build directory: $build_dir"
}
file mkdir $build_dir

puts "============================================================"
puts "Stage 2N-A13 F37X RTL-kernel XO packaging"
puts "ROOT=$root_dir"
puts "PART=$part_name"
puts "KERNEL=$top_name"
puts "XO=$xo_path"
puts "KERNEL_XML=$xml_path"
puts "CONTROL_INTERFACE=AXI4-Lite"
puts "M_AXI_PORT_COUNT=0"
puts "NO_XCLBIN_LINK=1"
puts "NO_FPGA_ACCESS=1"
puts "============================================================"

if {[llength [get_parts -quiet $part_name]] == 0} {
    fail "Vivado part is unavailable: $part_name"
}

create_project dlrm_f37x_stage2n_a13_package_v1 $project_dir \
    -part $part_name -force
set_property target_language Verilog [current_project]
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
    {F37X DLRM Automatic Pipeline RTL Kernel with Cycle Counters} $core
set_property description \
    {Stage 2N-A13 user-managed AXI4-Lite DLRM kernel preserving A10 v2 behavior and adding four read-only phase and total cycle counters} $core
set_property version 2.13 $core

ipx::infer_bus_interface ap_clk xilinx.com:signal:clock_rtl:1.0 $core
ipx::infer_bus_interface ap_rst_n xilinx.com:signal:reset_rtl:1.0 $core
ipx::associate_bus_interfaces -busif s_axi_control -clock ap_clk $core
ipx::associate_bus_interfaces -clock ap_clk -reset ap_rst_n $core

set memory_map [ipx::get_memory_maps s_axi_control -of_objects $core]
if {[llength $memory_map] == 0} {
    fail "Cannot find AXI4-Lite memory map s_axi_control"
}
set address_blocks [ipx::get_address_blocks -of_objects $memory_map]
if {[llength $address_blocks] == 0} {
    fail "Cannot find AXI4-Lite address block"
}
set address_block [lindex $address_blocks 0]

proc add_control_register {address_block name offset access description} {
    ipx::add_register $name $address_block
    set reg [ipx::get_registers $name -of_objects $address_block]
    set_property address_offset $offset $reg
    set_property size 32 $reg
    set_property access $access $reg
    set_property description $description $reg
}

# Keep the complete A10 v2 ABI and append only the four A13 read-only counters.
set register_specs {
    {CONTROL_STATUS 0x000 read-write {Legacy MLP command and status}}
    {VERSION 0x004 read-only {Legacy MLP interface version}}
    {RESULT_COUNT 0x008 read-only {Legacy MLP accepted-result count}}
    {LAYER_COUNT 0x010 read-write {Legacy MLP layer count}}
    {INITIAL_BUFFER 0x014 read-write {Legacy MLP initial activation buffer}}
    {DESC_INDEX 0x020 read-write {Legacy MLP descriptor index}}
    {DESC_WORD0 0x024 read-write {Legacy descriptor bits 31 to 0}}
    {DESC_WORD1 0x028 read-write {Legacy descriptor bits 63 to 32}}
    {DESC_WORD2 0x02C read-write {Legacy descriptor bits 95 to 64}}
    {ACT_BUFFER 0x040 read-write {Legacy activation buffer selector}}
    {ACT_CHUNK_INDEX 0x044 read-write {Legacy activation chunk index}}
    {ACT_LANE_MASK 0x048 read-write {Legacy activation lane-valid mask}}
    {ACT_DATA0 0x050 read-write {Legacy activation payload word 0}}
    {ACT_DATA1 0x054 read-write {Legacy activation payload word 1}}
    {ACT_DATA2 0x058 read-write {Legacy activation payload word 2}}
    {ACT_DATA3 0x05C read-write {Legacy activation payload word 3}}
    {ACT_DATA4 0x060 read-write {Legacy activation payload word 4}}
    {ACT_DATA5 0x064 read-write {Legacy activation payload word 5}}
    {ACT_DATA6 0x068 read-write {Legacy activation payload word 6}}
    {ACT_DATA7 0x06C read-write {Legacy activation payload word 7}}
    {WEIGHT_ADDRESS 0x080 read-write {Legacy weight-memory address}}
    {WEIGHT_DATA 0x084 read-write {Legacy signed INT8 weight}}
    {BIAS_ADDRESS 0x090 read-write {Legacy bias-memory address}}
    {BIAS_DATA 0x094 read-write {Legacy signed INT24 bias}}
    {RESULT_DATA 0x0A0 read-only {Legacy sign-extended result}}
    {RESULT_INDEX 0x0A4 read-only {Legacy result index}}
    {RESULT_META 0x0A8 read-only {Legacy result metadata}}
    {INT_CONTROL_STATUS 0x100 read-write {Standalone interaction command and status}}
    {INT_VERSION 0x104 read-only {Standalone interaction interface version}}
    {INT_RESULT_COUNT 0x108 read-only {Standalone interaction result count}}
    {INT_SHIFT 0x10C read-write {Standalone interaction output shift}}
    {INT_VECTOR_INDEX 0x110 read-write {Standalone feature-vector index}}
    {INT_VECTOR_DATA0 0x114 read-write {Standalone vector elements 0 and 1}}
    {INT_VECTOR_DATA1 0x118 read-write {Standalone vector elements 2 and 3}}
    {INT_VECTOR_DATA2 0x11C read-write {Standalone vector elements 4 and 5}}
    {INT_VECTOR_DATA3 0x120 read-write {Standalone vector elements 6 and 7}}
    {INT_RESULT_DATA 0x124 read-only {Standalone interaction result}}
    {INT_RESULT_INDEX 0x128 read-only {Standalone interaction result index}}
    {INT_RESULT_META 0x12C read-only {Standalone interaction result metadata}}
    {INT_LOADED_MASK 0x130 read-only {Standalone loaded-vector mask}}
    {PIPE_CONTROL_STATUS 0x180 read-write {Automatic pipeline commands and status}}
    {PIPE_VERSION 0x184 read-only {Stage 2N-A13 pipeline interface version}}
    {PIPE_RESULT_COUNT 0x188 read-only {Consumed final-result count}}
    {PIPE_PHASE_COUNTS 0x18C read-only {Pipeline phase and result counts}}
    {PIPE_DESC_INDEX 0x190 read-write {Pipeline descriptor staging index}}
    {PIPE_DESC_WORD0 0x194 read-write {Pipeline descriptor bits 31 to 0}}
    {PIPE_DESC_WORD1 0x198 read-write {Pipeline descriptor bits 63 to 32}}
    {PIPE_DESC_WORD2 0x19C read-write {Pipeline descriptor bits 95 to 64}}
    {PIPE_ACT_BUFFER 0x1A0 read-write {Pipeline activation buffer selector}}
    {PIPE_ACT_CHUNK_INDEX 0x1A4 read-write {Pipeline activation chunk index}}
    {PIPE_ACT_LANE_MASK 0x1A8 read-write {Pipeline activation lane-valid mask}}
    {PIPE_ACT_DATA0 0x1B0 read-write {Pipeline activation payload word 0}}
    {PIPE_ACT_DATA1 0x1B4 read-write {Pipeline activation payload word 1}}
    {PIPE_ACT_DATA2 0x1B8 read-write {Pipeline activation payload word 2}}
    {PIPE_ACT_DATA3 0x1BC read-write {Pipeline activation payload word 3}}
    {PIPE_ACT_DATA4 0x1C0 read-write {Pipeline activation payload word 4}}
    {PIPE_ACT_DATA5 0x1C4 read-write {Pipeline activation payload word 5}}
    {PIPE_ACT_DATA6 0x1C8 read-write {Pipeline activation payload word 6}}
    {PIPE_ACT_DATA7 0x1CC read-write {Pipeline activation payload word 7}}
    {PIPE_EMB_INDEX 0x1D0 read-write {Pipeline embedding index}}
    {PIPE_EMB_DATA0 0x1D4 read-write {Pipeline embedding payload word 0}}
    {PIPE_EMB_DATA1 0x1D8 read-write {Pipeline embedding payload word 1}}
    {PIPE_EMB_DATA2 0x1DC read-write {Pipeline embedding payload word 2}}
    {PIPE_EMB_DATA3 0x1E0 read-write {Pipeline embedding payload word 3}}
    {PIPE_WEIGHT_ADDRESS 0x1E4 read-write {Pipeline shared-weight address}}
    {PIPE_WEIGHT_DATA 0x1E8 read-write {Pipeline signed INT8 weight}}
    {PIPE_BIAS_ADDRESS 0x1EC read-write {Pipeline shared-bias address}}
    {PIPE_BIAS_DATA 0x1F0 read-write {Pipeline signed INT24 bias}}
    {PIPE_BOTTOM_CONFIG 0x1F4 read-write {Bottom descriptor configuration}}
    {PIPE_TOP_CONFIG 0x1F8 read-write {Top descriptor configuration}}
    {PIPELINE_CONFIG 0x1FC read-write {Feature-interaction shift configuration}}
    {PIPE_RESULT_DATA 0x200 read-only {Sign-extended final Top result}}
    {PIPE_RESULT_INDEX 0x204 read-only {Final result index}}
    {PIPE_RESULT_META 0x208 read-only {Final result valid last index and tag}}
    {PIPE_EMB_LOADED_MASK 0x20C read-only {Loaded pipeline embedding mask}}
    {PIPE_ERROR_CODE 0x210 read-only {Core and wrapper error code}}
    {PIPE_CONFIG_READY 0x214 read-only {Pipeline configuration ready bits}}
    {PIPE_BOTTOM_CYCLES 0x218 read-only {Most recent Bottom phase cycles}}
    {PIPE_INTERACTION_CYCLES 0x21C read-only {Most recent interaction phase cycles}}
    {PIPE_TOP_CYCLES 0x220 read-only {Most recent Top phase cycles}}
    {PIPE_TOTAL_CYCLES 0x224 read-only {START through final-result visibility cycles}}
}

foreach spec $register_specs {
    lassign $spec name offset access description
    add_control_register $address_block $name $offset $access $description
}

if {[llength $register_specs] != 81} {
    fail "Internal register specification count is not 81"
}

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
puts "A13_XO_BUILD=PASS"
puts "KERNEL_XML_SOURCE=GENERATED_BY_PACKAGE_XO"
puts "COMPONENT_XML_REGISTER_COUNT_EXPECTED=81"
puts "KERNEL_XML_ARGUMENT_COUNT_EXPECTED=78"
puts "XO=$xo_path"
puts "KERNEL_XML=$xml_path"
puts "NO_FPGA_ACCESS=1"
puts "============================================================"

close_project
