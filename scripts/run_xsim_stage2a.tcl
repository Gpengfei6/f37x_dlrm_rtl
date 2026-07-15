set script_path [file normalize [info script]]
set project_root [file normalize [file join [file dirname $script_path] ..]]
cd $project_root
file mkdir logs
file mkdir results
if {[file exists xsim.dir]} {
  file delete -force xsim.dir
}
if {[file exists work/xsim_stage2a]} {
  file delete -force work/xsim_stage2a
}
file mkdir work/xsim_stage2a
foreach stale_file [list results/xsim_stage2a_status.txt] {
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
      if {[llength $error_code] >= 3 && [lindex $error_code 0] eq "CHILDSTATUS"} {
        set exit_code [lindex $error_code 2]
      }
    }
  }
  write_text $log_path "$output\n"
  return [list $exit_code $output]
}

set rtl_files [list \
  rtl/common/rv_fifo.sv \
  rtl/common/runtime_relu_quant.sv \
  rtl/compute/mac_lane.sv \
  rtl/memory/banked_activation_buffer.sv \
  rtl/memory/local_weight_provider.sv \
  rtl/compute/vector_dot_product_core.sv \
  rtl/compute/dense_layer_engine.sv]

set testbenches [list \
  tb_mac_lane \
  tb_runtime_relu_quant \
  tb_banked_activation_buffer \
  tb_local_weight_provider \
  tb_vector_dot_product_core \
  tb_dense_layer_engine]

set compile_files $rtl_files
foreach testbench $testbenches {
  lappend compile_files "tb/${testbench}.sv"
}

set compile_command [linsert $compile_files 0 xvlog -sv]
lassign [run_logged $compile_command logs/xvlog_stage2a.log] compile_rc compile_output
if {$compile_rc != 0} {
  puts "run_xsim_stage2a: FAIL - xvlog"
  write_text results/xsim_stage2a_status.txt "xvlog COMPILE FAIL $compile_rc\n"
  exit 1
}

set overall_fail 0
set status_lines "xvlog COMPILE PASS 0\n"
foreach testbench $testbenches {
  set snapshot "${testbench}_stage2a_snapshot"
  lassign [run_logged [list xelab -debug typical --timescale 1ns/1ps \
      $testbench -s $snapshot] \
      "logs/xelab_stage2a_${testbench}.log"] elaborate_rc elaborate_output
  if {$elaborate_rc != 0} {
    append status_lines "$testbench ELAB FAIL $elaborate_rc\n"
    puts "$testbench: FAIL - elaboration"
    set overall_fail 1
    continue
  }
  append status_lines "$testbench ELAB PASS 0\n"

  lassign [run_logged [list xsim $snapshot -runall] \
      "logs/xsim_stage2a_${testbench}.log"] simulation_rc simulation_output
  set pass_marker "${testbench}: PASS"
  if {$simulation_rc != 0 || [string first $pass_marker $simulation_output] < 0} {
    append status_lines "$testbench SIM FAIL $simulation_rc\n"
    puts "$testbench: FAIL - simulation or PASS marker"
    set overall_fail 1
  } else {
    append status_lines "$testbench SIM PASS 0\n"
    puts "$testbench: PASS"
  }
}

write_text results/xsim_stage2a_status.txt $status_lines
if {$overall_fail} {
  puts "run_xsim_stage2a: FAIL"
  exit 1
}
puts "run_xsim_stage2a: PASS"
exit 0
