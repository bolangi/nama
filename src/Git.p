# ---------- Git Support ----------
package ::;
use Modern::Perl;
sub git { 
	return if is_test_script();
	$config->{use_git} or warn("@_: git command, but git is not enabled.
You may want to set use_git: 1 in .namarc"), return;
	logpkg('debug',"VCS command: git @_"); 
	$project->{repo}->run(@_) 
}
sub initialize_project_repository {
	logsub((caller(0))[3]);
	confess("no project dir") if ! project_dir();
	return unless $config->{use_git} and not is_test_script();
	pager("Creating git repository in ", join_path( project_dir(),  '.git' ))
		if ! -d join_path( project_dir(),  '.git' );
	Git::Repository->run( init => project_dir());
	$project->{repo} = Git::Repository->new( work_tree => project_dir() );
	my $is_new_project;
	$is_new_project = 1 if not -e $file->git_state_store;
	write_file($file->git_state_store, "{}\n") if $is_new_project;
	write_file($file->midi_store,          "") if not -e $file->midi_store;
	write_file($file->tempo_map,           "") if not -e $file->tempo_map; 
	git( add => $_ ) for $file->midi_store, $file->tempo_map, $file->git_state_store;
	git( commit => '--quiet', '--message' => $is_new_project 
											?  'initialize repository' 
											:  'committing prior unsaved changes (left after program abort?)' 
	);
}
sub git_tag_exists {
	logsub((caller(0))[3]);
	my $tag = shift;
	grep { $tag eq $_ } git( 'tag','--list');
}

# on command "get foo", Nama opens a branch name 'foo-branch', 
# or returns to HEAD of existing branch 'foo-branch'

sub tag_branch { "$_[0]-branch" }

sub restore_state_from_vcs {
	logsub((caller(0))[3]);
	my $name = shift; # tag or branch
	
	# checkout branch if matching branch exists
	
    if (git_branch_exists($name)){
		pager_newline( qq($name: branch exists. Checking out branch $name.) );
		git_checkout($name);
		
	}

	# checkout branch diverging at tag if matching that tag

	elsif ( git_tag_exists($name) ){

		my $tag = $name;
		my $branch = tag_branch($tag);
	
		if (git_branch_exists($branch)){
			pager_newline( qq(tag $tag: matching branch exists. Checking out $branch.) );
			git_checkout($branch);
		}

		else {
			pager_newline( "Creating and checking out branch $branch from tag $tag");
			git_create_branch($branch, $tag);
			
		}
	}
 	else { throw("$name: tag doesn't exist. Cannot checkout."), return  }

	restore_state_from_file();
}
 
sub git_snapshot {
	logsub((caller(0))[3]);
	my $commit_message = shift() || "";
	$config->{use_git} 
		and $project->{name} 
		and $project->{repo}
		or throw('failed to create snapshot'), return;
	save_state();
	reset_command_buffer(), return unless state_changed();
	git_commit($commit_message);
}
sub reset_command_buffer { $project->{command_buffer} = [] } 

sub git_commit {
	logsub((caller(0))[3]);
	my $commit_message = shift;
	no warnings 'uninitialized';
	use utf8;
	scalar @{$project->{command_buffer}} and $commit_message .= join "\n", 
		undef,
		(map{ $_->{command} } @{$project->{command_buffer}}),
		# context for first command
		"* track: $project->{command_buffer}->[0]->{context}->{track}",
		"* bus:   $project->{command_buffer}->[0]->{context}->{bus}",
		"* op:    $project->{command_buffer}->[0]->{context}->{op}",
	git( add => $file->git_state_store );
	git( commit => '--quiet', '--message', $commit_message);
	reset_command_buffer();
}

sub git_checkout {
	logsub((caller(0))[3]);
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
	logsub((caller(0))[3]);
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
	logsub((caller(0))[3]);
	return unless $config->{use_git};
	git("diff");
}

sub git_branch_exists { 
	logsub((caller(0))[3]);
	return unless $config->{use_git};
	my $branchname = shift;
	grep{ $_ eq $branchname } 
		map{ s/^\s+//; s/^\* //; $_}
		git("branch");
}

sub current_branch {
	logsub((caller(0))[3]);
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
	logsub((caller(0))[3]);
	my $display = $::project->{name};
	return $display unless $config->{use_git};
	my $cb = current_branch();
	$display .= ":$cb" if $cb and $cb ne 'master';
	$display
}
sub list_branches {
	pager_newline(
		"---Branches--- (asterisk marks current branch)",
		$project->{repo}->run('branch'),
		"",
		"-----Tags-----",
		$project->{repo}->run('tag','--list')	
	);
}

sub autosave {
		logsub((caller(0))[3]);
		git_snapshot(), return if $config->{autosave}
							and not $config->{opts}->{R}
							and not ($this_engine->started() 
											and ::ChainSetup::really_recording());
		throw('failed to autosave, are you recording?');
}
sub redo {
	if ($project->{redo}){
		git('cherry-pick',$project->{redo});
		load_project(name => $project->{name});
		delete $project->{redo};
	} else {throw("nothing to redo")}
	1
}
sub undo {
	pager("removing last commit"); 
	local $quiet = 1;

	# get the commit id
	my $show = git(qw/show HEAD/);	
	my ($commit) = $show =~ /commit ([a-z0-9]{10})/;

	# blow it away
	git(qw/reset --hard HEAD^/); 
	load_project( name => $project->{name});

	# remember it 
	$project->{redo} = $commit;
}
sub show_head_commit {
	my $show = git(qw/show HEAD/);	
	my ($commit) = $show =~ /commit ([a-z0-9]{10})/;
	my (undef,$msg)    = split "\n\n",$show;
	pager_newline("commit: $commit",$msg);
}
1
