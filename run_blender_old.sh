#!/bin/bash
# Stacia Wyman 22 July 2019
# Bash script to run BLENDER

# sh run_blender.sh  <path to reference genome> <path to IP bam> <path to control bam> <guide sequence> <output directory> "options as string"

REF=$1
IP=$2
CTRL=$3
GUIDE=$4
OUTDIR=$5
OPT=$6

if [ ! -e $IP ] 
then
	    echo "$IP does not exist"
	        exit
fi
if [ ! -e $CTRL ] 
then
	    echo "$CTRL does not exist"
	        exit
fi
    
if [ ! -d $OUTDIR ] 
then
	   mkdir $OUTDIR
fi

perl blender.pl $OPT $REF $GUIDE  $IP $CTRL > $OUTDIR/unfiltered_blender_hits.txt

# For pooled samples, comment out the next line and uncomment the filter_pool.pl line
perl filter.pl $OUTDIR/unfiltered_blender_hits.txt > $OUTDIR/filtered_blender_hits.txt
#perl filter_pool.pl $OUTDIR/unfiltered_blender_hits.txt > $OUTDIR/filtered_pooled_blender_hits.txt

# Add PAM to guide for visualization (TODO location of Cpf1 PAM should be on other side)
GUIDE="${GUIDE}NGG"
#GUIDE="${GUIDE}TTTN"
python draw_blender_fig.py $OUTDIR/filtered_blender_hits.txt $OUTDIR/blender_hits $GUIDE
