package ::Lat;
use Modern::Perl '2020';
our @ISA;
use Data::Dumper::Concise;
use overload '+' => \&add_latency,
			 "\"\"" => sub { join ' ',$_[0]->min, $_[0]->max };
sub new {
	my $class = shift;
	my ($min, $max) = @_;
	defined $min and defined $max or die "undefined field: min: $min or max; $max";
	die "Lat object has Min ($min) greater than Max ($max)" if $min > $max;
	my $self = bless [$min, $max], $class;
	$self;
}
sub add_latency {
	my (@latencies) = @_[0,1]; # throw away swap argument
	my ($min, $max) = (0,0);
	map{ $min += $_->min; $max += $_->max } @latencies;
	::Lat->new($min, $max);
}
sub min {$_[0]->[0] }
sub max {$_[0]->[1] }
sub values { $_[0]->min, $_[0]->max }

1;
__END__

