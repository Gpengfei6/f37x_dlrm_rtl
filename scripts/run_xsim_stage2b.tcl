set script_path [file normalize [info script]]
set project_root [file normalize [file join [file dirname $script_path] ..]]
cd $project_root

file mkdir logs
file mkdir results

if {[file exists xsim.dir]} {
  file delete -force xsim.dir
}
if {[file exists work/xsim_stage2b]} {
  file delete -force work/xsim_stage2b
}
file mkdir work/xsim_stage2b

foreach stale_file [list results/xsim_stage2b_status.txt] {
  if {[file exists $stale_file]} {
    file delete -force $stale_file
  }
}

proc write_text {path text} {
  set handle [open $path w]
  puts -nonewline $handle $text
  close $handle
}

proc run_logged {arguments log_path} {
  set rc [catch {exec {*}$arguments 2>@1} output options]
  set exit_code 0
  if {$rc != 0} {
    set exit_code 1
    if {[dict exists $options -errorcode]} {
      set error_code [dict get $options -errorcode]
      if {[llength $error_code] >= 3 &&
          [lindex $error_code 0] eq "CHILDSTATUS"} {
        set exit_code [lindex $error_code 2]
      }
    }
  }
  write_text $log_path "$output\n"
  return [list $exit_code $output]
}

set compile_files [list \
  rtl/common/rv_fifo.sv \
  rtl/common/runtime_relu_quant.sv \
  rtl/compute/mac_lane.sv \
  rtl/memory/banked_activation_buffer.sv \
  rtl/memory/local_weight_provider.sv \
  rtl/compute/vector_dot_product_core.sv \
  rtl/compute/dense_layer_engine.sv \
  rtl/control/mlp_sequence_controller.sv \
  tb/tb_mlp_sequence_controller.sv]

lassign [run_logged \
    [linsert $compile_files 0 xvlog -sv] \
    logs/xvlog_stage2b.log] compile_rc compile_output

if {$compile_rc != 0} {
  puts "run_xsim_stage2b: FAIL - xvlog"
  write_text results/xsim_stage2b_status.txt \
      "xvlog COMPILE FAIL $compile_rc\n"
  exit 1
}

set snapshot "tb_mlp_sequence_controller_stage2b_snapshot"

lassign [run_logged \
    [list xelab -debug typical --timescale 1ns/1ps \
        tb_mlp_sequence_controller -s $snapshot] \
    logs/xelab_stage2b.log] elaborate_rc elaborate_output

if {$elaborate_rc != 0} {
  puts "run_xsim_stage2b: FAIL - elaboration"
  write_text results/xsim_stage2b_status.txt \
      "xvlog COMPILE PASS 0\ntb_mlp_sequence_controller ELAB FAIL $elaborate_rc\n"
  exit 1
}

lassign [run_logged \
    [list xsim $snapshot -runall] \
    logs/xsim_stage2b.log] simulation_rc simulation_output

set pass_marker "tb_mlp_sequence_controller: PASS"

if {$simulation_rc != 0 ||
    [string first $pass_marker $simulation_output] < 0} {
  puts "run_xsim_stage2b: FAIL - simulation or PASS marker"
  write_text results/xsim_stage2b_status.txt \
      "xvlog COMPILE PASS 0\ntb_mlp_sequence_controller ELAB PASS 0\ntb_mlp_sequence_controller SIM FAIL $simulation_rc\n"
  exit 1
}

write_text results/xsim_stage2b_status.txt \
    "xvlog COMPILE PASS 0\ntb_mlp_sequence_controller ELAB PASS 0\ntb_mlp_sequence_controller SIM PASS 0\n"

puts "tb_mlp_sequence_controller: PASS"
puts "run_xsim_stage2b: PASS"
exit 0
