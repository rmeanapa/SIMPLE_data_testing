simple_exec prg=new_project projname=betagal  > LOG
cd betagal
filetab_movs.pl /mnt/beegfs/elmlund/testing-datasets/betagal/movies 
echo " >>> PROGRAM: import_movies" > LOG
simple_exec prg=import_movies cs=1.4 fraca=0.1 kv=200 smpd=0.885 filetab=movies.txt >> LOG
echo " >>> PROGRAM: motion_correct" >> LOG
simple_exec prg=motion_correct nparts=5 nthr=8 gainref=/mnt/beegfs/elmlund/testing-datasets/betagal/gain/gain.mrc total_dose=30.65 smpd_downscale=1.3 >> LOG
echo " >>> PROGRAM: ctf_estimate" >> LOG
simple_exec prg=ctf_estimate nparts=1 nthr=16 >> LOG
filetab_mrc.pl 2_motion_correct/
echo " >>> PROGRAM: pick" >> LOG
simple_exec prg=pick nparts=5 nthr=8 >> LOG
echo " >>> PROGRAM: extract" >> LOG
simple_exec prg=extract box=256 nparts=8 nthr=8 >> LOG
echo " >>> PROGRAM: selection" >> LOG
simple_exec prg=selection res_threshold=7 >> LOG
echo " >>> PROGRAM: abinitio2D" >> LOG
simple_exec prg=abinitio2D ncls=100 mskdiam=190 nthr=24 >> LOG 
echo " >>> PROGRAM: abinitio3D" >> LOG
simple_exec prg=abinitio3D pgrp=d2 mskdiam=190 nthr=40 >> LOG
