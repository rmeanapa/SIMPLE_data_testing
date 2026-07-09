simple_exec prg=new_project projname=clc  > LOG
cd clc 
filetab_movs.pl /mnt/beegfs/elmlund/testing-datasets/CLC/20220920_220725_wt_CLC7_OSTM1_0_1LMNG_2_5ATP_thinner_ice/movies/ 50 
echo " >>> PROGRAM: import_movies" > LOG
simple_exec prg=import_movies ctf=yes cs=2.7 fraca=0.1 kv=300 smpd=0.693 filetab=movies.txt >> LOG
echo " >>> PROGRAM: motion_correct" >> LOG
simple_exec prg=motion_correct smpd_downscale=1.3 total_dose=55.72 nparts=32 nthr=8 projfile=1_import_movies/clc.simple  >> LOG
echo " >>> PROGRAM: ctf_estimate" >> LOG
simple_exec prg=ctf_estimate projfile=2_motion_correct/clc.simple nparts=8 nthr=8 >> LOG 

filetab_mrc.pl 2_motion_correct/
echo " >>> PROGRAM: pick" >> LOG
simple_exec prg=pick picker=segdiam projfile=3_ctf_estimate/betagal.simple nparts=5 nthr=8 >> LOG
echo " >>> PROGRAM: extract" >> LOG
simple_exec prg=extract box=256 nparts=5 nthr=8 projfile=4_pick/betagal.simple >> LOG
echo " >>> PROGRAM: abinitio2D" >> LOG
simple_exec prg=abinitio2D ncls=100 mskdiam=190 nthr=32 projfile=5_extract/betagal.simple >> LOG 
echo " >>> PROGRAM: selection" >> LOG
simple_exec prg=selection res_threshold=9 oritype=cls2D projfile=6_abinitio2D/betagal.simple >> LOG
echo " >>> PROGRAM: abinitio3D" >> LOG
simple_exec prg=abinitio3D pgrp=d2 mskdiam=190 nthr=32 projfile=7_selection/betagal.simple >> LOG
echo " >>> PROGRAM: flex_eigenvol" >> LOG
simple_exec prg=flex_eigenvol vol1=8_abinitio3D/rec_final_state01_lp.mrc nthr=32 projfile=8_abinitio3D/betagal.simple >> LOG


name=clc

ls -l /mnt/beegfs/elmlund/testing-datasets/CLC/20220920_220725_wt_CLC7_OSTM1_0_1LMNG_2_5ATP_thinner_ice/movies/ > movies.txt
simple_exec prg=import_movies filetab=movies.txt smpd=0.693 ctf=yes cs=2.7 kv=300 fraca=0.1
simple_exec prg=motion_correct smpd_downscale=1.3 total_dose=55.72 nparts=32 nthr=8 projfile=1_import_movies/clc.simple script=yes
simple_exec prg=ctf_estimate projfile=2_motion_correct/clc.simple nparts=8 nthr=8 script=yes
simple_exec prg=oristats oritab=3_ctf_estimate/clc.simple ctfstats=yes nthr=8 oritype=mic
AVERAGE CTF RESOLUTION               :     3.85
STANDARD DEVIATION OF CTF RESOLUTION :     4.81
MINIMUM CTF RESOLUTION (BEST)        :     2.80
MAXIMUM CTF RESOLUTION (WORST)       :    50.00
AVERAGE DF                           :     1.61
STANDARD DEVIATION OF DF             :     0.63
MINIMUM DF                           :     0.20
MAXIMUM DF                           :     4.76
simple_exec prg=selection oritype=mic projfile=3_ctf_estimate/clc.simple ctfresthreshold=6 icefracthreshold=1
simple_exec prg=selection oritype=mic projfile=3_ctf_estimate/clc.simple ctfresthreshold=6 icefracthreshold=1 nran=300
simple_exec prg=print_project_field oritype=mic projfile=5_selection/clc.simple > tmp.txt
awk '{print $6}' tmp.txt > tmp2.txt
awk -F'=' '{print $2}' tmp2.txt > sel5.txt
simple_exec prg=mini_stream script=yes cs=2.7 kv=300 smpd=1.3 nthr=18 filetab=sel5.txt projfile=clc.simple
simple_exec prg=convert smpd=1.3 stk=picksel.spi outstk=picksel.mrc
simple_exec prg=pick nparts=16 nthr=6 pickrefs=picksel.mrc projfile=4_selection/$name.simple script=yes
simple_exec prg=extract nparts=8 nthr=6 box=200 projfile=7_pick/$name.simple script=yes
