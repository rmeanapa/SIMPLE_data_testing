simple_exec prg=new_project projname=nanox  > LOG
cd nanox 
filetab_movs.pl /mnt/beegfs/elmlund/NanoX/full_frame_data_sets/71-17/mrc 
echo " >>> PROGRAM: tseries_import" > LOG
single_exec prg=tseries_import filetab=movies.txt cs=-0.01 fraca=0.3 kv=300 smpd=0.358 >> LOG
echo " >>> PROGRAM: tseries_motion_correct" >> LOG
single_exec prg=tseries_motion_correct nparts=6 nthr=12 >> LOG 
echo " >>> PROGRAM: tseries_make_pickavg" >> LOG
single_exec prg=tseries_make_pickavg nthr=20 >> LOG
echo " >>> PROGRAM: track_particles" >> LOG
single_exec prg=track_particles boxfile=../positions_all.box fbody=tracked_ptcl nthr=12 >> LOG  
cd tracked_ptcl_01
echo " >>> PROGRAM: trajectory_denoise" >> LOG
single_exec prg=trajectory_denoise stk=tracked_ptcl_01.mrc smpd=0.358 nthr=40 >> LOG
echo " >>> PROGRAM: new_project" >> LOG
simple_exec prg=new_project projname=tracked_ptcl_01
cd tracked_ptcl_01
echo " >>> PROGRAM: import_particles" >> LOG
single_exec prg=import_particles cs=-0.01 fraca=0.3 kv=300 smpd=0.358 stk=../ppca_denoised.mrcs ctf=no >> LOG
echo " >>> PROGRAM: analysis2D_nano" >> LOG
single_exec prg=analysis2D_nano element=Pt nthr=16 >> LOG
#echo " >>> PROGRAM: map_cavgs_selection" >> LOG
#single_exec prg=map_cavgs_selection stk2=2_analysis2D_nano/selected.spi prune=yes >> LOG
echo " >>> PROGRAM: autorefine3D_nano" >> LOG
nohup single_exec prg=autorefine3D_nano vol1=startvol.mrc element=Pt smpd=0.358 pgrp=c1 lp=1.5 mskdiam=30 nthr=16 projfile=3_selection/reproc.simple > AUTOREFINE &
