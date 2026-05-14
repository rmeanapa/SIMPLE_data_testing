name=rnapol
smpd=0.732
dose=54
dir=/mnt/beegfs/elmlund/testing-datasets/RNA_polymerase/20240712_155703_86_RNApol_xlink_0_5_2s_bf6
gain=$dir/gain/$(ls $dir/gain)

simple_exec prg=new_project projname=$name qsys_partition=csbdevel
cd $name
find $dir/movies -type f > movies.txt
simple_exec prg=import_movies smpd=$smpd cs=2.7 kv=300 fraca=0.1 filetab=movies.txt
simple_exec prg=motion_correct gainref=$gain total_dose=$dose nparts=32 nthr=6 projfile=1_import_movies/$name.simple script=yes
simple_exec prg=oristats oritab=3_ctf_estimate/$name.simple ctfstats=yes nthr=8 oritype=mic
AVERAGE CTF RESOLUTION               :     4.52
STANDARD DEVIATION OF CTF RESOLUTION :     6.79
MINIMUM CTF RESOLUTION (BEST)        :     2.80
MAXIMUM CTF RESOLUTION (WORST)       :    50.00
AVERAGE DF                           :     1.42
STANDARD DEVIATION OF DF             :     0.51
MINIMUM DF                           :     0.20
MAXIMUM DF                           :     4.96
simple_exec prg=mini_stream cs=2.7 kv=300 smpd=1.3 nthr=18 filetab=sel5.txt script=yes
simple_exec prg=convert smpd=1.3 stk=picksel.spi outstk=picksel.mrc
simple_exec prg=pick nparts=16 nthr=6 pickrefs=picksel.mrc projfile=4_selection/$name.simple script=yes
simple_exec prg=extract nparts=8 nthr=6 box=240 projfile=7_pick/$name.simple script=yes