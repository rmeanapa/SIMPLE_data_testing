mkdir -p ryper; cd ryper
simple_exec prg=new_project projname=ryper dir=./ > LOG 2>&1
filetab_movs.pl /mnt/beegfs/elmlund/testing-datasets/RYPER/20220523_164637_RYPER_xlinked_monoG_CHAPS_bf0/movies >> LOG 2>&1
echo " >>> PROGRAM: import_movies" >> LOG 2>&1
simple_exec prg=import_movies cs=2.7 fraca=0.1 kv=200 smpd=0.405 filetab=movies.txt >> LOG 2>&1
echo " >>> PROGRAM: motion_correct" >> LOG 2>&1
simple_exec prg=motion_correct nparts=5 nthr=8 gainref=/mnt/beegfs/elmlund/testing-datasets/RYPER/20220523_164637_RYPER_xlinked_monoG_CHAPS_bf0/gain/gainref_05_23_2022.mrc total_dose=57 smpd_downscale=1.3 >> LOG 2>&1
echo " >>> PROGRAM: ctf_estimate" >> LOG 2>&1
simple_exec prg=ctf_estimate nparts=5 nthr=8 projfile=2_motion_correct/ryper.simple >> LOG 2>&1
filetab_mrc.pl 2_motion_correct/ >> LOG 2>&1
echo " >>> PROGRAM: pick" >> LOG 2>&1
simple_exec prg=pick picker=segdiam projfile=3_ctf_estimate/ryper.simple nparts=24 nthr=1 >> LOG 2>&1
echo " >>> PROGRAM: extract" >> LOG 2>&1
simple_exec prg=extract box=256 nparts=5 nthr=8 projfile=4_pick/ryper.simple >> LOG 2>&1
echo " >>> PROGRAM: abinitio2D" >> LOG 2>&1
simple_exec prg=abinitio2D ncls=90 mskdiam=180 nthr=20 nparts=4 >> LOG 2>&1
echo " >>> PROGRAM: model_cavgs_rejection" >> LOG 2>&1 
simple_exec prg=model_cavgs_rejection mskdiam=180 nthr=20 >> LOG 2>&1
echo " >>> PROGRAM: abinitio3D_cavgs" >> LOG 2>&1 
simple_exec prg=abinitio3D_cavgs pgrp=d2 mskdiam=180 nthr=40 >> LOG 2>&1
echo " >>> PROGRAM: abinitio3D" >> LOG 2>&1
simple_exec prg=abinitio3D pgrp=d2 mskdiam=180 nthr=8 nparts=10 cavg_ini_ext=yes >> LOG 2>&1
echo " >>> PROGRAM: refine3D_auto" >> LOG 2>&1 
simple_exec prg=refine3D_auto pgrp=d2 mskdiam=180 nparts=10 nthr=8 >> LOG 2>&1



#name=ryper
#smpd=0.405
#dose=57
#dir=/mnt/beegfs/elmlund/testing-datasets/RYPER/20220523_164637_RYPER_xlinked_monoG_CHAPS_bf0
##gain=$dir/gain/$(ls $dir/gain)
#gain=$dir/gain/gainref_05_23_2022.mrc
#
#simple_exec prg=new_project projname=$name qsys_partition=csbdevel
#cd $name
#find $dir/movies -type f > movies.txt
#simple_exec prg=import_movies smpd=$smpd cs=2.7 kv=200 fraca=0.1 filetab=movies.txt
#simple_exec prg=motion_correct gainref=$gain total_dose=$dose nparts=32 nthr=6 projfile=1_import_movies/$name.simple flipgain=y script=yes
#simple_exec prg=ctf_estimate projfile=2_motion_correct/$name.simple nparts=16 nthr=8 script=yes
#simple_exec prg=oristats oritab=3_ctf_estimate/$name.simple ctfstats=yes nthr=8 oritype=mic
#
#
#simple_exec prg=selection oritype=mic projfile=3_ctf_estimate/$name.simple ctfresthreshold=6 icefracthreshold=1
#simple_exec prg=selection oritype=mic projfile=3_ctf_estimate/$name.simple ctfresthreshold=6 icefracthreshold=1 nran=300
#simple_exec prg=print_project_field oritype=mic projfile=5_selection/$name.simple > tmp.txt
#awk '{print $6}' tmp.txt > tmp2.txt
#awk -F'=' '{print $2}' tmp2.txt > sel5.txt
#simple_exec prg=mini_stream script=yes cs=2.7 kv=300 smpd=1.3 nthr=18 filetab=sel5.txt projfile=$name.simple
#simple_exec prg=convert smpd=1.3 stk=selpick.spi outstk=picksel.mrc
#simple_exec prg=pick nparts=16 nthr=6 pickrefs=picksel.mrc projfile=4_selection/$name.simple script=yes
#simple_exec prg=extract nparts=8 nthr=6 box=180 projfile=7_pick/$name.simple script=yes
