simple_exec prg=new_project projname=apof
cd apof/
filetab_movs.pl /mnt/beegfs/elmlund/testing-datasets/apoferritin/20221214_105239_vitroEase_apoF_bf15_300kv_highres/movies
echo " >>> PROGRAM: import_movies" > LOG
simple_exec prg=import_movies cs=2.7 fraca=0.1 kv=300 smpd=0.693 filetab=movies.txt >> LOG
echo " >>> PROGRAM: motion_correct" >> LOG
simple_exec prg=motion_correct nparts=5 nthr=8 gainref=/mnt/beegfs/elmlund/testing-datasets/apoferritin/20221214_105239_vitroEase_apoF_bf15_300kv_highres/gain/20221214_114106_EER_GainReference.gain total_dose=51.8 smpd_downscale=1.3 >> LOG
echo " >>> PROGRAM: ctf_estimate" >> LOG
simple_exec prg=ctf_estimate nparts=5 nthr=8 >> LOG
simple_exec prg=oristats oritab=3_ctf_estimate/apoferritin_subset.simple nthr=1 ctfstats=yes oritype=mic >> LOG
#simple_exec prg=mini_stream cs=2.7 fraca=0.1 kv=300 smpd=1.3 filetab=filetab.txt nthr=24
#simple_exec prg=convert smpd=1.3 stk=mini_stream_selection.spi outstk=mini_stream_selection.mrc
#simple_exec prg=pick pickrefs=mini_stream_selection.mrc nparts=5 nthr=8 projfile=3_ctf_estimate/apof.simple
echo " >>> PROGRAM: pick" >> LOG
simple_exec prg=pick picker=segdiam nparts=5 nthr=8 projfile=3_ctf_estimate/apof.simple >> LOG
echo " >>> PROGRAM: extract" >> LOG
simple_exec prg=extract box=192 projfile=5_pick/apof.simple nparts=8 nthr=8 >> LOG
wc 5_pick/*box
echo " >>> PROGRAM: abinitio2D" >> LOG
simple_exec prg=abinitio2D ncls=50 mskdiam=160 nthr=24 >> LOG
echo " >>> PROGRAM: selection" >> LOG
simple_exec prg=selection res_threshold=9 oritype=cls2D projfile=6_abinitio2D/apof.simple >> LOG
#simple_exec prg=map_cavgs_selection stk2=abinitio2d_selected.spi
echo " >>> PROGRAM: abinitio3D" >> LOG
simple_exec prg=abinitio3D pgrp=o mskdiam=160 nthr=40 >> LOG


#simple_exec prg=new_project projname=apof
#cd apof
#filetab_movs.pl /mnt/beegfs/elmlund/testing-datasets/apoferritin/20221214_105239_vitroEase_apoF_bf15_300kv_highres/movies
#simple_exec prg=import_movies filetab=movies.txt smpd=0.693 ctf=yes cs=2.7 kv=300 fraca=0.1
#simple_exec prg=motion_correct smpd_downscale=1.3 total_dose=51.8 nparts=2 nthr=10 projfile=1_import_movies/apof.simple gainref=/mnt/beegfs/elmlund/testing-datasets/apoferritin/20221214_105239_vitroEase_apoF_bf15_300kv_highres/gain/20221214_114106_EER_GainReference.gain > MOTION_CORRECTION
#simple_exec prg=motion_correct smpd_downscale=1.3 total_dose=51.8 nparts=2 nthr=10 script=yes projfile=1_import_movies/apof.simple gainref=/mnt/beegfs/elmlund/testing-datasets/apoferritin/20221214_105239_vitroEase_apoF_bf15_300kv_highres/gain/20221214_114106_EER_GainReference.gain > MOTION_CORRECTION
#simple_exec prg=ctf_estimate projfile=2_motion_correct/apof.simple nparts=8 nthr=8 script=yes
#simple_exec prg=oristats oritab=3_ctf_estimate/apof.simple ctfstats=yes nthr=8 oritype=mic
#AVERAGE CTF RESOLUTION               :     4.31
#STANDARD DEVIATION OF CTF RESOLUTION :     6.39
#MINIMUM CTF RESOLUTION (BEST)        :     2.80
#MAXIMUM CTF RESOLUTION (WORST)       :    50.00
#AVERAGE DF                           :     1.06
#STANDARD DEVIATION OF DF             :     0.40
#MINIMUM DF                           :     0.20
#MAXIMUM DF                           :     4.96
#simple_exec prg=selection oritype=mic projfile=3_ctf_estimate/apof.simple ctfresthreshold=6 icefracthreshold=1
#simple_exec prg=selection oritype=mic projfile=3_ctf_estimate/apof.simple ctfresthreshold=6 icefracthreshold=1 nran=300
#simple_exec prg=print_project_field oritype=mic projfile=5_selection/apof.simple > tmp.txt
#awk '{print $6}' tmp.txt > tmp2.txt
#awk -F'=' '{print $2}' tmp2.txt > sel5.txt
#simple_exec prg=mini_stream script=yes cs=2.7 kv=300 smpd=1.3 nthr=18 filetab=sel5.txt projfile=apof.simple
#simple_exec prg=convert smpd=1.3 stk=picksel.spi outstk=picksel.mrc
#simple_exec prg=pick nparts=16 nthr=6 pickrefs=picksel.mrc projfile=4_selection/apof.simple script=yes
#simple_exec prg=extract nparts=8 nthr=6 box=200 projfile=7_pick/apof.simple script=yes
