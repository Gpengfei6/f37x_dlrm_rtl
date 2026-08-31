# Read-only routed-design reporting for a user-executed A16.2 Vitis link.
# Required environment variables: A16_2_ROUTED_DCP and A16_2_REPORT_DIR.

proc fail {message} {
    error $message
}

foreach required_env {A16_2_ROUTED_DCP A16_2_REPORT_DIR} {
    if {![info exists ::env($required_env)] || $::env($required_env) eq ""} {
        fail "Missing required environment variable: $required_env"
    }
}
set dcp_path [file normalize $::env(A16_2_ROUTED_DCP)]
set report_dir [file normalize $::env(A16_2_REPORT_DIR)]
if {![file isfile $dcp_path]} {
    fail "Routed checkpoint does not exist: $dcp_path"
}
if {[file exists $report_dir]} {
    fail "Refusing to overwrite routed report directory: $report_dir"
}
file mkdir $report_dir
open_checkpoint $dcp_path

report_timing_summary -delay_type min_max -max_paths 100 \
    -file [file join $report_dir post_route_timing_summary.rpt]
report_timing -delay_type max -max_paths 100 -nworst 1 \
    -file [file join $report_dir post_route_worst_setup_paths.rpt]
report_clocks -file [file join $report_dir post_route_clocks.rpt]
report_utilization -hierarchical -hierarchical_depth 3 \
    -file [file join $report_dir post_route_utilization.rpt]
report_drc -file [file join $report_dir post_route_drc.rpt]
report_methodology -file [file join $report_dir post_route_methodology.rpt]
check_timing -verbose -file [file join $report_dir post_route_check_timing.rpt]

set worst_path [get_timing_paths -quiet -delay_type max -max_paths 1]
if {[llength $worst_path] == 0} {
    set wns "NOT_PARSED"
    set worst_startpoint "NOT_PARSED"
    set worst_endpoint "NOT_PARSED"
} else {
    set wns [get_property SLACK [lindex $worst_path 0]]
    set worst_startpoint [get_property STARTPOINT_PIN [lindex $worst_path 0]]
    set worst_endpoint [get_property ENDPOINT_PIN [lindex $worst_path 0]]
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
    return [llength [get_cells -quiet -hierarchical -filter "REF_NAME =~ $pattern"]]
}
set lut_count [primitive_count LUT*]
set ff_count [primitive_count FD*]
set ramb36_count [primitive_count RAMB36*]
set ramb18_count [primitive_count RAMB18*]
set uram_count [primitive_count URAM*]
set dsp_count [primitive_count DSP48*]
set latch_count [primitive_count LD*]

set drc_error_count 0
set drc_critical_count 0
if {[llength [info commands get_drc_violations]] != 0} {
    foreach violation [get_drc_violations -quiet] {
        set severity [get_property SEVERITY $violation]
        if {$severity eq "Error"} {
            incr drc_error_count
        } elseif {$severity eq "Critical Warning"} {
            incr drc_critical_count
        }
    }
}
set methodology_error_count 0
set methodology_critical_count 0
if {[llength [info commands get_methodology_violations]] != 0} {
    foreach violation [get_methodology_violations -quiet] {
        set severity [get_property SEVERITY $violation]
        if {$severity eq "Error"} {
            incr methodology_error_count
        } elseif {$severity eq "Critical Warning"} {
            incr methodology_critical_count
        }
    }
}
set clock_rows {}
foreach clock [get_clocks -quiet] {
    lappend clock_rows "[get_property NAME $clock]:[get_property PERIOD $clock]"
}

set metrics_path [file join $report_dir post_route_metrics.txt]
set metrics [open $metrics_path w]
puts $metrics "A16_2_VITIS_POST_ROUTE_REPORT=COMPLETE"
puts $metrics "ROUTED_DCP=$dcp_path"
puts $metrics "TARGET_PART=[get_property PART [current_design]]"
puts $metrics "REQUESTED_CLOCK_NS=10.000"
puts $metrics "REQUESTED_CLOCK_MHZ=100"
puts $metrics "WNS_NS=$wns"
puts $metrics "TNS_NS=[format %.3f $tns]"
puts $metrics "FAILING_ENDPOINTS=$failing_endpoints"
puts $metrics "WORST_STARTPOINT=$worst_startpoint"
puts $metrics "WORST_ENDPOINT=$worst_endpoint"
puts $metrics "CLOCK_COUNT=[llength $clock_rows]"
puts $metrics "CLOCKS=[join $clock_rows ,]"
puts $metrics "LUT=$lut_count"
puts $metrics "FF=$ff_count"
puts $metrics "RAMB36=$ramb36_count"
puts $metrics "RAMB18=$ramb18_count"
puts $metrics "URAM=$uram_count"
puts $metrics "DSP=$dsp_count"
puts $metrics "LATCH=$latch_count"
puts $metrics "DRC_ERROR_COUNT=$drc_error_count"
puts $metrics "DRC_CRITICAL_WARNING_COUNT=$drc_critical_count"
puts $metrics "METHODOLOGY_ERROR_COUNT=$methodology_error_count"
puts $metrics "METHODOLOGY_CRITICAL_WARNING_COUNT=$methodology_critical_count"
close $metrics

puts "A16_2_VITIS_POST_ROUTE_REPORT=COMPLETE"
puts "METRICS=$metrics_path"
close_design
