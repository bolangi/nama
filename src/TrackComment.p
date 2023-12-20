package ::TrackComment;
use Role::Tiny;
use Modern::Perl '2020';
our $VERSION = 1.0;
use ::Globals qw($project);

sub is_comment {
	my $self = shift;
	$::project->{track_comments}->{$self->name}	
}
sub is_version_comment {
	my $self = shift;
	my $version = shift;
	{
	no warnings 'uninitialized';
	my $comments = $project->{track_version_comments}->{$self->name}->{$version};
	$comments and $comments->{user}
	}
}
sub set_comment {
	my ($track, $comment) = @_;
	$project->{track_comments}->{$track->name} = $comment
}
sub comment { 
	my ($track) = @_;
	$project->{track_comments}->{$track->name} 
}

sub version_comment {
	my ($track, $v) = @_;
	return unless $project->{track_version_comments}->{$track->name}{$v};
	my $text   = $project->{track_version_comments}->{$track->name}{$v}{user};
	$text .= " " if $text;
	my $system = $project->{track_version_comments}->{$track->name}{$v}{system};
	$text .= "* $system" if $system;
	$track->name." version $v: $text\n" if $text;
}
sub show_version_comments {
	my ($track, @v) = @_;
	return unless @v;
	::pager(map{ $track->version_comment($_) } @v);
}
sub add_version_comment {
	my ($track,$v,$text) = @_;
	$track->targets->{$v} or ::throw("$v: no such version"), return;	
	$project->{track_version_comments}->{$track->name}{$v}{user} = $text;
	$track->version_comment($v);
}
sub add_system_version_comment {
	my ($track,$v,$text) = @_;
	$track->targets->{$v} or ::throw("$v: no such version"), return;	
	$project->{track_version_comments}{$track->name}{$v}{system} = $text;
	$track->system_version_comment($v);
}
sub remove_version_comment {
	my ($track,$v) = @_;
	$track->targets->{$v} or ::throw("$v: no such version"), return;	
	delete $project->{track_version_comments}{$track->name}{$v}{user};
	$track->version_comment($v) || "$v: [comment deleted]\n";
}
sub remove_system_version_comment {
	my ($track,$v) = @_;
	delete $project->{track_version_comments}{$track->name}{$v}{system} if
		$project->{track_version_comments}{$track->name}{$v}
}
sub system_version_comment {
	my ($track, $v) = @_;
	return unless $project->{track_version_comments}->{$track->name}{$v};
	$project->{track_version_comments}->{$track->name}{$v}{system};
}
1;
