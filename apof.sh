simple_exec prg=new_project projname=apof
cd apof
filetab_movs.pl /mnt/beegfs/elmlund/testing-datasets/apoferritin/20221214_105239_vitroEase_apoF_bf15_300kv_highres/movies
simple_exec prg=import_movies filetab=movies.txt smpd=0.693 ctf=yes cs=2.7 kv=300 fraca=0.1
simple_exec prg=motion_correct smpd_downscale=1.3 total_dose=51.8 nparts=10 nthr=4 projfile=1_import_movies/apof.simple script=yes gainref=/mnt/beegfs/elmlund/testing-datasets/apoferritin/20221214_105239_vitroEase_apoF_bf15_300kv_highres/gain/20221214_114106_EER_GainReference.gain
simple_exec prg=ctf_estimate projfile=2_motion_correct/apof.simple nparts=8 nthr=8 script=yes
simple_exec prg=oristats oritab=3_ctf_estimate/apof.simple ctfstats=yes nthr=8 oritype=mic
#AVERAGE CTF RESOLUTION               :     4.31
#STANDARD DEVIATION OF CTF RESOLUTION :     6.39
#MINIMUM CTF RESOLUTION (BEST)        :     2.80
#MAXIMUM CTF RESOLUTION (WORST)       :    50.00
#AVERAGE DF                           :     1.06
#STANDARD DEVIATION OF DF             :     0.40
#MINIMUM DF                           :     0.20
#MAXIMUM DF                           :     4.96
simple_exec prg=selection oritype=mic projfile=3_ctf_estimate/apof.simple ctfresthreshold=6 icefracthreshold=1
simple_exec prg=selection oritype=mic projfile=3_ctf_estimate/apof.simple ctfresthreshold=6 icefracthreshold=1 nran=300
simple_exec prg=print_project_field oritype=mic projfile=5_selection/apof.simple > tmp.txt
awk '{print $6}' tmp.txt > tmp2.txt
awk -F'=' '{print $2}' tmp2.txt > sel5.txt
simple_exec prg=mini_stream script=yes cs=2.7 kv=300 smpd=1.3 nthr=18 filetab=sel5.txt projfile=apof.simple
simple_exec prg=convert smpd=1.3 stk=picksel.spi outstk=picksel.mrc
simple_exec prg=pick nparts=16 nthr=6 pickrefs=picksel.mrc projfile=4_selection/apof.simple script=yes
simple_exec prg=extract nparts=8 nthr=6 box=200 projfile=7_pick/apof.simple script=yes
