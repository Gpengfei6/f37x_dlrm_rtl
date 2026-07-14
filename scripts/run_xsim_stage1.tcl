set script_path [file normalize [info script]]
set project_root [file normalize [file join [file dirname $script_path] ..]]
cd $project_root
file mkdir logs
file mkdir results
if {[file exists xsim.dir]} {
  file delete -force xsim.dir
}
if {[file exists work/xsim]} {
  file delete -force work/xsim
}
file mkdir work/xsim
foreach stale_file [list results/rtl_top_outputs.hex results/xsim_stage1_status.txt] {
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
  rtl/include/dlrm_config_pkg.sv \
  rtl/common/rv_fifo.sv \
  rtl/common/saturating_round.sv \
  rtl/common/relu_quant.sv \
  rtl/compute/dot_product_core.sv \
  rtl/compute/dense_layer_core.sv \
  rtl/memory/embedding_mem_model.sv \
  rtl/pipeline/minimal_recommendation_pipeline.sv \
  rtl/top/dlrm_minimal_top.sv]

set testbenches [list \
  tb_rv_fifo \
  tb_saturating_round \
  tb_relu_quant \
  tb_dot_product_core \
  tb_dense_layer_core \
  tb_embedding_mem_model \
  tb_minimal_recommendation_pipeline \
  tb_dlrm_minimal_top]

set compile_files $rtl_files
foreach testbench $testbenches {
  lappend compile_files "tb/${testbench}.sv"
}

set compile_command [linsert $compile_files 0 xvlog -sv]
lassign [run_logged $compile_command logs/xvlog_stage1.log] compile_rc compile_output
if {$compile_rc != 0} {
  puts "run_xsim_stage1: FAIL - xvlog"
  write_text results/xsim_stage1_status.txt "xvlog COMPILE FAIL $compile_rc\n"
  exit 1
}

set overall_fail 0
set status_lines "xvlog COMPILE PASS 0\n"
foreach testbench $testbenches {
  set snapshot "${testbench}_snapshot"
  lassign [run_logged [list xelab -debug typical $testbench -s $snapshot] \
      "logs/xelab_${testbench}.log"] elaborate_rc elaborate_output
  if {$elaborate_rc != 0} {
    append status_lines "$testbench ELAB FAIL $elaborate_rc\n"
    puts "$testbench: FAIL - elaboration"
    set overall_fail 1
    continue
  }
  append status_lines "$testbench ELAB PASS 0\n"

  lassign [run_logged [list xsim $snapshot -runall] \
      "logs/xsim_${testbench}.log"] simulation_rc simulation_output
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

write_text results/xsim_stage1_status.txt $status_lines
if {$overall_fail} {
  puts "run_xsim_stage1: FAIL"
  exit 1
}
puts "run_xsim_stage1: PASS"
exit 0
