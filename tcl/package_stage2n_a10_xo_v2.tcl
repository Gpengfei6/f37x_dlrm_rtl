# Stage 2N-A10 v2: package the capacity-expanded automatic DLRM pipeline
# as a user-managed Vitis RTL kernel for the Inspur F37X platform.
#
# This script only creates an XO and kernel.xml. It does not link an xclbin,
# program an FPGA, access a render node, or reset a board.

set script_path [file normalize [info script]]
set script_dir [file dirname $script_path]
set root_dir [file normalize [file join $script_dir ..]]

set build_dir [file join $root_dir build stage2n_a10 package_v2]
set project_dir [file join $build_dir vivado_project]
set ip_dir [file join $build_dir dlrm_f37x_stage2n_a10_ip_v2]
set xo_path [file join $build_dir dlrm_f37x_rtl_kernel_stage2n_a10_v2.xo]
set xml_path [file join $build_dir kernel.xml]

set part_name "xcvu37p-fsvh2892-2L-e"
set top_name "dlrm_f37x_rtl_kernel_stage2n_a10_v2"

proc fail {message} {
    error $message
}

proc find_tracked_unique {root_dir basename_value} {
    set old_dir [pwd]
    cd $root_dir

    if {[catch {exec git ls-files} tracked_files]} {
        cd $old_dir
        fail "Unable to enumerate tracked files with git ls-files"
    }

    cd $old_dir

    set matches [list]
    foreach tracked_file [split $tracked_files "\n"] {
        if {$tracked_file eq ""} {
            continue
        }
        if {[file tail $tracked_file] eq $basename_value} {
            lappend matches \
                [file normalize [file join $root_dir $tracked_file]]
        }
    }

    if {[llength $matches] != 1} {
        puts stderr "SOURCE_LOOKUP_BASENAME=$basename_value"
        puts stderr "SOURCE_LOOKUP_MATCH_COUNT=[llength $matches]"
        foreach match $matches {
            puts stderr "SOURCE_LOOKUP_MATCH=$match"
        }
        fail "Expected exactly one tracked source named $basename_value"
    }

    return [lindex $matches 0]
}

set source_rv_fifo \
    [find_tracked_unique $root_dir rv_fifo.sv]
set source_relu_quant \
    [find_tracked_unique $root_dir runtime_relu_quant.sv]
set source_mac_lane \
    [find_tracked_unique $root_dir mac_lane.sv]
set source_activation_buffer \
    [find_tracked_unique $root_dir banked_activation_buffer.sv]
set source_weight_provider \
    [find_tracked_unique $root_dir local_weight_provider.sv]
set source_dot_core \
    [find_tracked_unique $root_dir vector_dot_product_core.sv]
set source_dense_engine \
    [find_tracked_unique $root_dir dense_layer_engine.sv]
set source_mlp_controller \
    [find_tracked_unique $root_dir mlp_sequence_controller.sv]
set source_verified_kernel \
    [find_tracked_unique $root_dir dlrm_f37x_rtl_kernel.sv]
set source_interaction \
    [find_tracked_unique $root_dir dlrm_feature_interaction_engine.sv]
set source_a2_top \
    [find_tracked_unique $root_dir dlrm_f37x_rtl_kernel_stage2n_a2.sv]
set source_segmented_controller \
    [find_tracked_unique $root_dir mlp_sequence_controller_segmented.sv]
set source_pipeline_controller \
    [find_tracked_unique $root_dir dlrm_internal_pipeline_controller.sv]
set source_a10_adapter \
    [find_tracked_unique $root_dir dlrm_internal_pipeline_axi_lite_adapter_stage2n_a10_v2.sv]
set source_a10_top \
    [find_tracked_unique $root_dir dlrm_f37x_rtl_kernel_stage2n_a10_v2.sv]

set rtl_files [list \
    $source_rv_fifo \
    $source_relu_quant \
    $source_mac_lane \
    $source_activation_buffer \
    $source_weight_provider \
    $source_dot_core \
    $source_dense_engine \
    $source_mlp_controller \
    $source_verified_kernel \
    $source_interaction \
    $source_a2_top \
    $source_segmented_controller \
    $source_pipeline_controller \
    $source_a10_adapter \
    $source_a10_top \
]

foreach rtl_file $rtl_files {
    if {![file exists $rtl_file]} {
        fail "Missing resolved RTL source: $rtl_file"
    }
}


file delete -force $build_dir
file mkdir $build_dir

puts "============================================================"
puts "Stage 2N-A10 v2 F37X capacity-expanded RTL-kernel XO packaging"
puts "Root : $root_dir"
puts "Part : $part_name"
puts "Top  : $top_name"
puts "XO   : $xo_path"
puts "XML  : $xml_path"
puts "NO XCLBIN LINK"
puts "NO FPGA PROGRAMMING OR RESET"
puts "============================================================"

if {[llength [get_parts -quiet $part_name]] == 0} {
    fail "Vivado part is unavailable: $part_name"
}

puts "========== RESOLVED RTL SOURCE ORDER =========="
foreach rtl_file $rtl_files {
    puts $rtl_file
}
puts "VERIFIED_KERNEL_SOURCE=$source_verified_kernel"
puts "A10_TOP_SOURCE=$source_a10_top"
puts "============================================================"

create_project dlrm_f37x_stage2n_a10_package_v2 $project_dir \
    -part $part_name \
    -force

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
    {F37X DLRM Capacity-Expanded Automatic Pipeline RTL Kernel} \
    $core
set_property description \
    {Stage 2N-A10 user-managed AXI4-Lite kernel preserving the legacy windows while expanding the automatic Bottom MLP to feature interaction to Top MLP pipeline for the Stage 2M model shape} \
    $core
set_property version 2.11 $core

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

# ---------------------------------------------------------------------------
# 0x000-0x0FF: preserved legacy MLP window.
# ---------------------------------------------------------------------------
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
    {Legacy MLP activation payload word zero}
add_control_register $address_block ACT_DATA1 0x054 read-write \
    {Legacy MLP activation payload word one}
add_control_register $address_block ACT_DATA2 0x058 read-write \
    {Legacy MLP activation payload word two}
add_control_register $address_block ACT_DATA3 0x05C read-write \
    {Legacy MLP activation payload word three}
add_control_register $address_block ACT_DATA4 0x060 read-write \
    {Legacy MLP activation payload word four}
add_control_register $address_block ACT_DATA5 0x064 read-write \
    {Legacy MLP activation payload word five}
add_control_register $address_block ACT_DATA6 0x068 read-write \
    {Legacy MLP activation payload word six}
add_control_register $address_block ACT_DATA7 0x06C read-write \
    {Legacy MLP activation payload word seven}
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

# ---------------------------------------------------------------------------
# 0x100-0x13F: preserved standalone feature-interaction window.
# ---------------------------------------------------------------------------
add_control_register $address_block INT_CONTROL_STATUS 0x100 read-write \
    {Standalone feature-interaction command and status}
add_control_register $address_block INT_VERSION 0x104 read-only \
    {Standalone interaction interface version}
add_control_register $address_block INT_RESULT_COUNT 0x108 read-only \
    {Accepted standalone interaction result count}
add_control_register $address_block INT_SHIFT 0x10C read-write \
    {Standalone interaction output right shift}
add_control_register $address_block INT_VECTOR_INDEX 0x110 read-write \
    {Standalone feature-vector index from zero to four}
add_control_register $address_block INT_VECTOR_DATA0 0x114 read-write \
    {Signed INT16 vector elements zero and one}
add_control_register $address_block INT_VECTOR_DATA1 0x118 read-write \
    {Signed INT16 vector elements two and three}
add_control_register $address_block INT_VECTOR_DATA2 0x11C read-write \
    {Signed INT16 vector elements four and five}
add_control_register $address_block INT_VECTOR_DATA3 0x120 read-write \
    {Signed INT16 vector elements six and seven}
add_control_register $address_block INT_RESULT_DATA 0x124 read-only \
    {Sign-extended standalone interaction output}
add_control_register $address_block INT_RESULT_INDEX 0x128 read-only \
    {Standalone interaction output index}
add_control_register $address_block INT_RESULT_META 0x12C read-only \
    {Standalone interaction result metadata}
add_control_register $address_block INT_LOADED_MASK 0x130 read-only \
    {Loaded mask for the five standalone feature vectors}

# ---------------------------------------------------------------------------
# 0x180-0x217: Stage 2N-A10 capacity-expanded automatic-pipeline window.
# ---------------------------------------------------------------------------
add_control_register $address_block PIPE_CONTROL_STATUS 0x180 read-write \
    {Automatic pipeline commands and status}
add_control_register $address_block PIPE_VERSION 0x184 read-only \
    {Stage 2N-A10 v2 capacity-expanded automatic-pipeline interface version}
add_control_register $address_block PIPE_RESULT_COUNT 0x188 read-only \
    {Consumed final-result count}
add_control_register $address_block PIPE_PHASE_COUNTS 0x18C read-only \
    {Pipeline phase, Bottom count, interaction count, and embedding mask}
add_control_register $address_block PIPE_DESC_INDEX 0x190 read-write \
    {Pipeline descriptor staging index}
add_control_register $address_block PIPE_DESC_WORD0 0x194 read-write \
    {Pipeline descriptor bits 31 to 0}
add_control_register $address_block PIPE_DESC_WORD1 0x198 read-write \
    {Pipeline descriptor bits 63 to 32}
add_control_register $address_block PIPE_DESC_WORD2 0x19C read-write \
    {Pipeline descriptor bits 95 to 64}
add_control_register $address_block PIPE_ACT_BUFFER 0x1A0 read-write \
    {Pipeline activation-buffer selector}
add_control_register $address_block PIPE_ACT_CHUNK_INDEX 0x1A4 read-write \
    {Pipeline activation chunk index}
add_control_register $address_block PIPE_ACT_LANE_MASK 0x1A8 read-write \
    {Pipeline activation lane-valid mask}
add_control_register $address_block PIPE_ACT_DATA0 0x1B0 read-write \
    {Pipeline activation payload word zero}
add_control_register $address_block PIPE_ACT_DATA1 0x1B4 read-write \
    {Pipeline activation payload word one}
add_control_register $address_block PIPE_ACT_DATA2 0x1B8 read-write \
    {Pipeline activation payload word two}
add_control_register $address_block PIPE_ACT_DATA3 0x1BC read-write \
    {Pipeline activation payload word three}
add_control_register $address_block PIPE_ACT_DATA4 0x1C0 read-write \
    {Pipeline activation payload word four}
add_control_register $address_block PIPE_ACT_DATA5 0x1C4 read-write \
    {Pipeline activation payload word five}
add_control_register $address_block PIPE_ACT_DATA6 0x1C8 read-write \
    {Pipeline activation payload word six}
add_control_register $address_block PIPE_ACT_DATA7 0x1CC read-write \
    {Pipeline activation payload word seven}
add_control_register $address_block PIPE_EMB_INDEX 0x1D0 read-write \
    {Pipeline embedding index from zero to three}
add_control_register $address_block PIPE_EMB_DATA0 0x1D4 read-write \
    {Pipeline embedding payload word zero}
add_control_register $address_block PIPE_EMB_DATA1 0x1D8 read-write \
    {Pipeline embedding payload word one}
add_control_register $address_block PIPE_EMB_DATA2 0x1DC read-write \
    {Pipeline embedding payload word two}
add_control_register $address_block PIPE_EMB_DATA3 0x1E0 read-write \
    {Pipeline embedding payload word three}
add_control_register $address_block PIPE_WEIGHT_ADDRESS 0x1E4 read-write \
    {Pipeline shared-weight address}
add_control_register $address_block PIPE_WEIGHT_DATA 0x1E8 read-write \
    {Pipeline signed INT8 weight}
add_control_register $address_block PIPE_BIAS_ADDRESS 0x1EC read-write \
    {Pipeline shared-bias address}
add_control_register $address_block PIPE_BIAS_DATA 0x1F0 read-write \
    {Pipeline signed INT24 bias}
add_control_register $address_block PIPE_BOTTOM_CONFIG 0x1F4 read-write \
    {Bottom descriptor base, count, and initial buffer}
add_control_register $address_block PIPE_TOP_CONFIG 0x1F8 read-write \
    {Top descriptor base, count, and input buffer}
add_control_register $address_block PIPELINE_CONFIG 0x1FC read-write \
    {Feature-interaction shift configuration}
add_control_register $address_block PIPE_RESULT_DATA 0x200 read-only \
    {Sign-extended final Top MLP result}
add_control_register $address_block PIPE_RESULT_INDEX 0x204 read-only \
    {Final result index}
add_control_register $address_block PIPE_RESULT_META 0x208 read-only \
    {Final result valid, last, index, and tag}
add_control_register $address_block PIPE_EMB_LOADED_MASK 0x20C read-only \
    {Loaded mask for the four pipeline embeddings}
add_control_register $address_block PIPE_ERROR_CODE 0x210 read-only \
    {Core and AXI-Lite wrapper error code}
add_control_register $address_block PIPE_CONFIG_READY 0x214 read-only \
    {Ready bits for descriptor, activation, embedding, weight, bias, and start channels}

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
puts "STAGE2N_A10_XO_PACKAGE_V2_PASS"
puts "XO=$xo_path"
puts "KERNEL_XML=$xml_path"
puts "NO XCLBIN LINK"
puts "NO FPGA PROGRAMMING OR RESET"
puts "============================================================"

close_project
