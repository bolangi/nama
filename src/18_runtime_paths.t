use v5.36;
use Test::More;
use Path::Tiny qw(path tempdir);
use JSON::PP;
use Cwd qw(getcwd);
use FindBin;
our ($project, @errors, @notices, @snapshots, $state_file, $loaded_state);
$project = {name => 'test'};
sub valid_track_name ($name) { $name ne 'nama' }
sub throw (@message) { push @errors, join '', @message }
sub notify (@message) { push @notices, join '', @message }
sub json_in ($s) { JSON::PP->new->decode($s) }
sub json_out ($s) { JSON::PP->new->canonical->encode($s) }
sub project_snapshot (@message) {
    push @snapshots, @message ? $message[0] : 'before';
    # Model save_state writing the current in-memory state.
    $state_file->spew_utf8(json_out($loaded_state)) if $loaded_state;
}
sub load_project (@args) { $loaded_state = json_in($state_file->slurp_utf8) }
my $root = path($FindBin::Bin)->parent;
# Inspect shipped modules without loading Nama's engines or UI dependencies.
# Normalize rooted namespaces so extracted routines use this test's stubs.
sub module_text ($relative) {
    my $text = $root->child('lib', $relative)->slurp_utf8;
    $text =~ s/Audio\x3a\x3aNama(?=\x3a\x3a)//g;
    return $text;
}
my $source = module_text('Audio/Nama/TrackUtils.pm');
my ($subs) = $source =~ /(sub rename_track .*?)(?=sub user_tracks_present)/s;
eval $subs; die $@ if $@;
my $tmp = tempdir;
my $wav = $tmp->child('audio dir')->mkdir;
$state_file = $tmp->child('State.json');
my $cwd = getcwd;
sub reset_case ($old = 'piano') {
    $_->remove for $wav->children;
    @errors = (); @notices = (); @snapshots = ();
    $loaded_state = { tracks => [{name => $old, target => $old}],
        nested => [{host_track => $old, comment => $old}],
        similarly_named => {name => $old . '2'} };
    $state_file->spew_utf8(json_out($loaded_state));
    $wav->child("${old}_1.wav")->spew_raw('take1');
    $wav->child("${old}_2.wav")->spew_raw('take2');
    $wav->child("${old}2_1.wav")->spew_raw('other');
}
reset_case('piano.x');
ok(rename_track('piano.x', q{New ' voice}, "$state_file", "$wav"), 'rename succeeds with regex punctuation and quotes');
is($wav->child(q{New ' voice_1.wav})->slurp_raw, 'take1', 'audio moved literally');
ok($wav->child('piano.x2_1.wav')->exists, 'longer track prefix untouched');
is($loaded_state->{tracks}[0]{name}, q{New ' voice}, 'loaded track renamed');
is($loaded_state->{nested}[0]{host_track}, q{New ' voice}, 'nested reference renamed');
is($loaded_state->{nested}[0]{comment}, 'piano.x', 'comment preserved');
is(json_in($state_file->slurp_utf8)->{tracks}[0]{name}, q{New ' voice}, 'final snapshot preserves rename');
is_deeply(\@snapshots, ['before', q{Rename track piano.x -> New ' voice}], 'snapshot order');
is(getcwd, $cwd, 'cwd unchanged');
reset_case();
$wav->child('voice_2.wav')->spew_raw('existing');
ok(!rename_track('piano', 'voice', "$state_file", "$wav"), 'destination collision rejected');
is($wav->child('voice_2.wav')->slurp_raw, 'existing', 'destination preserved');
ok($wav->child('piano_1.wav')->exists, 'preflight prevents partial rename');
is(scalar @snapshots, 0, 'no snapshot on preflight failure');
reset_case();
{
    no warnings 'redefine';
    my $real_move = \&Path::Tiny::move;
    my $calls = 0;
    local *Path::Tiny::move = sub {
        my ($self, $destination) = @_;
        die "simulated move failure\n" if $self->basename =~ /^piano_/ && ++$calls == 2;
        return $real_move->(@_);
    };
    ok(!rename_track('piano', 'voice', "$state_file", "$wav"), 'move failure reported');
}
ok($wav->child('piano_1.wav')->exists && $wav->child('piano_2.wav')->exists, 'prior move rolled back');
ok(!$wav->child('voice_1.wav')->exists && !$wav->child('voice_2.wav')->exists, 'no partial destination remains');
is(json_in($state_file->slurp_utf8)->{tracks}[0]{name}, 'piano', 'state preserved after failure');
like($errors[0], qr/simulated move failure/, 'specific failure communicated');
is(scalar @notices, 0, 'no success notification on failure');
reset_case();
{
    no warnings 'redefine';
    my $real_spew = \&Path::Tiny::spew_utf8;
    local *Path::Tiny::spew_utf8 = sub {
        my ($self, $data) = @_;
        die "simulated state write failure\n" if $data =~ /voice/;
        return $real_spew->(@_);
    };
    ok(!rename_track('piano', 'voice', "$state_file", "$wav"), 'state write failure reported');
}
ok($wav->child('piano_1.wav')->exists && $wav->child('piano_2.wav')->exists, 'moves rolled back after state write failure');
is(getcwd, $cwd, 'cwd unchanged on failures');
reset_case();
symlink 'missing', $wav->child('voice_1.wav') or die $!;
ok(!rename_track('piano', 'voice', "$state_file", "$wav"), 'dangling destination symlink rejected');
reset_case();
ok(!rename_track('piano', 'nama', "$state_file", "$wav"), 'invalid track name rejected');
is(scalar @snapshots, 0, 'invalid name rejected before snapshot');
ok($wav->child('piano_1.wav')->exists, 'invalid name leaves audio untouched');
reset_case();
ok(!rename_track('piano', 'voice/bad', "$state_file", "$wav"), 'path separator rejected');
# Runtime paths no longer mutate the process working directory.
for my $file (qw(Audio/Nama/TrackUtils.pm Audio/Nama/Edit.pm Audio/Nama/EcasoundCleanup.pm Audio/Nama.pm)) {
    unlike(module_text($file), qr/\bchdir\b/, "$file has no chdir");
}
# Postprocessing must keep the symlink target relative to the link directory,
# while handing an absolute input filename to the encoder.
our (%tn, $config, @encoding);
sub logsub (@args) { }
sub logpkg (@args) { }
sub nama_cmd (@args) { }
sub project_dir { "$tmp" }
sub join_path (@parts) { path(@parts)->stringify }
sub current_branch { 'master' }
sub git_sha { undef }
sub delete_existing_mixdown_tag_and_convenience_encodings (@args) { }
sub encode_mixdown_file (@args) { @encoding = @args }
{
    package MixStub;
    sub full_path { "$main::mix_path" }
    sub playback_version { 1 }
    sub add_system_version_comment { }
}
our $mix_path = $tmp->child('.wav', 'Mixdown_1.wav')->stringify;
path($mix_path)->parent->mkpath;
path($mix_path)->spew_raw('mix');
$tn{Mixdown} = bless {}, 'MixStub';
$config = { use_git => 0, mixdown_encodings => 'mp3' };
my ($postprocess) = module_text('Audio/Nama/EcasoundCleanup.pm')
    =~ /(sub mixdown_postprocessing .*?)(?=sub tag_mixdown_commit)/s;
eval $postprocess; die $@ if $@;
mixdown_postprocessing();
is(readlink($tmp->child('test_1.wav')), '.wav/Mixdown_1.wav', 'mixdown symlink retains relative target');
ok($tmp->child('test_1.wav')->is_file, 'mixdown link resolves from unrelated cwd');
is("$encoding[0]", $mix_path, 'encoder receives absolute audio path');
is(getcwd, $cwd, 'mixdown leaves cwd unchanged');
# Execute the actual grammar rewrite with a quoted project directory.
my ($git_rewrite) = module_text('Audio/Nama.pm')
    =~ /(    if \(\$shellcode =~ .*?)(?=\n\s*\x3a\x3anotify)/s;
ok(defined $git_rewrite, 'locate git command rewrite');
{
    my $shellcode = 'git status --short';
    eval $git_rewrite; die $@ if $@;
    like($shellcode, qr/^git -C '/, 'git selects directory explicitly');
}
done_testing;
