package ::Assign;
use Modern::Perl;
our $VERSION = 1.0;
use 5.008;
use feature 'state';
use strict;
use warnings;
no warnings q(uninitialized);
use Carp;
use YAML::Tiny;
use File::Slurp;
use File::HomeDir;
use Storable qw(nstore retrieve);
use JSON::XS;
use Data::Dumper::Concise;
#use Devel::Cycle;

require Exporter;

our @ISA = qw(Exporter);
our %EXPORT_TAGS = ( 'all' => [ qw(
		
		serialize
		assign
		assign_vars
		assign_var
		assign_var_map
		store_vars
		yaml_out
		yaml_in
		json_in
		json_out
		quote_yaml_scalars
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = ();

use ::Globals qw($debug $debug2);

our $to_json = JSON::XS->new->utf8->pretty(1) ;
use Carp;

sub assign {
	
	$debug2 and print "&assign\n";
	local $debug = 1;
	
	my %h = @_; # parameters appear in %h
	my $class;
	carp "didn't expect scalar here" if ref $h{data} eq 'SCALAR';
	carp "didn't expect code here" if ref $h{data} eq 'CODE';
	# print "data: $h{data}, ", ref $h{data}, $/;

	if ( ref $h{data} !~ /^(HASH|ARRAY|CODE|GLOB|HANDLE|FORMAT)$/){
		# we guess object
		$class = ref $h{data}; 
		$debug and print "I found an object of class $class...\n";
	} 
	$class = $h{class};
 	$class .= "::" unless $class =~ /::$/;  # SKIP_PREPROC
	my @vars = @{ $h{vars} };
	my $ref = $h{data};
	my $type = ref $ref;
	$debug and print <<ASSIGN;
	data type: $type
	data: $ref
	class: $class
	vars: @vars
ASSIGN
	#$debug and print yaml_out($ref);

	# index what sigil an identifier should get
	

	# autosave_interval  | $autosave_interval | $config->{autosave_interval}

	# $autosave_interval = ....
    # $config->autosave_interval = ....
	
	# we need to create search-and-replace strings
	# sigil-less old_identifier
	my %sigil;
	my %ident;
	map { 
		my $oldvar = my $var = $_;
		my ($dummy, $old_identifier) = /^([\$\%\@])([\-\w:\[\]{}]+)$/;
		$var = $h{var_map}->{$var} if $h{var_map} and $h{var_map}->{$var};
		say "oldvar: $oldvar, newvar: $var";
		my ($sigil, $identifier) = $var =~ /([\$\%\@])(\S+)/;
			$sigil{$old_identifier} = $sigil;
			$ident{$old_identifier} = $identifier;
	} @vars;

	print "SIGIL\n", yaml_out(\%sigil);
	print "IDENT\n", yaml_out(\%ident);

	
	#print join " ", "Variables:\n", @vars, $/ ;
	croak "expected hash" if ref $ref !~ /HASH/;
	my @keys =  keys %{ $ref }; # identifiers, *no* sigils
	$debug and print join " ","found keys: ", keys %{ $ref },"\n---\n";
	map{  
		my $eval;
		my $key = $_;
		chomp $key;
		my $sigil = $sigil{$key};
		my $full_class_path = 
 			$sigil . ($key =~/:\:/ ? '': $class) .  $ident{$key};

			# use the supplied class unless the variable name
			# contains \:\:
			
		$debug and print <<DEBUG;
key:             $key
sigil:      $sigil
full_class_path: $full_class_path
DEBUG
		if ( ! $sigil ){
			$debug and carp 
			"didn't find a match for $key in ", join " ", @vars, $/;
		} 
		else 
		{

			$eval .= $full_class_path;
			$eval .= q( = );

			my $val = $ref->{$key};

			if (! ref $val or ref $val eq 'SCALAR')  # scalar assignment
			{

				# extract value

				if ($val) { #  if we have something,

					# dereference it if needed
					
					ref $val eq q(SCALAR) and $val = $$val; 
															
					# quoting for non-numerical
					
					$val = qq("$val") unless  $val =~ /^[\d\.,+\-e]+$/ 
			
				} else { $val = q(undef) }; # or set as undefined

				$eval .=  $val;  # append to assignment

			} 
			elsif ( ref $val eq 'ARRAY' or ref $val eq 'HASH')
			{ 
				if ($sigil eq '$')	# assign reference
				{				
					$eval .= q($val) ;
				}
				else				# dereference and assign
				{
					$eval .= qq($sigil) ;
					$eval .= q({$val}) ;
				}
			}
			else { die "unsupported assignment: ".ref $val }
			$debug and print "eval string: ",$eval, $/; 
			eval($eval);
			$debug and $@ and carp "failed to eval $eval: $@\n";
		}  # end if sigil{key}
	} @keys;
	1;
}

sub assign_vars {
	$debug2 and print "&assign_vars\n";
	
	my %h = @_;
	my $source = $h{source};
	my @vars = @{ $h{vars} };
	my $class = $h{class};
	my $format = $h{format};
	# assigns vars in @vars to values from $source
	# $source can be a :
	#      - filename or
	#      - string containing YAML data
	#      - reference to a hash array containing assignments
	#
	# returns a $ref containing the retrieved data structure
	$debug and print "source: ", (ref $source) || $source, "\n";
	$debug and print "variable list: @vars\n";
	my $ref;

### figure out what to do with input

	if ($source !~ /\n/ and -f $source){
		if ( $source =~ /\.yml$/i or $format eq 'yaml'){
				$debug and print "found a yaml file: $source\n";
				$ref = yaml_in($source);
		} elsif ( $source =~ /\.pl$/i or $format eq 'perl'){
				$debug and print "found a perl file: $source\n";
				my $code = read_file($source);
				$ref = eval $code or carp "$source: eval failed: $@\n";
		} elsif ( $source =~ /\.json$/i ){
				$debug and print "found a JSON file: $source\n";
				my $json = read_file($source);
				$ref = decode_json($json);
		} else {
				$debug and print "assuming Storable file: $source\n";
				$ref = retrieve($source) # Storable
		}

	} elsif ( $source =~ /\n/ ){
		$debug and print "found yaml text\n";
		$ref = yaml_in($source);

	# pass a hash_ref to the assigner
	} elsif ( ref $source ) {
		$debug and print "found a reference\n";
		$ref = $source;
	} else { carp "$source: missing data source\n"; }

	assign(data => $ref, 
			vars => \@vars, 
			var_map => $h{var_map},
			class => $class);
	1;	

}

sub assign_var {
	my ($source, @vars) = @_;
	assign_vars(
				source => $source,
				vars   => \@vars,
		#		format => 'yaml', # breaks
				class => '::');
}

{my %var_map = qw(

[% qx(./var_map_gen) %]

);
sub assign_var_map {
	my ($source, @vars) = @_;
	say "assign_var_map, vars ", join " ", @vars;
	assign_vars(
				source => $source,
				vars   => \@vars,
				var_map => \%var_map,
		#		format => 'yaml', # breaks
				class => '::');
}
}
sub serialize {
	$debug2 and print "&serialize\n";
	my %h = @_;
	my @vars = @{ $h{vars} };
	my $class = $h{class};
	my $file  = $h{file};
	my $format = $h{format};
 	$class .= "::" unless $class =~ /::$/; # SKIP_PREPROC
	$debug and print "file: $file, class: $class\nvariables...@vars\n";
	my %state;
	map{ my ($sigil, $identifier) = /(.)([\w:]+)/; 



# for  YAML::Reader/Writer
#
#  all scalars must contain values, not references

		#my $value =  q(\\) 
		my $value =  ($sigil ne q($) ? q(\\) : q() ) 

							. $sigil
							. ($identifier =~ /:/ ? '' : $class)
							. $identifier;

# more YAML adjustments 
#
# restore will break if a null field is not converted to '~'
			
		 my $eval_string =  q($state{')
							. $identifier
							. q('})
							. q( = )
							. $value;
	$debug and print "attempting to eval $eval_string\n";
	eval($eval_string) or $debug  and print 
		"eval returned zero or failed ($@\n)";
	} @vars;
	# my $result1 = store \%state, $file; # old method
	if ( $h{file} ) {

		if ($h{format} eq 'storable') {
			my $result1 = nstore \%state, $file; # old method
		} elsif ($h{format} eq 'perl'){
			$file .= '.pl' unless $file =~ /\.pl$/;
			#my $pl = dump \%state;
			#write_file($file, $pl);
		} elsif ($h{format} eq 'yaml'){
			$file .= '.yml' unless $file =~ /\.yml$/;
			#find_cycle(\%state);
			my $yaml = yaml_out(\%state);
			write_file($file, $yaml);
			$debug and print $yaml;
		} elsif ($h{format} eq 'json'){
			$file .= '.json' unless $file =~ /\.json$/;
			#find_cycle(\%state);
          	my $json = $to_json->encode(\%state) . "\n";
			write_file($file, $json);
			$debug and print $json;
		} elsif ($h{format} eq 'dumper'){
			$file .= '.pl' unless $file =~ /\.pl$/;
			my $perl_source = Dumper(\%state);
			write_file($file, $perl_source);
			$debug and print $perl_source;
		}
	} else { yaml_out(\%state) }

}

sub json_out {
	$debug2 and carp "&json_out";
	my $data_ref = shift;
	my $type = ref $data_ref;
	croak "attempting to code wrong data type: $type"
		if $type !~ /HASH|ARRAY/;
	$to_json->encode($data_ref);
}

sub json_in {
	$debug2 and carp "&json_in";
	my $json = shift;
	my $data_ref = decode_json($json);
	$data_ref
}

sub yaml_out {
	
	$debug2 and carp "&yaml_out";
	my ($data_ref) = shift; 
	my $type = ref $data_ref;
	$debug and print "data ref type: $type\n "; 
	carp "can't yaml-out a Scalar!!\n" if ref $data_ref eq 'SCALAR';
	croak "attempting to code wrong data type: $type"
		if $type !~ /HASH|ARRAY/;
	my $output;
	#$debug and print join $/, keys %$data_ref, $/;
	$debug and print "about to write YAML as string\n";
	my $y = YAML::Tiny->new;
	$y->[0] = $data_ref;
	my $yaml = $y->write_string() . "...\n";
}
sub yaml_in {
	
	# $debug2 and print "&yaml_in\n";
	my $input = shift;
	my $yaml = $input =~ /\n/ # check whether file or text
		? $input 			# yaml text
		: read_file($input);	# file name
	if ($yaml =~ /\t/){
		croak "YAML file: $input contains illegal TAB character.";
	}
	$yaml =~ s/^\n+//  ; # remove leading newline at start of file
	$yaml =~ s/\n*$/\n/; # make sure file ends with newline
	my $y = YAML::Tiny->read_string($yaml);
	print "YAML::Tiny read error: $YAML::Tiny::errstr\n" if $YAML::Tiny::errstr;
	$y->[0];
}

sub quote_yaml_scalars {
	my $yaml = shift;
	my @modified;
	map
		{  
		chomp;
		if( /^(?<beg>(\s*\w+: )|(\s+- ))(?<end>.+)$/ ){
			my($beg,$end) = ($+{beg}, $+{end});
			# quote if contains colon and not quoted
			if ($end =~ /:\s/ and $end !~ /^('|")/ ){ 
				$end =~ s(')(\\')g; # escape existing single quotes
				$end = qq('$end') } # single-quote string
			push @modified, "$beg$end\n";
		}
		else { push @modified, "$_\n" }
	} split "\n", $yaml;
	join "", @modified;
}
	

1;

