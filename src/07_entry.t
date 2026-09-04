use Test2::Bundle::More;
use strict;
use warnings;
use ::Entry;

# These tests exercise Entry's text model without installing a terminal
# window. Rendering is covered by Tickit's own widget tests.
{
	no warnings 'redefine';
	*Tickit::Widget::Entry::_recalculate_scroll = sub { undef };
	*Tickit::Widget::Entry::_text_spliced = sub { };
	*Tickit::Widget::Entry::redraw = sub { };
}

sub entry {
	my ($text, $editable_from, $position) = @_;
	$editable_from //= 0;
	$position //= length $text;
	Tickit::Widget::Entry->new(
		text          => $text,
		position      => $position,
		editable_from => $editable_from,
	);
}

my $entry = entry('nama> command', 6, 0);
is($entry->editable_from, 6, 'editable boundary is stored');
is($entry->position, 6, 'initial cursor is clamped to boundary');

$entry->set_position(0);
is($entry->position, 6, 'set_position cannot cross boundary');
$entry->key_beginning_of_line;
is($entry->position, 6, 'beginning of line means beginning of editable input');
$entry->key_backward_char;
is($entry->position, 6, 'backward movement stops at boundary');

$entry = entry('nama> command', 6, 6);
$entry->key_backward_delete_char;
is($entry->text, 'nama> command', 'backspace at boundary is a no-op');

$entry = entry('nama> command', 6);
is($entry->text_delete(0, length $entry->text), 'command',
	'deletion crossing boundary returns only deleted input');
is($entry->text, 'nama> ', 'deletion crossing boundary preserves prefix');
is($entry->position, 6, 'deletion crossing boundary leaves cursor at boundary');

$entry = entry('nama> command', 6);
$entry->key_backward_delete_line;
is($entry->text, 'nama> ', 'C-u preserves prefix');

$entry = entry('nama>command', 5);
$entry->key_backward_delete_word;
is($entry->text, 'nama>', 'word deletion is clipped at boundary');

$entry = entry('nama> command', 6);
$entry->key_delete_line;
is($entry->text, 'nama> ', 'whole-line deletion deletes only editable input');

$entry = entry('nama> command', 6);
$entry->text_insert('new ', 0);
is($entry->text, 'nama> new command',
	'insertion before boundary is placed at start of editable input');

$entry = entry('nama> command', 6, 6);
$entry->key_overwrite_mode;
$entry->on_text('C');
is($entry->text, 'nama> Command', 'overwrite changes only editable text');

{
	package Local::MouseEvent;
	sub new { bless { col => $_[1] }, $_[0] }
	sub type { 'press' }
	sub button { 1 }
	sub col { $_[0]->{col} }
}

$entry = entry("λ> command", 3);
$entry->on_mouse(Local::MouseEvent->new(0));
is($entry->position, 3, 'mouse placement cannot enter Unicode prefix');

$entry = entry('prompt> text', 8, 10);
$entry->set_editable_from(11);
is($entry->editable_from, 11, 'editable boundary can be changed');
is($entry->position, 11, 'moving boundary right also moves cursor');

$entry->set_text('new');
is($entry->editable_from, 3, 'replacing text clamps boundary to new length');
is($entry->position, 3, 'replacing text keeps cursor within new bounds');

$entry = entry('abc', 99, 0);
is($entry->editable_from, 3, 'constructor clamps boundary to text length');
is($entry->position, 3, 'constructor clamps cursor after boundary');

$entry = entry('abc', -1, 0);
is($entry->editable_from, 0, 'constructor clamps negative boundary to zero');
$entry->text_delete(0, 1);
is($entry->text, 'bc', 'default boundary retains ordinary Entry editing');

done_testing();
__END__
