package ::Assign;
use 5.008;
use strict;
use warnings;
use Carp;
use IO::All;
use Data::YAML::Reader;
use Data::YAML::Writer;
use Storable;

require Exporter;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use Assign ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
#
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
		yamlify_commands

	
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
	
);

our $VERSION = '0.01';

package ::;
#use vars($debug, $debug2, $debug3);
our ($debug, $debug2, $debug3);
package ::Assign;
my $yw = Data::YAML::Writer->new;
my $yr = Data::YAML::Reader->new;
$debug = 0;
$debug2 = 1;
$debug3 = 0;

use Carp;

sub assign {
	local $debug = 1; # $debug3;
	
	$debug2 and print "&assign\n";
	
	my %h = @_; # parameters appear in %h
	my $class;
	carp "didn't expect scalar here" if ref $h{-data} eq 'SCALAR';
	carp "didn't expect code here" if ref $h{-data} eq 'CODE';
	print "data: $h{-data}, ", ref $h{-data}, $/;

	if ( ref $h{-data} !~ /^(HASH|ARRAY|CODE|GLOB|HANDLE|FORMAT)$/){
		# we guess object
		$class = ref $h{-data}; 
		$debug and print "I found an object of class $class...\n";
	} 
	$class = $h{-class};
	print "class: $h{-class}\n";
 	$class .= "\:\:" unless $class =~ /\:\:$/;; # backslashes protect
	# i can't see any reason why we should append this.
												#from preprocessor
	my @vars = @{ $h{-vars} };
	my $ref = $h{-data};
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
			# contains a class-denoting :\:
			
		$debug and print <<DEBUG;
key:             $key
full_class_path: $full_class_path
sigil{key}:      $sigil{$key}
DEBUG
		$sigil{$key} or carp 
			"didn't find a match for $key in ", join " ", @vars, $/;
		my ($sigil, $identifier) = ($sigil{$key}, $key);
		$eval .= $full_class_path;
		$eval .= q( = );

		my $val;

		if ($sigil eq '$') { # scalar assignment

			# extract value

			if ($ref->{$identifier}) { #  if we have something,

 				# take it
				
				$val = $ref->{$identifier};

				# dereference it if needed
				
				ref $val eq q(SCALAR) and $val = $$val; 
				ref $val eq q(SCALAR) and $val = $$val; 
														
				# quoting for non-numerical
				
				$val = qq("$val") unless  $val =~ /^[\d\.,+\-e]+$/ 
					#or 		ref $val;
		
			} else { $val = q(undef) }; # or set as undefined

			$eval .=  $val;  # append to assignment

		} else { # array, hash assignment

			$eval .= qq($sigil\{);
			$eval .= q($ref->{ );
			$eval .= qq("$identifier");
			$eval .= q( } );
			$eval .= q( } );
		}
		$debug and print $eval, $/, $/;
		eval($eval) or carp "failed to eval $eval: $@\n";
	} @keys;
	1;
}

sub assign_vars {
	$debug2 and print "&assign_vars\n";
	local $debug = $debug3;
	my %h = @_;
	my $source = $h{-source};
	my @vars = @{ $h{-vars} };
	my $class = $h{-class};
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

	$source !~ /.yml$/i and -f $source 
		and $ref = retrieve($source) # Storable
		#and $debug and print ("found Storable file: $source\n")

	## check for a filename

	or -f $source and $source =~ /.yml$/ 
		and $ref = yaml_in($source)
		#and $debug and print "found a yaml file: $source\n"
 	
	## check for a string

	or  $source =~ /^\s*---/s 
		and $ref = $yr->read($source)
		#and $debug and print "found yaml as text\n"

	## pass a hash_ref to the assigner

	or ref $source 
		and $ref = $source;
		#and $debug and print "found a reference\n"


	assign(-data => $ref, -vars => \@vars, -class => $class);
	1;	

}

sub serialize {
	$debug2 and print "&serialize\n";
	local $debug = 1;
	my %h = @_;
	my @vars = @{ $h{-vars} };
	my $class = $h{-class};
	my $file  = $h{-file};
 	$class .= "\:\:" unless $class =~ /\:\:$/;; # backslashes protect from preprocessor!
	$debug and print "file: $file, class: $class\nvariables...@vars\n";
	my %state;
	map{ my ($sigil, $identifier) = /(.)([\w:]+)/; 
		 my $eval_string =  q($state{')
							. $identifier
							. q('})
							. q( = )
							. ($sigil ne q($) ? q(\\) : q() ) 
							. $sigil
							. ($identifier =~ /:/ ? '' : $class)
							. $identifier;
	$debug and print "attempting to eval $eval_string\n";
	eval($eval_string) or $debug  and print 
		"eval returned zero or failed ($!\n)";
	} @vars;
	# my $result1 = store \%state, $file; # old method
	if ( $h{-file} ) {

		if ($h{-storable}) {
			my $result1 = store \%state, $file; # old method
		} else {
			$file .= '.yml' unless $file =~ /\.yml$/;
			my $yaml = yaml_out(\%state);
			$yaml > io($file);
			$debug and print $yaml;
		}
	} else { yaml_out(\%state) }

}

sub yaml_out {
	local $debug = 0;
	local $debug2 = 0;
	$debug2 and print "&yaml_out\n";
	my ($data_ref) = shift; 
	my $type = ref $data_ref;
	$debug and print "data ref type: $type\n "; 
	carp "can't yaml-out a Scalar!!\n" if ref $data_ref eq 'SCALAR';
	croak "attempting to code wrong data type: $type"
		if $type !~ /HASH|ARRAY/;
	my $output;
    $yw->write( $data_ref, \$output ); 
	$output;
}
sub yaml_in {
	local $debug = 0;
	# $debug2 and print "&yaml_in\n";
	my $file = shift;
	my $yaml; 
	if ($file !~ /\n/) {
		$debug and print "assuming yaml filename input\n";
		$yaml = io($file)->all;
	} else { 
		$debug and print "assuming yaml text input\n";
		$yaml = $file;
	}
	$yr->read( $yaml ); # returns ref
}
sub yamlify_commands {
	my @in = @_;
	@in = map{ 	s/\t{2}/\t\t\t/ ; 
			s/^\t(?!\t)/\t-\n\t\t/;
			s/\t/  /g;
			s/\s+$/\n/g;
			$_;
		} @in;
		@in;

}

## support functions

sub create_dir {
	my @dirs = @_;
	map{ my $dir = $_;
		-e $dir and (carp "create_dir: '$dir' already exists, skipping...\n") 
			or mkdir $dir
			or carp qq(failed to create directory "$dir": $!\n);
		} @dirs;
}

sub join_path {
	local $debug = 0;
	no warnings;
	my @parts = @_;
	my $path = join '/', @parts;
	$path =~ s(/{2,})(/)g;
	$debug and print "path: $path\n";
	$path;
	use warnings;
}

sub wav_off {
	my $wav = shift;
	$wav =~ s/\.wav\s*$//i;
	$wav;
}

sub strip_all{ strip_blank_lines( strip_comments(@_) ) }

sub strip_blank_lines {
	map{ s/\n(\s*\n)+/\n/sg } @_;
	map{ s/^\n//sg } @_;
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
1;

