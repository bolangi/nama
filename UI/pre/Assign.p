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
		
		serial
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
	local $debug = $debug3;
	
	$debug2 and print "&assign\n";
	
	my %h = @_;
	my $class;
	croak "didn't expect scalar here" if ref $h{DATA} eq 'SCALAR';
	croak "didn't expect code here" if ref $h{DATA} eq 'CODE';

	if ( ref $h{DATA} !~ /^(HASH|ARRAY|CODE|GLOB|HANDLE|FORMAT)$/){
		# we guess object
		$class = ref $h{DATA}; 
		$debug and print "I found a class: $class, I think...\n";
	} 
	$class = $h{CLASS} if $h{CLASS};
 	$class .= "\:\:" unless $class =~ /\:\:/;; # protecting from preprocessor!
	my @vars = @{ $h{VARS} };
	my $ref = $h{DATA};
	my %sigil;
	map{ 
		my ($s, $identifier) = /(.)(\w+)/;
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
		my $full_class_path = 
			$sigil{$key} . $class . $key;
		$sigil{$key} or croak 
			"didn't find a match for $key in ", join " ", @vars, $/;
		$debug and print "full_class_path: $full_class_path\n";;
		#$debug and print "full: $full\n";;
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
				
				$val = qq("$val") unless  $val =~ /^[\d.,+-e]+$/ 
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
	my ($source, @vars) = @_;
	$debug2 and print "&assign_vars\n";
	local $debug = 1;
	# assigns vars in @var_list to values from $source
	# $source can be a :
	#      - filename or
	#      - string containing YAML data
	#      - reference to a hash array containing assignments
	#
	# returns a $ref containing the retrieved data structure
	$debug and print "file: $source\n";
	$debug and print "variable list: @vars\n";
	my $ref;

### figure out what to do with input

	$source !~ /.yaml$/i and -f $source 
		and $debug and print ("found Storable file: $source\n")
		and $ref = retrieve($source) # Storable

	## check for a filename

	or -f $source and $source =~ /.yaml$/ 
		and $debug and print "found a yaml file: $source\n"
		and $ref = yaml_in($source)
 	
	## check for a string

	or  $source =~ /^\s*---/s 
		and $debug and print "found yaml as text\n"
		and $ref = $yr->read($source)

	## pass a hash_ref to the assigner

	or ref $source 
		and $debug and print "found a reference\n"
		and $ref = $source;


	assign(DATA => $ref, VARS => \@vars, CLASS => '::'); # XX HARDCODED
	1;	

}

sub store_vars {
	local $debug = 1;
	$debug2 and print "&store_vars\n";
	my %h = @_;
	my $class = $h{CLASS};
	my $file  = $h{FILE};
 	$class .= "\:\:" unless $class =~ /\:\:/;; # protecting from preprocessor!
	my @vars = @{ $h{VARS} };
	my %sigil;
	$debug and print "vars: @vars\n";
	$debug and print "file: $file\n";
	my %state;
	map{ my ($sigil, $identifier) = /(.)(\w+)/; 
		 my $eval_string =  q($state{)
							. $identifier
							. q(} = \\) # double backslash needed
							. $sigil
							. $class
							. $identifier;
	$debug and print "attempting to eval $eval_string\n";
	eval($eval_string) or print "failed to eval $eval_string: $!\n";
	} @vars;
	if ($h{STORABLE}) {
		my $result1 = store \%state, $file; # old method
	} else {
		$file .= '.yaml' unless $file =~ /\.yaml$/;
		my $yamlout = yaml_out(\%state);
		$yamlout > io $file;
	}

}
sub serial {
	my %h = @_;
	my @vars = @{ $h{VARS} };
	my $class = $h{CLASS} if $h{CLASS};
 	$class .= "\:\:" unless $class =~ /\:\:/;; # protecting from preprocessor!
	# now we will only store in yaml
	$debug2 and print "&serial\n";
	my %state;
	map{ my ($sigil, $identifier) = /(.)(\w+)/; 
		 my $eval_string =  q($state{)
							. $identifier
							. q(})
							. q( = )
							. ($sigil ne q($) ? q(\\) : q() ) 
							. $sigil
							. $class
							. $identifier;
	$debug and print "attempting to eval $eval_string\n";
	eval($eval_string) or print "failed to eval $eval_string: $!\n";
	} @vars;
	# my $result1 = store \%state, $file; # old method
	yaml_out(\%state);


}

sub yaml_out {
	local $debug = 0;
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
	my $dir = shift;
	-e $dir and 
		(carp "create_dir: '$dir' already exists, skipping...\n"), 
		return;
	mkdir $dir
	or carp qq(failed to create directory "$dir": $!\n);
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
	@_;
	 
}

sub strip_comments { #  
	map{ s/#.*$//mg; } @_;
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

