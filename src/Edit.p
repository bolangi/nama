# ----------- Edit ------------
package ::Edit;
use Modern::Perl;
our $VERSION = 1.0;
use Carp;
no warnings qw(uninitialized);
our @ISA;
use vars qw($n %by_index);
use ::Object qw( 
				n
				play_from_mark
				rec_on_mark
				rec_off_mark
				host_track
				host_version
				punch_track
				punch_version
				start_pos
				 );
%by_index = ();	# return ref to Mark by name
sub next_n {
	my $n = 1;
	while( $by_index{$n} ){ $n++}
	$n
}
sub new {
	my $class = shift;	
	my %vals = @_;
	croak "undeclared field: @_" if grep{ ! $_is_field{$_} } keys %vals;
	
	my $object = bless { n => next_n(), @_	}, $class;
	$by_index{$object->n} = $object;

	#print "object class: $class, object type: ", ref $object, $/;
	
	$object
	
}

sub edit_name {
	my $self = shift;
	join '-', $self->host_track, 'v'.$self->host_version, 'edit'.$self->n
}

sub play_from_name {
	my $self = shift;
	join '-', $self->edit_name,'play-from'
}
sub rec_on_name {
	my $self = shift;
	join '-', $self->edit_name,'rec-on'
}
sub rec_off_name {
	my $self = shift;
	join '-', $self->edit_name,'rec-off'
}

sub remove { # supply index
	my $i = shift;
	my $edit = $by_index{$i};
	my $track = $::tn{$edit->track};
	
	# remove object from index
	delete $by_index{$i};

}
1;

