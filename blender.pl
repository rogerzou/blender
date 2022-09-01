#!/usr/bin/perl

# Version 1.0 
# 11/11/18 Stacia Wyman staciawyman@berkeley.edu

# BLENDER is a companion program to the DISCOVER-Seq assay to identify off-target editing
# sites from MRE11 ChIP-Seq  experiments.  It takes aligned bamfiles from the IP 
# experiment and (optionally) a control bamfile and identifies locations with stacks
# of reads at putative cutsites. PAM sequences can be provided by the user as well as
# a guide sequence. BLENDER makes use of the ENCODE ChIP-Seq Blacklists for human and
# mouse which are lists of regions in the genome that have artifactual large numbers 
# of reads. These lists and the control bam plus PAM sequences and the guide 
# are used to filter out false positives.  BLENDER runs on mouse mm10 and 
# human hg38 genomes (blacklists coordinates are for these genomes).

use Getopt::Long;

my %both_starts;
my $verbose = 0;
my $debug = 0;
my $pams   = "GG,AG";
my $nuclease = "Cas9";
my $threshold = 3;
GetOptions ("c=i" => \$threshold,    # numeric
            "p=s"   => \$pams,
            "n=s"   => \$nuclease,  # Cas9 vs Cas12
            "debug"    => \$debug,     # flag
	    "no_guide" => \$no_guide,  # flag
            "verbose"  => \$verbose)   # flag
  or die("USAGE: perl blender.pl [options] <reference genome> <guide sequence> <edited bam> <control bam>\n");

# print "Nuclease: $nuclease\n";
# print "PAMs: $pams\n";

$control_bam = "";
if (!$no_guide) {
    if ($#ARGV < 3) { print "Missing argument $#ARGV \n"; exit; }
    if (length($ARGV[1]) != 20) { print "Please provide a 20bp guide sequence.$ARGV[0]\n"; exit; }
    $genome = $ARGV[0];
    $input_guide = $ARGV[1];
    $edited_bam = $ARGV[2];
    $control_bam = $ARGV[3];
} else {
    $genome = $ARGV[0];
    $edited_bam = $ARGV[1];
    $control_bam = $ARGV[2];
}

@pamlist = split(/,/,$pams);
# Test params
$check_guide = 1;
if ($no_guide) {
    $check_guide = 0;
}
$max_mismatches = 8;
$min_discoscore = 3;

if ($verbose) {
    if ($no_guide) {
        print "Options: pams @pamlist\nVerbose $verbose\nThreshold $threshold\nNo Guide TRUE\nEditedBam $edited_bam\n";
    } else {
        print "Options: pams @pamlist\nVerbose $verbose\nThreshold $threshold\nGuide $input_guide\nEditedBam $edited_bam\n";
    }
}

# Used to get $genome from bam file, but it only works for BWA, so now taking it as argument.
# Get organism/location of reference genome from @PG line in bamfile header
# $PG = `samtools view -H $edited_bam | grep PG`;
# if ($PG =~ /sampe\s+(.+?)\s+/) {
#     $genome = $1;
# }

# Set blacklist and chromosome list from genome, assumes mm10 and hg38 and 
# that "mm10" is in name of reference genome
if ($genome =~ /mm10/) {            # if mm10
    $blacklist_file = "./mm10.blacklist.bed";
    @chroms = (1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,"X","Y");
} elsif ($genome =~ /hg38/) {        # if hg38
    $blacklist_file = "./hg38.blacklist.bed";
    @chroms = (1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,"X","Y");
} elsif ($genome =~ /hg19/) {        # if hg19
    $blacklist_file = "./hg19.blacklist.bed";
    @chroms = (1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,"X","Y");
}

print "Chr:Start-End\tCutsite\tDiscoscore\tCutsite Ends\tStrand\tPAM\tGuide sequence\tMismatches\n";

# For each chromosome, traverse bam file, looking for putative cutsites and output them
foreach $i (@chroms) {
    undef %rev_starts;
    undef %for_starts;
    undef %both_starts;
    $c = "chr".$i;
    open(F,"samtools view $edited_bam $c |");
    # Compile list for forward read blunt ends and reverse read blunt ends
    while (<F>) {
	chomp;
        my ($read,$flag,$chr,$start_loc,$MQ,$cigar,$a,$b,$tlen,$seq) = split(/\t/);
	my $seqlen = length($seq) ;
        # Test: 
	# tlen == 0 means mate is unmapped
        # flag & 0x08 == read is second in pair
        # mapping quality over 25
	if ($tlen == 0 && $MQ > 25) {
	    if (!($flag & 0x08)) { # read is not second in pair
                $for_starts{$start_loc}++;
	        $both_starts{$start_loc}++;
	    } else { # second in pair, so pileup at other end of read
                $rev_starts{$start_loc+$seqlen-1}++;
	        $both_starts{$start_loc+$seqlen-1}++;
	    }
	}
        # OR tlen < 0, so mate is upstream, this is second
	if ($MQ > 25 && $tlen > 0) {
            $for_starts{$start_loc}++;
	    $both_starts{$start_loc}++;
        }
        # OR tlen > 0, so mate is downstream, this is first, so want to record 
	if ($MQ > 25 && $tlen < 0) {
            $rev_starts{$start_loc+$seqlen-1}++;
	    $both_starts{$start_loc+$seqlen-1}++;
        }
    }
    close(F);
    # Combine forw and rev blunt ends at cut site to create one pile per putative cut site
    foreach my $start (sort { $a <=> $b } keys(%for_starts) ) {
	if (($rev_starts{$start-1} + $for_starts{$start}) >= $threshold) {
	    $both_starts{$start-1} += $both_starts{$start};
	}
    }

    foreach my $start (sort { $a <=> $b } keys(%both_starts) ) {
	$l = "$c:$start-$start";
        if ($both_starts{$start} >= $threshold) {
	# Might implement this again, but not yet
        #if ($both_starts{$start} >= $threshold || ($both_starts{$start} == 2 && 
	#($both_starts{$start-1}+$both_starts{$start}+$both_starts{$start+2}) >= $threshold)) {
	    if ($debug) {print "Check both_starts $c:$start, $both_starts{$start}\n";}
	    if (blacklist($c,$start)) { 
    	        if ($verbose) { print "$c:$start\t$sum\t$both_starts{$start}\tFILTERED:blacklisted\n"; }
		next; 
	    }
	    if ($control_bam) {
                $d_control = `samtools depth -r $l $control_bam`;
	        chomp($d_control);
	        ($x,$y,$depth_con) = split(/\t/,$d_control);
	        if ($depth_con > 10) { 
		    #if ($verbose) {print "CONTROL Skipping $l, $depth_con, $both_starts{$start} \n";}
		    next;
	        }
	    } 

	    $over_max = 0;
	    $pamleft = check_pam_left($c,$start);
	    $pamright = check_pam_right($c,$start);

    	    if ($pamleft) {
                $d = `samtools depth -r $l $edited_bam`;
	        chomp($d);
	        ($x,$y,$depth) = split(/\t/,$d);
	 	if ($depth > 0 ) {
	            if ($both_starts{$start}/$depth < .25) { 
    	                if ($verbose){ print "$c:$s-$e\t$start\t$sum\t$both_starts{$start}\tantisense\tN$pamleft\t\tFILTERED:deep area\n";}
			$over_max = 1;
		    }
		}
		if (!$over_max) {
            if ($nuclease eq "Cas9") {          # if PAM is left for Cas9 (PAM on right for Cpf1), set start/end coords
                $s = $start - 2; $e = $start + 17;
                $Npamleft = "N$pamleft";
            } elsif ($nuclease eq "Cpf1" || $nuclease eq "Cas12") {
                $s = $start - 4; $e = $start + 15;
                $Npamleft = $pamleft . 'N';
            } else {
                print "ERROR NUCLEASE NOT Cas9 or Cpf1/Cas12\n";
            }
    		    my $guide = get_guide($c,$s,$e);
    		    my $sum = add_window($start,5);
		    if ($sum < $min_discoscore) { next;} 
		    $guide = revcomp($guide);
		    my $mm = guide_mm($input_guide,$guide);
		    if ($check_guide)  {
			if ($mm <= $max_mismatches) {
    	                    print "$c:$s-$e\t$start\t$sum\t$both_starts{$start}\tantisense\t$Npamleft\t$guide\t$mm\n";
			} else {
    	                    if ($verbose) {print "$c:$s-$e\t$start\t$sum\t$both_starts{$start}\tantisense\t$Npamleft\t$guide FILTERED: $mm mismatches\n";}
			}
    		    } else {
    	                print "$c:$s-$e\t$start\t$sum\t$both_starts{$start}\tantisense\t$Npamleft\t$guide\t$mm\n";
		    }
		}
    	    }
    	    if ($pamright) { 
                $d = `samtools depth -r $l $edited_bam`;
	        chomp($d);
	        ($x,$y,$depth) = split(/\t/,$d);
	 	if ($depth > 0 ) {
	            if ($both_starts{$start}/$depth < .25) { 
    	                if ($verbose) {print "$c:$s-$e\t$start\t$sum\t$both_starts{$start}\tsense\tN$pamright\t$guide\tFILTERED:deep area\n";}
			$over_max = 1;
			next;
		    }
		}
		if (!$over_max) {
            if ($nuclease eq "Cas9") {          # if PAM is right for Cas9 (PAM on left for Cpf1), set start/end coords
                $Npamright = "N$pamright";
            } elsif ($nuclease eq "Cpf1" || $nuclease eq "Cas12") {
                $Npamright = $pamright . 'N';
            } else {
                print "ERROR NUCLEASE NOT Cas9 or Cpf1/Cas12\n";
            }
    	            $e = $start + 3; $s = $start - 16;
    		    $guide = get_guide($c,$s,$e);
    		    $sum = add_window($start,5);
		    if ($sum < $min_discoscore) { next;} 
		    my $mm = guide_mm($input_guide,$guide);
		    if ($check_guide)  { # guide was given as input parameter
			if ($mm <= $max_mismatches) {
    	                    print "$c:$s-$e\t$start\t$sum\t$both_starts{$start}\tsense\t$Npamright\t$guide\t$mm\n";
			} else {
    	                    if ($verbose) {print "$c:$s-$e\t$start\t$sum\t$both_starts{$start}\tsense\t$Npamright\t$guide FILTERED: $mm mismatches\n";}
		 	    next;
			}
		    } else {
    	                print "$c:$s-$e\t$start\t$sum\t$both_starts{$start}\tsense\t$Npamright\t$guide\t$mm\n";
		    }
		}
    	    }
	}
    }
}

sub check_pam_left {
    my ($chr,$x) = @_;
    my $ref_pam = "";
    if ($nuclease eq "Cas9") {          # if PAM is left for Cas9 (PAM on right for Cpf1)
        $s = $x-5; $e = $x-4;
    } elsif ($nuclease eq "Cpf1" || $nuclease eq "Cas12") {
        $s = $x+17; $e = $x+19;
    } else {
        print "ERROR NUCLEASE NOT Cas9 or Cpf1/Cas12\n";
    }
    my $coords = $chr.":".$s."-".$e;
    # covers edge case where start of read is so early leading to querying coordinates < 0
    if ($s < 0 || $e < 0) {
        if ($verbose){print "check_pam_left(): Start coord is $x\n. PAM check $s-$e is out of bounds.";}
        return "";
    }
    open(F,"samtools faidx $genome $coords  | ") || die "Couldnt open $!";
    while (<F>) {
	if (/^>/) { next; }
	chomp;
	$ref_pam = uc($_);
    }
    close(F);
   
    foreach my $pam (@pamlist) {
      if ($ref_pam eq revcomp($pam)) { return $pam; }
    }
    return "";
}
	

# alt pam is AG
sub check_pam_right {
    my ($chr,$x) = @_;
    
    my $ref_pam = "";
    if ($nuclease eq "Cas9") {          # if PAM is right for Cas9 (PAM on left for Cpf1)
        $s = $x+5; $e = $x+6;
    } elsif ($nuclease eq "Cpf1" || $nuclease eq "Cas12") {
        $s = $x-20; $e = $x-18;
    } else {
        print "ERROR NUCLEASE NOT Cas9 or Cpf1/Cas12\n";
    }
    $coords = $chr.":".$s."-".$e;
    # covers edge case where start of read is so early leading to querying coordinates < 0
    if ($s < 0 || $e < 0) {
        if ($verbose){print "check_pam_right(): Start coord is $x\n. PAM check $s-$e is out of bounds.";}
        return "";
    }
    open(F,"samtools faidx $genome $coords  | ") || die "Couldnt open $!";
    while (<F>) {
	chomp;
	if (/^>/) { next; }
	$ref_pam = uc($_);
    }
    close(F);
    foreach my $pam (@pamlist) {
      if ($ref_pam eq $pam) { return $pam; }
    }
    return "";
}

sub get_guide {
    my ($chr,$start,$end) = @_;

    $coords = $chr.":".$start."-".$end;
    open(F,"samtools faidx $genome $coords | ") || die "Couldnt open $!";
    while (<F>) {
	chomp;
	if (/^>/) { next; } 
	return uc($_);
    }
}

sub get_guide_from_bam {
    my ($chr,$start,$end) = @_;

    $coords = $chr.":".$start."-".$end;
    open(F,"samtools mpileup -r $coords -f $genome $edited_bam 2>/dev/null | ") || die "Couldnt open $!";
    $str = "";
    while (<F>) {
	chomp;
	($chr,$loc,$nt,$depth) = split(/\t/);
	$str .= $nt;
    }
    close(F);
    return (uc($str));
}

# add window plus 1bp over cutsite for forward and for reverse
sub add_window {
    my ($start,$window_size) = @_;
    $sum = 0;
    for (my $i = $start-($window_size-1); $i <= $start+1; $i++) {
	$sum += $rev_starts{$i};
    } 
    for (my $i = $start; $i <= $start+$window_size; $i++) {
	$sum += $for_starts{$i};
    } 
    return $sum;
}

sub blacklist {
    my ($chr,$start) = @_;
    open(F,$blacklist_file) || die "couldn't open $blacklist_file";
    while (<F>) {
	chomp;
	($b_chr,$b_start,$b_end) = split(/\t/);
	if (($chr eq $b_chr) && ($start >= $b_start) && ($start <= $b_end)) {
	    #print "FILTERED BLACKLIST $chr;$start\n";
	    return 1;
	}
    }
    return 0;
}

# Check how many mismatches between input guide and guide sequence at target site
sub guide_mm {
    my ($input_guide,$guide) = @_;
    my $mm = 0;
    (@input) = split(//,uc($input_guide));
    (@check) = split(//,uc($guide));
    for (my $i = 0; $i <= $#input; $i++) {
	if ($input[$i] ne $check[$i]) { $mm++; }
    }
    return $mm;
}

sub revcomp {
    my ($dna) = @_;
    my $rc = reverse($dna);
    $rc =~ tr/ABCDGHMNRSTUVWXYabcdghmnrstuvwxy/TVGHCDKNYSAABWXRtvghcdknysaabwxr/;
    return $rc;
}
