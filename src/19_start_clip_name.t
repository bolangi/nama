use v5.36;
use Test::More;
use FindBin;
our ($clip_prompt_active, $ui, @created, @validated, $ended, $started, $opening);
package ClipTestUI {
 sub prompt_for_text ($self, $message, $callback) { $self->{callback} = $callback; $self->{prompts}++ }
}
package ChainSetup { sub really_recording { 0 } }
sub current_timeline_position { 12 }
sub stop_transport { }
sub set_timeline_position ($time) { }
sub clip_state { (2, $opening) }
sub valid_track_name ($name) { push @validated, $name; $name ne 'play' }
sub end_clip ($time) { $ended++ }
sub register_clip_endpoint (%args) { push @created, \%args }
sub start_transport { $started++ }
open my $fh, '<', "$FindBin::Bin/../src/Mark.p" or die $!;
my $source = do { local $/; <$fh> };
my ($sub) = $source =~ /(sub start_clip \{.*?)(?=sub end_clip)/s;
eval $sub; die $@ if $@;
sub reset_case {
 $ui = bless {prompts => 0}, 'ClipTestUI'; $clip_prompt_active = 0;
 @created = (); @validated = (); $ended = $started = 0; $opening = 1;
}
reset_case(); start_clip(); $ui->{callback}->('play');
is_deeply(\@validated, ['play'], 'validate exact entered name');
is($ui->{prompts}, 2, 'invalid name prompts again');
ok($clip_prompt_active, 'prompt remains guarded');
is(scalar @created, 0, 'invalid name creates no mark');
is($ended, 0, 'invalid name leaves previous clip open');
is($started, 0, 'transport stays stopped during retry');
$ui->{callback}->('lecture');
is($created[0]{name}, 'lecture', 'corrected label accepted');
is($created[0]{index}, 3, 'retry preserves next clip index');
is($created[0]{time}, 12, 'retry preserves clip position');
is($ended, 1, 'previous clip closed once after valid name');
is($started, 1, 'playback resumes after valid name');
ok(!$clip_prompt_active, 'guard released');
reset_case(); start_clip(); $ui->{callback}->(undef);
is(scalar @validated, 0, 'cancel bypasses validation');
is(scalar @created, 0, 'cancel creates no mark');
is($ended, 0, 'cancel preserves previous clip');
is($started, 1, 'cancel resumes playback');
reset_case(); start_clip(); $ui->{callback}->('');
is_deeply(\@validated, ['clip 3'], 'blank label validates default name');
is($created[0]{name}, '', 'blank label remains blank for default naming');
done_testing;
