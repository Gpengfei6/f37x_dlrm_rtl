# Stage 2F: Artix-7 out-of-context post-route implementation feasibility.
# Vivado 2020.2-compatible Tcl; intended for local Vivado 2022.1 precheck and
# exact-source server reproduction under Vivado 2020.2.
#
# Optional environment overrides (both paths must remain inside the repository):
#   STAGE2F_RESULT_DIR result directory (default results/stage2f)
#   STAGE2F_WORK_DIR   work directory (default work/stage2f)
#
# Run from any directory:
#   vivado -mode batch -nojournal -log logs/vivado_stage2f_post_route.log \
#       -source scripts/run_stage2f_post_route.tcl

set script_path [file normalize [info script]]
set project_root [file normalize [file join [file dirname $script_path] ..]]
cd $project_root

set top_name "mlp_sequence_controller"
set part_name "xc7a200tfbg484-2"
set clock_period_ns "10.000"

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

proc read_text {path} {
  set handle [open $path r]
  set text [read $handle]
  close $handle
  return $text
}

proc normalized_path_is_within {candidate root} {
  set normalized_candidate [string map {\\ /} [file normalize $candidate]]
  set normalized_root [string trimright \
      [string map {\\ /} [file normalize $root]] "/"]
  if {$::tcl_platform(platform) eq "windows"} {
    set normalized_candidate [string tolower $normalized_candidate]
    set normalized_root [string tolower $normalized_root]
  }
  if {$normalized_candidate eq $normalized_root} {
    return 1
  }
  return [expr {
      [string first "${normalized_root}/" $normalized_candidate] == 0
  }]
}

proc normalized_paths_equal {left right} {
  set normalized_left [string map {\\ /} [file normalize $left]]
  set normalized_right [string map {\\ /} [file normalize $right]]
  if {$::tcl_platform(platform) eq "windows"} {
    return [string equal -nocase $normalized_left $normalized_right]
  }
  return [string equal $normalized_left $normalized_right]
}

if {![normalized_path_is_within $result_dir $project_root]} {
  puts stderr "run_stage2f_post_route: FAIL - result directory is outside repository"
  exit 1
}
if {![normalized_path_is_within $work_dir $project_root]} {
  puts stderr "run_stage2f_post_route: FAIL - work directory is outside repository"
  exit 1
}
if {[normalized_paths_equal $result_dir $project_root] ||
    [normalized_paths_equal $work_dir $project_root]} {
  puts stderr "run_stage2f_post_route: FAIL - refusing to use repository root as generated directory"
  exit 1
}
if {[normalized_paths_equal $result_dir $work_dir]} {
  puts stderr "run_stage2f_post_route: FAIL - result and work directories must differ"
  exit 1
}

if {[file exists $result_dir]} {
  file delete -force $result_dir
}
if {[file exists $work_dir]} {
  file delete -force $work_dir
}
file mkdir $result_dir
file mkdir $work_dir

array set stage2f {
  SYNTH_STATE NOT_RUN
  OPT_STATE NOT_RUN
  PLACE_STATE NOT_RUN
  PHYS_OPT_STATE NOT_RUN
  ROUTE_STATE NOT_RUN
  SETUP_WNS_NS NA
  SETUP_TNS_NS NA
  SETUP_FAILING_ENDPOINTS NA
  HOLD_WHS_NS NA
  HOLD_THS_NS NA
  HOLD_FAILING_ENDPOINTS NA
  UNROUTED_NETS NA
  LATCH_COUNT NA
  TOTAL_LUTS NA
  LOGIC_LUTS NA
  LUTRAMS NA
  SRLS NA
  FFS NA
  RAMB36 NA
  RAMB18 NA
  DSP_BLOCKS NA
  ERROR_COUNT 0
  CRITICAL_WARNING_COUNT 0
  DRC_ERROR_COUNT NA
  DRC_CRITICAL_WARNING_COUNT NA
  METHODOLOGY_CRITICAL_WARNING_COUNT NA
  POWER_REPORT_STATE NOT_RUN
  TIMING_STATE NOT_EVALUATED
}
set command_error_count 0

proc write_stage2f_status {marker} {
  global result_dir top_name part_name clock_period_ns stage2f

  set status_text "$marker\n"
  append status_text "TOP=$top_name\n"
  append status_text "PART=$part_name\n"
  append status_text "CLOCK_PERIOD_NS=$clock_period_ns\n"
  foreach key [list \
      SYNTH_STATE OPT_STATE PLACE_STATE PHYS_OPT_STATE ROUTE_STATE \
      SETUP_WNS_NS SETUP_TNS_NS SETUP_FAILING_ENDPOINTS \
      HOLD_WHS_NS HOLD_THS_NS HOLD_FAILING_ENDPOINTS \
      UNROUTED_NETS LATCH_COUNT TOTAL_LUTS LOGIC_LUTS LUTRAMS SRLS \
      FFS RAMB36 RAMB18 DSP_BLOCKS ERROR_COUNT CRITICAL_WARNING_COUNT \
      DRC_ERROR_COUNT DRC_CRITICAL_WARNING_COUNT \
      METHODOLOGY_CRITICAL_WARNING_COUNT POWER_REPORT_STATE TIMING_STATE] {
    append status_text "$key=$stage2f($key)\n"
  }
  append status_text "RESULT_DIR=$result_dir\n"
  append status_text "POST_ROUTE_CHECKPOINT=[file join $result_dir post_route.dcp]\n"
  write_text [file join $result_dir stage2f_post_route_status.txt] $status_text
}

proc fail_stage2f {state_key message} {
  global stage2f command_error_count
  incr command_error_count
  set stage2f(ERROR_COUNT) $command_error_count
  if {$state_key ne ""} {
    set stage2f($state_key) FAIL
  }
  write_stage2f_status "STAGE2F_RUN_FAIL"
  puts stderr "run_stage2f_post_route: FAIL - $message"
  exit 1
}

proc sum_negative_slack {paths} {
  set total 0.0
  foreach path $paths {
    set slack [get_property SLACK $path]
    if {$slack < 0.0} {
      set total [expr {$total + $slack}]
    }
  }
  return $total
}

proc report_rule_severity_count {report_path severity} {
  set total 0
  set text [read_text $report_path]
  foreach line [split $text "\n"] {
    set line_severity ""
    set violations 0
    if {[regexp {^\|\s*[^|]+\|\s*([^|]+)\s*\|.*\|\s*([0-9]+)\s*\|\s*$} \
        $line -> line_severity violations]} {
      if {[string equal -nocase [string trim $line_severity] $severity]} {
        set total [expr {$total + $violations}]
      }
    }
  }
  return $total
}

puts "============================================================"
puts "Stage 2F Artix-7 OOC post-route implementation feasibility"
puts "Top module : $top_name"
puts "Part       : $part_name"
puts "Clock      : $clock_period_ns ns (100 MHz)"
puts "Result dir : $result_dir"
puts "Work dir   : $work_dir"
puts "Mode       : out_of_context implementation"
puts "============================================================"

if {[llength [get_parts -quiet $part_name]] == 0} {
  fail_stage2f "SYNTH_STATE" "Vivado part not found: $part_name"
}

# Keep this source order identical to scripts/run_synth_stage2c.tcl.
set rtl_files [list \
  [file join $project_root rtl/common/rv_fifo.sv] \
  [file join $project_root rtl/common/runtime_relu_quant.sv] \
  [file join $project_root rtl/compute/mac_lane.sv] \
  [file join $project_root rtl/memory/banked_activation_buffer.sv] \
  [file join $project_root rtl/memory/local_weight_provider.sv] \
  [file join $project_root rtl/compute/vector_dot_product_core.sv] \
  [file join $project_root rtl/compute/dense_layer_engine.sv] \
  [file join $project_root rtl/control/mlp_sequence_controller.sv]]

foreach rtl_file $rtl_files {
  if {![file exists $rtl_file]} {
    fail_stage2f "SYNTH_STATE" "Missing RTL source: $rtl_file"
  }
}

set xdc_file [file join $project_root constraints/stage2c_mlp_clock.xdc]
if {![file exists $xdc_file]} {
  fail_stage2f "SYNTH_STATE" "Missing constraint file: $xdc_file"
}

# Keep all non-project Vivado scratch state under the clean Stage 2F work tree.
cd $work_dir

set read_rc [catch {
  foreach rtl_file $rtl_files {
    read_verilog -sv $rtl_file
  }
  read_xdc $xdc_file
} read_message]
if {$read_rc != 0} {
  fail_stage2f "SYNTH_STATE" "Source/constraint read failed:\n$read_message"
}

set synth_rc [catch {
  synth_design \
      -top $top_name \
      -part $part_name \
      -mode out_of_context \
      -flatten_hierarchy rebuilt \
      -directive Default
} synth_message]
if {$synth_rc != 0} {
  fail_stage2f "SYNTH_STATE" "synth_design failed:\n$synth_message"
}
set stage2f(SYNTH_STATE) COMPLETE
if {[catch {
  write_checkpoint -force [file join $result_dir post_synth.dcp]
} checkpoint_message]} {
  fail_stage2f "" "post-synth checkpoint failed:\n$checkpoint_message"
}

set opt_rc [catch {opt_design} opt_message]
if {$opt_rc != 0} {
  fail_stage2f "OPT_STATE" "opt_design failed:\n$opt_message"
}
set stage2f(OPT_STATE) COMPLETE
if {[catch {
  write_checkpoint -force [file join $result_dir post_opt.dcp]
} checkpoint_message]} {
  fail_stage2f "" "post-opt checkpoint failed:\n$checkpoint_message"
}

set place_rc [catch {place_design} place_message]
if {$place_rc != 0} {
  fail_stage2f "PLACE_STATE" "place_design failed:\n$place_message"
}
set stage2f(PLACE_STATE) COMPLETE
if {[catch {
  write_checkpoint -force [file join $result_dir post_place.dcp]
} checkpoint_message]} {
  fail_stage2f "" "post-place checkpoint failed:\n$checkpoint_message"
}

set phys_opt_rc [catch {phys_opt_design} phys_opt_message]
if {$phys_opt_rc != 0} {
  fail_stage2f "PHYS_OPT_STATE" "phys_opt_design failed:\n$phys_opt_message"
}
set stage2f(PHYS_OPT_STATE) COMPLETE

set route_rc [catch {route_design} route_message]
if {$route_rc != 0} {
  fail_stage2f "ROUTE_STATE" "route_design failed:\n$route_message"
}
set stage2f(ROUTE_STATE) COMPLETE
if {[catch {
  write_checkpoint -force [file join $result_dir post_route.dcp]
} checkpoint_message]} {
  fail_stage2f "" "post-route checkpoint failed:\n$checkpoint_message"
}

set report_rc [catch {
  report_timing_summary \
      -delay_type min_max \
      -max_paths 20 \
      -report_unconstrained \
      -check_timing_verbose \
      -file [file join $result_dir post_route_timing_summary.rpt]
  report_utilization \
      -hierarchical \
      -hierarchical_depth 4 \
      -file [file join $result_dir post_route_utilization.rpt]
  report_route_status \
      -file [file join $result_dir post_route_route_status.rpt]
  report_drc \
      -file [file join $result_dir post_route_drc.rpt]
  report_methodology \
      -file [file join $result_dir post_route_methodology.rpt]
  report_clock_utilization \
      -file [file join $result_dir post_route_clock_utilization.rpt]
  report_high_fanout_nets \
      -max_nets 50 \
      -file [file join $result_dir post_route_high_fanout.rpt]
  report_design_analysis \
      -congestion \
      -file [file join $result_dir post_route_congestion.rpt]
} report_message]
if {$report_rc != 0} {
  fail_stage2f "" "required post-route report failed:\n$report_message"
}

set power_report_path [file join $result_dir post_route_power.rpt]
if {[llength [info commands report_power]] == 0} {
  set stage2f(POWER_REPORT_STATE) UNAVAILABLE
  write_text $power_report_path \
      "report_power is unavailable in this Vivado version; non-blocking OOC boundary.\n"
} else {
  set power_rc [catch {
    report_power -file $power_report_path
  } power_message]
  if {$power_rc != 0} {
    set stage2f(POWER_REPORT_STATE) UNAVAILABLE
    write_text $power_report_path \
        "report_power could not run in this OOC context; non-blocking boundary.\n$power_message\n"
  } else {
    set stage2f(POWER_REPORT_STATE) COMPLETE
  }
}

set setup_path [lindex [get_timing_paths -quiet \
    -delay_type max -max_paths 1] 0]
set hold_path [lindex [get_timing_paths -quiet \
    -delay_type min -max_paths 1] 0]
if {$setup_path eq "" || $hold_path eq ""} {
  set stage2f(TIMING_STATE) NO_TIMING_PATH
  write_stage2f_status "STAGE2F_RUN_COMPLETE"
  puts stderr "run_stage2f_post_route: FAIL - setup or hold timing path is missing"
  exit 1
}

set setup_failing_paths [get_timing_paths -quiet \
    -delay_type max -slack_lesser_than 0.0 -nworst 1 -max_paths 100000]
set hold_failing_paths [get_timing_paths -quiet \
    -delay_type min -slack_lesser_than 0.0 -nworst 1 -max_paths 100000]

set stage2f(SETUP_WNS_NS) [format "%.3f" [get_property SLACK $setup_path]]
set stage2f(SETUP_TNS_NS) \
    [format "%.3f" [sum_negative_slack $setup_failing_paths]]
set stage2f(SETUP_FAILING_ENDPOINTS) [llength $setup_failing_paths]
set stage2f(HOLD_WHS_NS) [format "%.3f" [get_property SLACK $hold_path]]
set stage2f(HOLD_THS_NS) \
    [format "%.3f" [sum_negative_slack $hold_failing_paths]]
set stage2f(HOLD_FAILING_ENDPOINTS) [llength $hold_failing_paths]

set incomplete_route_nets [get_nets -quiet -hierarchical -filter {
  ROUTE_STATUS == UNROUTED || ROUTE_STATUS == PARTIAL
}]
set stage2f(UNROUTED_NETS) [llength $incomplete_route_nets]

set latch_cells [get_cells -quiet -hierarchical -filter {
  PRIMITIVE_TYPE =~ LATCH.*
}]
set stage2f(LATCH_COUNT) [llength $latch_cells]

set utilization_path [file join $result_dir post_route_utilization.rpt]
set utilization_text [read_text $utilization_path]
set utilization_pattern [format {
^\|\s*%s\s*\|\s*\(top\)\s*\|\s*([0-9]+)\s*\|\s*([0-9]+)\s*\|\s*([0-9]+)\s*\|\s*([0-9]+)\s*\|\s*([0-9]+)\s*\|\s*([0-9]+)\s*\|\s*([0-9]+)\s*\|\s*([0-9]+)\s*\|
} $top_name]
if {![regexp -line $utilization_pattern $utilization_text -> \
    total_luts logic_luts lutrams srls ffs ramb36 ramb18 dsp_blocks]} {
  fail_stage2f "" "could not parse top-level post-route utilization"
}
set stage2f(TOTAL_LUTS) $total_luts
set stage2f(LOGIC_LUTS) $logic_luts
set stage2f(LUTRAMS) $lutrams
set stage2f(SRLS) $srls
set stage2f(FFS) $ffs
set stage2f(RAMB36) $ramb36
set stage2f(RAMB18) $ramb18
set stage2f(DSP_BLOCKS) $dsp_blocks

set drc_path [file join $result_dir post_route_drc.rpt]
set methodology_path [file join $result_dir post_route_methodology.rpt]
set stage2f(DRC_ERROR_COUNT) \
    [report_rule_severity_count $drc_path "Error"]
set stage2f(DRC_CRITICAL_WARNING_COUNT) \
    [report_rule_severity_count $drc_path "Critical Warning"]
set stage2f(METHODOLOGY_CRITICAL_WARNING_COUNT) \
    [report_rule_severity_count $methodology_path "Critical Warning"]
set stage2f(ERROR_COUNT) $command_error_count

if {$stage2f(ROUTE_STATE) eq "COMPLETE" &&
    $stage2f(UNROUTED_NETS) == 0 &&
    $stage2f(SETUP_FAILING_ENDPOINTS) == 0 &&
    $stage2f(HOLD_FAILING_ENDPOINTS) == 0 &&
    $stage2f(SETUP_WNS_NS) >= 0.0 &&
    $stage2f(HOLD_WHS_NS) >= 0.0} {
  set stage2f(TIMING_STATE) TIMING_MET
} else {
  set stage2f(TIMING_STATE) TIMING_FAILED
}

write_stage2f_status "STAGE2F_RUN_COMPLETE"

puts "============================================================"
puts "run_stage2f_post_route: COMPLETE"
puts "Route state       : $stage2f(ROUTE_STATE)"
puts "Unrouted nets     : $stage2f(UNROUTED_NETS)"
puts "Setup WNS/TNS     : $stage2f(SETUP_WNS_NS) / $stage2f(SETUP_TNS_NS) ns"
puts "Setup failures    : $stage2f(SETUP_FAILING_ENDPOINTS)"
puts "Hold WHS/THS      : $stage2f(HOLD_WHS_NS) / $stage2f(HOLD_THS_NS) ns"
puts "Hold failures     : $stage2f(HOLD_FAILING_ENDPOINTS)"
puts "Timing state      : $stage2f(TIMING_STATE)"
puts "Post-route DCP    : [file join $result_dir post_route.dcp]"
puts "Reports           : $result_dir"
puts "============================================================"

if {$stage2f(TIMING_STATE) ne "TIMING_MET"} {
  puts stderr "run_stage2f_post_route: FAIL - post-route timing acceptance not met"
  exit 1
}
if {$stage2f(DRC_ERROR_COUNT) != 0} {
  puts stderr "run_stage2f_post_route: FAIL - post-route DRC errors present"
  exit 1
}
exit 0
