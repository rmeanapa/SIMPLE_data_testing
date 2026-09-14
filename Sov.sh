mkdir -p Sov; cd Sov
simple_exec prg=new_project projname=Sov dir=./ > LOG 2>&1
filetab_movs.pl /mnt/beegfs/elmlund/testing-datasets/Sov/20240627_160740_78_P70_shd_grid8/movies >> LOG 2>&1
echo " >>> PROGRAM: import_movies" >> LOG 2>&1
simple_exec prg=import_movies cs=2.7 fraca=0.1 kv=300 smpd=0.732 filetab=movies.txt >> LOG 2>&1
echo " >>> PROGRAM: motion_correct" >> LOG 2>&1
simple_exec prg=motion_correct nparts=5 nthr=8 gainref= total_dose=59.3 smpd_downscale=1.3 >> LOG 2>&1
echo " >>> PROGRAM: ctf_estimate" >> LOG 2>&1
simple_exec prg=ctf_estimate nparts=5 nthr=8 projfile=2_motion_correct/Sov.simple >> LOG 2>&1
filetab_mrc.pl 2_motion_correct/ >> LOG 2>&1
echo " >>> PROGRAM: pick" >> LOG 2>&1
simple_exec prg=pick picker=segdiam projfile=3_ctf_estimate/Sov.simple nparts=24 nthr=1 >> LOG 2>&1
echo " >>> PROGRAM: extract" >> LOG 2>&1
simple_exec prg=extract box=256 nparts=5 nthr=8 projfile=4_pick/Sov.simple >> LOG 2>&1
echo " >>> PROGRAM: abinitio2D" >> LOG 2>&1
simple_exec prg=abinitio2D ncls=90 mskdiam=180 nthr=20 nparts=4 >> LOG 2>&1
echo " >>> PROGRAM: model_cavgs_rejection" >> LOG 2>&1
simple_exec prg=model_cavgs_rejection mskdiam=180 nthr=20 >> LOG 2>&1
echo " >>> PROGRAM: abinitio3D_cavgs" >> LOG 2>&1
simple_exec prg=abinitio3D_cavgs pgrp=d2 mskdiam=180 nthr=40 >> LOG 2>&1
echo " >>> PROGRAM: abinitio3D" >> LOG 2>&1
simple_exec prg=abinitio3D pgrp=d2 mskdiam=180 nthr=8 nparts=10 cavg_ini_ext=yes >> LOG 2>&1
echo " >>> PROGRAM: refine3D_auto" >> LOG 2>&1
simple_exec prg=refine3D_auto pgrp=d2 mskdiam=180 nparts=10 nthr=8 >> LOG 2>&1

#name=Sov
#smpd=0.732
#dose=59.3
#dir=/mnt/beegfs/elmlund/testing-datasets/Sov/20240627_160740_78_P70_shd_grid8
#gain=$dir/gain/$(ls $dir/gain)
#
#/mnt/beegfs/elmlund/testing-datasets/Sov/20240627_160740_78_P70_shd_grid8/movies/.FoilHole_28489381_Data_27464199_18_20240628_054636_EER.eer.5wUcUt need be removed
#
#simple_exec prg=new_project projname=$name qsys_partition=csbdevel
#cd $name
#find $dir/movies -type f > movies.txt
#simple_exec prg=import_movies smpd=$smpd cs=2.7 kv=300 fraca=0.1 filetab=movies.txt
#simple_exec prg=motion_correct gainref=$gain total_dose=$dose nparts=32 nthr=6 projfile=1_import_movies/$name.simple script=yes
#simple_exec prg=ctf_estimate projfile=2_motion_correct/$name.simple nparts=16 nthr=8 script=yes
#simple_exec prg=oristats oritab=3_ctf_estimate/$name.simple ctfstats=yes nthr=8 oritype=mic
#AVERAGE CTF RESOLUTION               :     5.19
#STANDARD DEVIATION OF CTF RESOLUTION :     7.64
#MINIMUM CTF RESOLUTION (BEST)        :     2.80
#MAXIMUM CTF RESOLUTION (WORST)       :    50.00
#AVERAGE DF                           :     1.67
#STANDARD DEVIATION OF DF             :     0.65
#MINIMUM DF                           :     0.20
#MAXIMUM DF                           :     4.98
#simple_exec prg=selection oritype=mic projfile=3_ctf_estimate/$name.simple ctfresthreshold=7 icefracthreshold=1
#simple_exec prg=selection oritype=mic projfile=4_selection/$name.simple nran=300
#simple_exec prg=print_project_field oritype=mic projfile=5_selection/$name.simple > tmp.txt
#awk '{print $6}' tmp.txt > tmp2.txt
#awk -F'=' '{print $2}' tmp2.txt > sel5.txt
#simple_exec prg=mini_stream script=yes cs=2.7 kv=300 smpd=1.3 nthr=18 filetab=sel5.txt projfile=$name.simpl
