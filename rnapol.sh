
mkdir -p rnapol; cd rnapol
simple_exec prg=new_project projname=rnapol dir=./ > LOG 2>&1
filetab_movs.pl /mnt/beegfs/elmlund/testing-datasets/rnapol/movies >> LOG 2>&1
echo " >>> PROGRAM: import_movies" >> LOG 2>&1
simple_exec prg=import_movies cs=1.4 fraca=0.1 kv=200 smpd=0.885 filetab=movies.txt >> LOG 2>&1
echo " >>> PROGRAM: motion_correct" >> LOG 2>&1
simple_exec prg=motion_correct nparts=5 nthr=8 gainref=/mnt/beegfs/elmlund/testing-datasets/rnapol/gain/gain.mrc total_dose=30.65 smpd_downscale=1.3 >> LOG 2>&1
echo " >>> PROGRAM: ctf_estimate" >> LOG 2>&1
simple_exec prg=ctf_estimate nparts=5 nthr=8 projfile=2_motion_correct/rnapol.simple >> LOG 2>&1
filetab_mrc.pl 2_motion_correct/ >> LOG 2>&1
echo " >>> PROGRAM: pick" >> LOG 2>&1
simple_exec prg=pick picker=segdiam projfile=3_ctf_estimate/rnapol.simple nparts=5 nthr=8 >> LOG 2>&1
echo " >>> PROGRAM: extract" >> LOG 2>&1
simple_exec prg=extract box=256 nparts=5 nthr=8 projfile=4_pick/rnapol.simple >> LOG 2>&1
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

#simple_exec prg=abinitio2D ncls=100 mskdiam=190 nthr=32 projfile=5_extract/rnapol.simple >> LOG 
#echo " >>> PROGRAM: selection" >> LOG
#simple_exec prg=selection res_threshold=9 oritype=cls2D projfile=6_abinitio2D/rnapol.simple >> LOG
#echo " >>> PROGRAM: abinitio3D" >> LOG
#simple_exec prg=abinitio3D pgrp=d2 mskdiam=190 nthr=32 projfile=7_selection/rnapol.simple >> LOG
#echo " >>> PROGRAM: flex_eigenvol" >> LOG
#simple_exec prg=flex_eigenvol vol1=8_abinitio3D/rec_final_state01_lp.mrc nthr=32 projfile=8_abinitio3D/rnapol.simple >> LOG
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
