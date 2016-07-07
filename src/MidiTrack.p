# ---------- MidiTrack -----------
#
package ::MidiTrack;
use Modern::Perl;
use Carp qw(carp cluck croak);
use SUPER;
use Try::Tiny;
use ::Globals qw(:all);
use ::Log qw(logpkg logsub);
#no warnings qw(uninitialized redefine);
#
#    this is what we will lose:
#
use Role::Tiny::With;
 	 '::TrackIO';
# with '::Wav',
# 	 '::WavModify',
# 	 '::TrackRegion',
# 	 '::TrackComment',
# 	 '::TrackEffect',
# 	 '::TrackLatency',
# 	 '::EffectNickname',
# 	 '::BusUtil';
#use Memoize qw(memoize unmemoize); # TODO  
our $VERSION = 1.0;

use ::Util qw(freq input_node dest_type dest_string join_path);
use ::Assign qw(json_out);

# "import" 
package ::Track;
our ($n,%by_name,@by_index,%track_names,%by_index);
package ::MidiTrack;
# use ::Object qw(
# [ % qx(./strip_all ./track_fields) % ]
# );
#
our @ISA = '::Track';
our (%_is_field);


sub idx { # return first free track index
	my $n = 0;
	while (++$n){
		return $n if not $by_index{$n}
	}
}
sub new {
	# returns a reference to an object 
	#
	# tracks are indexed by:
	# (1) name and 
	# (2) by an assigned index that is used as chain_id
	#     the index may be supplied as a parameter
	#
	# 

	my $class = shift;
	my %vals = @_;
	my $novol = delete $vals{novol};
	my $nopan = delete $vals{nopan};
	my $restore = delete $vals{restore};
	say "restoring track $vals{name}" if $restore;
	my @undeclared = grep{ ! $_is_field{$_} } keys %vals;
    croak "undeclared field: @undeclared" if @undeclared;
	
	# silently return if track already exists
	# why not return track? TODO
	
	return if $by_name{$vals{name}};

	my $n = $vals{n} || idx(); 
	my $object = bless { 


		## 		defaults ##
					class	=> $class,
					name 	=> "Midi_$n", 
					group	=> 'Midi', 
					n    	=> $n,
					ops     => [],
					width => 1,
					vol  	=> undef,
					pan 	=> undef,

					modifiers 		=> q(), # start, reverse, audioloop, playat
					looping 		=> undef, # do we repeat our sound sample
					source_type 	=> q(midi),
					source_id   	=> "1",
					send_type 		=> undef,
					send_id   		=> undef,
					old_vol_level	=> undef,

					@_ 			}, $class;

	$track_names{$vals{name}}++;
	$by_index{$n} = $object;
	$by_name{ $object->name } = $object;

	$::this_midi_track = $object;
	$::ui->track_gui($object->n) unless $object->hide;
	logpkg('debug',$object->name, ": ","newly created track",$/,json_out($object->as_hash));
	$object;
}


### object methods

sub snapshot {
	my $track = shift;
	my $fields = shift;
	my %snap; 
	my $i = 0;
	for(@$fields){
		$snap{$_} = $track->$_;
	}
	\%snap;
}


# create an edge representing sound source

# blows up when I move it to TrackIO

sub input_path { 

	my $track = shift;

	# the corresponding bus handles input routing for mix tracks
	
	# bus mix tracks don't usually need to be connected
	return() if $track->is_mix_track and $track->rec_status ne PLAY;

	# the track may route to:
	# + another track
	# + an external source (soundcard or JACK client)
	# + a WAV file

	if($track->source_type eq 'track'){ ($track->source_id, $track->name) } 

	elsif($track->rec_status =~ /REC|MON/){ 
		(input_node($track->source_type), $track->name) } 

	elsif($track->rec_status eq PLAY and ! $mode->doodle){
		('wav_in', $track->name) 
	}
}

# remove track object and all effects

sub remove {
	my $track = shift;
	my $n = $track->n;
	$ui->remove_track_gui($n); 
	# remove corresponding fades
	map{ $_->remove } grep { $_->track eq $track->name } values %::Fade::by_index;
	# remove effects
 	map{ ::remove_effect($_) } @{ $track->ops };
 	delete $by_index{$n};
 	delete $by_name{$track->name};
}


# Modified from Object.p to save class
# should this be used in other classes?
sub as_hash {
	my $self = shift;
	my $class = ref $self;
	bless $self, 'HASH'; # easy magic
	my %guts = %{ $self };
	$guts{class} = $class; # make sure we save the correct class name
	bless $self, $class; # restore
	return \%guts;
}
sub input_object {
	my $track = shift;
	$::IO::by_name{$track->name}->{input}
}
sub output_object {
	my $track = shift;
	$::IO::by_name{$track->name}->{output}
}
sub rec_setup_script { 
	my $track = shift;
	join_path(::project_dir(), $track->name."-rec-setup.sh")
}
sub rec_cleanup_script { 
	my $track = shift;
	join_path(::project_dir(), $track->name."-rec-cleanup.sh")
}
sub current_edit { $_[0]->{current_edit}//={} }
sub is_mix_track {
	my $track = shift;
	($bn{$track->name} or $track->name eq 'Master') and $track->rw eq MON
}
sub bus { $bn{$_[0]->group} }

{ my %system_track = map{ $_, 1} qw( Master Mixdown Eq Low
Mid High Boost );
sub is_user_track { ! $system_track{$_[0]->name} }
sub is_system_track { $system_track{$_[0]->name} } 
}

sub engine_group {
	my $track = shift;
	my $bus = $bn{$track->group};
	$bus->engine_group || $track->{engine_group} || 'Nama'
}
sub engine {
	my $track = shift;
	$en{$track->engine_group}
}



1;
__END__


