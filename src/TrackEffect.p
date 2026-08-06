package ::TrackEffect;
use v5.36;
our $VERSION = 1.0;
use Role::Tiny;
use ::Effect qw(fxn);
use ::Globals qw($project);
use Try::Tiny;
use List::MoreUtils qw(first_index);

# current operator and current parameter for the track
sub op { $project->{current_op}->{$_[0]->name} //= $_[0]->{ops}->[-1] }
sub op_id { $_[0]->op }
sub selected_effect { fxn($_[0]->op_id) }
sub effect_ids { $_[0]->ops }

sub param { $project->{current_param}->{$_[0]->op_id} //= 1 }

sub stepsize {
	$project->{current_stepsize}->{$_[0]->op_id}->[$_[0]->param] //= 0.01
	# TODO use hint if available
}
sub pos {
	my $track = shift;
	my $op_id = $track->op_id;
	my $index = first_index {$_ eq $op_id } @{$track->effect_ids};
	return($index || 0);
}
sub user_effects {
	my $track = shift;
	map{ fxn($_) } $track->user_effect_ids;
}
sub channel_ops {
	my $track = shift;
	grep{ $_->is_channel_op } $track->effects;
}
sub audio_ops {
	my $track = shift;
	grep{ 
		! $_->is_channel_op
		and ! $_->is_controller

	} $track->effects;
}
sub ops_ecasound_order {
	my $track = shift;
	$track->channel_ops, $track->audio_ops
}
sub ecasound_dynamic_apply_list { # audio ops and their controllers
	my $track = shift;
	grep{ ! $_->is_channel_op } $track->effects;
}
sub effects {
	my $track = shift;
	map{ ::fxn($_) } @{ $track->effect_ids }
}
sub ops_o { $_[0]->effects }
sub apply_ops {
	my $track = shift;
	$_->apply_op for $track->ecasound_dynamic_apply_list;
}
sub user_effect_ids {
	my $track = shift;
	my @skip = 	grep {fxn($_)}  # must exist
				map { $track->{$_} } qw(vol pan fader latency_op );

	# make a dictionary of ops to exclude
	# that includes utility ops and their controllers
	
	my %skip;

	map{ $skip{$_}++ } @skip, ::expanded_ops_list(@skip);

	grep{ ! $skip{$_} } @{ $track->{ops} || [] };
}
sub user_ops { $_[0]->user_effect_ids }

sub first_effect_of_type {
	my $track = shift;
	my $type = shift;
	for my $effect_id ( @{$track->effect_ids} ){
		my $FX = fxn($effect_id);
		return $FX if $FX->type =~ /$type/ # Plate matches el:Plate
	}
}
sub effect_id_by_name {
	my $track = shift;
	my $ident = shift;
	for my $FX ($track->user_effects)
	{ return $FX->id if $FX->name eq $ident }
}
sub vol_level { my $self = shift; try { $self->volume_effect->params->[0] } }
sub pan_level { my $self = shift; try { $self->pan_effect->params->[0] } }
sub vol_id { $_[0]->vol }
sub volume_effect { my $self = shift; fxn($self->vol_id) }
sub pan_id { $_[0]->pan }
sub pan_effect { my $self = shift; fxn($self->pan_id) }
sub fader_id { $_[0]->fader }
sub fader_effect { my $self = shift; fxn($self->fader) }
sub latency_effect_id { $_[0]->latency_op }
sub latency_effect { my $self = shift; fxn($self->latency_op) }
sub mute {
	
	my $track = shift;
	my $nofade = shift;

	# do nothing if track is already muted
	return if defined $track->old_vol_level();

	# do nothing if track has no volume operator
	my $vol = $track->volume_effect;
	return unless $vol;

	# store vol level for unmute
	$track->set(old_vol_level => $vol->params->[0]);
	
	$nofade 
		? $vol->_modify_effect(1, $vol->mute_level)
		: $vol->fadeout
}
sub unmute {
	my $track = shift;
	my $nofade = shift;

	# do nothing if we are not muted
	return if ! defined $track->old_vol_level;

	$nofade
		? $track->volume_effect->_modify_effect(1, $track->old_vol_level)
		: $track->volume_effect->fadein($track->old_vol_level);

	$track->set(old_vol_level => undef);
}
sub get_inserts {
	my $track = shift;
	grep{ $_->{track} eq $track->name} values %::Insert::by_index;
}

1;
