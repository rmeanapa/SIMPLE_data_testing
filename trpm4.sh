simple_exec prg=new_project projname=trpm4  > LOG
cd trpm4 
filetab_movs.pl /mnt/beegfs/elmlund/testing-datasets/TRPM4/20231113_161724_83_hsTRPM4_BA_5mgml_2s_m10/movies 50
echo " >>> PROGRAM: import_movies" > LOG
simple_exec prg=import_movies cs=2.7 fraca=0.1 kv=300 smpd=0.732 filetab=movies.txt >> LOG
echo " >>> PROGRAM: motion_correct" >> LOG
simple_exec prg=motion_correct nparts=5 nthr=8 gainref=/mnt/beegfs/elmlund/testing-datasets/TRPM4/20231113_161724_83_hsTRPM4_BA_5mgml_2s_m10/gain/20231019_151343_EER_GainReference.gain total_dose=55 smpd_downscale=1.3 >> LOG
echo " >>> PROGRAM: ctf_estimate" >> LOG
simple_exec prg=ctf_estimate nparts=5 nthr=8 projfile=2_motion_correct/trpm4.simple >> LOG
filetab_mrc.pl 2_motion_correct/
echo " >>> PROGRAM: oristats" >> LOG
simple_exec prg=oristats oritab=3_ctf_estimate/trpm4.simple nthr=1 ctfstats=yes oritype=mic >> LOG
echo " >>> PROGRAM: selection" >> LOG
simple_exec prg=selection projfile=3_ctf_estimate/trpm4.simple ctfresthreshold=7 icefracthreshold=1 oritype=mic >> LOG
echo " >>> PROGRAM: print_project" >> LOG
simple_exec prg=print_project_field oritype=mic projfile=4_selection/trpm4.simple | awk '{print $6}' | awk -F'=' '{print $2}' > ctf_icefrac_selection.txt 
echo " >>> PROGRAM: pick" >> LOG
simple_exec prg=pick picker=segdiam projfile=3_ctf_estimate/trpm4.simple nparts=5 nthr=8 >> LOG
echo " >>> PROGRAM: extract" >> LOG
simple_exec prg=extract box=256 nparts=5 nthr=8 projfile=5_pick/trpm4.simple >> LOG
echo " >>> PROGRAM: abinitio2D" >> LOG
simple_exec prg=abinitio2D ncls=100 mskdiam=190 nthr=32 projfile=6_extract/trpm4.simple >> LOG 
echo " >>> PROGRAM: selection" >> LOG
simple_exec prg=selection res_threshold=9 oritype=cls2D projfile=7_abinitio2D/trpm4.simple >> LOG
echo " >>> PROGRAM: abinitio3D" >> LOG
simple_exec prg=abinitio3D pgrp=d2 mskdiam=190 nthr=32 projfile=8_selection/trpm4.simple >> LOG

