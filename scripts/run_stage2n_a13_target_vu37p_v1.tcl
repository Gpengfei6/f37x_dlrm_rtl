# Optional standalone exact-part A13 implementation diagnostic.
#
# This is not the authoritative F37X platform timing gate. The authoritative
# result comes from the routed design produced by Vitis hardware link. This
# script exists to isolate exact xcvu37p RTL implementation behavior before or
# after that link, and never creates an XO/xclbin or accesses a device.

set script_path [file normalize [info script]]
set script_dir [file dirname $script_path]
set root_dir [file normalize [file join $script_dir ..]]

set part_name "xcvu37p-fsvh2892-2L-e"
set top_name "dlrm_f37x_rtl_kernel_stage2n_a13_v1"
set build_dir [file join $root_dir build stage2n_a13 target_vu37p_v1]
set report_dir [file join $build_dir reports]
set status_path [file join $build_dir target_vu37p_status.txt]
set xdc_path [file join $root_dir constraints stage2n_a13_cycle_counter_100mhz_v1.xdc]

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

if {![file isfile $xdc_path]} {
    fail "Missing A13 100 MHz constraint: $xdc_path"
}
if {[file exists $build_dir]} {
    fail "Refusing to overwrite exact-part diagnostic directory: $build_dir"
}
file mkdir $report_dir

if {[llength [get_parts -quiet $part_name]] == 0} {
    fail "Vivado part is unavailable: $part_name"
}

puts "A13_STANDALONE_TARGET_DIAGNOSTIC=START"
puts "PART=$part_name"
puts "TOP=$top_name"
puts "CLOCK_NS=10.000"
puts "AUTHORITATIVE_F37X_TIMING=NO_USE_VITIS_ROUTED_DESIGN"
puts "NO_FPGA_ACCESS=1"

create_project -in_memory -part $part_name
set_property target_language Verilog [current_project]
read_verilog -sv $rtl_files
read_xdc $xdc_path

synth_design -mode out_of_context -top $top_name -part $part_name
report_utilization -file [file join $report_dir post_synth_utilization.rpt]
report_timing_summary -delay_type min_max \
    -file [file join $report_dir post_synth_timing_summary.rpt]

opt_design
place_design
phys_opt_design
route_design

report_timing_summary -delay_type min_max -max_paths 100 \
    -file [file join $report_dir post_route_timing_summary.rpt]
report_timing -delay_type max -max_paths 100 -nworst 1 \
    -file [file join $report_dir post_route_worst_setup_paths.rpt]
report_utilization -hierarchical -hierarchical_depth 3 \
    -file [file join $report_dir post_route_utilization.rpt]
report_drc -file [file join $report_dir post_route_drc.rpt]
report_methodology -file [file join $report_dir post_route_methodology.rpt]
check_timing -verbose -file [file join $report_dir post_route_check_timing.rpt]

if {[llength [info commands report_high_fanout_nets]] != 0} {
    catch {
        report_high_fanout_nets -fanout_greater_than 100 -max_nets 100 \
            -file [file join $report_dir post_route_high_fanout.rpt]
    }
}
if {[llength [info commands report_ram_utilization]] != 0} {
    catch {
        report_ram_utilization \
            -file [file join $report_dir post_route_ram_utilization.rpt]
    }
}

set worst_path [get_timing_paths -quiet -delay_type max -max_paths 1]
if {[llength $worst_path] == 0} {
    set wns "NOT_PARSED"
} else {
    set wns [get_property SLACK [lindex $worst_path 0]]
}
set failing_paths [get_timing_paths -quiet -delay_type max \
    -max_paths 100000 -nworst 1 -slack_lesser_than 0.0]
set failing_endpoints [llength $failing_paths]
set tns 0.0
foreach path $failing_paths {
    set slack [get_property SLACK $path]
    if {$slack < 0.0} {
        set tns [expr {$tns + $slack}]
    }
}

proc primitive_count {pattern} {
    return [llength [get_cells -quiet -hierarchical \
        -filter "REF_NAME =~ $pattern"]]
}

set lut_count [primitive_count LUT*]
set ff_count [primitive_count FD*]
set ramb36_count [primitive_count RAMB36*]
set ramb18_count [primitive_count RAMB18*]
set uram_count [primitive_count URAM*]
set dsp_count [primitive_count DSP48*]
set latch_count [primitive_count LD*]

set timing_pass 0
if {$wns ne "NOT_PARSED" && $wns >= 0.0 && $failing_endpoints == 0} {
    set timing_pass 1
}

set status [open $status_path w]
if {$timing_pass} {
    set diagnostic_result "PASS"
    puts $status "A13_STANDALONE_TARGET_DIAGNOSTIC=PASS"
} else {
    set diagnostic_result "FAIL"
    puts $status "A13_STANDALONE_TARGET_DIAGNOSTIC=FAIL"
}
puts $status "AUTHORITATIVE_F37X_TIMING=NO"
puts $status "TARGET_PART=$part_name"
puts $status "REQUESTED_CLOCK_NS=10.000"
puts $status "REQUESTED_CLOCK_MHZ=100"
puts $status "WNS_NS=$wns"
puts $status "TNS_NS=[format %.3f $tns]"
puts $status "FAILING_ENDPOINTS=$failing_endpoints"
puts $status "LUT=$lut_count"
puts $status "FF=$ff_count"
puts $status "RAMB36=$ramb36_count"
puts $status "RAMB18=$ramb18_count"
puts $status "URAM=$uram_count"
puts $status "DSP=$dsp_count"
puts $status "LATCH=$latch_count"
puts $status "NO_FPGA_ACCESS=1"
close $status

puts "A13_STANDALONE_TARGET_DIAGNOSTIC=$diagnostic_result"
puts "STATUS=$status_path"
puts "AUTHORITATIVE_F37X_TIMING=NO_USE_VITIS_ROUTED_DESIGN"

if {!$timing_pass} {
    fail "Standalone exact-part implementation did not meet 100 MHz"
}
