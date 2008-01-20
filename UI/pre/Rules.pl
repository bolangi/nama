my $mixer_out = ::Rule->new( #  this is the master fader
	name			=> 'mixer_out', 
	chain_id		=> 'Mixer_out',

	target			=> 'none',
	
	# sub{ defined $inputs{mixed}  or $debug and print("no customers for mixed, skipping\n"), 0},

	input_type 		=> 'mixed', # bus name
	input_object	=> $loopb, 

	output_type		=> 'device',
	output_object	=> 'stereo',

	status			=> 1,

);

my $mix_down = ::Rule->new(

	name			=> 'mix_file', 
	chain_id		=> 'Mixdown',
	target			=> 'all', # default
	condition => sub{ 
		defined $outputs{mixed} or $debug 
			and print("no customers for mixed, skipping mixdown\n"), 0}, 

	input_type 		=> 'mixed', # bus name
	input_object	=> $loopb,

	output_type		=> 'file',
	output_object   => sub {
		my $track = shift; 
		join " ", $track->full_path, $mix_to_disk_format},

	status			=> 1,
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
	post_input		=>	\&mono_to_stereo,
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
	post_input			=>	\&mono_to_stereo,
	condition 		=> sub { my $track = shift; 
							return "satisfied" if defined
							$inputs{cooked}->{"loop," . $track->n}; 
							0 } ,
	status			=>  1,
);



=comment

# Multi: output 'cooked' monitor channels to side-by-side
# PCMs starting at the monitor channel assignment in the track menu.
#  Default to PCMs 1 & 2.

	name	=>	q(multi), 
	target	=>	q(mon),  
	id		=>	q(m),
	output	=>	q(multi),
	type	=>	q(cooked),
	pre_output	=>	\&pre_multi,
	status	=> 0,

# Live: apply effects to REC channels route to multichannel sound card
# as above. 

	name	=>  q(live),
	target	=>  q(rec),
	id		=>	q(L),
	output	=>  q(multi),
	type	=>  q(cooked),
	pre_output	=>	\&pre_multi,
	status	=>  0,

	push @{ $inputs{cooked}->{$n} }, $chain_id if $rec_status eq 'REC'
	push @{ $outputs{$oid{output}} }, $chain_id;

=cut
