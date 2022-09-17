#!/bin/bash
# Stacia Wyman 22 July 2019
# Bash script to run BLENDER

# sh run_blender.sh  <path to reference genome> <path to IP bam> <path to control bam> <guide sequence> <output directory> "options as string"

GUIDE=$1
INFILE=$2
OUTFILE=$3

# Add PAM to guide for visualization (TODO location of Cpf1 PAM should be on other side)
GUIDE="${GUIDE}NGG"
#GUIDE="${GUIDE}TTTN"
python draw_blender_fig.py $INFILE $OUTFILE $GUIDE
