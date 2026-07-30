mkdir -p motab; cd motab 
simple_exec prg=new_project projname=motab dir=./ > LOG 
filetab_movs.pl /mnt/beegfs/elmlund/testing-datasets/MotAB/20220708_141209_csMotAB_FliGc_short_linker_1_3mgml_3s_bfmin5/movies 100 >> LOG
echo " >>> PROGRAM: import_movies" >> LOG
simple_exec prg=import_movies cs=2.7 fraca=0.1 kv=300 smpd=0.693 filetab=movies.txt >> LOG
echo " >>> PROGRAM: motion_correct" >> LOG
simple_exec prg=motion_correct nparts=5 nthr=8 gainref=/mnt/beegfs/elmlund/testing-datasets/MotAB/20220708_141209_csMotAB_FliGc_short_linker_1_3mgml_3s_bfmin5/gain/20220708_141047_EER_GainReference.gain total_dose=56.5 smpd_downscale=1.3 >> LOG
echo " >>> PROGRAM: ctf_estimate" >> LOG
simple_exec prg=ctf_estimate nparts=5 nthr=8 projfile=2_motion_correct/motab.simple >> LOG
filetab_mrc.pl 2_motion_correct/ >> LOG
echo " >>> PROGRAM: pick" >> LOG
simple_exec prg=pick picker=segdiam projfile=3_ctf_estimate/motab.simple nparts=5 nthr=8 >> LOG
echo " >>> PROGRAM: extract" >> LOG
simple_exec prg=extract box=256 nparts=5 nthr=8 projfile=4_pick/motab.simple >> LOG
echo " >>> PROGRAM: abinitio2D" >> LOG
simple_exec prg=abinitio2D ncls=100 mskdiam=190 nthr=32 projfile=5_extract/motab.simple >> LOG 
echo " >>> PROGRAM: selection" >> LOG
simple_exec prg=selection res_threshold=24 oritype=cls2D projfile=6_abinitio2D/motab.simple >> LOG
echo " >>> PROGRAM: abinitio3D" >> LOG
simple_exec prg=abinitio3D pgrp=d2 mskdiam=190 nthr=32 projfile=7_selection/motab.simple >> LOG
#echo " >>> PROGRAM: flex_eigenvol" >> LOG
#simple_exec prg=flex_eigenvol vol1=8_abinitio3D/rec_final_state01_lp.mrc nthr=32 projfile=8_abinitio3D/motab.simple >> LOG

