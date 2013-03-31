{
package ::Latency;
use Modern::Perl;
use ::Object qw(min max);
use overload '+' => \&add_latencies,
			 "\"\"" => sub { "$_->[0] $_->[1]" };

sub new {
	my $class = shift;
	my ($min, $max) = @_;
	bless{ min => $min, max => $max }, $class
}
sub add_latencies {
	my (@latencies) = @_;
	my ($min, $max) = (0,0);
	map{ $min += $_->min; $max += $_->max } @latencies
	__PACKAGE__->new($min, $max);
}
my $l1 = __PACKAGE__->new(2,4);
my $l2 = __PACKAGE__->new(4,8);
} # end package ::Latency



