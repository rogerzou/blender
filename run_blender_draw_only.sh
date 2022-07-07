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

# Add PAM to guide for visualization (location of Cpf1 should be on other side..TODO need to fix in draw_blender_fig.py
if [[ "$OPT" == *"Cas9"* ]]; then
    GUIDE="${GUIDE}NGG"
elif [[ "$OPT" == *"Cpf1"* ]]; then
    GUIDE="${GUIDE}TTTN"
elif [[ "$OPT" == *"Cas12"* ]]; then
    GUIDE="${GUIDE}TTTN"
fi
python draw_blender_fig.py $OUTDIR/filtered_blender_hits.txt $OUTDIR/blender_hits $GUIDE 
