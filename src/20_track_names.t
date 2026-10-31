use v5.36;
use Test::More;
use FindBin;
our (%tn, $text, $mastering, @errors);
$mastering = { track_names => [qw(EQ Low Mid High Boost)] };
sub throw ($message) { push @errors, $message }
open my $fh, '<', "$FindBin::Bin/../lib/Audio/Nama/TrackUtils.pm" or die $!;
my $source = do { local $/; <$fh> };
# Run extracted routines against the stubs in this test's namespace.
$source =~ s/Audio\x3a\x3aNama(?=\x3a\x3a)//g;
my ($validator) = $source =~ /(sub valid_track_name .*?)(?=sub add_track \{)/s;
eval $validator; die $@ if $@;
$text = {
 commands => { add_track => { short => 'at' } },
 rtmidi_commands => { rt_play => { short => 'play' } },
 command_shortcuts => { custom_short => 'custom_command' },
 midi_command_names => { tnew => 1 },
 iam => { 'cs-connect' => 1 },
 user_command => { custom => 1 },
};
for my $name (qw(nama midi rtm rtmidi rmd add_track add-track at rt_play rt-play play tnew cs-connect custom custom-short), 'EQ', '', '12foo', 'foo:bar') {
 @errors = ();
 ok(!valid_track_name($name), "reject '$name'");
 is(scalar @errors, 1, 'one diagnostic');
}
$tn{piano} = 1;
ok(!valid_track_name('piano'), 'reject duplicate');
for my $name (qw(Piano saxophone clip_1 Main Null)) {
 ok(valid_track_name($name), "allow $name");
}
# No command registries yet: still validate syntax and prefixes.
$text = {};
ok(valid_track_name('piano2'), 'works before grammar setup');
ok(!valid_track_name('nama'), 'prefix reserved before setup');
# Check all creation routes converge on add_track and rename validates before I/O.
like($source, qr/my %vals = .*?return unless valid_track_name\(\$vals\{name\}\)/s, 'creation validates final name');
my ($rename) = $source =~ /(sub rename_track .*?)(?=sub rename_track_state_references)/s;
my $validation = index($rename, 'return unless valid_track_name($newname);');
my $snapshot = index($rename, 'project_snapshot();');
ok($validation >= 0 && $snapshot > $validation, 'rename validates before snapshot');
done_testing;
