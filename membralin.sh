mkdir -p membralin; cd membralin
simple_exec prg=new_project projname=membralin dir=./ > LOG 2>&1
filetab_movs.pl /mnt/projects/CSB-CryoEM-raw/krios/2025/apr/20250425_154646_59_MBRL_GDN_2s_m25/movies >> LOG 2>&1
echo " >>> PROGRAM: import_movies" >> LOG 2>&1
simple_exec prg=import_movies cs=2.7 fraca=0.1 kv=300 smpd=0.732 filetab=movies.txt >> LOG 2>&1
echo " >>> PROGRAM: motion_correct" >> LOG 2>&1
#simple_exec prg=motion_correct nparts=5 nthr=8 gainref= total_dose=57 smpd_downscale=1.3 >> LOG 2>&1
simple_exec prg=motion_correct nparts=5 nthr=8 total_dose=57 smpd_downscale=1.3 >> LOG 2>&1
echo " >>> PROGRAM: ctf_estimate" >> LOG 2>&1
simple_exec prg=ctf_estimate nparts=5 nthr=8 projfile=2_motion_correct/membralin.simple >> LOG 2>&1
filetab_mrc.pl 2_motion_correct/ >> LOG 2>&1
echo " >>> PROGRAM: pick" >> LOG 2>&1
simple_exec prg=pick picker=segdiam projfile=3_ctf_estimate/membralin.simple nparts=5 nthr=8 >> LOG 2>&1
echo " >>> PROGRAM: extract" >> LOG 2>&1
simple_exec prg=extract box=256 nparts=5 nthr=8 projfile=4_pick/membralin.simple >> LOG 2>&1
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

#name=membralin
#smpd=0.732
#dose=57
#dir=/mnt/projects/CSB-CryoEM-raw/krios/2025/apr/20250425_154646_59_MBRL_GDN_2s_m25
#gain=$dir/gain/20250414_150420_EER_GainReference.gain
#
#find $dir/movies -type f > movies.txt
#simple_exec prg=import_movies smpd=$smpd cs=2.7 kv=300 fraca=0.1 filetab=movies.txt
#simple_exec prg=motion_correct gainref=$gain total_dose=$dose nparts=32 nthr=6 projfile=1_import_movies/$name.simple script=yes
#simple_exec prg=ctf_estimate projfile=2_motion_correct/$name.simple nparts=8 nthr=8 script=yes
#simple_exec prg=oristats oritab=3_ctf_estimate/$name.simple ctfstats=yes nthr=8 oritype=mic
#AVERAGE CTF RESOLUTION               :     4.39
#STANDARD DEVIATION OF CTF RESOLUTION :     1.36
#MINIMUM CTF RESOLUTION (BEST)        :     2.80
#MAXIMUM CTF RESOLUTION (WORST)       :    50.00
#AVERAGE DF                           :     1.46
#STANDARD DEVIATION OF DF             :     0.44
#MINIMUM DF                           :     0.20
#MAXIMUM DF                           :     3.84
#simple_exec prg=selection oritype=mic projfile=3_ctf_estimate/$name.simple ctfresthreshold=6 icefracthreshold=1
#simple_exec prg=selection oritype=mic projfile=4_selection/$name.simple nran=300
#simple_exec prg=print_project_field oritype=mic projfile=5_selection/$name.simple > tmp.txt
#awk '{print $6}' tmp.txt > tmp2.txt
#awk -F'=' '{print $2}' tmp2.txt > sel5.txt
#simple_exec prg=mini_stream script=yes cs=2.7 kv=300 smpd=1.3 nthr=18 filetab=sel5.txt projfile=$name.simple
