package ::Engine;
our $VERSION = 1.0;
use Modern::Perl;
use Carp;
our @ISA;
our %by_name;
our @ports = (57000..57050);
our %port = (
	fof => 57201,
	bus => 57202,
);
use ::Globals qw(:all);
use ::Object qw( 
				name
				port
				jack_seek_delay
				jack_operation_mode
				events
				socket
				pids
				ecasound
				buffersize
				 );

initialize();

sub initialize {
	%by_name = ();	
	*pager_newline = \&::pager_newline;
}
sub new {
	my $class = shift;	
	my %vals = @_;
	croak "undeclared field: @_" if grep{ ! $_is_field{$_} } keys %vals;
	pager_newline("$vals{name}: returning existing engine"), 
		return $by_name{$vals{name}} if $by_name{$vals{name}};
	my $object = bless { name => 'default', %vals }, $class;
	#print "object class: $class, object type: ", ref $object, $/;
	$by_name{ $object->name } = $object;
	$object->start_ecasound();
	$::this_engine = $object;
	
}
sub start_ecasound {
	my $self = shift;
 	my @existing_pids = split " ", qx(pgrep ecasound);
	$self->launch_ecasound_server;
	@{$self->{pids}} = grep{ 	my $pid = $_; 
							! grep{ $pid == $_ } @existing_pids
						 }	split " ", qx(pgrep ecasound);
	
	$self->init_ecasound_socket;
}
sub init_ecasound_socket {
	my $self = shift;
	my $port = $self->port;
	pager_newline("Creating socket on port $port.");
	$self->{socket} = new IO::Socket::INET (
		PeerAddr => 'localhost', 
		PeerPort => $port, 
		Proto => 'tcp', 
	); 
	die "Could not create socket: $!\n" unless $self->{socket}; 
}
sub launch_ecasound_server {
	my $self = shift;
	my $port = $self->port;
	
	# we'll try to communicate with an existing ecasound
	# process provided:
	#
	# started with --server option
	# --server-tcp-port option matches 
	
	my $command = "ecasound -K -C --server --server-tcp-port=$port";
	my $redirect = ">/dev/null &";
	my $ps = qx(ps ax);
	pager_newline("Using existing Ecasound server"), return 
		if  $ps =~ /ecasound/
		and $ps =~ /--server/
		and ($ps =~ /tcp-port=$port/);
	pager_newline("Starting Ecasound server");
 	system("$command $redirect") == 0 or carp "system $command failed: $?\n";
	sleep 1;
}
1

__END__
