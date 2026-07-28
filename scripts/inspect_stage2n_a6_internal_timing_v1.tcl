# Stage 2N-A6 internal timing acceptance v1.
#
# This script reuses the existing Stage 2N-A6 post-route checkpoint and
# evaluates only the timing that belongs to the RTL block itself:
#   register -> register setup and hold paths.
#
# Top-level output-port hold paths are reported separately because their final
# requirement depends on the future AXI/XRT/F37X shell connection.
#
# No synthesis, placement, routing, XO/xclbin build, FPGA programming, or reset.

set script_path [file normalize [info script]]
set repo_root [file normalize [file join [file dirname $script_path] ..]]
cd $repo_root

set expected_top "dlrm_internal_pipeline_controller"
set expected_part "xcvu37p-fsvh2892-2L-e"
set expected_clock_name "stage2n_a6_clk"
set expected_period_ns 10.000

if {[info exists ::env(STAGE2N_A6_EXISTING_DCP)] &&
    [string length $::env(STAGE2N_A6_EXISTING_DCP)] > 0} {
  set checkpoint [file normalize $::env(STAGE2N_A6_EXISTING_DCP)]
} else {
  set checkpoint [file normalize \
      "results/stage2n_a6_ooc_v2/post_route.dcp"]
}

if {[info exists ::env(STAGE2N_A6_ACCEPT_RESULT_DIR)] &&
    [string length $::env(STAGE2N_A6_ACCEPT_RESULT_DIR)] > 0} {
  set result_dir [file normalize $::env(STAGE2N_A6_ACCEPT_RESULT_DIR)]
} else {
  set result_dir [file normalize \
      "results/stage2n_a6_internal_accept_v1"]
}

proc write_text {path text} {
  set handle [open $path w]
  puts -nonewline $handle $text
  close $handle
}

proc append_status {var_name key value} {
  upvar 1 $var_name text
  append text "$key=$value\n"
}

proc fail_accept {result_dir message {code 1}} {
  file mkdir $result_dir
  set text "STAGE2N_A6_INTERNAL_TIMING_ACCEPT_V1_FAIL\n"
  append text "MESSAGE=$message\n"
  write_text \
      [file join $result_dir \
          stage2n_a6_internal_timing_accept_v1_status.txt] \
      $text
  puts stderr "Stage 2N-A6 internal timing acceptance failed: $message"
  exit $code
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

proc primitive_count {filter_expression} {
  return [llength [get_cells -quiet -hier -filter $filter_expression]]
}

proc increment_dict {dict_var key} {
  upvar 1 $dict_var values
  if {![dict exists $values $key]} {
    dict set values $key 0
  }
  dict incr values $key
}

if {![file exists $checkpoint]} {
  fail_accept $result_dir "post-route checkpoint is missing: $checkpoint"
}

if {[file exists $result_dir]} {
  file delete -force $result_dir
}
file mkdir $result_dir

puts "============================================================"
puts "Stage 2N-A6 internal timing acceptance v1"
puts "Checkpoint : $checkpoint"
puts "Results    : $result_dir"
puts "Acceptance : internal register-to-register paths only"
puts "No synthesis/place/route rerun"
puts "No XO/xclbin build"
puts "No FPGA programming or reset"
puts "============================================================"

set open_rc [catch {open_checkpoint $checkpoint} open_message open_options]
if {$open_rc != 0} {
  set detail $open_message
  if {[dict exists $open_options -errorinfo]} {
    append detail "\n" [dict get $open_options -errorinfo]
  }
  fail_accept $result_dir "open_checkpoint failed: $detail"
}

set actual_top [get_property TOP [current_design]]
set actual_part [get_property PART [current_design]]

if {$actual_top ne $expected_top} {
  fail_accept $result_dir \
      "unexpected top: $actual_top; expected $expected_top"
}
if {$actual_part ne $expected_part} {
  fail_accept $result_dir \
      "unexpected part: $actual_part; expected $expected_part"
}

update_timing

set clocks [get_clocks -quiet $expected_clock_name]
if {[llength $clocks] != 1} {
  fail_accept $result_dir \
      "expected clock $expected_clock_name is missing or duplicated"
}

set actual_period_ns [get_property PERIOD $clocks]
if {[expr {abs($actual_period_ns - $expected_period_ns)}] > 0.001} {
  fail_accept $result_dir \
      "clock period is $actual_period_ns ns; expected $expected_period_ns ns"
}

set registers [all_registers]
if {[llength $registers] == 0} {
  fail_accept $result_dir "no registers were found in the routed design"
}

set internal_setup_worst [get_timing_paths \
    -quiet \
    -delay_type max \
    -from $registers \
    -to $registers \
    -max_paths 1 \
    -nworst 1]

set internal_hold_worst [get_timing_paths \
    -quiet \
    -delay_type min \
    -from $registers \
    -to $registers \
    -max_paths 1 \
    -nworst 1]

if {[llength $internal_setup_worst] == 0} {
  fail_accept $result_dir "no internal setup timing path was returned"
}
if {[llength $internal_hold_worst] == 0} {
  fail_accept $result_dir "no internal hold timing path was returned"
}

set internal_setup_wns \
    [safe_property [lindex $internal_setup_worst 0] SLACK "NA"]
set internal_hold_whs \
    [safe_property [lindex $internal_hold_worst 0] SLACK "NA"]

set internal_setup_negative [get_timing_paths \
    -quiet \
    -delay_type max \
    -from $registers \
    -to $registers \
    -slack_lesser_than 0.0 \
    -max_paths 100000 \
    -nworst 100000]

set internal_hold_negative [get_timing_paths \
    -quiet \
    -delay_type min \
    -from $registers \
    -to $registers \
    -slack_lesser_than 0.0 \
    -max_paths 100000 \
    -nworst 100000]

set internal_setup_failing [llength $internal_setup_negative]
set internal_hold_failing [llength $internal_hold_negative]
set internal_setup_tns [sum_negative_slacks $internal_setup_negative]
set internal_hold_ths [sum_negative_slacks $internal_hold_negative]

set output_hold_negative [get_timing_paths \
    -quiet \
    -delay_type min \
    -to [all_outputs] \
    -slack_lesser_than 0.0 \
    -max_paths 100000 \
    -nworst 100000]

set output_hold_count [llength $output_hold_negative]
set output_hold_worst "NA"
set output_hold_tns 0.0

if {$output_hold_count > 0} {
  set output_hold_worst \
      [safe_property [lindex $output_hold_negative 0] SLACK "NA"]
  set output_hold_tns [sum_negative_slacks $output_hold_negative]
}

report_timing \
    -delay_type max \
    -from $registers \
    -to $registers \
    -max_paths 50 \
    -nworst 50 \
    -path_type full_clock_expanded \
    -input_pins \
    -file [file join $result_dir internal_setup_paths.rpt]

report_timing \
    -delay_type min \
    -from $registers \
    -to $registers \
    -max_paths 50 \
    -nworst 50 \
    -path_type full_clock_expanded \
    -input_pins \
    -file [file join $result_dir internal_hold_paths.rpt]

report_timing \
    -delay_type min \
    -to [all_outputs] \
    -max_paths 50 \
    -nworst 50 \
    -path_type full_clock_expanded \
    -input_pins \
    -file [file join $result_dir output_hold_paths_reference_only.rpt]

report_timing_summary \
    -delay_type min_max \
    -max_paths 50 \
    -report_unconstrained \
    -check_timing_verbose \
    -file [file join $result_dir full_ooc_timing_summary_reference_only.rpt]

report_utilization \
    -hierarchical \
    -hierarchical_depth 6 \
    -file [file join $result_dir utilization.rpt]

check_timing \
    -verbose \
    -file [file join $result_dir check_timing.rpt]

report_drc \
    -file [file join $result_dir drc.rpt]

set route_status_counts [dict create]
set bad_route_nets [list]

foreach net [get_nets -quiet -hier] {
  set route_status [safe_property $net ROUTE_STATUS UNKNOWN]
  increment_dict route_status_counts $route_status

  if {
      $route_status eq "UNROUTED" ||
      $route_status eq "PARTIALLY_ROUTED"
  } {
    lappend bad_route_nets $net
  }
}

set unrouted_nets [llength $bad_route_nets]

set route_text ""
foreach key [lsort [dict keys $route_status_counts]] {
  append route_text "$key=[dict get $route_status_counts $key]\n"
}

if {$unrouted_nets > 0} {
  append route_text "BAD_ROUTE_NETS_BEGIN\n"
  foreach net $bad_route_nets {
    append route_text "$net\n"
  }
  append route_text "BAD_ROUTE_NETS_END\n"
}

write_text \
    [file join $result_dir route_status_direct_query.txt] \
    $route_text

set latch_count [expr {
    [primitive_count {REF_NAME =~ LD*}] +
    [primitive_count {REF_NAME =~ LATCH*}]
}]

set lut_count [primitive_count {REF_NAME =~ LUT*}]
set ff_count [primitive_count {REF_NAME =~ FD*}]
set ramb36_count [primitive_count {REF_NAME =~ RAMB36*}]
set ramb18_count [primitive_count {REF_NAME =~ RAMB18*}]
set dsp_count [primitive_count {REF_NAME =~ DSP48*}]

set drc_error_count 0
set drc_critical_warning_count 0
set drc_warning_count 0
set drc_advisory_count 0
set drc_other_count 0

foreach violation [get_drc_violations -quiet] {
  set severity [safe_property $violation SEVERITY UNKNOWN]

  switch -- $severity {
    "Error" {
      incr drc_error_count
    }
    "Critical Warning" {
      incr drc_critical_warning_count
    }
    "Warning" {
      incr drc_warning_count
    }
    "Advisory" {
      incr drc_advisory_count
    }
    default {
      incr drc_other_count
    }
  }
}

set internal_setup_met [expr {
    ($internal_setup_wns >= 0.0) &&
    ($internal_setup_failing == 0)
}]

set internal_hold_met [expr {
    ($internal_hold_whs >= 0.0) &&
    ($internal_hold_failing == 0)
}]

set route_met [expr {$unrouted_nets == 0}]
set latch_met [expr {$latch_count == 0}]
set drc_error_free [expr {$drc_error_count == 0}]

set overall_pass [expr {
    $internal_setup_met &&
    $internal_hold_met &&
    $route_met &&
    $latch_met &&
    $drc_error_free
}]

set status_text ""
if {$overall_pass} {
  append status_text "STAGE2N_A6_INTERNAL_TIMING_ACCEPT_V1_PASS\n"
} else {
  append status_text "STAGE2N_A6_INTERNAL_TIMING_ACCEPT_V1_FAIL\n"
}

append_status status_text "CHECKPOINT" $checkpoint
append_status status_text "TOP" $actual_top
append_status status_text "PART" $actual_part
append_status status_text "CLOCK_NAME" $expected_clock_name
append_status status_text "CLOCK_PERIOD_NS" $actual_period_ns
append_status status_text "REGISTER_COUNT" [llength $registers]
append_status status_text "INTERNAL_SETUP_WNS_NS" $internal_setup_wns
append_status status_text "INTERNAL_SETUP_TNS_NS" $internal_setup_tns
append_status status_text \
    "INTERNAL_SETUP_FAILING_PATHS" $internal_setup_failing
append_status status_text "INTERNAL_HOLD_WHS_NS" $internal_hold_whs
append_status status_text "INTERNAL_HOLD_THS_NS" $internal_hold_ths
append_status status_text \
    "INTERNAL_HOLD_FAILING_PATHS" $internal_hold_failing
append_status status_text \
    "OUTPUT_HOLD_VIOLATING_PATHS_REFERENCE_ONLY" $output_hold_count
append_status status_text \
    "OUTPUT_HOLD_WORST_SLACK_NS_REFERENCE_ONLY" $output_hold_worst
append_status status_text \
    "OUTPUT_HOLD_TNS_NS_REFERENCE_ONLY" $output_hold_tns
append_status status_text "UNROUTED_NETS" $unrouted_nets
append_status status_text "LATCH_COUNT" $latch_count
append_status status_text "LUT_COUNT_DIRECT" $lut_count
append_status status_text "FF_COUNT_DIRECT" $ff_count
append_status status_text "RAMB36_COUNT_DIRECT" $ramb36_count
append_status status_text "RAMB18_COUNT_DIRECT" $ramb18_count
append_status status_text "DSP_COUNT_DIRECT" $dsp_count
append_status status_text "DRC_ERROR_COUNT" $drc_error_count
append_status status_text \
    "DRC_CRITICAL_WARNING_COUNT" $drc_critical_warning_count
append_status status_text "DRC_WARNING_COUNT" $drc_warning_count
append_status status_text "DRC_ADVISORY_COUNT" $drc_advisory_count
append_status status_text "DRC_OTHER_COUNT" $drc_other_count
append_status status_text "INTERNAL_SETUP_MET" $internal_setup_met
append_status status_text "INTERNAL_HOLD_MET" $internal_hold_met
append_status status_text "ROUTE_MET" $route_met
append_status status_text "LATCH_MET" $latch_met
append_status status_text "DRC_ERROR_FREE" $drc_error_free
append_status status_text \
    "OUTPUT_HOLD_EXCLUDED_PENDING_FINAL_SHELL" "1"
append_status status_text "NO_SYNTH_PLACE_ROUTE_RERUN" "1"
append_status status_text "NO_XO_OR_XCLBIN_BUILD" "1"
append_status status_text "NO_FPGA_PROGRAMMING_OR_RESET" "1"

set status_path [file join $result_dir \
    stage2n_a6_internal_timing_accept_v1_status.txt]
write_text $status_path $status_text

puts "============================================================"
puts "Stage 2N-A6 internal timing acceptance result"
puts "Internal setup WNS/TNS  : $internal_setup_wns / $internal_setup_tns ns"
puts "Internal setup failures : $internal_setup_failing"
puts "Internal hold WHS/THS    : $internal_hold_whs / $internal_hold_ths ns"
puts "Internal hold failures   : $internal_hold_failing"
puts "Output hold reference    : $output_hold_count paths, worst $output_hold_worst ns"
puts "Unrouted nets            : $unrouted_nets"
puts "Latch count              : $latch_count"
puts "LUT / FF                 : $lut_count / $ff_count"
puts "RAMB36 / RAMB18 / DSP    : $ramb36_count / $ramb18_count / $dsp_count"
puts "DRC Error/Critical       : $drc_error_count / $drc_critical_warning_count"
puts "Status                    : $status_path"
puts "============================================================"

if {!$overall_pass} {
  exit 20
}

exit 0
