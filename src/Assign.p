package ::Assign;
use Modern::Perl;
our $VERSION = 1.0;
use 5.008;
use feature 'state';
use strict;
use warnings;
no warnings q(uninitialized);
use Carp qw(carp confess croak cluck);
use YAML::Tiny;
use File::Slurp;
use File::HomeDir;
use ::Log qw(logsub logpkg);
use Storable qw(nstore retrieve);
use JSON::XS;
use Data::Dumper::Concise;

require Exporter;

our @ISA = qw(Exporter);
our %EXPORT_TAGS = ( 'all' => [ qw(
		
		serialize
		assign
		assign_singletons
		store_vars
		json_out
		yaml_in
		json_in
		json_out
		quote_yaml_scalars
		var_map
        config_vars
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = ();

our $to_json = JSON::XS->new->utf8->allow_blessed->pretty->canonical(1) ;
use Carp;

{my $var_map = { qw(

[% qx(./var_map_gen) %]

) };
sub var_map {  $var_map } # to allow outside access while keeping
                          # working lexical
sub config_vars { grep {$_ ne '**' } keys %$var_map }

sub assign {
  # Usage: 
  # assign ( 
  # data 	=> $ref,
  # vars 	=> \@vars,
  # var_map => 1,
  #	class => $class
  #	);

	logsub("&assign");
	
	my %h = @_; # parameters appear in %h
	my $class;
	logpkg('logcarp',"didn't expect scalar here") if ref $h{data} eq 'SCALAR';
	logpkg('logcarp',"didn't expect code here") if ref $h{data} eq 'CODE';
	# print "data: $h{data}, ", ref $h{data}, $/;

	if ( ref $h{data} !~ /^(HASH|ARRAY|CODE|GLOB|HANDLE|FORMAT)$/){
		# we guess object
		$class = ref $h{data}; 
		logpkg('debug',"I found an object of class $class");
	} 
	$class = $h{class};
 	$class .= "::" unless $class =~ /::$/;  # SKIP_PREPROC
	my @vars = @{ $h{vars} };
	my $ref = $h{data};
	my $type = ref $ref;
	logpkg('debug',<<ASSIGN);
	data type: $type
	data: $ref
	class: $class
	vars: @vars
ASSIGN
	#logpkg('debug',sub{json_out($ref)});

	# index what sigil an identifier should get

	# we need to create search-and-replace strings
	# sigil-less old_identifier
	my %sigil;
	my %ident;
	map { 
		my $oldvar = my $var = $_;
		my ($dummy, $old_identifier) = /^([\$\%\@])([\-\>\w:\[\]{}]+)$/;
		$var = $var_map->{$var} if $h{var_map} and $var_map->{$var};

		logpkg('debug',"oldvar: $oldvar, newvar: $var") unless $oldvar eq $var;
		my ($sigil, $identifier) = $var =~ /([\$\%\@])(\S+)/;
			$sigil{$old_identifier} = $sigil;
			$ident{$old_identifier} = $identifier;
	} @vars;

	logpkg('debug',sub{"SIGIL\n". json_out(\%sigil)});
	#%ident = map{ @$_ } grep{ $_->[0] ne $_->[1] } map{ [$_, $ident{$_}]  }  keys %ident; 
	my %ident2 = %ident;
	while ( my ($k,$v) = each %ident2)
	{
		delete $ident2{$k} if $k eq $v
	}
	logpkg('debug',sub{"IDENT\n". json_out(\%ident2)});
	
	#print join " ", "Variables:\n", @vars, $/ ;
	croak "expected hash" if ref $ref !~ /HASH/;
	my @keys =  keys %{ $ref }; # identifiers, *no* sigils
	logpkg('debug',sub{ join " ","found keys: ", keys %{ $ref },"\n---\n"});
	map{  
		my $eval;
		my $key = $_;
		chomp $key;
		my $sigil = $sigil{$key};
		my $full_class_path = 
 			$sigil . ($key =~/:\:/ ? '': $class) .  $ident{$key};

			# use the supplied class unless the variable name
			# contains \:\:
			
		logpkg('debug',<<DEBUG);
key:             $key
sigil:      $sigil
full_class_path: $full_class_path
DEBUG
		if ( ! $sigil ){
			logpkg('debug',sub{
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
			logpkg('debug',"eval string: $eval"); 
			eval($eval);
			logpkg('logcarp',"failed to eval $eval: $@") if $@;
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
	logsub('&assign_singletons');
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
				logpkg('debug',"eval: $cmd");
				eval $cmd;
				logpkg('logcarp',"error during eval: $@") if $@;
			} keys %{ $data->{$ident} }
		}
	} @singleton_idents;  # list of "singleton" variables
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
	  yaml	   => sub { my($ref, $path) = @_; write_file($path, json_out($ref))},
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
	logsub("&serialize");

	my %h = @_;
	my @vars = @{ $h{vars} };
	my $class = $h{class};
	my $file  = $h{file};
	my $format = $h{format} // 'perl'; # default to Data::Dumper::Concise

 	$class //= "::";
	$class =~ /::$/ or $class .= '::'; # SKIP_PREPROC
	logpkg('debug',"file: $file, class: $class\nvariables...@vars");

	# first we marshall data into %state

	my %state;

	map{ 
		my ($sigil, $identifier, $key) = /$parse_re/;

	logpkg('debug',"found sigil: $sigil, ident: $identifier, key: $key");

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

		logpkg('debug',"value: $value");

			
		 my $eval_string =  q($state{')
							. $identifier
							. q('})
							. ($key ? qq(->{$key}) : q() )
							. q( = )
							. $value;

		if ($identifier){
			logpkg('debug',"attempting to eval $eval_string");
			eval($eval_string);
			logpkg('error', "eval failed ($@)") if $@;
		}
	} @vars;
	logpkg('debug',sub{join $/,'\%state', Dumper \%state});

	# YAML out for screen dumps
	return( json_out(\%state) ) unless $h{file};

	# now we serialize %state
	
	my $path = $h{file};

	serialize_and_write(\%state, $path, $format);
}
}

sub json_out {
	logsub("&json_out");
	my $data_ref = shift;
	my $type = ref $data_ref;
	croak "attempting to code wrong data type: $type"
		if $type !~ /HASH|ARRAY/;
	$to_json->encode($data_ref);
}

sub json_in {
	logsub("&json_in");
	my $json = shift;
	my $data_ref = decode_json($json);
	$data_ref
}

sub yaml_in {
	
	# logsub("&yaml_in");
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

