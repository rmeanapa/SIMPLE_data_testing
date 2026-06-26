simple_exec prg=new_project projname=proteasome
cd proteasome 
filetab_movs.pl /mnt/beegfs/elmlund/testing-datasets/proteasome/movies  
echo " >>> PROGRAM: import_movies" > LOG
simple_exec prg=import_movies cs=2.7 fraca=0.1 kv=300 smpd=0.6575 filetab=movies.txt >> LOG
echo " >>> PROGRAM: motion_correct" >> LOG
simple_exec prg=motion_correct nparts=16 nthr=4 gainref=/mnt/beegfs/elmlund/testing-datasets/proteasome/gain/norm-amibox05-0.mrc total_dose=53 smpd_downscale=1.3  flipgain=y >> LOG
echo " >>> PROGRAM: ctf_estimate" >> LOG
simple_exec prg=ctf_estimate nparts=16 nthr=4 >> LOG
echo " >>> PROGRAM: oristats" >> LOG
 simple_exec prg=oristats oritab=3_ctf_estimate/proteasome.simple nthr=1 ctfstats=yes oritype=mic >> LOG
echo " >>> PROGRAM: selection" >> LOG
simple_exec prg=selection projfile=3_ctf_estimate/proteasome.simple  ctfresthreshold=6 icefracthreshold=1 oritype=mic >> LOG
#echo " >>> PROGRAM: print_project" >> LOG
#simple_exec prg=print_project_field oritype=mic projfile=4_selection/proteasome.simple | awk '{print $6}' | awk -F'=' '{print $2}' > ctf_icefrac_selection.txt 
#echo " >>> PROGRAM: mini_stream" >> LOG
#simple_exec prg=mini_stream cs=2.7 fraca=0.1 kv=300 smpd=0.6575 filetab=ctf_icefrac_selection.txt nparts=16 nthr=4 >> LOG
echo " >>> PROGRAM: pick" >> LOG
simple_exec prg=pick picker=segdiam projfile=4_selection/proteasome.simple nparts=5 nthr=8 >> LOG
echo " >>> PROGRAM: extract" >> LOG
simple_exec prg=extract box=256 nparts=5 nthr=8 projfile=5_pick/proteasome.simple >> LOG
echo " >>> PROGRAM: abinitio2D" >> LOG
simple_exec prg=abinitio2D ncls=100 mskdiam=190 nthr=32 projfile=6_extract/proteasome.simple >> LOG
echo " >>> PROGRAM: selection" >> LOG
simple_exec prg=selection res_threshold=9 oritype=cls2D projfile=7_abinitio2D/proteasome.simple >> LOG
echo " >>> PROGRAM: abinitio3D" >> LOG
simple_exec prg=abinitio3D pgrp=d2 mskdiam=190 nthr=32 projfile=8_selection/proteasome.simple >> LOG


#project_name='proteasome'
#sampling_distance=0.6575           
#total_dose=53
#acceleration_voltage=300           
#spherical_aberration=2.7           
#amplitude_contrast_fraction=0.1
#sampling_distance_downscale=1.3   
#box_size=250         # in pixels
#mask_diameter=200    # in Angstroms
#num_classes=50
# # Manual selection of Mini Stream Classes
# simple_exec prg=convert smpd=${sampling_distance_downscale} stk=mini_stream_selection.spi outstk=mini_stream_selection.mrc
# simple_exec prg=pick pickrefs=mini_stream_selection.mrc nparts=16 nthr=4 projfile=3_ctf_estimate/${project_name}.simple
# simple_exec prg=extract box=${box_size} projfile=6_pick/${project_name}.simple nparts=16 nthr=4
# wc 6_pick/*box | tail -1
# simple_exec prg=abinitio2D ncls=${num_classes} mskdiam=${mask_diameter} nparts=16 nthr=4
# # Manual selection of Abinitio 2D Classes
# simple_exec prg=map_cavgs_selection stk2=abinitio2d_selection.spi
# simple_exec prg=abinitio3D pgrp=d7 mskdiam=${mask_diameter} nparts=16 nthr=4

