my $mixer_out = ::Rule->new( #  this is the master fader
	name			=> 'mixer_out', 
	chain_id		=> 'Mixer_out',

	target			=> 'none',

# condition =>	sub{ defined $inputs{mixed}  
# 	or $debug and print("no customers for mixed, skipping\n"), 0},

	input_type 		=> 'mixed', # bus name
	input_object	=> $loopb, 

	output_type		=> 'device',
	output_object	=> $mixer_out_device,

	status			=> 1,

);

my $mix_down = ::Rule->new(

	name			=> 'mix_file', 
	chain_id		=> 'Mixdown',
	target			=> 'none', 
	
	# sub{ defined $outputs{mixed} or $debug 
	#		and print("no customers for mixed, skipping mixdown\n"), 0}, 

	input_type 		=> 'mixed', # bus name
	input_object	=> $loopb,

	output_type		=> 'file',
	output_object   => sub {
		my $track = shift; 
		join " ", $track->full_path, $mix_to_disk_format},

	status			=> 0,
);

my $mix_link = ::Rule->new(

	name			=>  'mix_link',
	chain_id		=>  'Mix_link',
	target			=>  'none',
	input_type		=>  'mixed',
	input_object	=>  $loopa,
	output_type		=>  'mixed',
	output_object	=>  $loopb,
	status			=>  1,
	
);

my $mix_setup = ::Rule->new(

	name			=>  'mix_setup',
	chain_id		=>  sub { my $track = shift; "J". $track->n },
	target			=>  'all',
	input_type		=>  'cooked',
	input_object	=>  sub { my $track = shift; "loop," .  $track->n },
	output_object	=>  $loopa,
	output_type		=>  'cooked',
	condition 		=>  sub{ defined $inputs{mixed} },
	status			=>  1,
	
);



my $mon_setup = ::Rule->new(
	
	name			=>  'mon_setup', 
	target			=>  'MON',
	chain_id 		=>	sub{ my $track = shift; $track->n },
	input_type		=>  'file',
	input_object	=>  sub{ my $track = shift; $track->full_path },
	output_type		=>  'cooked',
	output_object	=>  sub{ my $track = shift; "loop," .  $track->n },
	post_input		=>	sub{ my $track = shift; $track->mono_to_stereo},
	status			=>  1,
);
	
my $rec_file = ::Rule->new(

	name		=>  'rec_file', 
	target		=>  'REC',
	chain_id	=>  sub{ my $track = shift; 'R'. $track->n },   
	input_type	=>  'device',
	input_object=>  'multi',
	output_type	=>  'file',
	output_object   => sub {
		my $track = shift; 
		join " ", $track->full_path, $raw_to_disk_format},
	status		=>  1,
);

# Rec_setup: must come last in oids list, convert REC
# inputs to stereo and output to loop device which will
# have Vol, Pan and other effects prior to various monitoring
# outputs and/or to the mixdown file output.
		
my $rec_setup = ::Rule->new(

	name			=>	'rec_setup', 
	chain_id		=>  sub{ my $track = shift; $track->n },   
	target			=>	'REC',
	input_type		=>  'device',
	input_object	=>  'multi',
	output_type		=>  'cooked',
	output_object	=>  sub{ my $track = shift; "loop," .  $track->n },
	post_input			=>	sub{ my $track = shift;
									$track->rec_route .
									$track->mono_to_stereo 
									},
	condition 		=> sub { my $track = shift; 
							return "satisfied" if defined
							$inputs{cooked}->{"loop," . $track->n}; 
							0 } ,
	status			=>  1,
);

my $multi = ::Rule->new(

	name			=>  'multi', 
	target			=>  'MON',
	chain_id 		=>	sub{ my $track = shift; "M".$track->n },
	input_type		=>  'file',
	input_object	=>  sub{ my $track = shift; "loop," .  $track->n},
	output_type		=>  'device',
	output_object	=>  'multi',
	pre_output		=>	sub{ my $track = shift; $track->pre_multi},
	status			=>  1,
);

# Live: apply effects to REC channels route to multichannel sound card
# as above. 
sub eliminate_loops {
	# given track
	my $n = shift;
	my $loop_id = "loop,$n";
	return unless defined $inputs{cooked}->{$loop_id} 
		and scalar @{$inputs{cooked}->{$loop_id}} == 1;
	# get customer's id from cooked list and remove it from the list

	my $cooked_id = pop @{ $inputs{cooked}->{$loop_id} }; 

	# i.e. J2

	# add chain $n to the list of the customer's (rule's) output device 
	
	#my $rule  = grep{ $cooked_id =~ /$_->chain_id/ } ::Rule::all_rules();  
	my $rule = $mix_setup; 
	defined $outputs{device}->{$rule->output_object} 
	  or $outputs{device}->{$rule->output_object} = [];
	push @{ $outputs{device}->{$rule->output_object} }, $n;


	# remove chain $n as source for the loop

	delete $outputs{cooked}->{$loop_id}; 
	
	# remove customers that use loop as input

	delete $inputs{cooked}->{$loop_id}; 

	# remove cooked customer from his output device list

	@{ $outputs{device}->{$rule->output_object} } = 
		grep{$_ ne $cooked_id} @{ $outputs{device}->{$rule->output_object} };

	# transfer any intermediate processing to numeric chain,
	# deleting the source.
	$post_input{$n} .= $post_input{$cooked_id};
	$pre_output{$n} .= $pre_output{$cooked_id}; 
	delete $post_input{$cooked_id};
	delete $pre_output{$cooked_id};
}

