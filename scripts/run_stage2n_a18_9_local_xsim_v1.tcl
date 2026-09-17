# Local A18.9 XSim runtime. A Tcl catch of `run all` must fail the process.
set rc 0
if {[catch {run all} err]} {
    puts "A18_9_XSIM_RUN_ERROR=$err"
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
