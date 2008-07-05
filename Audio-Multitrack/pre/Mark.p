
# ----------- Mark ------------
package ::Mark;
use Carp;
our @ISA;
use vars qw($n %by_name @all  %used_names);
use ::Object qw( 
				 name 
                 time
				 active
				 );
@all = ();	
%by_name = ();	# return ref to Mark by name
%used_names = (); 

sub new {
	my $class = shift;	
	my %vals = @_;
	croak "undeclared field: @_" if grep{ ! $_is_field{$_} } keys %vals;
	croak  "name already in use: $vals{name}\n"
		 if $used_names{$vals{name}}; # null name returns false
	my $object = bless { 

		## 		defaults ##

					active  => 1,
					name => "",

					@_ 			}, $class;

	#print "object class: $class, object type: ", ref $object, $/;
	if ($object->name) {
		$used_names{$vals{name}}++;
		$by_name{ $object->name } = $object;
	}
	push @all, $object;
	$::this_mark = $object;
	
	$object;
	
}

sub set_name {
	my $mark = shift;
	my $name = shift;
	print "name: $name\n";
	if ( defined $by_name{ $name } ){ }
	else {
		$mark->set(name => $name);
		$used_names{$name}++;
		$by_name{ $name } = $mark;
	}
}

sub jump_here {
	my $mark = shift;
	::eval_iam( "setpos " . $mark->time);
	$::this_mark = $mark;
}
sub remove {
	my $mark = shift;
	if ( $mark->name ) {
		delete $by_name{$mark->name};
		delete $used_names{$mark->name};
	}
	$::debug and warn "marks found: ",scalar @all, $/;
	# @all = (), return if scalar @all
	@all = grep { $_->time != $mark->time } @all;

}
sub next { 
	my $mark = shift;
	::next_mark();
}
sub previous {
	my $mark = shift; 
	::previous_mark();
}

# -- Class Methods

sub all { sort { $a->time <=> $b->time }@all }

sub loop_start { 
	my @points =sort { $a->time <=> $b->time } 
		map{ mark_object($_)} @::loop_endpoints[0,1];
	$points[0];
}
sub loop_end {
	my @points =sort { $a->time <=> $b->time } 
		map{ mark_object($_)} @::loop_endpoints[0,1];
	$points[1];
}
sub mark_object {
	my $tag = shift;
	my @marks = ::Mark::all();
	my $mark;
	if ($tag =~ /\d+/){
		$mark = $marks[$tag];
	} else {
		$mark = $::Mark::by_name{$tag};
	}
	$mark->jump_here if defined $mark; 
}

	
1;

