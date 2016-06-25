package ::EffectNickname;
use Modern::Perl;
use Role::Tiny;

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
1;
