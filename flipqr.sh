mkdir -p flipqr; cd flipqr 
simple_exec prg=new_project projname=flipqr dir=./ > LOG 2>&1
filetab_movs.pl mnt/beegfs/elmlund/testing-datasets/FliPQR_FlhB/20180419_104101_FliPQRFlhB_4mgml_collect/movies >> LOG 2>&1
echo " >>> PROGRAM: import_movies" >> LOG 2>&1
simple_exec prg=import_movies cs=2.7 fraca=0.1 kv=300 smpd=0.822 filetab=movies.txt >> LOG 2>&1
echo " >>> PROGRAM: motion_correct" >> LOG 2>&1
#simple_exec prg=motion_correct nparts=5 nthr=8 gainref=/mnt/beegfs/elmlund/testing-datasets/betagal/gain/gain.mrc total_dose=48 smpd_downscale=1.3 >> LOG 2>&1
simple_exec prg=motion_correct nparts=5 nthr=8 total_dose=48 smpd_downscale=1.3 >> LOG 2>&1
echo " >>> PROGRAM: ctf_estimate" >> LOG 2>&1
simple_exec prg=ctf_estimate nparts=5 nthr=8 projfile=2_motion_correct/flipqr.simple >> LOG 2>&1
filetab_mrc.pl 2_motion_correct/ >> LOG 2>&1
echo " >>> PROGRAM: pick" >> LOG 2>&1
simple_exec prg=pick picker=segdiam projfile=3_ctf_estimate/flipqr.simple nparts=5 nthr=8 >> LOG 2>&1
echo " >>> PROGRAM: extract" >> LOG 2>&1
simple_exec prg=extract box=256 nparts=5 nthr=8 projfile=4_pick/flipqr.simple >> LOG 2>&1
echo " >>> PROGRAM: abinitio2D" >> LOG 2>&1
simple_exec prg=abinitio2D ncls=90 mskdiam=180 nthr=20 nparts=4 >> LOG 2>&1
echo " >>> PROGRAM: model_cavgs_rejection" >> LOG 2>&1
simple_exec prg=model_cavgs_rejection mskdiam=180 nthr=20 >> LOG 2>&1
echo " >>> PROGRAM: abinitio3D_cavgs" >> LOG 2>&1
simple_exec prg=abinitio3D_cavgs pgrp=d2 mskdiam=180 nthr=40 >> LOG 2>&1
echo " >>> PROGRAM: abinitio3D" >> LOG 2>&1
simple_exec prg=abinitio3D pgrp=c1 mskdiam=180 nthr=8 nparts=10 cavg_ini_ext=yes >> LOG 2>&1
echo " >>> PROGRAM: refine3D_auto" >> LOG 2>&1
simple_exec prg=refine3D_auto pgrp=c1 mskdiam=180 nparts=10 nthr=8 >> LOG 2>&1


#name=flipqr
#smpd=0.822
#dose=48
#dir=/mnt/beegfs/elmlund/testing-datasets/FliPQR_FlhB/20180419_104101_FliPQRFlhB_4mgml_collect/movies
##gain=/mnt/beegfs/elmlund/testing-datasets/FliPQR_FlhB/20180419_104101_FliPQRFlhB_4mgml_collect/gain/
#
#ls /mnt/beegfs/elmlund/testing-datasets/FliPQR_FlhB/20180419_104101_FliPQRFlhB_4mgml_collect/movies/* >movies.txt
#/mnt/beegfs/elmlund/testing-datasets/FliPQR_FlhB/20180419_104101_FliPQRFlhB_4mgml_collect/movies/FoilHole_20021658_Data_18961417_18961418_20180420_1720-130286.mrc is corrupted and need be removed
#
#simple_exec prg=import_movies smpd=$smpd cs=2.7 kv=300 fraca=0.1 filetab=movies.txt
#simple_exec prg=motion_correct nparts=32 nthr=6 total_dose=$dose projfile=1_import_movies/$name.simple script=yes
#simple_exec prg=ctf_estimate nparts=8 nthr=6 projfile=2_motion_correct/$name.simple script=yes
#simple_exec prg=oristats oritab=3_ctf_estimate/flipqr.simple ctfstats=yes nthr=8 oritype=mic
#AVERAGE CTF RESOLUTION               :     4.80
#STANDARD DEVIATION OF CTF RESOLUTION :     7.16
#MINIMUM CTF RESOLUTION (BEST)        :     2.80
#MAXIMUM CTF RESOLUTION (WORST)       :    50.00
#AVERAGE DF                           :     1.67
#STANDARD DEVIATION OF DF             :     0.73
#MINIMUM DF                           :     0.20
#MAXIMUM DF                           :     4.83
#simple_exec prg=selection oritype=mic projfile=3_ctf_estimate/$name.simple ctfresthreshold=6 icefracthreshold=1
#simple_exec prg=selection oritype=mic projfile=3_ctf_estimate/$name.simple ctfresthreshold=6 icefracthreshold=1 nran=300
#simple_exec prg=print_project_field oritype=mic projfile=5_selection/$name.simple > tmp.txt
#awk '{print $6}' tmp.txt > tmp2.txt
#awk -F'=' '{print $2}' tmp2.txt > sel5.txt
#simple_exec prg=mini_stream script=yes cs=2.7 kv=300 smpd=1.3 nthr=18 filetab=sel5.txt projfile=$name.simple
#simple_exec prg=convert smpd=1.3 stk=picksel.spi outstk=picksel.mrc
#simple_exec prg=pick nparts=16 nthr=6 pickrefs=picksel.mrc projfile=4_selection/$name.simple script=yes
#simple_exec prg=extract nparts=8 nthr=6 box=180 projfile=7_pick/$name.simple script=yes
