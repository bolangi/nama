{
package ::Insert;
use Modern::Perl;
use Carp;
no warnings qw(uninitialized redefine);
our $VERSION = 0.1;
our ($debug);
local $debug = 0;
use vars qw(%by_index);
use ::Object qw(
	insert_type
	class
	send_type
	send_id
	return_type
	return_id
	wet_track
	dry_track
	tracks
	track
	wetness
);
# tracks: deprecated

initialize();

sub initialize { %by_index = () }

sub idx { # return first free index
	my $n = 0;
	while (++$n){
		return $n if not $by_index{$n}
	}
}

sub wet_name {
	my $name = shift;
	"$name\_wet"
}
sub dry_name {
	my $name = shift;
	"$name\_dry"
}
sub new {
	my $class = shift;
	my %vals = @_;
	my $track = $::tn{$vals{track}};
	my @undeclared = grep{ ! $_is_field{$_} } keys %vals;
    croak "undeclared field: @undeclared" if @undeclared;
	my $name = $track->name;
	my $wet = ::SlaveTrack->new( 
				name => wet_name($name),
				target => $name,
				group => 'Insert',
				rw => 'REC',
				hide => 1,
			);
	my $dry = ::SlaveTrack->new( 
				name => dry_name($name),
				target => $name,
				group => 'Insert',
				hide => 1,
				rw => 'REC');
	$vals{n} ||= idx(); 
	my $self = bless { 
					class	=> $class, 	# for restore
					dry_vol => $dry->vol,
					wet_vol => $wet->vol,
					wetness		=> 100,
					%vals,
								}, $class;
	$by_index{$self->n} = $self;
	if (! $self->{return_id}){
		$self->{return_type} = $self->{send_type};
		$self->{return_id} =  $self->{send_id} if $self->{return_type} eq 'jack_client';
		$self->{return_id} =  $self->{send_id} + 2 if $self->{return_type} eq 'soundcard';
	}
	$self;
}
sub remove {
	my $self = shift;
	$::tn{ wet_name($self->track) }->remove;
	$::tn{ dry_name($self->track) }->remove;
	my $type = (ref $self) =~ /Pre/ ? 'prefader_insert' : 'postfader_insert';
	$::tn{ $self->track }->set(  $type => undef );
	delete $by_index{$self->n};
}
	
sub add_insert {
	my ($type, $send_id, $return_id) = @_;
	# $type : prefader_insert | postfader_insert
	my $old_this_track = $::this_track;
	my $t = $::this_track;
	my $name = $t->name;

	# the input fields will be ignored, since the track will get input
	# via the loop device track_insert
	
	my $class =  $type =~ /pre/ ? '::PreFaderInsert' : '::PostFaderInsert';
	
	my $i = $class->new( 
		send_type 	=> ::dest_type($send_id),
		send_id	  	=> $send_id,
		return_type 	=> ::dest_type($return_id),
		return_id	=> $return_id,
		track => $t, # pass track object, store track name in insert object
	);
	$t->$class and $by_index{$t->$class}->remove;
	$t->set($type => $i->n); 
	$::this_track = $old_this_track;
}

}
{
package ::PostFaderInsert;
use Modern::Perl; use Carp; our @ISA = qw(::Insert);
}
{
package ::PreFaderInsert;
use Modern::Perl; use Carp; our @ISA = qw(::Insert);
}
1;
