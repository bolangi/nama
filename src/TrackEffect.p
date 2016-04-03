package ::TrackEffect;
use Modern::Perl;
use Role::Tiny;
use ::Effect qw(fxn);
use Try::Tiny;

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
sub effect_nickname_count {
	my ($track, $nick) = @_;
	my $count = 0;
	for my $FX ($track->user_ops_o){ $count++ if $FX->name =~ /^$nick\d*$/ }
	$count
}
sub unique_surname {
	my ($track, $surname) = @_;
	# increment supplied surname to be unique to the track if necessary 
	# return arguments:
	# $surname, $previous_surnames
	my $max = undef;
	my %found;
	for my $FX ($track->user_ops_o)
	{ 
		if( $FX->surname =~ /^$surname(\d*)$/)
		{
			$found{$FX->surname}++;
			no warnings qw(uninitialized numeric);
			$max = $1 if $1 > $max;
		}
	}
	if (%found){ $surname.++$max, join ' ',sort keys %found } else { $surname }
}
sub unique_nickname {
	my ($track, $nickname) = @_;
	my $i = 0;
	my @found;
	for my $FX ($track->user_ops_o)
	{ 
		if( $FX->name =~ /^$nickname(\d*)$/)
		{
			push @found, $FX->name; 
			$i = $1 if $1 and $1 > $i
		}
	}
	$nickname. (@found ? ++$i : ""), "@found"
}
# return effect IDs matching a surname
sub with_surname {
	my ($track, $surname) = @_;
	my @found;
	for my $FX ($track->user_ops_o)
	{ push @found, $FX->id if $FX->surname eq $surname }
	@found ? "@found" : undef
}
sub vol_level { my $self = shift; try { $self->vol_o->params->[0] } }
sub pan_level { my $self = shift; try { $self->pan_o->params->[0] } }
sub vol_o { my $self = shift; fxn($self->vol) }
sub pan_o { my $self = shift; fxn($self->pan) }
1;
