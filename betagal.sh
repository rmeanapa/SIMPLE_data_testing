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
echo " >>> PROGRAM: mini_stream" >> LOG
simple_exec prg=mini_stream cs=1.4 fraca=0.1 kv=200 smpd=1.3 filetab=filetab.txt nthr=24 >> LOG

#simple_exec prg=map_cavgs_selection stk2=4_mini_stream/cavgs_iter026_ranked.mrc ares=10

#simple_exec prg=stackops top=6 stk=4_mini_stream/cavgs_iter026_ranked.mrc smpd=1.275 nthr=4 >> LOG
echo " >>> PROGRAM: stackops" >> LOG
simple_exec prg=stackops top=6 stk=4_mini_stream/shaped_ranked_cavgs.mrcs smpd=1.275 nthr=4 >> LOG
echo " >>> PROGRAM: pick" >> LOG
simple_exec prg=pick pickrefs=outstk.mrc nparts=5 nthr=8 projfile=3_ctf_estimate/betagal.simple >> LOG

#simple_exec prg=convert stk=selected.spi outstk=selected.mrc smpd=1.3
#simple_exec prg=pick pickrefs=selected.mrc nparts=5 nthr=8 projfile=3_ctf_estimate/betagal_rec2.simple
#wc 5_pick/*box| wc
#wc 5_pick/*box
echo " >>> PROGRAM: extract" >> LOG
simple_exec prg=extract box=256 projfile=5_pick/betagal.simple nparts=8 nthr=8 >> LOG
echo " >>> PROGRAM: abinitio2D" >> LOG
simple_exec prg=abinitio2D ncls=100 mskdiam=190 nthr=24 >> LOG 
echo " >>> PROGRAM: abinitio3D" >> LOG
#simple_exec prg=map_cavgs_selection stk2=selected_abinitio2D.spi prune=yes
simple_exec prg=abinitio3D pgrp=d2 mskdiam=190 nthr=40 >> LOG

