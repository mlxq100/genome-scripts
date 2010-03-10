#!/usr/bin/perl -w
use strict;
# author jason stajich <stajich@berkeley.edu>
# description:
# this script will turn GFF (2 or 3) into gtf (gff 2.5) suitable for twinscan training 
# by adding start and stop codons (removing 1st and last codons from the annotated CDS).
# There are probably a few problems with this approach, but it works well enough and I am assuming the
# validate_gtf.pl script from the Brent lab catches any problems to weed out.
#
# It currently expects GFF2 data to have either Transcript or GenePrediction group tag
use Bio::DB::Fasta;
use Getopt::Long;

my $debug = 0;
GetOptions (
	    'v|version!' => \$debug);

my $db= Bio::DB::Fasta->new(shift @ARGV);
# Frame is calculated as (3 - ((length-frame) mod 3)) mod 3
my @order;
my %gene;
my %seen;
while(<>) {
    my @line = split(/\t/,$_);
    next if uc($line[2]) ne 'CDS';
    my $last = pop @line;
    chomp($last);
    my $group;
    if( $last =~ /(Transcript|GenePrediction)\s+(\S+)/ ) {
	($group) = $2;
    } elsif( $last =~ /Parent=([^;]+);?/) {
	$group = $1;
	$group =~ s/Model\.//;
    } 
    if( ! $group ) {
	warn("no group in $_\n");
	next;
    } 
    if( ! $seen{$group}++ ) {
	push @order, $group;
    }
    push @{$gene{$group}}, [ @line, 
			     sprintf('transcript_id "%s"; gene_id "%s";',
				     "$group.1", $group)];
}
for my $gene ( @order ) {
    my @ordered_cds = ( map { $_->[1] }
			sort { $a->[0] <=> $b->[0]}
			map { [$_->[3] * ($_->[6] eq '-' ? -1 : 1), $_] }
			@{$gene{$gene}} );
	my $i = 1;
	my $count = scalar @ordered_cds;
    my $running = 0;
    for my $cds ( @ordered_cds ) {
	my $type;
        if( $count == 1 ) {
        $type = 'single';
        } elsif( $count == $i ) {
        $type = 'terminal';
        } elsif( $i == 1 ) {
        $type = 'initial';
        } else {
        $type = 'internal';
        }
        $cds->[-1] = "exontype \"$type\"; ".$cds->[-1];
	$cds->[7]  = ( $running % 3);
	$running += abs($cds->[4] - $cds->[3]) + 1;
	$i++;
     }

    my ($fexon,$lexon) = ($ordered_cds[0], $ordered_cds[-1]);
    if( $fexon->[6] eq '+' ) {
	#$fexon->[-1] =~ s/exontype\s+\S+\s*//;
	unshift @ordered_cds, [$fexon->[0], $fexon->[1], 'start_codon',
		   $fexon->[3],
		   $fexon->[3] + 2,
		   $fexon->[5],
		   $fexon->[6],
		   '.',
		   $fexon->[8]];
	$fexon->[3] += 3;
    } else {
	my $grp = $fexon->[8];
	$grp =~ s/exontype\s+\S+\s*//;
	print join("\t", $fexon->[0], $fexon->[1], 'start_codon',
		   $fexon->[4]-2,
		   $fexon->[4],
		   $fexon->[5],
		   $fexon->[6],
		   '.',
		   $grp), "\n";	
	$fexon->[4] -= 3;
    }
    
    if($lexon->[6] eq '-' ){
	if( $debug ) {
	    my $last_codon = $db->seq($lexon->[0], 
				      $lexon->[3]+ 2 => $lexon->[3] );
	    
	    my $next_last_codon = $db->seq($lexon->[0], $lexon->[3]+5 => $lexon->[3]+3);
	    print "last_codon $last_codon : next_last_codon $next_last_codon\n";
	    print "last exon ",$db->seq($lexon->[0],
					$lexon->[4] => $lexon->[3]),"\n"; 
	}
	my $grp = $lexon->[8];
	$grp =~ s/exontype\s+\S+\s*//;
	push @ordered_cds, [$lexon->[0], $lexon->[1], 'stop_codon',
			    $lexon->[3],
			    $lexon->[3] + 2,
			    $lexon->[5],
			    $lexon->[6],
			    '.',
			    $grp,
			    ];
	$lexon->[3] += 3;
	if( $debug ) {
	    print "last exon ",$db->seq($lexon->[0],
					$lexon->[4] => $lexon->[3]),"\n"; 
	}
    } else {
	if( $debug ) {
	    my $last_codon = $db->seq($lexon->[0], $lexon->[4]-2 => $lexon->[4]);
	    my $next_last_codon = $db->seq($lexon->[0], $lexon->[4]-5 => $lexon->[4]-3);
	    print "last_codon $last_codon : next_last_codon $next_last_codon\n";
	    print "last exon ",$db->seq($lexon->[0],
					$lexon->[3] => $lexon->[4]),"\n"; 
	}
	my $grp = $lexon->[8];
	$grp =~ s/exontype\s+\S+\s*//;
	push @ordered_cds,[$lexon->[0], $lexon->[1], 'stop_codon',
		   $lexon->[4]-2,
		   $lexon->[4],
		   $lexon->[5],
		   $lexon->[6],
		   '.',
		   $grp];
	$lexon->[4] -= 3;
	if( $debug )  {
	    print "last exon ",$db->seq($lexon->[0],
					$lexon->[3] => $lexon->[4]),"\n"; 
	}
    }
    for my $cds ( @ordered_cds ) {
	print join("\t", @$cds), "\n";
    }


}
