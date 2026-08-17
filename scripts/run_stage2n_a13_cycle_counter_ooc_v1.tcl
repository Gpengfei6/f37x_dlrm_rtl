# Stage 2N-A13 local OOC synthesis/timing worker.
#
# The PowerShell runner invokes this script once for the frozen A10 v2 top and
# once for the A13 v1 top. No checkpoint, XO, xclbin, or board action is made.

set script_path [file normalize [info script]]
set repo_root [file normalize [file join [file dirname $script_path] ..]]
cd $repo_root

foreach required_env {STAGE2N_A13_SYNTH_TOP STAGE2N_A13_SYNTH_LABEL STAGE2N_A13_SYNTH_RESULT_DIR STAGE2N_A13_SYNTH_PART} {
  if {![info exists ::env($required_env)] ||
      [string length $::env($required_env)] == 0} {
    puts stderr "Missing environment variable $required_env"
    exit 2
  }
}

set synth_top $::env(STAGE2N_A13_SYNTH_TOP)
set synth_label $::env(STAGE2N_A13_SYNTH_LABEL)
set result_dir [file normalize $::env(STAGE2N_A13_SYNTH_RESULT_DIR)]
set part_name $::env(STAGE2N_A13_SYNTH_PART)
set xdc_path [file normalize \
    "constraints/stage2n_a13_cycle_counter_100mhz_v1.xdc"]

if {[file exists $result_dir]} {
  puts stderr "Result directory already exists: $result_dir"
  exit 3
}
file mkdir $result_dir

proc write_text {path text} {
  set handle [open $path w]
  puts -nonewline $handle $text
  close $handle
}

proc safe_property {object property_name {default_value "NA"}} {
  if {[llength $object] == 0} {
    return $default_value
  }
  set rc [catch {get_property $property_name $object} value]
  if {$rc != 0 || [string length $value] == 0} {
    return $default_value
  }
  return $value
}

proc primitive_count {filter_expression} {
  return [llength [get_cells -quiet -hier -filter $filter_expression]]
}

proc sum_negative_slacks {paths} {
  set total 0.0
  foreach path $paths {
    set slack [safe_property $path SLACK 0.0]
    if {$slack < 0.0} {
      set total [expr {$total + $slack}]
    }
  }
  return $total
}

proc count_severity {objects expected} {
  set count 0
  foreach object $objects {
    if {[safe_property $object SEVERITY ""] eq $expected} {
      incr count
    }
  }
  return $count
}

set sources [list \
    rtl/common/rv_fifo.sv \
    rtl/common/runtime_relu_quant.sv \
    rtl/compute/mac_lane.sv \
    rtl/memory/banked_activation_buffer.sv \
    rtl/memory/local_weight_provider.sv \
    rtl/compute/vector_dot_product_core.sv \
    rtl/compute/dense_layer_engine.sv \
    rtl/control/mlp_sequence_controller.sv \
    rtl/top/dlrm_f37x_rtl_kernel.sv \
    rtl/interaction/dlrm_feature_interaction_engine.sv \
    rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a2.sv \
    rtl/control/mlp_sequence_controller_segmented.sv \
    rtl/pipeline/dlrm_internal_pipeline_controller.sv \
    rtl/pipeline/dlrm_internal_pipeline_controller_stage2n_a13_v1.sv \
    rtl/f37x/dlrm_internal_pipeline_axi_lite_adapter_stage2n_a10_v2.sv \
    rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a10_v2.sv \
    rtl/f37x/dlrm_internal_pipeline_axi_lite_adapter_stage2n_a13_v1.sv \
    rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a13_v1.sv]

foreach source $sources {
  if {![file exists $source]} {
    puts stderr "Missing synthesis source: $source"
    exit 4
  }
}
if {![file exists $xdc_path]} {
  puts stderr "Missing synthesis constraint: $xdc_path"
  exit 5
}

puts "STAGE2N_A13_SYNTH_LABEL=$synth_label"
puts "STAGE2N_A13_SYNTH_TOP=$synth_top"
puts "STAGE2N_A13_SYNTH_PART=$part_name"

read_verilog -sv $sources
read_xdc $xdc_path
synth_design \
    -top $synth_top \
    -part $part_name \
    -mode out_of_context \
    -flatten_hierarchy rebuilt

report_utilization \
    -hierarchical \
    -hierarchical_depth 6 \
    -file [file join $result_dir post_synth_utilization.rpt]
report_ram_utilization \
    -file [file join $result_dir post_synth_ram_utilization.rpt]
report_timing_summary \
    -delay_type min_max \
    -max_paths 50 \
    -report_unconstrained \
    -check_timing_verbose \
    -file [file join $result_dir post_synth_timing_summary.rpt]
report_timing \
    -delay_type max \
    -max_paths 50 \
    -nworst 50 \
    -path_type full_clock_expanded \
    -input_pins \
    -file [file join $result_dir post_synth_setup_paths.rpt]
check_timing \
    -verbose \
    -file [file join $result_dir check_timing.rpt]
report_drc \
    -file [file join $result_dir drc.rpt]
report_methodology \
    -file [file join $result_dir methodology.rpt]
report_high_fanout_nets \
    -timing \
    -load_types \
    -max_nets 50 \
    -file [file join $result_dir high_fanout.rpt]

set worst_setup [get_timing_paths \
    -quiet \
    -delay_type max \
    -max_paths 1 \
    -nworst 1]
set negative_setup [get_timing_paths \
    -quiet \
    -delay_type max \
    -slack_lesser_than 0.0 \
    -max_paths 100000 \
    -nworst 1]

set wns [safe_property [lindex $worst_setup 0] SLACK "NA"]
set tns [sum_negative_slacks $negative_setup]
set failing_endpoints [llength $negative_setup]
set worst_startpoint [safe_property [lindex $worst_setup 0] STARTPOINT_PIN "NA"]
set worst_endpoint [safe_property [lindex $worst_setup 0] ENDPOINT_PIN "NA"]

set lut_count [primitive_count {REF_NAME =~ LUT*}]
set ff_count [primitive_count {REF_NAME =~ FD*}]
set ramb36_count [primitive_count {REF_NAME =~ RAMB36*}]
set ramb18_count [primitive_count {REF_NAME =~ RAMB18*}]
set dsp_count [primitive_count {REF_NAME =~ DSP48*}]
set latch_count [expr {
    [primitive_count {REF_NAME =~ LD*}] +
    [primitive_count {REF_NAME =~ LATCH*}]
}]

set drc_objects [get_drc_violations -quiet]
set methodology_objects [get_methodology_violations -quiet]
set drc_error_count [count_severity $drc_objects "Error"]
set drc_critical_count [count_severity $drc_objects "Critical Warning"]
set drc_warning_count [count_severity $drc_objects "Warning"]
set methodology_error_count \
    [count_severity $methodology_objects "Error"]
set methodology_critical_count \
    [count_severity $methodology_objects "Critical Warning"]
set methodology_warning_count \
    [count_severity $methodology_objects "Warning"]

set timing_met [expr {
    ($wns ne "NA") &&
    ($wns >= 0.0) &&
    ($failing_endpoints == 0)
}]
set overall_pass [expr {
    $timing_met &&
    ($latch_count == 0) &&
    ($drc_error_count == 0)
}]

set status_text ""
if {$overall_pass} {
  append status_text "STAGE2N_A13_OOC_SYNTH_V1_PASS\n"
} else {
  append status_text "STAGE2N_A13_OOC_SYNTH_V1_FAIL\n"
}
append status_text "LABEL=$synth_label\n"
append status_text "TOP=$synth_top\n"
append status_text "PART=$part_name\n"
append status_text "CLOCK_PERIOD_NS=10.000\n"
append status_text "SYNTHESIS_COMPLETED=1\n"
append status_text "WNS_NS=$wns\n"
append status_text "TNS_NS=$tns\n"
append status_text "FAILING_ENDPOINTS=$failing_endpoints\n"
append status_text "WORST_STARTPOINT=$worst_startpoint\n"
append status_text "WORST_ENDPOINT=$worst_endpoint\n"
append status_text "LUT_COUNT=$lut_count\n"
append status_text "FF_COUNT=$ff_count\n"
append status_text "RAMB36_COUNT=$ramb36_count\n"
append status_text "RAMB18_COUNT=$ramb18_count\n"
append status_text "DSP_COUNT=$dsp_count\n"
append status_text "LATCH_COUNT=$latch_count\n"
append status_text "DRC_ERROR_COUNT=$drc_error_count\n"
append status_text "DRC_CRITICAL_WARNING_COUNT=$drc_critical_count\n"
append status_text "DRC_WARNING_COUNT=$drc_warning_count\n"
append status_text "METHODOLOGY_ERROR_COUNT=$methodology_error_count\n"
append status_text "METHODOLOGY_CRITICAL_WARNING_COUNT=$methodology_critical_count\n"
append status_text "METHODOLOGY_WARNING_COUNT=$methodology_warning_count\n"
append status_text "TIMING_MET=$timing_met\n"
append status_text "NO_DCP_WRITTEN=1\n"
append status_text "NO_XO_OR_XCLBIN_BUILD=1\n"
append status_text "NO_FPGA_ACCESS=1\n"
append status_text "NO_FPGA_PROGRAMMING_OR_RESET=1\n"

set status_path [file join $result_dir status.txt]
write_text $status_path $status_text
puts $status_text

exit 0
