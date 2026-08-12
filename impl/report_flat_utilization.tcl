# Generate the device-level resource table from an implemented checkpoint.
# Usage: vivado -mode batch -source impl/report_flat_utilization.tcl -tclargs <routed.dcp> <report.rpt>
if {$argc != 2} {
    error "Usage: report_flat_utilization.tcl <routed.dcp> <report.rpt>"
}
open_checkpoint [lindex $argv 0]
report_utilization -file [lindex $argv 1]
