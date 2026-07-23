# Stage 2F: Artix-7 out-of-context post-route implementation feasibility.
# Compatible with Vivado 2020.2 and Vivado 2022.1.
#
# Optional environment overrides:
#   STAGE2F_PART       - default: xc7a200tfbg484-2
#   STAGE2F_RESULT_DIR - default: results/stage2f
#   STAGE2F_WORK_DIR   - default: work/stage2f
#
# Run from the repository root:
#   vivado -mode batch -nolog -nojournal \
#     -source scripts/run_stage2f_post_route.tcl

set script_path [file normalize [info script]]
set project_root [file normalize [file join [file dirname $script_path] ..]]
cd $project_root

set top_name "mlp_sequence_controller"
set default_part "xc7a200tfbg484-2"
set clock_period_ns "10.000"

if {[info exists ::env(STAGE2F_PART)] &&
    [string length $::env(STAGE2F_PART)] > 0} {
  set part_name $::env(STAGE2F_PART)
} else {
  set part_name $default_part
}

if {[info exists ::env(STAGE2F_RESULT_DIR)] &&
    [string length $::env(STAGE2F_RESULT_DIR)] > 0} {
  set result_dir [file normalize $::env(STAGE2F_RESULT_DIR)]
} else {
  set result_dir [file normalize "results/stage2f"]
}

if {[info exists ::env(STAGE2F_WORK_DIR)] &&
    [string length $::env(STAGE2F_WORK_DIR)] > 0} {
  set work_dir [file normalize $::env(STAGE2F_WORK_DIR)]
} else {
  set work_dir [file normalize "work/stage2f"]
}

proc write_text {path text} {
  set handle [open $path w]
  puts -nonewline $handle $text
  close $handle
}

proc append_status_line {status_var key value} {
  upvar 1 $status_var status_text
  append status_text "$key=$value\n"
}

proc fail_stage2f {result_dir message {exit_code 1}} {
  puts stderr "run_stage2f_post_route: FAIL - $message"
  file mkdir $result_dir
  set failure_text "STAGE2F_RUN_FAIL\n"
  append failure_text "MESSAGE=$message\n"
  write_text \
      [file join $result_dir stage2f_post_route_status.txt] \
      $failure_text
  exit $exit_code
}

proc run_required_step {step_name script_body result_dir} {
  puts "------------------------------------------------------------"
  puts "Stage 2F step: $step_name"
  puts "------------------------------------------------------------"

  set step_rc [catch {uplevel 1 $script_body} step_message step_options]
  if {$step_rc != 0} {
    set detail "$step_name failed:\n$step_message"
    if {[dict exists $step_options -errorinfo]} {
      append detail "\n" [dict get $step_options -errorinfo]
    }
    fail_stage2f $result_dir $detail
  }
}

proc report_nonblocking {description script_body warning_var} {
  upvar 1 $warning_var warning_text

  set report_rc [catch {uplevel 1 $script_body} report_message]
  if {$report_rc != 0} {
    puts "WARNING: $description was not generated: $report_message"
    append warning_text "$description: $report_message\n"
    return 0
  }
  return 1
}

proc read_file_text {path} {
  set handle [open $path r]
  set text [read $handle]
  close $handle
  return $text
}

proc parse_timing_summary {
    report_text
    setup_wns_var setup_tns_var setup_fail_var setup_total_var
    hold_whs_var hold_ths_var hold_fail_var hold_total_var} {
  upvar 1 $setup_wns_var setup_wns
  upvar 1 $setup_tns_var setup_tns
  upvar 1 $setup_fail_var setup_fail
  upvar 1 $setup_total_var setup_total
  upvar 1 $hold_whs_var hold_whs
  upvar 1 $hold_ths_var hold_ths
  upvar 1 $hold_fail_var hold_fail
  upvar 1 $hold_total_var hold_total

  set numeric_row_pattern {^[ \t]*(-?[0-9]+\.[0-9]+)[ \t]+(-?[0-9]+\.[0-9]+)[ \t]+([0-9]+)[ \t]+([0-9]+)[ \t]+(-?[0-9]+\.[0-9]+)[ \t]+(-?[0-9]+\.[0-9]+)[ \t]+([0-9]+)[ \t]+([0-9]+)}

  foreach line [split $report_text "\n"] {
    if {[regexp $numeric_row_pattern $line \
        -> setup_wns setup_tns setup_fail setup_total \
        hold_whs hold_ths hold_fail hold_total]} {
      return 1
    }
  }
  return 0
}

proc parse_unrouted_nets {route_report_text unrouted_var} {
  upvar 1 $unrouted_var unrouted_nets

  set patterns [list \
      {# of unrouted nets[^0-9]*([0-9]+)} \
      {Number of Unrouted Nets[^0-9]*([0-9]+)} \
      {Unrouted Nets[^0-9]*([0-9]+)}]

  foreach pattern $patterns {
    if {[regexp -nocase $pattern $route_report_text -> value]} {
      set unrouted_nets $value
      return 1
    }
  }
  return 0
}

proc parse_top_utilization {
    report_text top_name
    total_luts_var logic_luts_var lutrams_var srls_var
    ffs_var ramb36_var ramb18_var dsp_var} {
  upvar 1 $total_luts_var total_luts
  upvar 1 $logic_luts_var logic_luts
  upvar 1 $lutrams_var lutrams
  upvar 1 $srls_var srls
  upvar 1 $ffs_var ffs
  upvar 1 $ramb36_var ramb36
  upvar 1 $ramb18_var ramb18
  upvar 1 $dsp_var dsp_blocks

  foreach line [split $report_text "\n"] {
    if {[string first "| $top_name" $line] < 0} {
      continue
    }

    set fields [list]
    foreach raw_field [split $line "|"] {
      set field [string trim $raw_field]
      if {$field ne ""} {
        lappend fields $field
      }
    }

    if {[llength $fields] < 10} {
      continue
    }

    set values [lrange $fields 2 9]
    set valid 1
    foreach value $values {
      if {![string is integer -strict $value]} {
        set valid 0
        break
      }
    }

    if {!$valid} {
      continue
    }

    lassign $values \
        total_luts logic_luts lutrams srls \
        ffs ramb36 ramb18 dsp_blocks
    return 1
  }
  return 0
}

if {[file exists $result_dir]} {
  file delete -force $result_dir
}
if {[file exists $work_dir]} {
  file delete -force $work_dir
}

file mkdir $result_dir
file mkdir $work_dir

puts "============================================================"
puts "Stage 2F Artix-7 OOC post-route implementation feasibility"
puts "Top module : $top_name"
puts "Part       : $part_name"
puts "Clock      : $clock_period_ns ns (100 MHz)"
puts "Mode       : out_of_context"
puts "Results    : $result_dir"
puts "Work       : $work_dir"
puts "============================================================"

if {[llength [get_parts -quiet $part_name]] == 0} {
  fail_stage2f $result_dir "Vivado part not found: $part_name"
}

set rtl_files [list \
  rtl/common/rv_fifo.sv \
  rtl/common/runtime_relu_quant.sv \
  rtl/compute/mac_lane.sv \
  rtl/memory/banked_activation_buffer.sv \
  rtl/memory/local_weight_provider.sv \
  rtl/compute/vector_dot_product_core.sv \
  rtl/compute/dense_layer_engine.sv \
  rtl/control/mlp_sequence_controller.sv]

foreach rtl_file $rtl_files {
  if {![file exists $rtl_file]} {
    fail_stage2f $result_dir "Missing RTL source: $rtl_file"
  }
}

set xdc_file "constraints/stage2c_mlp_clock.xdc"
if {![file exists $xdc_file]} {
  fail_stage2f $result_dir "Missing constraint file: $xdc_file"
}

set synth_state "NOT_RUN"
set opt_state "NOT_RUN"
set place_state "NOT_RUN"
set phys_opt_state "NOT_RUN"
set route_state "NOT_RUN"

run_required_step "read sources and constraints" {
  foreach rtl_file $rtl_files {
    read_verilog -sv $rtl_file
  }
  read_xdc $xdc_file
} $result_dir

run_required_step "synth_design" {
  synth_design \
      -top $top_name \
      -part $part_name \
      -mode out_of_context \
      -flatten_hierarchy rebuilt \
      -directive Default
} $result_dir
set synth_state "SYNTH_COMPLETE"
write_checkpoint -force [file join $result_dir post_synth.dcp]

run_required_step "opt_design" {
  opt_design
} $result_dir
set opt_state "OPT_COMPLETE"
write_checkpoint -force [file join $result_dir post_opt.dcp]

run_required_step "place_design" {
  place_design
} $result_dir
set place_state "PLACE_COMPLETE"
write_checkpoint -force [file join $result_dir post_place.dcp]

run_required_step "phys_opt_design" {
  phys_opt_design
} $result_dir
set phys_opt_state "PHYS_OPT_COMPLETE"
write_checkpoint -force [file join $result_dir post_phys_opt.dcp]

run_required_step "route_design" {
  route_design
} $result_dir
set route_state "ROUTE_COMPLETE"
set post_route_checkpoint [file join $result_dir post_route.dcp]
write_checkpoint -force $post_route_checkpoint

set timing_report_path \
    [file join $result_dir post_route_timing_summary.rpt]
set utilization_report_path \
    [file join $result_dir post_route_utilization.rpt]
set route_status_report_path \
    [file join $result_dir post_route_route_status.rpt]

report_timing_summary \
    -delay_type min_max \
    -max_paths 20 \
    -report_unconstrained \
    -check_timing_verbose \
    -file $timing_report_path

report_utilization \
    -hierarchical \
    -hierarchical_depth 4 \
    -file $utilization_report_path

report_route_status \
    -file $route_status_report_path

check_timing \
    -verbose \
    -file [file join $result_dir post_route_check_timing.rpt]

report_drc \
    -file [file join $result_dir post_route_drc.rpt]

report_methodology \
    -file [file join $result_dir post_route_methodology.rpt]

report_clock_utilization \
    -file [file join $result_dir post_route_clock_utilization.rpt]

report_high_fanout_nets \
    -max_nets 50 \
    -file [file join $result_dir post_route_high_fanout.rpt]

set optional_report_warnings ""
set congestion_report_generated [report_nonblocking \
    "post-route congestion report" {
      report_design_analysis \
          -congestion \
          -file [file join $result_dir post_route_congestion.rpt]
    } optional_report_warnings]

set power_report_generated [report_nonblocking \
    "post-route power report" {
      report_power \
          -file [file join $result_dir post_route_power.rpt]
    } optional_report_warnings]

set timing_text [read_file_text $timing_report_path]
set utilization_text [read_file_text $utilization_report_path]
set route_status_text [read_file_text $route_status_report_path]

set setup_wns "NA"
set setup_tns "NA"
set setup_failing_endpoints "NA"
set setup_total_endpoints "NA"
set hold_whs "NA"
set hold_ths "NA"
set hold_failing_endpoints "NA"
set hold_total_endpoints "NA"

set timing_parse_ok [parse_timing_summary \
    $timing_text \
    setup_wns setup_tns \
    setup_failing_endpoints setup_total_endpoints \
    hold_whs hold_ths \
    hold_failing_endpoints hold_total_endpoints]

set unrouted_nets "NA"
set route_parse_ok [parse_unrouted_nets \
    $route_status_text unrouted_nets]

set total_luts "NA"
set logic_luts "NA"
set lutrams "NA"
set srls "NA"
set ffs "NA"
set ramb36 "NA"
set ramb18 "NA"
set dsp_blocks "NA"

set utilization_parse_ok [parse_top_utilization \
    $utilization_text $top_name \
    total_luts logic_luts lutrams srls \
    ffs ramb36 ramb18 dsp_blocks]

set latch_cells [get_cells -quiet -hier -filter {
  PRIMITIVE_TYPE =~ LATCH.*
}]
set latch_count [llength $latch_cells]

set timing_state "TIMING_UNKNOWN"
if {$timing_parse_ok && $route_parse_ok} {
  if {
      ($route_state eq "ROUTE_COMPLETE") &&
      ($unrouted_nets == 0) &&
      ($setup_failing_endpoints == 0) &&
      ($hold_failing_endpoints == 0) &&
      ($setup_wns >= 0.0) &&
      ($hold_whs >= 0.0)
  } {
    set timing_state "TIMING_MET"
  } else {
    set timing_state "TIMING_NOT_MET"
  }
}

set status_text "STAGE2F_RUN_COMPLETE\n"
append_status_line status_text "TOP" $top_name
append_status_line status_text "PART" $part_name
append_status_line status_text "CLOCK_PERIOD_NS" $clock_period_ns
append_status_line status_text "SYNTH_STATE" $synth_state
append_status_line status_text "OPT_STATE" $opt_state
append_status_line status_text "PLACE_STATE" $place_state
append_status_line status_text "PHYS_OPT_STATE" $phys_opt_state
append_status_line status_text "ROUTE_STATE" $route_state
append_status_line status_text "SETUP_WNS_NS" $setup_wns
append_status_line status_text "SETUP_TNS_NS" $setup_tns
append_status_line status_text \
    "SETUP_FAILING_ENDPOINTS" $setup_failing_endpoints
append_status_line status_text \
    "SETUP_TOTAL_ENDPOINTS" $setup_total_endpoints
append_status_line status_text "HOLD_WHS_NS" $hold_whs
append_status_line status_text "HOLD_THS_NS" $hold_ths
append_status_line status_text \
    "HOLD_FAILING_ENDPOINTS" $hold_failing_endpoints
append_status_line status_text \
    "HOLD_TOTAL_ENDPOINTS" $hold_total_endpoints
append_status_line status_text "UNROUTED_NETS" $unrouted_nets
append_status_line status_text "LATCH_COUNT" $latch_count
append_status_line status_text "TOTAL_LUTS" $total_luts
append_status_line status_text "LOGIC_LUTS" $logic_luts
append_status_line status_text "LUTRAMS" $lutrams
append_status_line status_text "SRLS" $srls
append_status_line status_text "FFS" $ffs
append_status_line status_text "RAMB36" $ramb36
append_status_line status_text "RAMB18" $ramb18
append_status_line status_text "DSP_BLOCKS" $dsp_blocks
append_status_line status_text \
    "CONGESTION_REPORT_GENERATED" $congestion_report_generated
append_status_line status_text \
    "POWER_REPORT_GENERATED" $power_report_generated
append_status_line status_text "ERROR_COUNT" "NA"
append_status_line status_text "CRITICAL_WARNING_COUNT" "NA"
append_status_line status_text "TIMING_STATE" $timing_state
append_status_line status_text "CHECKPOINT" $post_route_checkpoint

write_text \
    [file join $result_dir stage2f_post_route_status.txt] \
    $status_text

if {$optional_report_warnings ne ""} {
  write_text \
      [file join $result_dir optional_report_warnings.txt] \
      $optional_report_warnings
}

puts "============================================================"
puts "run_stage2f_post_route: COMPLETE"
puts "Route state             : $route_state"
puts "Unrouted nets           : $unrouted_nets"
puts "Setup WNS/TNS           : $setup_wns / $setup_tns ns"
puts "Setup failing endpoints : $setup_failing_endpoints"
puts "Hold WHS/THS            : $hold_whs / $hold_ths ns"
puts "Hold failing endpoints  : $hold_failing_endpoints"
puts "Timing state            : $timing_state"
puts "LUT / FF                : $total_luts / $ffs"
puts "RAMB36 / RAMB18 / DSP   : $ramb36 / $ramb18 / $dsp_blocks"
puts "Latch count             : $latch_count"
puts "Reports                 : $result_dir"
puts "============================================================"

if {!$timing_parse_ok} {
  puts stderr "run_stage2f_post_route: timing summary parsing failed"
  exit 2
}
if {!$route_parse_ok} {
  puts stderr "run_stage2f_post_route: route status parsing failed"
  exit 3
}
if {!$utilization_parse_ok} {
  puts stderr "run_stage2f_post_route: utilization parsing failed"
  exit 4
}
if {$timing_state ne "TIMING_MET"} {
  puts stderr "run_stage2f_post_route: implementation completed but timing/route acceptance failed"
  exit 5
}

exit 0
