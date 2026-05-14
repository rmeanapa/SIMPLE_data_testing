name=trpm4
smpd=0.732
dose=55
dir=/mnt/beegfs/elmlund/testing-datasets/TRPM4/20231113_161724_83_hsTRPM4_BA_5mgml_2s_m10
gain=$dir/gain/$(ls $dir/gain)

simple_exec prg=new_project projname=$name qsys_partition=csbdevel
cd $name
find $dir/movies -type f > movies.txt
simple_exec prg=import_movies smpd=$smpd cs=2.7 kv=300 fraca=0.1 filetab=movies.txt
simple_exec prg=motion_correct gainref=$gain total_dose=$dose nparts=32 nthr=6 projfile=1_import_movies/$name.simple script=yes
simple_exec prg=ctf_estimate projfile=2_motion_correct/$name.simple nparts=16 nthr=8 script=yes
simple_exec prg=oristats oritab=3_ctf_estimate/$name.simple ctfstats=yes nthr=8 oritype=mic
AVERAGE CTF RESOLUTION               :     4.99
STANDARD DEVIATION OF CTF RESOLUTION :     5.40
MINIMUM CTF RESOLUTION (BEST)        :     3.02
MAXIMUM CTF RESOLUTION (WORST)       :    50.00
AVERAGE DF                           :     0.52
STANDARD DEVIATION OF DF             :     0.33
MINIMUM DF                           :     0.20
MAXIMUM DF                           :     4.86
simple_exec prg=selection oritype=mic projfile=3_ctf_estimate/$name.simple ctfresthreshold=7 icefracthreshold=1
simple_exec prg=selection oritype=mic projfile=3_ctf_estimate/$name.simple ctfresthreshold=7 icefracthreshold=1 nran=300
simple_exec prg=print_project_field oritype=mic projfile=5_selection/$name.simple > tmp.txt
awk '{print $6}' tmp.txt > tmp2.txt
awk -F'=' '{print $2}' tmp2.txt > sel5.txt
simple_exec prg=mini_stream script=yes cs=2.7 kv=300 smpd=1.3 nthr=18 filetab=sel5.txt projfile=$name.simple

simple_exec prg=extract nparts=8 nthr=6 box=180 projfile=7_pick/$name.simple script=yes