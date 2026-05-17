if {$argc < 5} {
    puts "ERROR: usage synth_one_top.tcl <repo_root> <part> <top> <out_dir> <rtl_files...>"
    exit 2
}

set repo_root [file normalize [lindex $argv 0]]
set part_name [lindex $argv 1]
set top_name  [lindex $argv 2]
set out_dir   [file normalize [lindex $argv 3]]
set rtl_files [lrange $argv 4 end]

file mkdir $out_dir
create_project -in_memory -part $part_name

foreach rel_file $rtl_files {
    set abs_file [file normalize [file join $repo_root $rel_file]]
    if {![file exists $abs_file]} {
        puts "ERROR: RTL file not found: $abs_file"
        exit 3
    }
    read_verilog -sv $abs_file
}

synth_design -top $top_name -part $part_name -flatten_hierarchy rebuilt

set clk_ports [get_ports -quiet clk]
if {[llength $clk_ports] > 0} {
    create_clock -name clk_100m -period 10.000 $clk_ports
}

check_timing -file [file join $out_dir "${top_name}_check_timing.rpt"]
report_utilization -file [file join $out_dir "${top_name}_utilization_synth.rpt"]
report_timing_summary -delay_type max -max_paths 10 -file [file join $out_dir "${top_name}_timing_summary_synth.rpt"]
write_checkpoint -force [file join $out_dir "${top_name}_synth.dcp"]

puts "SYNTH_CHECK PASS top=$top_name part=$part_name out_dir=$out_dir"
