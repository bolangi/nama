package ::TrackComment;
use Role::Tiny;
use Modern::Perl;
use ::Globals qw($project);
sub set_comment {
	my ($track, $comment) = @_;
	$project->{track_comments}->{$track->name} = $comment
}
sub comment { $project->{track_comments}->{$_[0]->name} }

sub version_comment {
	my ($track, $v) = @_;
	return unless $project->{track_version_comments}->{$track->name}{$v};
	my $text   = $project->{track_version_comments}->{$track->name}{$v}{user};
	$text .= " " if $text;
	my $system = $project->{track_version_comments}->{$track->name}{$v}{system};
	$text .= "* $system" if $system;
	"$v: $text\n" if $text;
}
sub show_version_comments {
	my ($t, @v) = @_;
	return unless @v;
	::pager(map{ $t->version_comment($_) } @v);
}
sub add_version_comment {
	my ($t,$v,$text) = @_;
	$t->targets->{$v} or ::throw("$v: no such version"), return;	
	$project->{track_version_comments}->{$t->name}{$v}{user} = $text;
	$t->version_comment($v);
}
sub add_system_version_comment {
	my ($t,$v,$text) = @_;
	$t->targets->{$v} or ::throw("$v: no such version"), return;	
	$project->{track_version_comments}{$t->name}{$v}{system} = $text;
	$t->version_comment($v);
}
sub remove_version_comment {
	my ($t,$v) = @_;
	$t->targets->{$v} or ::throw("$v: no such version"), return;	
	delete $project->{track_version_comments}{$t->name}{$v}{user};
	$t->version_comment($v) || "$v: [comment deleted]\n";
}
sub remove_system_version_comment {
	my ($t,$v) = @_;
	delete $project->{track_version_comments}{$t->name}{$v}{system} if
		$project->{track_version_comments}{$t->name}{$v}
}
1;
