# Stage 2N-A6 hold-path and DRC diagnostic v2.
#
# Opens the existing A6 post-route checkpoint and diagnoses:
#   - every negative-slack hold path;
#   - whether each path is port-related or fully internal;
#   - DRC violation severities and rules.
#
# It does not rerun synthesis, placement, physical optimization, or routing.
# It does not build an XO/xclbin and does not access an FPGA board.

set script_path [file normalize [info script]]
set repo_root [file normalize [file join [file dirname $script_path] ..]]
cd $repo_root

set expected_top "dlrm_internal_pipeline_controller"
set expected_part "xcvu37p-fsvh2892-2L-e"

if {[info exists ::env(STAGE2N_A6_EXISTING_DCP)] &&
    [string length $::env(STAGE2N_A6_EXISTING_DCP)] > 0} {
  set checkpoint [file normalize $::env(STAGE2N_A6_EXISTING_DCP)]
} else {
  set checkpoint [file normalize \
      "results/stage2n_a6_ooc_v2/post_route.dcp"]
}

if {[info exists ::env(STAGE2N_A6_DIAG_RESULT_DIR)] &&
    [string length $::env(STAGE2N_A6_DIAG_RESULT_DIR)] > 0} {
  set result_dir [file normalize $::env(STAGE2N_A6_DIAG_RESULT_DIR)]
} else {
  set result_dir [file normalize \
      "results/stage2n_a6_hold_drc_diag_v2"]
}

proc write_text {path text} {
  set handle [open $path w]
  puts -nonewline $handle $text
  close $handle
}

proc fail_diag {result_dir message {code 1}} {
  file mkdir $result_dir
  set text "STAGE2N_A6_HOLD_DRC_DIAG_V2_FAIL\n"
  append text "MESSAGE=$message\n"
  write_text \
      [file join $result_dir stage2n_a6_hold_drc_diag_v2_status.txt] \
      $text
  puts stderr "Stage 2N-A6 hold/DRC diagnostic failed: $message"
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

proc object_class {object} {
  return [safe_property $object CLASS UNKNOWN]
}

proc object_name {object} {
  return [safe_property $object NAME UNKNOWN]
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

proc increment_dict {dict_var key} {
  upvar 1 $dict_var values
  if {![dict exists $values $key]} {
    dict set values $key 0
  }
  dict incr values $key
}

proc normalize_tsv_field {value} {
  set result $value
  regsub -all {\t} $result { } result
  regsub -all {\r?\n} $result { } result
  return $result
}

proc write_timing_path_report {paths output_path empty_label} {
  if {[llength $paths] == 0} {
    write_text $output_path "$empty_label\n"
    return
  }

  # Vivado 2020.2 does not allow -delay_type together with -of_objects.
  # The timing-path objects already retain their min-delay type.
  # The deprecated -nets switch is deliberately omitted.
  report_timing \
      -of_objects $paths \
      -path_type full_clock_expanded \
      -input_pins \
      -file $output_path
}

if {![file exists $checkpoint]} {
  fail_diag $result_dir "checkpoint is missing: $checkpoint"
}

if {[file exists $result_dir]} {
  file delete -force $result_dir
}
file mkdir $result_dir

puts "============================================================"
puts "Stage 2N-A6 hold-path and DRC diagnostic v2"
puts "Checkpoint : $checkpoint"
puts "Results    : $result_dir"
puts "No synth/place/route rerun"
puts "No XO/xclbin build"
puts "No FPGA programming or reset"
puts "============================================================"

set open_rc [catch {open_checkpoint $checkpoint} open_message open_options]
if {$open_rc != 0} {
  set detail $open_message
  if {[dict exists $open_options -errorinfo]} {
    append detail "\n" [dict get $open_options -errorinfo]
  }
  fail_diag $result_dir "open_checkpoint failed: $detail"
}

set actual_top [get_property TOP [current_design]]
set actual_part [get_property PART [current_design]]

if {$actual_top ne $expected_top} {
  fail_diag $result_dir \
      "unexpected top: $actual_top; expected $expected_top"
}
if {$actual_part ne $expected_part} {
  fail_diag $result_dir \
      "unexpected part: $actual_part; expected $expected_part"
}

update_timing

set all_hold_paths [get_timing_paths \
    -quiet \
    -delay_type min \
    -slack_lesser_than 0.0 \
    -max_paths 10000 \
    -nworst 10000]

set input_hold_paths [get_timing_paths \
    -quiet \
    -delay_type min \
    -from [all_inputs] \
    -slack_lesser_than 0.0 \
    -max_paths 10000 \
    -nworst 10000]

set output_hold_paths [get_timing_paths \
    -quiet \
    -delay_type min \
    -to [all_outputs] \
    -slack_lesser_than 0.0 \
    -max_paths 10000 \
    -nworst 10000]

set internal_hold_paths [get_timing_paths \
    -quiet \
    -delay_type min \
    -from [all_registers] \
    -to [all_registers] \
    -slack_lesser_than 0.0 \
    -max_paths 10000 \
    -nworst 10000]

set hold_count [llength $all_hold_paths]
set input_hold_count [llength $input_hold_paths]
set output_hold_count [llength $output_hold_paths]
set internal_hold_count [llength $internal_hold_paths]

set worst_hold_slack "NA"
set hold_tns 0.0
if {$hold_count > 0} {
  set worst_hold_slack \
      [safe_property [lindex $all_hold_paths 0] SLACK "NA"]
  set hold_tns [sum_negative_slacks $all_hold_paths]
}

write_timing_path_report \
    $all_hold_paths \
    [file join $result_dir hold_all_negative_paths.rpt] \
    "NO_NEGATIVE_HOLD_PATHS"

write_timing_path_report \
    $input_hold_paths \
    [file join $result_dir hold_from_inputs.rpt] \
    "NO_NEGATIVE_HOLD_PATHS_FROM_INPUTS"

write_timing_path_report \
    $output_hold_paths \
    [file join $result_dir hold_to_outputs.rpt] \
    "NO_NEGATIVE_HOLD_PATHS_TO_OUTPUTS"

write_timing_path_report \
    $internal_hold_paths \
    [file join $result_dir hold_internal_reg_to_reg.rpt] \
    "NO_NEGATIVE_INTERNAL_REGISTER_TO_REGISTER_HOLD_PATHS"

set hold_tsv \
    "INDEX\tSLACK_NS\tPATH_GROUP\tSTART_CLASS\tSTARTPOINT\tEND_CLASS\tENDPOINT\tDATAPATH_DELAY_NS\tLOGIC_LEVELS\n"

set class_pair_counts [dict create]
set index 0

foreach path $all_hold_paths {
  incr index

  set startpoint [get_property STARTPOINT_PIN $path]
  set endpoint [get_property ENDPOINT_PIN $path]

  set start_class [object_class $startpoint]
  set end_class [object_class $endpoint]
  set start_name [object_name $startpoint]
  set end_name [object_name $endpoint]

  set slack [safe_property $path SLACK NA]
  set path_group [safe_property $path PATH_GROUP NA]
  set datapath_delay [safe_property $path DATAPATH_DELAY NA]
  set logic_levels [safe_property $path LOGIC_LEVELS NA]

  set class_pair "${start_class}->${end_class}"
  increment_dict class_pair_counts $class_pair

  append hold_tsv \
      "$index\t$slack\t[normalize_tsv_field $path_group]\t$start_class\t[normalize_tsv_field $start_name]\t$end_class\t[normalize_tsv_field $end_name]\t$datapath_delay\t$logic_levels\n"
}

write_text \
    [file join $result_dir hold_negative_paths.tsv] \
    $hold_tsv

set hold_class_text ""
foreach key [lsort [dict keys $class_pair_counts]] {
  append hold_class_text \
      "$key=[dict get $class_pair_counts $key]\n"
}
write_text \
    [file join $result_dir hold_class_summary.txt] \
    $hold_class_text

set drc_violations [get_drc_violations -quiet]
set drc_total_count [llength $drc_violations]

set drc_error_count 0
set drc_critical_warning_count 0
set drc_warning_count 0
set drc_advisory_count 0
set drc_other_count 0

set drc_rule_counts [dict create]
set drc_severity_counts [dict create]

set drc_tsv \
    "INDEX\tSEVERITY\tRULE\tNAME\tMESSAGE\n"

set index 0
foreach violation $drc_violations {
  incr index

  set severity [safe_property $violation SEVERITY UNKNOWN]
  set rule [safe_property $violation RULE UNKNOWN]
  set name [safe_property $violation NAME UNKNOWN]
  set message [safe_property $violation MSG ""]

  if {$rule eq "UNKNOWN"} {
    set rule [safe_property $violation RULE_NAME UNKNOWN]
  }
  if {$message eq ""} {
    set message [safe_property $violation DESCRIPTION ""]
  }

  increment_dict drc_rule_counts $rule
  increment_dict drc_severity_counts $severity

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

  append drc_tsv \
      "$index\t[normalize_tsv_field $severity]\t[normalize_tsv_field $rule]\t[normalize_tsv_field $name]\t[normalize_tsv_field $message]\n"
}

write_text \
    [file join $result_dir drc_violations.tsv] \
    $drc_tsv

set drc_summary_text "DRC_SEVERITY_COUNTS\n"
foreach key [lsort [dict keys $drc_severity_counts]] {
  append drc_summary_text \
      "$key=[dict get $drc_severity_counts $key]\n"
}

append drc_summary_text "\nDRC_RULE_COUNTS\n"
foreach key [lsort [dict keys $drc_rule_counts]] {
  append drc_summary_text \
      "$key=[dict get $drc_rule_counts $key]\n"
}

write_text \
    [file join $result_dir drc_summary.txt] \
    $drc_summary_text

report_drc \
    -file [file join $result_dir drc_full.rpt]

set likely_io_constraint_artifact 0
if {
    ($hold_count > 0) &&
    ($internal_hold_count == 0) &&
    (($input_hold_count + $output_hold_count) == $hold_count)
} {
  set likely_io_constraint_artifact 1
}

set status_text "STAGE2N_A6_HOLD_DRC_DIAG_V2_COMPLETE\n"
append status_text "CHECKPOINT=$checkpoint\n"
append status_text "TOP=$actual_top\n"
append status_text "PART=$actual_part\n"
append status_text "TOTAL_HOLD_VIOLATING_PATHS=$hold_count\n"
append status_text "WORST_HOLD_SLACK_NS=$worst_hold_slack\n"
append status_text "HOLD_TNS_NS=$hold_tns\n"
append status_text "INPUT_RELATED_HOLD_PATHS=$input_hold_count\n"
append status_text "OUTPUT_RELATED_HOLD_PATHS=$output_hold_count\n"
append status_text "INTERNAL_REG_TO_REG_HOLD_PATHS=$internal_hold_count\n"
append status_text "LIKELY_IO_CONSTRAINT_ARTIFACT=$likely_io_constraint_artifact\n"
append status_text "DRC_TOTAL_VIOLATIONS=$drc_total_count\n"
append status_text "DRC_ERROR_COUNT=$drc_error_count\n"
append status_text "DRC_CRITICAL_WARNING_COUNT=$drc_critical_warning_count\n"
append status_text "DRC_WARNING_COUNT=$drc_warning_count\n"
append status_text "DRC_ADVISORY_COUNT=$drc_advisory_count\n"
append status_text "DRC_OTHER_COUNT=$drc_other_count\n"
append status_text "NO_SYNTH_PLACE_ROUTE_RERUN=1\n"
append status_text "NO_XO_OR_XCLBIN_BUILD=1\n"
append status_text "NO_FPGA_PROGRAMMING_OR_RESET=1\n"

set status_path \
    [file join $result_dir stage2n_a6_hold_drc_diag_v2_status.txt]
write_text $status_path $status_text

puts "============================================================"
puts "Stage 2N-A6 hold/DRC diagnostic v2"
puts "Hold violating paths     : $hold_count"
puts "Worst hold slack         : $worst_hold_slack ns"
puts "Hold TNS                 : $hold_tns ns"
puts "Input-related hold paths : $input_hold_count"
puts "Output-related hold paths: $output_hold_count"
puts "Internal reg-to-reg hold : $internal_hold_count"
puts "Likely I/O artifact      : $likely_io_constraint_artifact"
puts "DRC total                : $drc_total_count"
puts "DRC Error/Critical       : $drc_error_count / $drc_critical_warning_count"
puts "DRC Warning/Advisory     : $drc_warning_count / $drc_advisory_count"
puts "Status                   : $status_path"
puts "============================================================"

exit 0
