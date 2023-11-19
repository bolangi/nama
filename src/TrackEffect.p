package ::TrackEffect;
use Modern::Perl '2020';
use Role::Tiny;
use ::Effect qw(fxn);
use ::Globals qw($project);
use Try::Tiny;
use List::MoreUtils qw(first_index);

# current operator and current parameter for the track
sub op { $project->{current_op}->{$_[0]->name} //= $_[0]->{ops}->[-1] }

sub param { $project->{current_param}->{$_[0]->op} //= 1 }

sub stepsize {
	$project->{param_stepsize}->{$_[0]->op}->[$_[0]->param] //= 0.01 
	# TODO use hint if available
}
sub pos {
	my $track = shift;
	my $op = $track->op;
	my $index = first_index {$_ eq $op } @{$track->ops};
	return($index || 0);
}
sub user_ops_o {
	my $track = shift;
	map{ fxn($_) } $track->user_ops();
}
sub channel_ops {
	my $track = shift;
	grep{ $_->is_channel_op } $track->ops_o;	
}
sub audio_ops {
	my $track = shift;
	grep{ 
			! $_->is_channel_op
		and ! $_->is_controller

	} $track->ops_o;	
}
sub ops_ecasound_order {
	my $track = shift;
	$track->channel_ops, $track->audio_ops
}
sub ecasound_dynamic_apply_list { # audio ops and their controllers
	my $track = shift;
	grep{ ! $_->is_channel_op } $track->ops_o;
}
sub ops_o {
	my $track = shift;
	map{ ::fxn($_) } @{ $track->ops }
}
sub apply_ops {
	my $track = shift;
	$_->apply_op for $track->ecasound_dynamic_apply_list;
}
sub user_ops {
	my $track = shift;
	my @skip = 	grep {fxn($_)}  # must exist
				map { $track->{$_} } qw(vol pan fader latency_op );

	# make a dictionary of ops to exclude
	# that includes utility ops and their controllers
	
	my %skip;

	map{ $skip{$_}++ } @skip, ::expanded_ops_list(@skip);

	grep{ ! $skip{$_} } @{ $track->{ops} || [] };
}

sub first_effect_of_type {
	my $track = shift;
	my $type = shift;
	for my $op ( @{$track->ops} ){
		my $FX = fxn($op);
		return $FX if $FX->type =~ /$type/ # Plate matches el:Plate
	}
}
sub effect_id_by_name {
	my $track = shift;
	my $ident = shift;
	for my $FX ($track->user_ops_o)
	{ return $FX->id if $FX->name eq $ident }
}
sub vol_level { my $self = shift; try { $self->vol_o->params->[0] } }
sub pan_level { my $self = shift; try { $self->pan_o->params->[0] } }
sub vol_o { my $self = shift; fxn($self->vol) }
sub pan_o { my $self = shift; fxn($self->pan) }
sub mute {
	
	my $track = shift;
	my $nofade = shift;

	# do nothing if track is already muted
	return if defined $track->old_vol_level();

	# do nothing if track has no volume operator
	my $vol = $track->vol_o;
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
		? $track->vol_o->_modify_effect(1, $track->old_vol_level)
		: $track->vol_o->fadein($track->old_vol_level);

	$track->set(old_vol_level => undef);
}
sub get_inserts {
	my $track = shift;
	grep{ $_->{track} eq $track->name} values %::Insert::by_index;
}

1;
