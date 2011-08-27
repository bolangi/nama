#!/usr/bin/perl
use Modern::Perl;
use File::Slurp;
my %var_map = 
			
			map  { split " ", $_ }  # store as key/value pairs
			grep { my @var = split " ", $_; @var == 2 } # take only substitutions
			grep{ ! /^\s*$/ }  	# skip blank lines
			split "\n", var_map();

my @singletons = singletons();
use Data::Dumper;
#print Dumper \%var_map;
#print join $/, singletons();

my @target_files = glob("*.p *pl *.t");
my %files;
map{ say $_} @target_files;
map{ $files{$_} = read_file($_)} @target_files;

my @old_vars = keys %var_map;
map{ my $file = $_;

	map {   my $old_var_name = $_;
			my $ov_regex = qr/my [^;\n]*?$old_var_name\b/m;
			say "my declaration with old var name $old_var_name found in file $file" 
				if $files{$file} =~ /$ov_regex/m
	} @old_vars;
	map {
			my $singleton_name = $_;
			my $s_regex = qr/my [^;\n]*?$singleton_name\b/m;
			say "my declaration with singleton name $singleton_name found in file $file" 
				if $files{$file} =~ /$s_regex/m
	} @singletons
} @target_files;

sub singletons {
	my $singletons = read_file("./singletons.pl");
	map{ s/,//; $_ } split " ", $singletons;
}



sub var_map { 

	my $var_map = read_file("./var_map");
	$var_map
}

__END__


@effects -> $effects

Collision detection

I don't want to replace any lexical variables that
happened to be named the same as globals!

do I have any 'my' variables named @effects? # would be wrongly substituted
do I have any 'my' variables named $config  # would mask global

assume one-line 'my' statements 

we have a problem if this is true:

$regex = qr/^\s*my .*?$old_var_name\b/m;
$regex = qr/^\s*my .*?$singleton_name\b/m;

Do I have any variables named $effects? 

Exclude $effects_gui (followed by underscore)
Exclude $effects[$i] (normally subscripted array)

$regex = qr/\$effects(?![_\[])/;

