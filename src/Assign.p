package ::Assign;
our $VERSION = 1.0;
use 5.008;
use strict;
use warnings;
no warnings q(uninitialized);
use Carp;
use YAML::Tiny;
use IO::All;
use Storable;
#use Devel::Cycle;

require Exporter;

our @ISA = qw(Exporter);
our %EXPORT_TAGS = ( 'all' => [ qw(
		
		serialize
		assign
		assign_vars
		store_vars
		yaml_out
		yaml_in
		create_dir
		join_path
		wav_off
		strip_all
		strip_blank_lines
		strip_comments
		remove_spaces
		read_file
		expand_tilde
		resolve_path
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = ();


package ::;
our ($debug, $debug2, $debug3);
package ::Assign;

use Carp;

sub assign {
	
	$debug2 and print "&assign\n";
	
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

	my %sigil;
	map{ 
		my ($s, $identifier) = /(.)([\w:]+)/;
		$sigil{$identifier} = $s;
	} @vars;
	#print yaml_out(\%sigil); exit;
	#print join " ", "Variables:\n", @vars, $/ ;
	croak "expected hash" if ref $ref !~ /HASH/;
	my @keys =  keys %{ $ref };
	$debug and print join " ","found keys: ", keys %{ $ref },"\n---\n";
	map{  
		my $eval;
		my $key = $_;
		chomp $key;
		my $full_class_path = 
			$sigil{$key} . ($key =~/:\:/ ? '': $class) . $key;

			# use the supplied class unless the variable name
			# contains \:\:
			
# 		$debug and print <<DEBUG;
# key:             $key
# full_class_path: $full_class_path
# sigil{key}:      $sigil{$key}
# DEBUG
		if ( ! $sigil{$key} ){
			$debug and carp 
			"didn't find a match for $key in ", join " ", @vars, $/;
		} else {
			my ($sigil, $identifier) = ($sigil{$key}, $key);
			$eval .= $full_class_path;
			$eval .= q( = );

			my $val = $ref->{$identifier};

			if ($sigil eq '$') { # scalar assignment

				# extract value

				if ($val) { #  if we have something,

					# dereference it if needed
					
					ref $val eq q(SCALAR) and $val = $$val; 
															
					# quoting for non-numerical
					
					$val = qq("$val") unless  $val =~ /^[\d\.,+\-e]+$/ 
			
				} else { $val = q(undef) }; # or set as undefined

				$eval .=  $val;  # append to assignment

			} else { # array, hash assignment
					

				$eval .= qq($sigil\{);
				$eval .= q($ref->{ );
				$eval .= qq("$identifier");
				$eval .= q( } );
				$eval .= q( } );
			}
			$debug and print $eval, $/; 
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
	# assigns vars in @var_list to values from $source
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
				my $code = io($source)->all ;
				$ref = eval $code or carp "$source: eval failed: $@\n";
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
			class => $class);
	1;	

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
			my $result1 = store \%state, $file; # old method
		} elsif ($h{format} eq 'perl'){
			$file .= '.pl' unless $file =~ /\.pl$/;
			#my $pl = dump \%state;
			#$pl > io($file);
		} elsif ($h{format} eq 'yaml'){
			$file .= '.yml' unless $file =~ /\.yml$/;
			#find_cycle(\%state);
			my $yaml = yaml_out(\%state);
			$yaml > io($file);
			$debug and print $yaml;
		}
	} else { yaml_out(\%state) }

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
		: io($input)->all;	# file name
	if ($yaml =~ /\t/){
		croak "YAML file: $input contains illegal TAB character.";
	}
	$yaml =~ s/^\n+//  ; # remove leading newline at start of file
	$yaml =~ s/\n*$/\n/; # make sure file ends with newline
	my $y = YAML::Tiny->read_string($yaml);
	print "YAML::Tiny read error: $YAML::Tiny::errstr\n" if $YAML::Tiny::errstr;
	$y->[0];
}

## support functions

sub create_dir {
	my @dirs = @_;
	map{ my $dir = $_;
	$debug and print "creating [ $dir ]\n";
		-e $dir 
#and (carp "create_dir: '$dir' already exists, skipping...\n") 
			or system qq( mkdir -p $dir)
		} @dirs;
}

sub join_path {
	
	my @parts = @_;
	my $path = join '/', @parts;
	$path =~ s(/{2,})(/)g;
	#$debug and print "path: $path\n";
	$path;
}

sub wav_off {
	my $wav = shift;
	$wav =~ s/\.wav\s*$//i;
	$wav;
}

sub strip_all{ strip_trailing_spaces(strip_blank_lines( strip_comments(@_))) }

sub strip_trailing_spaces {
	map {s/\s+$//} @_;
	@_;
}
sub strip_blank_lines {
	map{ s/\n(\s*\n)+/\n/sg } @_;
	map{ s/^\n+//s } @_;
	@_;
	 
}

sub strip_comments { #  
	map{ s/#.*$//mg; } @_;
	map{ s/\s+$//mg; } @_;

	@_
} 

sub remove_spaces {                                                             
        my $entry = shift;                                                      
        # remove leading and trailing spaces                                    
                                                                                
        $entry =~ s/^\s*//;                                                     
        $entry =~ s/\s*$//;                                                     
                                                                                
        # convert other spaces to underscores                                   
                                                                                
        $entry =~ s/\s+/_/g;                                                    
        $entry;                                                                 
}                                                                               
sub resolve_path {
	my $path = shift;
	$path = expand_tilde($path);
	$path = File::Spec::Link->resolve_all($path);
}
sub expand_tilde { 
	my $path = shift; 

	# ~bob -> /home/bob
	$path =~ s(
		^ 		# beginning of line
		~ 		# tilde
		(\w+) 	# username
	)
	(/home/$1)x;

	# ~/something -> /home/bob/something
	$path =~ s( 
		^		# beginning of line
		~		# tilde
		/		# slash
	)
	($ENV{HOME}/)x;
	$path
}
sub read_file {
	my $path = shift;
	$path = resolve_path($path);
	io($path)->all;
}

1;

