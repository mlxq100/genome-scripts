#!/usr/bin/perl -w
use strict;

use Getopt::Long;
use Bio::SeqIO;
my $debug = 0;


use constant GENES    => 'coprinus_gene_summary.tab';
use constant ORTHOS   => 'coprinus_orthologs.tab';
use constant ORPHANS  => 'coprinus_orphans.tab';
use constant PARALOGS => 'coprinus_paralogs.tab';
use constant REPEATS  => 'coprinus_rptmask.tab';
use constant INTERGENIC => 'coprinus_intergenic_summary.tab';
use constant HAPLOTYPES => 'recombination_rates.tab';
use constant DS => 'coprinus_avg_ds.tab';


my $DIR = 'plot';
my $odir = 'chrom_summary';
GetOptions(
	   'dir:s'      => \$DIR,
	   );


my $dir = shift;
my %CHROMS;
{
 my $seq = Bio::SeqIO->new(-format => 'fasta', -file=> "$DIR/genome.fa");
 my $i = 0;
 while( my $s = $seq->next_seq ) {
   $CHROMS{$s->display_id} = [$i++,$s->length];   
 }
}

my $genes = Windows->new('genes');
$genes->parse( File::Spec->catfile($DIR,GENES),
	       qw(chrom chrom_start));

my $repeats = Windows->new('repeats');
$repeats->parse(File::Spec->catfile($DIR,REPEATS),
		qw(chrom start));

my $orthos = Windows->new('orthologs');
$orthos->parse(File::Spec->catfile($DIR,ORTHOS),
	       qw(src src_start));
#$orthos->normalize($genes);

my $orphans = Windows->new('orphans'); # orphans
$orphans->parse(File::Spec->catfile($DIR,ORPHANS),
		qw(chrom chrom_start));
#$orphans->normalize($genes);

my $paralogs = Windows->new('paralogs'); #paralogs
$paralogs->parse(File::Spec->catfile($DIR,PARALOGS),
		 qw(chrom chrom_start));
#$paralogs->normalize($genes);

my $dS = Windows->new('dS'); #paralogs
$dS->parse(File::Spec->catfile($DIR,DS),
		 qw(scaffold start_position dS));

my $dupnum = Windows->new('dupNum'); #paralogs
$dupnum->parse(File::Spec->catfile($DIR,DS),
		 qw(scaffold start_position count));

#my $ssgenes = Windows->new('ssgenes'); #species-specificgenes
#$ssgenes->parse(File::Spec->catfile($DIR,SSGENES),
#		qw(chrom chrom_start));
#$ssgenes->normalize($genes);

my %dat = ( 'genes'   => $genes,
	    'repeats' => $repeats,
	    'paralogs' => $paralogs,
	    'orthologs'=> $orthos,
	    'orphans'  => $orphans,
	    'dupnum'   => $dupnum,
	    #'species_specific' => $ssgenes,
	    );

open(my $blocks => (File::Spec->catfile($DIR,HAPLOTYPES))) || die $!;
my %blocks;
my $block_hdr = <$blocks>;
while(<$blocks>) {
    next if /^#/;
    my @line = split;
    push @{$blocks{$line[0]}->{$line[5]}}, [$line[1],$line[2]];
}

for my $dat ( keys %dat ) {
    open(my $hotfh => ">$odir/$dat\_hot.dat") || die $!;
    print $hotfh join("\t",qw(CHROM BIN TOTAL)),"\n";

    open(my $coldfh => ">$odir/$dat\_cold.dat") || die $!;
    print $coldfh join("\t",qw(CHROM BIN TOTAL)),"\n";

    open(my $avgfh => ">$odir/$dat\_avg.dat") || die $!;    
    print $avgfh join("\t",qw(CHROM BIN TOTAL)),"\n";

    open(my $notCfh => ">$odir/$dat\_notcold.dat") || die $!;    
    print $notCfh join("\t",qw(CHROM BIN TOTAL)),"\n";

    for my $chrom (sort { $CHROMS{$a}->[0] <=> $CHROMS{$b}->[0] } 
		   keys %CHROMS) {
	next if $chrom =~ /^U/i;
#	warn( "Processing $chrom ...\n");
#	print "$chrom ", $CHROMS{$chrom}->[1], "\n";
	for my $blocks ( @{$blocks{$chrom}->{'HOT'}} ) {
	    my $bins = &process_lumped($dat{$dat},$chrom,
				       @$blocks);	    
	    print $hotfh   join("\n",@$bins),"\n" if scalar @$bins; 
	    print $notCfh  join("\n",@$bins),"\n" if scalar @$bins;

	}
	for my $blocks ( @{$blocks{$chrom}->{'COLD'}} ) {
	    my $bins = &process_lumped($dat{$dat},$chrom,
				       @$blocks);	    
	    print $coldfh join("\n",@$bins),"\n" if scalar @$bins;
	}
	for my $blocks ( @{$blocks{$chrom}->{'NEUTRAL'}} ) {
	    my $bins = &process_lumped($dat{$dat},$chrom,
				       @$blocks);	    
	    print $notCfh  join("\n",@$bins),"\n" if scalar @$bins;
	    print $avgfh join("\n",@$bins),"\n" if scalar @$bins;
	}
	
    }
    open(R, ">$odir/coldhot_$dat.R") || die $!;
    printf R "%scold <- read.table(\"%s_cold.dat\",header=T)\n",$dat,$dat;
    printf R "%shot <- read.table(\"%s_hot.dat\",header=T)\n",$dat,$dat;
    printf R "%savg <- read.table(\"%s_avg.dat\",header=T)\n",$dat,$dat;
    printf R "%snotcold <- read.table(\"%s_notcold.dat\",header=T)\n",$dat,$dat;

    printf R "pdf(\"cold_hot_avg_%s.pdf\")\n",$dat;
    printf R "boxplot(%scold\$TOTAL,%shot\$TOTAL,%savg\$TOTAL,%snotcold\$TOTAL,main=\"%s Cold-Hot-Avg Density BoxPlot\", outline=FALSE, names=c(\"Cold\",\"Hot\",\"Avg\", \"NotCold\"))\n",$dat,$dat,$dat,$dat,$dat;
    printf R "summary(%shot\$TOTAL)\n",$dat;
    printf R "summary(%savg\$TOTAL)\n",$dat;
    printf R "summary(%scold\$TOTAL)\n",$dat;
    printf R "summary(%snotcold\$TOTAL)\n",$dat;

    printf R "var.test(%scold\$TOTAL,%shot\$TOTAL)\n",$dat,$dat;
    printf R "var.test(%shot\$TOTAL,%savg\$TOTAL)\n",$dat,$dat;
    printf R "var.test(%scold\$TOTAL,%savg\$TOTAL)\n",$dat,$dat;
    printf R "var.test(%scold\$TOTAL,%snotcold\$TOTAL)\n",$dat,$dat;


    printf R "ks.test(%scold\$TOTAL,%shot\$TOTAL)\n",$dat,$dat;
    printf R "ks.test(%shot\$TOTAL,%savg\$TOTAL)\n",$dat,$dat;
    printf R "ks.test(%scold\$TOTAL,%savg\$TOTAL)\n",$dat,$dat;
    printf R "ks.test(%scold\$TOTAL,%snotcold\$TOTAL)\n",$dat,$dat;

    printf R "wilcox.test(%scold\$TOTAL,%shot\$TOTAL)\n",$dat,$dat;
    printf R "wilcox.test(%shot\$TOTAL,%savg\$TOTAL)\n",$dat,$dat;
    printf R "wilcox.test(%scold\$TOTAL,%savg\$TOTAL)\n",$dat,$dat;
    printf R "wilcox.test(%scold\$TOTAL,%snotcold\$TOTAL)\n",$dat,$dat;
}

{
# need to do the dS summary
    my $dat = 'dS';
    $dat{$dat} = $dS;
    open(my $hotfh => ">$odir/$dat\_hot.dat") || die $!;
    print $hotfh join("\t",qw(CHROM BIN MEAN)),"\n";
    
    open(my $coldfh => ">$odir/$dat\_cold.dat") || die $!;
    print $coldfh join("\t",qw(CHROM BIN MEAN)),"\n";
    
    open(my $avgfh => ">$odir/$dat\_avg.dat") || die $!;    
    print $avgfh join("\t",qw(CHROM BIN MEAN)),"\n";

    open(my $notCfh => ">$odir/$dat\_notcold.dat") || die $!;    
    print $notCfh join("\t",qw(CHROM BIN MEAN)),"\n";
    
    for my $chrom (sort { $CHROMS{$a}->[0] <=> $CHROMS{$b}->[0] } 
		   keys %CHROMS) {
	next if $chrom =~ /^U/i;
#	warn( "Processing $chrom ...\n");
#	print "$chrom ", $CHROMS{$chrom}->[1], "\n";
	for my $blocks ( @{$blocks{$chrom}->{'HOT'}} ) {
	    my $bins = &process_lumped_value($dat{$dat},$chrom,
				       @$blocks);	    
	    print $hotfh   join("\n",@$bins),"\n" if scalar @$bins;
	    print $notCfh  join("\n",@$bins),"\n" if scalar @$bins;
	    
	}
	for my $blocks ( @{$blocks{$chrom}->{'COLD'}} ) {
	    my $bins = &process_lumped_value($dat{$dat},$chrom,
				       @$blocks);	    
	    print $coldfh join("\n",@$bins),"\n" if scalar @$bins;
	}
	for my $blocks ( @{$blocks{$chrom}->{'NEUTRAL'}} ) {
	    my $bins = &process_lumped_value($dat{$dat},$chrom,
					     @$blocks);	    
	    print $avgfh join("\n",@$bins),"\n" if scalar @$bins;
	    print $notCfh  join("\n",@$bins),"\n" if scalar @$bins;
	}
	
    }
    open(R, ">$odir/coldhot_$dat.R") || die $!;
    printf R "%scold <- read.table(\"%s_cold.dat\",header=T)\n",$dat,$dat;
    printf R "%shot <- read.table(\"%s_hot.dat\",header=T)\n",$dat,$dat;
    printf R "%savg <- read.table(\"%s_avg.dat\",header=T)\n",$dat,$dat;
    printf R "%snotcold <- read.table(\"%s_notcold.dat\",header=T)\n",$dat,$dat;
    
    printf R "pdf(\"cold_hot_avg_%s.pdf\")\n",$dat;
    printf R "boxplot(%scold\$MEAN,%shot\$MEAN,%savg\$MEAN,%snotcold\$MEAN,main=\"%s Cold-Hot-Avg Density BoxPlot\", outline=FALSE, names=c(\"Cold\",\"Hot\",\"Avg\",\"NotCold\"))\n",$dat,$dat,$dat,$dat,$dat;
    printf R "summary(%shot\$MEAN)\n",$dat;
    printf R "summary(%savg\$MEAN)\n",$dat;
    printf R "summary(%scold\$MEAN)\n",$dat;
    printf R "summary(%snotcold\$MEAN)\n",$dat;
    printf R "ks.test(%scold\$MEAN,%shot\$MEAN)\n",$dat,$dat;
    printf R "ks.test(%shot\$MEAN,%savg\$MEAN)\n",$dat,$dat;
    printf R "ks.test(%scold\$MEAN,%savg\$MEAN)\n",$dat,$dat;
    printf R "ks.test(%scold\$MEAN,%snotcold\$MEAN)\n",$dat,$dat;
}

sub process_lumped {
    my ($obj,$chrom,$left,$right) = @_;
    my $flag = 'total';

    my $bins = $obj->fetch_bins($chrom);
    my @d;
    for my $bin (@$bins) {
	if( $bin >= $left && $bin <= $right ) {
	    push @d, join("\t", $chrom,$bin,$obj->$flag($chrom,$bin));
	} 
    }
    return \@d;
}

sub process_lumped_value {
    my ($obj,$chrom,$left,$right) = @_;
    my $flag = 'average';

    my $bins = $obj->fetch_bins($chrom);
    my @d;
    for my $bin (@$bins) {
	if( $bin >= $left && $bin <= $right ) {
	    my $avg = $obj->$flag($chrom,$bin);
	    next if $avg > 4;
	    push @d, join("\t", $chrom,$bin,$avg);
	} 
    }
    return \@d;
}

package Windows;

use List::Util qw(sum max);
# constants for sliding windows
use constant WINDOW        => 50_000;
use constant STEP          => 50_000;

sub new {
  my ($self,$label) = @_;
  my $this = bless {},$self;
  $this->{label} = $label;
  $this->{fh} = undef;
  return $this;
}


sub parse {
    my ($self,$file,$group_by,$bin_by,$save_by, $filter) = @_;
    my $cols = fetch_columns($file);
    for my $col ( $group_by, $bin_by, $save_by) {
	if( defined $col && ! exists $cols->{$bin_by}) {
	    die("cannot find column $bin_by in $file\n");
	}
    }
    warn( "parsing: $file ...\n");
    my $positions = {};
    open($self->{fh} => $file) or die "$! $file\n";;    
    my $fh = $self->{fh};
    while (<$fh>) {
	chomp;
	# Skip comments
	next if (/^\#/);
	# Fetch the position of the bin_by and group_by
	# columns in the fields array
	my @fields    = split("\t",$_);
	my $bin_val   = $fields[$cols->{$bin_by}];
	my $group_val = $fields[$cols->{$group_by}];

	# Is the value out of range?
	if ($bin_val > $CHROMS{$group_val}[1]) {	
	    print STDERR "Positional value out of range for chromosome $group_val...$bin_val\t",
	    $CHROMS{$group_val}[1],"\n";
	    next;
	}
	# Save both the physical position to map and the value...
	# (these may or may not be the same thing!)
	# This is normally used for things like KaKs values, 
	# where I am plotting values (and not just sums of occurences) 
	# against the physical position
	my $value = 0;
	if( defined $save_by ) {
	    $value  = eval { $fields[$cols->{$save_by}] };
	    if( ! defined $filter || &$filter($value))  {
		push (@{$self->{nonsliding}->{$group_val}},[$bin_val,$value]);
	    } else {
		next;
	    }
	}  else {
	    $value = 1;
	    # Okay, I didn't find a save_by value. Just plotting by the bin_value
	}
	$value   ||= $bin_val;
	push (@{$positions->{$group_val}},[$bin_val,$value]);
    }
    $self->sliding_windows($positions);
    return;
}

# Which windows does this fall into?
sub sliding_windows {
    my ($self,$positions) = @_;

    print STDERR "   binning...\n";
    for my $group_value (keys %$positions) {
	# Get the maximal limit (ie the highest scoring feature)
	my @positions = sort { $a->[0] <=> $b->[0] } @{$positions->{$group_value}};
	for my $temp (@positions) {
	    my ($fstart,$value) = @$temp;
	    $self->stuff($fstart,$value,$positions[-1]->[0],$group_value);
	}
    }
    # calculate the average and total values in each bin
    $self->calc_averages();
}


# This is a new attempt at a vastly more efficient 
# calculated sliding window algorithm
sub stuff {
    my ($self,$fstart,$value,$max,$key) = @_;

    # Calculate the center bin position based on the STEP size,
    # not the WINDOW size...
    my $center_bin_index = int ($fstart / STEP);

    # How many steps are there per window?
    my $steps = WINDOW / STEP;

    # One approach: the feature should fall into equal bins on both sides
    # This centers each window on the bin point - maybe not quite accurate...
    # my $start = $center_bin_index - ($steps/2);
    # my $stop  = $center_bin_index + ($steps/2);

    # Second approach: the center_bin_index is really the LAST bin
    # that should contain the feature (that is, it's the upper limit
    # for bins containing the feature).
    my $start = $center_bin_index - $steps; # 0-based indexing
    my $stop  = $center_bin_index + 1;

    # Is $start less than 0?
    $start = ($start < 0) ? 0 : $start;

    # Non-overlapping bins...
    if ($steps == 1) {
	$start = $center_bin_index;
	$stop  = $center_bin_index;
    }
    for (my $i=$start;$i<=$stop;$i+=1) {
	my $bin = $i * STEP;
	push (@{$self->{groups}->{$key}->{$bin}->{values}},$value);
#	print STDERR "\t",$i,"\t",$bin,"\t",$value,,"\t",$fstart,"\n";
    }
    return;
}

# Calculate an average for each bin or a total value.
sub calc_averages {
    my $self = shift;
    warn("   calculating average...\n");
    my ($max_average,$max_total,$max_value_all) = (0,0,0);
    
    # maybe should also calculate 1SD to help in setting an upper limit cutoff?
    for my $group_by ($self->fetch_groups()) {	
	warn("group is empty") unless defined $group_by;
	my $bins = $self->fetch_bins($group_by);
	my $max_value = 0;
	for my $bin (@$bins) {
	    my $all = $self->fetch_values($group_by,$bin);

	    my $sum = &sum (@$all);
	    my $avg = $sum / scalar @$all;
	    $self->{groups}->{$group_by}->{$bin}->{average} = $avg;
	    $self->{groups}->{$group_by}->{$bin}->{total} = scalar @$all;
	    
	    $max_value = max(@$all, $max_value);
	    $max_total   = max( scalar @$all, $max_total);
	    $max_average = max($avg,$max_average);
	}
	$self->{'max_y_value_'.$group_by}   = $max_value;
	$max_value_all = max($max_value, $max_value_all);
    }
    $self->{'max_y_total'} = $max_total || 1;
    $self->{'max_y_value'} = $max_value_all || 1;
    $self->{'max_y_average'} = $max_average || 1;
}

sub fetch_columns {
  my $file = shift;
  open(IN,$file)|| die "$! $file\n";
  my %cols;
  while (<IN>) {
    chomp;
    my $line = $_;
    $line =~ s/\#//g;
    my @cols = split("\t",$line);
    my $pos = 0;
    for (@cols) {
      $cols{$_} = $pos;
      $pos++;
    }
    last;
  }
  return \%cols;
}


# Normalization
sub normalize {
    my ($numerator,$denominator) = @_;

    # Iterate through all the bins in the numerator
    # looking up the corresponding values in the denominator.

    my $max;
    print STDERR "   normalizing...\n";
    for my $group ($numerator->fetch_groups()) {
	my $bins = $numerator->fetch_bins($group);
	for my $bin (@$bins) {
	    my $total = $numerator->total($group,$bin);
	    my $denom_total = $denominator->total($group,$bin);
	    my $normalized = eval { $total / $denom_total };
	    $normalized ||= '0';
	    $max ||= $normalized;
	    $max = max($normalized,$max);
	    $numerator->{groups}->{$group}->{$bin}->{normalized} = $normalized;
	}
    }
    $numerator->{max_y_normalized} = $max;
}

# Data access methods
sub fetch_groups {  return keys %{shift->{groups}}; }

sub fetch_bins {
  my ($self,$group,$min,$max) = @_;
  my @bins = keys %{$self->{groups}->{$group}};
  my @sorted = sort { $a <=> $b } @bins;
  return \@sorted;
}
sub fetch_values {
  my ($self,$group,$bin) = @_;
  my @vals = @{$self->{groups}->{$group}->{$bin}->{values}};
  return \@vals;
}

sub total   {  
  my ($self,$group,$bin) = @_;
  return $self->{groups}->{$group}->{$bin}->{total};
}

sub average {  
  my ($self,$group,$bin) = @_;
  return $self->{groups}->{$group}->{$bin}->{average};
}

sub normalized {  
  my ($self,$group,$bin) = @_;
  return $self->{groups}->{$group}->{$bin}->{normalized};
}



sub print_info {
  my ($self,$tag,$field) = @_;
  $field ||= 'total';
  my $file = $self->{dumped_file};
  open OUT,">dumped_values/$file.out";
  for my $group ($self->fetch_groups()) {

    # Print out some header information
    print OUT "#chromosome=$group\n";
    print OUT "#field_content=$field\n";
    print OUT "#max_y_average=" . $self->{max_y_average} . "\n";
    print OUT "#max_y_total=" . $self->{max_y_total} . "\n";
    print OUT "#max_y_normalized=" . $self->{max_y_normalized} . "\n";
    my $bins = $self->fetch_bins($group);
    for my $bin (@$bins) {
      my $normalized = $self->normalized($group,$bin);
      my $total = $self->$field($group,$bin);
      print OUT $group,"\t",$bin,"\t",$total,"\n";
    }
  }
  close OUT;
}


sub calc_y_scale {
  my ($self,$tag,$height) = @_;
  my $max = $self->{'max_y_' . $tag};
  unless( defined $max ) { warn("no max for ".'max_y_' . $tag."\n") }
  return 1 unless $max;
  return $height / $max;
}

1;
