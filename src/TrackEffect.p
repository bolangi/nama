package ::TrackEffect;
use Modern::Perl;
use Role::Tiny;
use ::Effect qw(fxn);
use ::Globals qw($project);
use Try::Tiny;

# current operator and current parameter for the track
sub op { $project->{current_op}->{$_[0]->name} //= $_[0]->{ops}->[-1] }

sub param { $project->{current_param}->{$_[0]->op} //= 1 }

sub stepsize {
	$project->{current_stepsize}->{$_[0]->op}->[$_[0]->param] //= 0.01 
	# TODO use hint if available
}
sub pos {
	my $track = shift;
	first_index{$_ eq $track->op} @{$track->ops};
}


sub user_ops_o {
	my $track = shift;
	map{ fxn($_) } $track->user_ops();
}
		
sub apply_ops {
	my $track = shift;
	map{ $_->apply_op }	# add operator to the ecasound chain
	map{ fxn($_) } 		# convert to objects
	@{ $track->ops }  	# start with track ops list
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
1;
