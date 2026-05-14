name=Sov
smpd=0.732
dose=59.3
dir=/mnt/beegfs/elmlund/testing-datasets/Sov/20240627_160740_78_P70_shd_grid8
gain=$dir/gain/$(ls $dir/gain)

/mnt/beegfs/elmlund/testing-datasets/Sov/20240627_160740_78_P70_shd_grid8/movies/.FoilHole_28489381_Data_27464199_18_20240628_054636_EER.eer.5wUcUt need be removed

simple_exec prg=new_project projname=$name qsys_partition=csbdevel
cd $name
find $dir/movies -type f > movies.txt
simple_exec prg=import_movies smpd=$smpd cs=2.7 kv=300 fraca=0.1 filetab=movies.txt
simple_exec prg=motion_correct gainref=$gain total_dose=$dose nparts=32 nthr=6 projfile=1_import_movies/$name.simple script=yes
simple_exec prg=ctf_estimate projfile=2_motion_correct/$name.simple nparts=16 nthr=8 script=yes
simple_exec prg=oristats oritab=3_ctf_estimate/$name.simple ctfstats=yes nthr=8 oritype=mic
AVERAGE CTF RESOLUTION               :     5.19
STANDARD DEVIATION OF CTF RESOLUTION :     7.64
MINIMUM CTF RESOLUTION (BEST)        :     2.80
MAXIMUM CTF RESOLUTION (WORST)       :    50.00
AVERAGE DF                           :     1.67
STANDARD DEVIATION OF DF             :     0.65
MINIMUM DF                           :     0.20
MAXIMUM DF                           :     4.98
simple_exec prg=selection oritype=mic projfile=3_ctf_estimate/$name.simple ctfresthreshold=7 icefracthreshold=1
simple_exec prg=selection oritype=mic projfile=4_selection/$name.simple nran=300
simple_exec prg=print_project_field oritype=mic projfile=5_selection/$name.simple > tmp.txt
awk '{print $6}' tmp.txt > tmp2.txt
awk -F'=' '{print $2}' tmp2.txt > sel5.txt
simple_exec prg=mini_stream script=yes cs=2.7 kv=300 smpd=1.3 nthr=18 filetab=sel5.txt projfile=$name.simpl