package ::Assign;
our $VERSION = 1.0;
use 5.008;
use strict;
use warnings;
no warnings q(uninitialized);
use Carp;
use IO::All;
use Data::YAML;
use Data::YAML::Reader;
use Data::YAML::Writer;
use Data::Rmap qw(:all);
use Data::Dump qw(dump);
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
	
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
	
);


package ::;
our ($debug, $debug2, $debug3);
package ::Assign;
use vars qw($yw $yr);
$yw = Data::YAML::Writer->new;
$yr = Data::YAML::Reader->new;

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
 	$class .= "\:\:" unless $class =~ /\:\:$/;; # backslashes protect
												#from preprocessor
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
			
		$debug and print <<DEBUG;
key:             $key
full_class_path: $full_class_path
sigil{key}:      $sigil{$key}
DEBUG
		if ($debug){
		 $sigil{$key} 
		or carp "didn't find a match for $key in ", join " ", @vars, $/;
		}
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
				
			if ( ! defined $val ){
				if ($sigil eq '@'){    $ref->{$identifier} = [] }
				elsif ($sigil eq '%'){ $ref->{$identifier} = {} }
				else {warn "unexpected sigil: $sigil\n"}
			}


			$eval .= qq($sigil\{);
			$eval .= q($ref->{ );
			$eval .= qq("$identifier");
			$eval .= q( } );
			$eval .= q( } );
		}
		$debug and print $eval, $/, $/;
		eval($eval);
		$debug and $@ and carp "failed to eval $eval: $@\n";
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

	if (-f $source){
		if ( $source =~ /\.yml$/i ){
				$debug and print "found a yaml file: $source\n";
				$ref = yaml_in($source);
		} elsif ( $source =~ /\.pl$/i ){
				$debug and print "found a perl file: $source\n";
				my $code = io($source)->all ;
				$ref = eval $code or carp "$source: eval failed: $@\n";
		} else {
				$debug and print "assuming Storable file: $source\n";
				$ref = retrieve($source) # Storable
		}

	# check for a yaml string
	} elsif ( $source =~ /^\s*---/s ){
		$debug and print "found yaml text\n";
		$ref = $yr->read($source);

	# pass a hash_ref to the assigner
	} elsif ( ref $source ) {
		$debug and print "found a reference\n";
		$ref = $source;
	} else { carp "$source: unidentified data source\n"; }


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
	my $method = $h{type};
 	$class .= "\:\:" unless $class =~ /\:\:$/;; # backslashes protect from preprocessor!
	$debug and print "file: $file, class: $class\nvariables...@vars\n";
	my %state;
	my $tilde = q('~');
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

		if ($h{storable} or $h{format} eq 'storable') {
			my $result1 = store \%state, $file; # old method
		} 
		elsif ($h{format} eq 'perl'){
			$file .= '.pl' unless $file =~ /\.pl$/;
			my $pl = dump \%state;
			$pl > io($file);
		} else {
			$file .= '.yml' unless $file =~ /\.yml$/;
			rmap_array { $_ = q(~) if ! scalar @$_ } \%state;
			rmap_hash  { $_ = q(~) if ! scalar %$_ } \%state;
			rmap       { $_ = q(~) if !         $_ } \%state;
			my $yaml = yaml_out(\%state);
			$yaml > io($file);
			$debug and print $yaml;
		}
	} else { yaml_out(\%state) }

}

sub yaml_out {
	
	$debug2 and print "&yaml_out\n";
	my ($data_ref) = shift; 
	my $type = ref $data_ref;
	$debug and print "data ref type: $type\n "; 
	carp "can't yaml-out a Scalar!!\n" if ref $data_ref eq 'SCALAR';
	croak "attempting to code wrong data type: $type"
		if $type !~ /HASH|ARRAY/;
	my $output;
	#$debug and print join $/, keys %$data_ref, $/;
	$debug and print "about to write YAML as string\n";
    $yw->write( $data_ref, \$output ) if $type =~ /HASH|ARRAY/;
	$output;
}
sub yaml_in {
	
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
	eval q[$yr->read( $yaml )]  or croak "yaml read failed: $@" ; # returns ref
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
1;

