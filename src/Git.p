# ---------- Git Support ----------
package ::;
use Modern::Perl;
sub git { 
	$config->{use_git} or warn("@_: git command, but git is not enabled.
You may want to set use_git: 1 in .namarc"), return;
	logpkg('debug',"VCS command: git @_"); 
	$project->{repo}->run(@_) 
}
sub git_tag_exists {
	my $tag = shift;
	grep { $tag eq $_ } git( 'tag','--list');
}

# on command "get foo", Nama opens a branch name 'foo-branch', 
# or returns to HEAD of existing branch 'foo-branch'

sub tag_branch { "$_[0]-branch" }

sub restore_state_from_vcs {
	logsub("&restore_state_from_vcs");
	my $name = shift; # tag or branch
	
	# checkout branch if matching branch exists
	
    if (git_branch_exists($name)){
		pager3( qq($name: branch exists. Checking out branch $name.) );
		git_checkout($name);
		
	}

	# checkout branch diverging at tag if matching that tag

	elsif ( git_tag_exists($name) ){

		my $tag = $name;
		my $branch = tag_branch($tag);
	
		if (git_branch_exists($branch)){
			pager3( qq(tag $tag: matching branch exists. Checking out $branch.) );
			git_checkout($branch);
		}

		else {
			pager3( "Creating and checking out branch $branch from tag $tag");
			git_create_branch($branch, $tag);
			
		}
	}
 	else { throw("$name: tag doesn't exist. Cannot checkout."), return  }

	restore_state_from_file();
}
 
sub git_snapshot {
	logsub("&git_snapshot");
	return unless $config->{use_git};
	return unless state_changed();
	my $commit_message = shift() || "no comment";
	git_commit($commit_message);
}
	
sub git_commit {
	logsub("&git_commit");
	my $commit_message = shift;
	no warnings 'uninitialized';
	$commit_message = join "\n", 
		$commit_message,
		# context for first command
		"Context:",
		" + track: $project->{undo_buffer}->[0]->{context}->{track}",
		" + bus:   $project->{undo_buffer}->[0]->{context}->{bus}",
		" + op:    $project->{undo_buffer}->[0]->{context}->{op}",
		# all commands since last commit
		map{ $_->{command} } @{$project->{undo_buffer}};
		
	git( add => $file->git_state_store );
	git( commit => '--quiet', '--message', $commit_message);
	$project->{undo_buffer} = [];
}

sub git_checkout {
	logsub("&git_checkout");
	my ($branchname, @args) = @_;
	return unless $config->{use_git};

	my $exist_message = git_branch_exists($branchname)
				?  undef
				: "$branchname: branch does not exist.";
	my $dirty_tree_msg  = !! state_changed() 
		?  "You have changes to working files.
You cannot switch branches until you commit
these changes, or throw them away."
		: undef;
		
	my $conjunction = ($dirty_tree_msg and $exist_message) 
			? "And by the way, "
			: undef;

	throw( $dirty_tree_msg, 
			$conjunction, 
			$exist_message, 
			"No action taken."), return
		if $dirty_tree_msg or $exist_message;

	git(checkout => $branchname, @args);

}
sub git_create_branch {
	logsub("&git_create_branch");
	my ($branchname, $branchfrom) = @_;
	return unless $config->{use_git};
	# create new branch
	my @args;
	my $from_target;
	$from_target = "from $branchfrom" if $branchfrom;
	push @args, $branchname;
	push(@args, $branchfrom) if $branchfrom;
	pager("Creating branch $branchname $from_target");
	git(checkout => '-b', @args)
}

sub state_changed {  
	logsub("&state_changed");
	return unless $config->{use_git};
	git("diff");
}

sub git_branch_exists { 
	logsub("&git_branch_exists");
	return unless $config->{use_git};
	my $branchname = shift;
	grep{ $_ eq $branchname } 
		map{ s/^\s+//; s/^\* //; $_}
		git("branch");
}

sub current_branch {
	logsub("&current_branch");
	return unless $project->{repo};
	my ($b) = map{ /\* (\S+)/ } grep{ /\*/ } split "\n", git('branch');
	$b
}

sub git_sha {
	my $commit = shift || 'HEAD';
		my ($sha) = git(show => $commit) =~ /commit ([0-9a-f]{10})/;
		$sha
}
sub git_branch_display {
	logsub("&git_branch_display");
	return unless $config->{use_git};
	my $cb = current_branch();
	return unless $cb and $cb ne 'master';
	"git:".current_branch()." "
}
sub list_branches {
	pager3(
		"---Branches--- (asterisk marks current branch)",
		$project->{repo}->run('branch'),
		"",
		"-----Tags-----",
		$project->{repo}->run('tag','--list')	
	);
}

sub autosave {
	logsub("&autosave");
	my ($original_branch) = current_branch();
	my @args = qw(undo --quiet);
	unshift @args, '-b' if ! git_branch_exists('undo');
	git(checkout => @args);
	save_state();
	git_snapshot();
	git_checkout($original_branch, '--quiet');

}

sub merge_undo_branch {
	logsub("&merge_undo_branch");
	my $this_branch = current_branch();
	autosave();
	return unless my $diff = git(diff => $this_branch, 'undo');
	git( qw{ merge --no-ff undo -m}, q{merge autosave commits} );
	git( qw{ branch -d undo } );
}
1
