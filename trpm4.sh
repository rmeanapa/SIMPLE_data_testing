mkdir -p trpm4; cd trpm4
simple_exec prg=new_project projname=trpm4 dir=./  > LOG 2>&1
filetab_movs.pl /mnt/beegfs/elmlund/testing-datasets/TRPM4/20231113_161724_83_hsTRPM4_BA_5mgml_2s_m10/movies 50 >> LOG 2>&1
echo " >>> PROGRAM: import_movies" >> LOG 2>&1
simple_exec prg=import_movies cs=2.7 fraca=0.1 kv=300 smpd=0.732 filetab=movies.txt >> LOG 2>&1
echo " >>> PROGRAM: motion_correct" >> LOG 2>&1
simple_exec prg=motion_correct nparts=5 nthr=8 gainref=/mnt/beegfs/elmlund/testing-datasets/TRPM4/20231113_161724_83_hsTRPM4_BA_5mgml_2s_m10/gain/20231019_151343_EER_GainReference.gain total_dose=55 smpd_downscale=1.3 >> LOG 2>&1
echo " >>> PROGRAM: ctf_estimate" >> LOG 2>&1
simple_exec prg=ctf_estimate nparts=5 nthr=8 projfile=2_motion_correct/trpm4.simple >> LOG 2>&1
filetab_mrc.pl 2_motion_correct/ >> LOG 2>&1
echo " >>> PROGRAM: oristats" >> LOG 2>&1
simple_exec prg=oristats oritab=3_ctf_estimate/trpm4.simple nthr=1 ctfstats=yes oritype=mic >> LOG 2>&1
echo " >>> PROGRAM: selection" >> LOG 2>&1
simple_exec prg=selection projfile=3_ctf_estimate/trpm4.simple ctfresthreshold=7 icefracthreshold=1 oritype=mic >> LOG 2>&1
echo " >>> PROGRAM: print_project" >> LOG 2>&1
simple_exec prg=print_project_field oritype=mic projfile=4_selection/trpm4.simple | awk '{print $6}' | awk -F'=' '{print $2}' > ctf_icefrac_selection.txt  2>&1
echo " >>> PROGRAM: pick" >> LOG 2>&1
simple_exec prg=pick picker=segdiam projfile=3_ctf_estimate/trpm4.simple nparts=5 nthr=8 >> LOG 2>&1
echo " >>> PROGRAM: extract" >> LOG 2>&1
simple_exec prg=extract box=256 nparts=5 nthr=8 projfile=5_pick/trpm4.simple >> LOG 2>&1
echo " >>> PROGRAM: abinitio2D" >> LOG 2>&1
simple_exec prg=abinitio2D ncls=90 mskdiam=180 nthr=20 nparts=4 >> LOG 2>&1
echo " >>> PROGRAM: model_cavgs_rejection" >> LOG 2>&1
simple_exec prg=model_cavgs_rejection mskdiam=180 nthr=20 >> LOG 2>&1
echo " >>> PROGRAM: abinitio3D_cavgs" >> LOG 2>&1
simple_exec prg=abinitio3D_cavgs pgrp=c4 mskdiam=180 nthr=40 >> LOG 2>&1
echo " >>> PROGRAM: abinitio3D" >> LOG 2>&1
simple_exec prg=abinitio3D pgrp=c4 mskdiam=180 nthr=8 nparts=10 cavg_ini_ext=yes >> LOG 2>&1
echo " >>> PROGRAM: refine3D_auto" >> LOG 2>&1
simple_exec prg=refine3D_auto pgrp=c4 mskdiam=180 nparts=10 nthr=8 >> LOG 2>&1

#simple_exec prg=abinitio2D ncls=100 mskdiam=190 nthr=32 projfile=5_extract/betagal.simple >> LOG 
#echo " >>> PROGRAM: selection" >> LOG
#simple_exec prg=selection res_threshold=9 oritype=cls2D projfile=6_abinitio2D/betagal.simple >> LOG
#echo " >>> PROGRAM: abinitio3D" >> LOG
#simple_exec prg=abinitio3D pgrp=c4 mskdiam=190 nthr=32 projfile=7_selection/betagal.simple >> LOG
#echo " >>> PROGRAM: flex_eigenvol" >> LOG
#simple_exec prg=flex_eigenvol vol1=8_abinitio3D/rec_final_state01_lp.mrc nthr=32 projfile=8_abinitio3D/betagal.simple >> LOG


#echo " >>> PROGRAM: abinitio2D" >> LOG
#simple_exec prg=abinitio2D ncls=100 mskdiam=190 nthr=32 projfile=6_extract/trpm4.simple >> LOG 
#echo " >>> PROGRAM: selection" >> LOG
#simple_exec prg=selection res_threshold=50 oritype=cls2D projfile=7_abinitio2D/trpm4.simple >> LOG
#echo " >>> PROGRAM: abinitio3D" >> LOG
#simple_exec prg=abinitio3D pgrp=c4 mskdiam=190 nthr=32 projfile=8_selection/trpm4.simple >> LOG
