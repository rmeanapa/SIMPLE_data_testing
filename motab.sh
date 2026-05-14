name=motab
smpd=0.693
dose=56.5
dir=/mnt/beegfs/elmlund/testing-datasets/MotAB/20220708_141209_csMotAB_FliGc_short_linker_1_3mgml_3s_bfmin5
gain=$dir/gain/20220708_141047_EER_GainReference.gain

simple_exec prg=new_project projname=motab qsys_partition=csbdevel
cd $name
find $dir/movies -type f > movies.txt
simple_exec prg=import_movies smpd=$smpd cs=2.7 kv=300 fraca=0.1 filetab=movies.txt
simple_exec prg=motion_correct gainref=$gain total_dose=$dose nparts=32 nthr=6 projfile=1_import_movies/$name.simple script=yes
simple_exec prg=ctf_estimate nparts=32 nthr=6 projfile=2_motion_correct/$name.simple script=yes
simple_exec prg=oristats oritab=3_ctf_estimate/$name.simple ctfstats=yes nthr=8 oritype=mic
AVERAGE CTF RESOLUTION               :     5.57
STANDARD DEVIATION OF CTF RESOLUTION :     9.71
MINIMUM CTF RESOLUTION (BEST)        :     2.80
MAXIMUM CTF RESOLUTION (WORST)       :    50.00
AVERAGE DF                           :     1.13
STANDARD DEVIATION OF DF             :     0.58
MINIMUM DF                           :     0.20
MAXIMUM DF                           :     4.97
simple_exec prg=selection oritype=mic projfile=3_ctf_estimate/$name.simple ctfresthreshold=8 icefracthreshold=1
simple_exec prg=selection oritype=mic projfile=4_selection/$name.simple nran=300
simple_exec prg=print_project_field oritype=mic projfile=5_selection/$name.simple > tmp.txt
awk '{print $6}' tmp.txt > tmp2.txt
awk -F'=' '{print $2}' tmp2.txt > sel5.txt
simple_exec prg=mini_stream script=yes cs=2.7 kv=300 smpd=1.3 nthr=18 filetab=sel5.txt projfile=$name.simple
simple_exec prg=extract nparts=8 nthr=6 box=264 projfile=7_pick/$name.simple script=yes