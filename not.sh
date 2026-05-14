name=not
smpd=0.732
dose=54
dir=/mnt/beegfs/elmlund/testing-datasets/Not/20240316_223846_67_80S_Not_module_monoG_2s_min20
gain=$dir/gain/20240315_170616_EER_GainReference.gain

simple_exec prg=new_project projname=motab qsys_partition=csbdevel
cd $name
find $dir/movies -type f > movies.txt
simple_exec prg=import_movies smpd=$smpd cs=2.7 kv=300 fraca=0.1 filetab=movies.txt
simple_exec prg=motion_correct gainref=$gain total_dose=$dose nparts=32 nthr=6 projfile=1_import_movies/$name.simple script=yes
simple_exec prg=ctf_estimate projfile=2_motion_correct/$name.simple nparts=8 nthr=8 script=yes
simple_exec prg=oristats oritab=3_ctf_estimate/$name.simple ctfstats=yes nthr=8 oritype=mic
AVERAGE CTF RESOLUTION               :     3.71
STANDARD DEVIATION OF CTF RESOLUTION :     4.70
MINIMUM CTF RESOLUTION (BEST)        :     2.80
MAXIMUM CTF RESOLUTION (WORST)       :    50.00
AVERAGE DF                           :     0.98
STANDARD DEVIATION OF DF             :     0.37
MINIMUM DF                           :     0.20
MAXIMUM DF                           :     4.92
simple_exec prg=selection oritype=mic projfile=3_ctf_estimate/$name.simple ctfresthreshold=6 icefracthreshold=1
simple_exec prg=selection oritype=mic projfile=3_ctf_estimate/$name.simple ctfresthreshold=6 icefracthreshold=1 nran=300
simple_exec prg=print_project_field oritype=mic projfile=5_selection/$name.simple > tmp.txt
awk '{print $6}' tmp.txt > tmp2.txt
awk -F'=' '{print $2}' tmp2.txt > sel5.txt
simple_exec prg=mini_stream script=yes cs=2.7 kv=300 smpd=1.3 nthr=18 filetab=sel5.txt projfile=$name.simple
simple_exec prg=pick nparts=16 nthr=6 pickrefs=picksel.mrc projfile=4_selection/$name.simple script=yes
simple_exec prg=extract nparts=8 nthr=6 box=420 projfile=7_pick/$name.simple script=yes