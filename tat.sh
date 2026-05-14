name=tat
smpd=0.723
dose=54
dir=/mnt/beegfs/elmlund/testing-datasets/Tat/20211029_142344_nsTatBC
#gain=$dir/gain/$(ls $dir/gain)

simple_exec prg=new_project projname=$name qsys_partition=csbdevel
cd $name
find $dir/movies -type f > movies.txt
simple_exec prg=import_movies smpd=$smpd cs=2.7 kv=300 fraca=0.1 filetab=movies.txt
simple_exec prg=motion_correct total_dose=$dose nparts=32 nthr=6 projfile=1_import_movies/$name.simple script=yes
simple_exec prg=ctf_estimate projfile=2_motion_correct/$name.simple nparts=16 nthr=8 script=yes
simple_exec prg=oristats oritab=3_ctf_estimate/$name.simple ctfstats=yes nthr=8 oritype=mic
AVERAGE CTF RESOLUTION               :     5.46
STANDARD DEVIATION OF CTF RESOLUTION :     9.51
MINIMUM CTF RESOLUTION (BEST)        :     2.80
MAXIMUM CTF RESOLUTION (WORST)       :    50.00
AVERAGE DF                           :     1.25
STANDARD DEVIATION OF DF             :     0.58
MINIMUM DF                           :     0.20
MAXIMUM DF                           :     4.98
simple_exec prg=selection oritype=mic projfile=3_ctf_estimate/$name.simple ctfresthreshold=8 icefracthreshold=1 nthr=4
simple_exec prg=selection oritype=mic projfile=3_ctf_estimate/$name.simple ctfresthreshold=8 icefracthreshold=1 nthr=4 nran=300
simple_exec prg=print_project_field oritype=mic projfile=5_selection/$name.simple > tmp.txt
awk '{print $6}' tmp.txt > tmp2.txt
awk -F'=' '{print $2}' tmp2.txt > sel5.txt
simple_exec prg=mini_stream script=yes cs=2.7 kv=300 smpd=1.3 nthr=18 filetab=sel5.txt projfile=$name.simple
simple_exec prg=convert smpd=1.3 stk=picksel.spi outstk=picksel.mrc
simple_exec prg=pick nparts=16 nthr=6 pickrefs=picksel.mrc projfile=4_selection/$name.simple script=yes
simple_exec prg=extract nparts=10 nthr=6 box=180 projfile=7_pick/$name.simple script=yes