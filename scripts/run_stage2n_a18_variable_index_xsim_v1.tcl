# Stage 2N-A18 variable-index public-kernel XSim runtime.
# Local RTL/XSim only. Does not program a board or write docs/evidence.
# A Tcl catch of `run all` must fail the process. `quit` with no code is
# not a PASS; the PowerShell wrapper still requires TB completion markers.

set tb_top tb_dlrm_f37x_rtl_kernel_stage2n_a18_v1
set rc 0
if {[catch {run all} err]} {
    puts "A18_XSIM_RUN_ERROR=$err"
    set rc 1
}
if {$rc != 0} {
    if {[catch {quit -force -code 1}]} {
        exit 1
    }
}
if {[catch {quit -code 0}]} {
    exit 0
}
