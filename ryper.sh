name=ryper
smpd=0.405
dose=57
dir=/mnt/beegfs/elmlund/testing-datasets/RYPER/20220523_164637_RYPER_xlinked_monoG_CHAPS_bf0
#gain=$dir/gain/$(ls $dir/gain)
gain=$dir/gain/gainref_05_23_2022.mrc

simple_exec prg=new_project projname=$name qsys_partition=csbdevel
cd $name
find $dir/movies -type f > movies.txt
simple_exec prg=import_movies smpd=$smpd cs=2.7 kv=200 fraca=0.1 filetab=movies.txt
simple_exec prg=motion_correct gainref=$gain total_dose=$dose nparts=32 nthr=6 projfile=1_import_movies/$name.simple flipgain=y script=yes
simple_exec prg=ctf_estimate projfile=2_motion_correct/$name.simple nparts=16 nthr=8 script=yes
simple_exec prg=oristats oritab=3_ctf_estimate/$name.simple ctfstats=yes nthr=8 oritype=mic


simple_exec prg=selection oritype=mic projfile=3_ctf_estimate/$name.simple ctfresthreshold=6 icefracthreshold=1
simple_exec prg=selection oritype=mic projfile=3_ctf_estimate/$name.simple ctfresthreshold=6 icefracthreshold=1 nran=300
simple_exec prg=print_project_field oritype=mic projfile=5_selection/$name.simple > tmp.txt
awk '{print $6}' tmp.txt > tmp2.txt
awk -F'=' '{print $2}' tmp2.txt > sel5.txt
simple_exec prg=mini_stream script=yes cs=2.7 kv=300 smpd=1.3 nthr=18 filetab=sel5.txt projfile=$name.simple
simple_exec prg=convert smpd=1.3 stk=selpick.spi outstk=picksel.mrc
simple_exec prg=pick nparts=16 nthr=6 pickrefs=picksel.mrc projfile=4_selection/$name.simple script=yes
simple_exec prg=extract nparts=8 nthr=6 box=180 projfile=7_pick/$name.simple script=yes