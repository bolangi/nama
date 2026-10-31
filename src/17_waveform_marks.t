use v5.36;
use Test::More;
use ::Mark;
use ::Text;

# Load the GUI helper module without starting Nama or an audio engine.
{
    package ::;
    no warnings 'redefine';
    use Carp qw(croak);
    use ::Globals qw(:all);
    our ($fade_blocked, $refresh_count);
    sub notify { }
    sub logpkg { }
    sub logsub { }
    sub fade_uses_mark { $fade_blocked }
    sub throw { }
    sub adjusted_time_from_timeline_position { $_[0] - 10 }
    sub set_position { }
    sub request_setup { }
    sub colonize { $_[0] }
}
{
    package Local::MarkUI;
    our @ISA = ('::Text');
    sub refresh_marks { $::refresh_count++ }
}

$::ui = bless {}, 'Local::MarkUI';
$::refresh_count = 0;
::Mark::initialize();
my $plain = ::Mark->new(name => 'Verse', time => 12.5);
ok($::refresh_count > 0, 'creation notifies shared UI hook');
my $before = $::refresh_count;
::modify_mark($plain, 14, 1);
is($plain->time, 14, 'shared command moves mark');
is($::refresh_count, $before + 1, 'movement notifies UI');
$plain->set_name('Bridge');
ok(!exists $::Mark::by_name{Verse}, 'rename removes old lookup');
is($::Mark::by_name{Bridge}, $plain, 'rename registers new lookup');
my $start = ::ClipMark->new(time => 15, clip_index => 1, clip_name => 'Lecture', clip_endpoint => 'start');
my $end = ::ClipMark->new(time => 20, clip_index => 1, clip_name => 'Lecture', clip_endpoint => 'end');
is(scalar @{[::Mark::all()]}, 3, 'both clip endpoints survive creation');
isnt($start->name, $end->name, 'endpoint lookup names are distinct');
is($::Mark::by_name{$start->name}, $start, 'start has its own lookup');
my ($index, $opening) = ::clip_state();
is($index, 1, 'shared clip state recognizes ClipMark class');
ok(!defined $opening, 'paired clip is closed');
$end->set_name('Conclusion');
is($end->clip_name, 'Conclusion', 'renaming clip endpoint updates its label field');
$end->set_name('Lecture');
my @saved = map { $_->as_hash } ::Mark::all();
is($saved[1]{class}, '::ClipMark', 'serialized clip preserves class');
::Mark::initialize();
my @restored = map { ::Mark->new(%$_) } @saved;
ok($restored[1] isa '::ClipMark', 'project restore reconstructs clip class');
my %legacy = $saved[2]->%*;
delete $legacy{class};
my $legacy_mark = ::Mark->new(%legacy);
ok($legacy_mark isa '::ClipMark', 'legacy clip fields also restore as ClipMark');
$before = $::refresh_count;
$::fade_blocked = 1;
$plain = $restored[0];
$plain->remove;
is($::refresh_count, $before, 'blocked deletion leaves display untouched');
is(scalar @{[::Mark::all()]}, 3, 'blocked deletion leaves mark intact');
$::fade_blocked = 0;
$plain->remove;
is(scalar @{[::Mark::all()]}, 2, 'shared removal deletes mark');
is($::refresh_count, $before + 1, 'shared removal notifies UI');
eval { ::Mark->new(class => 'Not::AMark', time => 1) };
like($@, qr/Not a mark class/, 'invalid saved class is rejected');

subtest 'Tk buttons and waveform overlays' => sub {
    eval { require Tk; 1 } or plan skip_all => 'Perl Tk unavailable';
    my $mw = eval { MainWindow->new };
    $mw or plan skip_all => 'No X display available';
    require ::Graphical;
    $::gui = {
        main_window => $mw,
        mark_frame => $mw->Frame->pack,
        waveform_canvas => $mw->Scrolled('Canvas', -width => 400, -height => 200, -scrollregion => [0, 0, 400, 200])->pack,
        marks => {},
        _nama_palette => {OffBackground => 'white'},
    };
    $::config = {display_waveform => 1, waveform_pixels_per_second => 10, waveform_canvas_y => 200};
    $::ui = bless {}, '::Graphical';
    ::Mark::initialize();
    my $canvas = $::gui->{waveform_canvas};
    $canvas->createRectangle(0, 0, 400, 200, -fill => 'white', -tags => 'waveform');
    my $cursor = $canvas->createLine(120, 0, 120, 200, -width => 1, -fill => 'yellow', -tags => 'playback-indicator');
    my $normal = ::Mark->new(name => 'Opening', time => 12);
    my $a = ::ClipMark->new(time => 13, clip_index => 1, clip_name => 'Talk', clip_endpoint => 'start');
    my $b = ::ClipMark->new(time => 18, clip_index => 1, clip_name => 'Talk', clip_endpoint => 'end');
    my $items = sub { [$canvas->find('withtag', 'waveform-marks')] };
    my $lines = sub { [grep { $canvas->type($_) eq 'line' } $items->()->@*] };
    my $labels = sub { [grep { $canvas->type($_) eq 'text' } $items->()->@*] };
    is(scalar $items->()->@*, 6, 'three lines and three labels');
    is_deeply([map { $canvas->itemcget($_, '-fill') } $lines->()->@*], ['blue', 'green', 'black'], 'ordinary/start/end colors');
    is_deeply([map { 0 + $canvas->itemcget($_, '-width') } $lines->()->@*], [2, 2, 2], 'marks twice the one-pixel cursor width');
    is_deeply([$canvas->coords($lines->()->[0])], [120, 0, 120, 200], 'uses project time, not offset-adjusted time');
    is_deeply([map { $canvas->itemcget($_, '-text') } $labels->()->@*], ['Opening', 'Talk', 'Talk'], 'mark and clip labels');
    is(scalar keys $::gui->{marks}->%*, 3, 'buttons reflect all three marks');
    my @all = $canvas->find('all');
    is($all[-1], $cursor, 'yellow cursor is above overlays');
    $::ui->refresh_marks;
    is(scalar $items->()->@*, 6, 'repeated refresh does not duplicate overlays');
    my @buttons = $::gui->{mark_frame}->children;
    is(scalar @buttons, 3, 'repeated refresh does not duplicate buttons');
    ::modify_mark($normal, 14, 1);
    is_deeply([$canvas->coords($lines->()->[1])], [140, 0, 140, 200], 'shared move redraws line at new time');
    $normal->set_name('New name');
    ok(grep({ $canvas->itemcget($_, '-text') eq 'New name' } $labels->()->@*), 'shared rename redraws label');
    $normal->remove;
    is(scalar $items->()->@*, 4, 'shared remove deletes line and label');
    $canvas->delete('waveform-marks');
    $::ui->restore_time_marks;
    is(scalar $items->()->@*, 4, 'restore hook rebuilds overlays');
    $::config->{display_waveform} = 0;
    ::refresh_waveform_marks();
    is(scalar $items->()->@*, 0, 'disabled waveform clears overlays');
    $::config->{display_waveform} = 1;
    ::refresh_waveform_marks();
    is(scalar $items->()->@*, 4, 'redrawing waveform restores overlays');
    ::update_indicator_at(16);
    is_deeply([$canvas->coords($cursor)], [160, 0, 160, 200], 'playback cursor still moves after mark redraw');
    @all = $canvas->find('all');
    is($all[-1], $cursor, 'moving cursor remains on top');
    ::Mark::initialize();
    is(scalar $items->()->@*, 0, 'project reset clears overlays');
    is(scalar keys $::gui->{marks}->%*, 0, 'project reset clears buttons');
    $mw->destroy;
    $::gui = {};
};
$::ui = bless {}, '::Text';
::Mark->new(name => 'Terminal only', time => 1);
pass('terminal-only UI needs no Tk widgets');
done_testing();
