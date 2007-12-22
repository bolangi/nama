package Session;
our @ISA='';
use Carp;
use Object::Tiny qw(name);
sub session_dir{
	my $self = shift;
	join_path( wav_dir(), $self->name)
}
sub new { my $class = shift; 
	my %vals = @_;
	$vals{name} or carp "invoked without values" and return;
	my $name = $vals{name};
	remove_spaces( $vals{name} );
	$vals{name} = $name;
	$vals{create_dir} and create_dir($name) and delete $vals{create_dir};
	return bless { %vals }, $class; }
my $s = Session->new(name => 'paul_brocante');
print $s->session_dir;

