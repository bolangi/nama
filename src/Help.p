# -------------------- Help ----------------------

package ::;
use Modern::Perl;

{
no warnings 'uninitialized';
sub helpline {
	my $cmd = shift;
	my $out = "Command: $cmd\n";
	$out .=  "Shortcuts: $text->{commands}->{$cmd}->{short}\n"
			if $text->{commands}->{$cmd}->{short};	
	$out .=  "Category: $text->{commands}->{$cmd}->{type}\n";
	my $what = munge_help($text->{commands}->{$cmd}->{what});
	$out .=  "Description: $what\n";
	$out .=  "Usage: $cmd "; 

	if ( $text->{commands}->{$cmd}->{parameters} 
			&& $text->{commands}->{$cmd}->{parameters} ne 'none' ){
		$out .=  $text->{commands}->{$cmd}->{parameters}
	}
	$out .= "\n";
	my $example = $text->{commands}->{$cmd}->{example};
	$example = munge_help($example);
	#$example =~ s/!n/\n/g;
	if ($example){
		$out .=  "Example: ";
		if ($example =~ /\n/s){
			$example = "\n$example";    # add leading newline
			$example =~ s(\n)(\n    )g; # indent
		}
		$out .=  $example;
		$out .= "\n";
	}
	($/, ucfirst $out, $/);
	
}
sub munge_help {
	my $text = shift;
	$text =~ s/(^\s*)!(\s*#)/$1 $2/mg;
	$text =~ s/(^\s*!)/#/mg;
	$text
}
}
sub helptopic {
	my $user_input = shift;

	# we expect topic number or topic name
	
	my ($index, $name);
	if( $user_input =~ /(\D+)/ ){ 
		$name = $1;
	}
	else { 
		$index = $user_input;
		$name = $help->{arr_topic}->[$index];
	}
	#system("man","nama") if $index== 15;
	format_help_topic($index, $name);
}

sub format_help_topic {
	my ($index, $name) = @_;
	my @output;
	push @output, "\n-- ", ucfirst $name, " --\n\n";
	push @output, $help->{topic}->{$name}, $/;
	push @output, $help->{usage} if $index == 14;
	@output
}

sub help { 
	my $name = shift;
	$name =~ s/-/_/g;  # help indices require underscores
	chomp $name;
	#print "seeking help for argument: $name\n";
	$text->{iam}->{$name} and pager(<<IAM);

$name is an Ecasound command.  See 'man ecasound-iam'.
IAM
	my @output;
	if ( $help->{topic}->{$name}){
		@output = helptopic($name);
	} elsif ($name =~ /^0/){
		@output = map{ helptopic $_ } @{$help->{arr_topic}};
	} elsif ( $name =~ /^(\d+)$/ and $1 < 20  ){
		@output = helptopic($name)
	} else {
		my %helped = (); 
		my @help = ();
		if ( $text->{commands}->{$name} ){
			push @help, helpline($name);
			$helped{$name}++
		}
		map
		{  
			my $cmd = $_ ;
			if ($cmd =~ /$name/ )
			{
				push @help, helpline($cmd) unless $helped{$cmd}
					or $cmd =~ /-/; # skip hyphenated command forms
									# which lack full help
				$helped{$cmd}++ ;
			}
			no warnings 'uninitialized';
			if ( ! $helped{$cmd} and
					grep{ /$name/ } split " ", $text->{commands}->{$cmd}->{short})
			{
				push @help, helpline($cmd) 
			}
		} keys %{$text->{commands}};

		if ( @help ){ push @output, 
			qq("$name" matches the following commands:\n\n), @help;
		}
	}
	if (@output){
		map{ s/_/-/g } @output;
		::pager( @output ); 
	} else { throw("$name: no help found.\n"); }
	
}
sub help_effect {
	my ($input, $id, $no_match, @output);
	$id = $input = shift;
	push @output, "\n";

	# e.g. help tap_reverb    
	#      help 2142
	#      help var_chipmunk # preset

	# convert digits to LADSPA label

	if ($id !~ /\D/){ $id = $fx_cache->{ladspa_id_to_label}->{$id} or $no_match++ } 

	# convert ladspa_label to el:ladspa_label
	# convert preset_name  to pn:preset_name
	
	if ($fx_cache->{full_label_to_index}->{$id}){} # we are ready
	elsif ( $fx_cache->{partial_label_to_full}->{$id} ) { $id = $fx_cache->{partial_label_to_full}->{$id} }
	else { $no_match++ }

	# one-line help for Ecasound presets
	
	if ($id =~ /pn:/) {
		push @output, grep{ /$id/  } @{$fx_cache->{user_help}};
	}

	# full help for LADSPA/LV2 plugins
	
	elsif ( $id =~ /el:/  ) { @output = $fx_cache->{ladspa_help}->{$id} }
	elsif ( $id =~ /elv2:/) { @output = $fx_cache->{lv2_help}->{$id}    }
	else { 
		@output = qq("$id" is an Ecasound chain operator.
Type 'man ecasound' at a shell prompt for details.);
	}

	if( $no_match ){ throw("No effects were found matching: $input\n\n"); }
	else { ::pager(@output) }
}

sub find_effect {
	my @keys = @_;
	#print "keys: @keys\n";
	#my @output;
	my @matches = grep{ 
		my $_help = $_; 
		my $didnt_match;
		map{ $_help =~ /\Q$_\E/i or $didnt_match++ }  @keys;
		! $didnt_match; # select if no cases of non-matching
	} @{$fx_cache->{user_help}};
	if ( @matches ){
	::pager( $text->{wrap}->paragraphs(@matches) , "\n" );
	} else { throw(join " ", "No effects were found matching:",@keys,"\n\n") }
}


@{$help->{arr_topic}} = qw( all
                    project
                    track
                    chain_setup
                    transport
                    marks
                    effects
                    group
                    bus
                    mixdown
                    prompt 
                    diagnostics
					fades
					edits

                ) ;

[% qx(cat ./help_topic.pl) %]
1;
