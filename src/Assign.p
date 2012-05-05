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
use ::Log qw(logit);
use Storable qw(nstore retrieve);
use JSON::XS;
use Data::Dumper::Concise;

require Exporter;

our @ISA = qw(Exporter);
our %EXPORT_TAGS = ( 'all' => [ qw(
		
		serialize
		assign
		assign_singletons
		assign_pronouns
		assign_serialization_arrays
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

our $to_json = JSON::XS->new->utf8->pretty->canonical(1) ;
use Carp;

our $logger = Log::Log4perl->get_logger();

{my $var_map = { qw(

[% qx(./var_map_gen) %]

) };
sub var_map {  $var_map } # to allow outside access while keeping
                          # working lexical


sub assign {
  # Usage: 
  # assign ( 
  # data 	=> $ref,
  # vars 	=> \@vars,
  # var_map => 1,
  #	class => $class
  #	);

	logit('SUB','debug',"&assign");
	
	my %h = @_; # parameters appear in %h
	my $class;
	$logger->logcarp("didn't expect scalar here") if ref $h{data} eq 'SCALAR';
	$logger->logcarp("didn't expect code here") if ref $h{data} eq 'CODE';
	# print "data: $h{data}, ", ref $h{data}, $/;

	if ( ref $h{data} !~ /^(HASH|ARRAY|CODE|GLOB|HANDLE|FORMAT)$/){
		# we guess object
		$class = ref $h{data}; 
		$logger->debug("I found an object of class $class");
	} 
	$class = $h{class};
 	$class .= "::" unless $class =~ /::$/;  # SKIP_PREPROC
	my @vars = @{ $h{vars} };
	my $ref = $h{data};
	my $type = ref $ref;
	$logger->debug(<<ASSIGN);
	data type: $type
	data: $ref
	class: $class
	vars: @vars
ASSIGN
	#$debug and print yaml_out($ref);

	# index what sigil an identifier should get

	# we need to create search-and-replace strings
	# sigil-less old_identifier
	my %sigil;
	my %ident;
	map { 
		my $oldvar = my $var = $_;
		my ($dummy, $old_identifier) = /^([\$\%\@])([\-\>\w:\[\]{}]+)$/;
		$var = $var_map->{$var} if $h{var_map} and $var_map->{$var};

		$logger->debug("oldvar: $oldvar, newvar: $var");
		my ($sigil, $identifier) = $var =~ /([\$\%\@])(\S+)/;
			$sigil{$old_identifier} = $sigil;
			$ident{$old_identifier} = $identifier;
	} @vars;

	$logger->debug(sub{"SIGIL\n". yaml_out(\%sigil)});
	$logger->debug(sub{"IDENT\n". yaml_out(\%ident)});
	
	#print join " ", "Variables:\n", @vars, $/ ;
	croak "expected hash" if ref $ref !~ /HASH/;
	my @keys =  keys %{ $ref }; # identifiers, *no* sigils
	$logger->debug(sub{ join " ","found keys: ", keys %{ $ref },"\n---\n"});
	map{  
		my $eval;
		my $key = $_;
		chomp $key;
		my $sigil = $sigil{$key};
		my $full_class_path = 
 			$sigil . ($key =~/:\:/ ? '': $class) .  $ident{$key};

			# use the supplied class unless the variable name
			# contains \:\:
			
		$logger->debug(<<DEBUG);
key:             $key
sigil:      $sigil
full_class_path: $full_class_path
DEBUG
		if ( ! $sigil ){
			$logger->logwarn(sub{
			"didn't find a match for $key in ", join " ", @vars, $/;
			});
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
			$logger->debug("eval string: $eval"); 
			eval($eval);
			$logger->logcarp("failed to eval $eval: $@") if $@;
		}  # end if sigil{key}
	} @keys;
	1;
}
}

# assign_singletons() assigns hash key/value entries
# rather than a top-level hash reference to avoid
# clobbering singleton key/value pairs initialized
# elsewhere.
 
my @singleton_idents = map{ /^.(.+)/; $1 }  # remove leading '$' sigil
qw(
[% qx(cat ./singletons.pl) %]
);
sub assign_singletons {
	my $ref = shift;
	my $data = $ref->{data} or die "expected data got undefined";
	my $class = $ref->{class} // '::';
	$class .= '::'; # SKIP_PREPROC
	map {
		my $ident = $_;
		if( defined $data->{$ident}){
			my $type = ref $data->{$ident};
			$type eq 'HASH' or die "$ident: expect hash, got $type";
			map{ 
				my $key = $_;
				my $cmd = join '',
					'$',
					$class,
					$ident,
					'->{',
					$key,
					'}',
					' = $data->{$ident}->{$key}';
				$logger->debug("eval: $cmd");
				eval $cmd;
				$logger->logcarp("error during eval: $@") if $@;
			} keys %{ $data->{$ident} }
		}
	} @singleton_idents;
}
sub assign_pronouns {
	my $ref = shift;
	my $data = $ref->{data} or die "expected data got undefined";
	my $class = $ref->{class} // '::';
	$class .= '::'; # SKIP_PREPROC
	my @pronouns = qw(this_op this_track_name);
	map { 
		my $ident = @_;
		if( defined $data->{$ident} ){
			my $type = ref $data->{$ident};
			die "$ident: expected scalar, got $type" if $type;
			my $cmd = q($).$class.$ident. q( = $data->{$ident});
			$logger->debug("eval: $cmd");
			eval $cmd;
			$logger->logcarp("error during eval: $@") if $@;
		}
	} @pronouns;
}

{
my @arrays = map{ /^.(.+)/; $1 }  # remove leading '@' sigil
qw(
[% qx(cat ./serialize.pl) %]
);
sub assign_serialization_arrays {
	my $ref = shift;
	my $data = $ref->{data} or die "expected data got undefined";
	my $class = $ref->{class} // '::';
	$class .= '::'; # SKIP_PREPROC
	map {
		my $ident = $_;
		if( defined $data->{$ident} ){
			my $type = ref $data->{$ident};
			$type eq 'ARRAY' or die "$ident: expected ARRAY, got $type";
			my $cmd = q($).$class.$ident. q( = @{$data->{$ident}});
			#my $cmd = q(*).$class.$ident. q( = $data->{$ident});
			$logger->debug("eval: $cmd");
			eval $cmd;
			$logger->logcarp("error during eval: $@") if $@;
		}
	} @arrays;
}
}

our %suffix = 
	(
		storable => "bin",
		perl	 => "pl",
		json	 => "json",
		yaml	 => "yml",
	);
our %dispatch = 
	( storable => sub { my($ref, $path) = @_; nstore($ref, $path) },
	  perl     => sub { my($ref, $path) = @_; write_file($path, Dumper $ref) },
	  yaml	   => sub { my($ref, $path) = @_; write_file($path, yaml_out($ref))},
	  json	   => sub { my($ref, $path) = @_; write_file($path, json_out($ref))},
	);

sub serialize_and_write {
	my ($ref, $path, $format) = @_;
	$path .= ".$suffix{$format}" unless $path =~ /\.$suffix{$format}$/;
	$dispatch{$format}->($ref, $path)
}


{
	my $parse_re =  		# initialize only once
			qr/ ^ 			# beginning anchor
			([\%\@\$]) 		# first character, sigil
			([\w:]+)		# identifier, possibly perl namespace 
			(?:->{(\w+)})?  # optional hash key for new hash-singleton vars
			$ 				# end anchor
			/x;
sub serialize {
	logit('SUB','debug',"&serialize");

	my %h = @_;
	my @vars = @{ $h{vars} };
	my $class = $h{class};
	my $file  = $h{file};
	my $format = $h{format} // 'perl'; # default to Data::Dumper::Concise

 	$class //= "::";
	$class =~ /::$/ or $class .= '::'; # SKIP_PREPROC
	$logger->debug("file: $file, class: $class\nvariables...@vars");

	# first we marshall data into %state

	my %state;

	map{ 
		my ($sigil, $identifier, $key) = /$parse_re/;

	$logger->debug("found sigil: $sigil, ident: $identifier, key: $key");

# note: for  YAML::Reader/Writer  all scalars must contain values, not references
# more YAML adjustments 
# restore will break if a null field is not converted to '~'

		#my $value =  q(\\) 

# directly assign scalar, but take hash/array references
# $state{ident} = $scalar
# $state{ident} = \%hash
# $state{ident} = \@array

# in case $key is provided
# $state{ident}->{$key} = $singleton->{$key};
#
			

		my $value =  ($sigil ne q($) ? q(\\) : q() ) 

							. $sigil
							. ($identifier =~ /:/ ? '' : $class)
							. $identifier
							. ($key ? qq(->{$key}) : q());

		$logger->debug("value: $value");

			
		 my $eval_string =  q($state{')
							. $identifier
							. q('})
							. ($key ? qq(->{$key}) : q() )
							. q( = )
							. $value;

		if ($identifier){
			$logger->debug("attempting to eval $eval_string");
			eval($eval_string) or $debug  and print 
				"eval returned zero or failed ($@\n)";
		}
	} @vars;
	$logger->debug(sub{join $/,'\%state', Dumper \%state});

	# YAML out for screen dumps
	return( yaml_out(\%state) ) unless $h{file};

	# now we serialize %state
	
	my $path = $h{file};

	serialize_and_write(\%state, $path, $format);
}
}

sub json_out {
	logit('SUB','debug',"&json_out");
	my $data_ref = shift;
	my $type = ref $data_ref;
	croak "attempting to code wrong data type: $type"
		if $type !~ /HASH|ARRAY/;
	$to_json->encode($data_ref);
}

sub json_in {
	logit('SUB','debug',"&json_in");
	my $json = shift;
	my $data_ref = decode_json($json);
	$data_ref
}

sub yaml_out {
	
	logit('SUB','debug',"&yaml_out");
	my ($data_ref) = shift; 
	my $type = ref $data_ref;
	$logger->debug("data ref type: $type");
	$logger->logcarp("can't yaml-out a Scalar!!") if ref $data_ref eq 'SCALAR';
	$logger->logcroak("attempting to code wrong data type: $type")
		if $type !~ /HASH|ARRAY/;
	my $output;
	#$debug and print join $/, keys %$data_ref, $/;
	$logger->debug("about to write YAML as string");
	my $y = YAML::Tiny->new;
	$y->[0] = $data_ref;
	my $yaml = $y->write_string() . "...\n";
}
sub yaml_in {
	
	# logit('SUB','debug',"&yaml_in");
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

