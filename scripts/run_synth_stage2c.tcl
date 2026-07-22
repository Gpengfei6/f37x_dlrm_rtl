# Stage 2C: out-of-context synthesis review for the multilayer MLP controller.
# Vivado 2020.2-compatible Tcl; locally reviewed with Vivado 2022.1.
#
# Optional environment override:
#   $env:STAGE2C_PART = "xc7a200tfbg484-2"
#
# Run from the repository root:
#   vivado -mode batch -nolog -nojournal -source scripts/run_synth_stage2c.tcl

set script_path [file normalize [info script]]
set project_root [file normalize [file join [file dirname $script_path] ..]]
cd $project_root

set top_name "mlp_sequence_controller"
set default_part "xc7a200tfbg484-2"

if {[info exists ::env(STAGE2C_PART)] &&
    [string length $::env(STAGE2C_PART)] > 0} {
  set part_name $::env(STAGE2C_PART)
} else {
  set part_name $default_part
}

set result_dir [file normalize "results/stage2c"]
set work_dir [file normalize "work/stage2c"]

if {[file exists $result_dir]} {
  file delete -force $result_dir
}
if {[file exists $work_dir]} {
  file delete -force $work_dir
}

file mkdir $result_dir
file mkdir $work_dir

proc write_text {path text} {
  set handle [open $path w]
  puts -nonewline $handle $text
  close $handle
}

proc fail_stage2c {result_dir message} {
  puts stderr "run_synth_stage2c: FAIL - $message"
  write_text \
      [file join $result_dir stage2c_synth_status.txt] \
      "STAGE2C_SYNTH_FAIL\n$message\n"
  exit 1
}

puts "============================================================"
puts "Stage 2C multilayer MLP synthesis review"
puts "Top module : $top_name"
puts "Part       : $part_name"
puts "Clock      : 10.000 ns (100 MHz)"
puts "Mode       : out_of_context"
puts "============================================================"

if {[llength [get_parts -quiet $part_name]] == 0} {
  fail_stage2c $result_dir "Vivado part not found: $part_name"
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
    fail_stage2c $result_dir "Missing RTL source: $rtl_file"
  }
}

set xdc_file "constraints/stage2c_mlp_clock.xdc"
if {![file exists $xdc_file]} {
  fail_stage2c $result_dir "Missing constraint file: $xdc_file"
}

set read_rc [catch {
  foreach rtl_file $rtl_files {
    read_verilog -sv $rtl_file
  }
  read_xdc $xdc_file
} read_message]

if {$read_rc != 0} {
  fail_stage2c $result_dir "Source/constraint read failed:\n$read_message"
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
  fail_stage2c $result_dir "synth_design failed:\n$synth_message"
}

set checkpoint_path [file join $result_dir post_synth.dcp]
write_checkpoint -force $checkpoint_path

report_utilization \
    -hierarchical \
    -hierarchical_depth 4 \
    -file [file join $result_dir post_synth_utilization.rpt]

set ram_report_path [file join $result_dir post_synth_ram_utilization.rpt]
if {[llength [info commands report_ram_utilization]] > 0} {
  report_ram_utilization -file $ram_report_path
} else {
  write_text $ram_report_path \
      "report_ram_utilization is unavailable in this Vivado version.\n"
}

report_timing_summary \
    -delay_type max \
    -max_paths 20 \
    -report_unconstrained \
    -check_timing_verbose \
    -file [file join $result_dir post_synth_timing_summary.rpt]

check_timing \
    -verbose \
    -file [file join $result_dir post_synth_check_timing.rpt]

report_clock_utilization \
    -file [file join $result_dir post_synth_clock_utilization.rpt]

report_high_fanout_nets \
    -max_nets 50 \
    -file [file join $result_dir post_synth_high_fanout.rpt]

report_methodology \
    -file [file join $result_dir post_synth_methodology.rpt]

report_drc \
    -file [file join $result_dir post_synth_drc.rpt]

set worst_path [lindex [get_timing_paths -delay_type max -max_paths 1] 0]
if {$worst_path eq ""} {
  set worst_slack "NA"
  set timing_state "NO_TIMING_PATH"
} else {
  set worst_slack [get_property SLACK $worst_path]
  if {$worst_slack >= 0.0} {
    set timing_state "TIMING_MET"
  } else {
    set timing_state "TIMING_NEGATIVE"
  }
}

set latch_cells [get_cells -quiet -hier -filter {
  PRIMITIVE_TYPE =~ LATCH.*
}]
set latch_count [llength $latch_cells]

set status_text ""
append status_text "STAGE2C_SYNTH_COMPLETE\n"
append status_text "TOP=$top_name\n"
append status_text "PART=$part_name\n"
append status_text "CLOCK_PERIOD_NS=10.000\n"
append status_text "TIMING_STATE=$timing_state\n"
append status_text "WORST_SLACK_NS=$worst_slack\n"
append status_text "LATCH_COUNT=$latch_count\n"
append status_text "RAM_REPORT=$ram_report_path\n"
append status_text "CHECKPOINT=$checkpoint_path\n"

write_text \
    [file join $result_dir stage2c_synth_status.txt] \
    $status_text

puts "============================================================"
puts "run_synth_stage2c: COMPLETE"
puts "Timing state : $timing_state"
puts "Worst slack  : $worst_slack ns"
puts "Latch count  : $latch_count"
puts "Reports      : $result_dir"
puts "============================================================"

exit 0
