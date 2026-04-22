#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2021-2022 -- leonerd@leonerd.org.uk

use v5.26;
use Object::Pad 0.75 ':experimental(init_expr adjust_params)';

package Tickit::Widget::Entry::Plugin::Completion 0.02;
class Tickit::Widget::Entry::Plugin::Completion
   :strict(params);

use feature 'fc';

use Carp;

use Tickit::Widget 0.55;  # Can ->set_style on '<Tab>' key

use Tickit::Utils qw( textwidth );
use List::Util qw( max );

use constant PEN_UNDER => Tickit::Pen->new( u => 1 );

=head1 NAME

C<Tickit::Widget::Entry::Plugin::Completion> - add word-completion logic to a L<Tickit::Widget::Entry>

=head1 SYNOPSIS

   use Tickit::Widget::Entry;
   use Tickit::Widget::Entry::Plugin::Completion;

   my $entry = Tickit::Widget::Entry->new( ... );
   Tickit::Widget::Entry::Plugin::Completion->apply( $entry,
      words => [ make_words() ],
   );

   ...

=head1 DESCRIPTION

This package applies code to a L<Tickit::Widget::Entry> instance to implement
word-completion logic while editing. This logic is activated by pressing the
C<< <Tab> >> key.

If the word currently being edited has a unique match in the list of words,
then the word is completed entirely, followed by a space.

If there are multiple words that could complete from the word at the cursor,
then a popup menu is presented showing the next available characters or
matches. The user can continue typing more characters to narrow down the
choice until a unique match is found.

=cut

=head1 METHODS

=cut

=head2 apply

   Tickit::Widget::Entry::Plugin::Completion->apply( $entry, %params )

Applies the plugin code to the given L<Tickit::Widget::Entry> instance.

The following named parameters are recognised

=over 4

=item gen_words => CODE

   @words = $gen_words->( %args )

A CODE reference to a subroutine used to generate the list of words at the
current position. It is passed the following name/value pairs to assist it:

=over 4

=item word => STRING

The partial word currently being completed.

=item wordpos => INT

The position of the beginning of the word, within the line. Will be 0 for the
initial word of the line.

=item entry => C<Tickit::Widget::Entry>

The underlying entry widget instance.

=back

=item words => ARRAY

A shortcut to providing C<gen_words>; a reference to an array containing all
the possible words, in no particular order, that are offered for completion.

=item use_popup => BOOL

Optional. If false, do not display a popup menu. Defaults to true.

When this is disabled, the completion logic will apply longest-prefix matching
on the set of available words, but will not otherwise display or offer any
interactive UI on the list of matches.

=item ignore_case => BOOL

Optional. If true, word matching will be performed ignoring case, by using the
C</i> regexp flag. Defaults to false. When the completion logic has selected a
word to insert, it may change the case of the text already in the buffer to
match the completion word.

=item append_after_word => STRING

Optional. If set, append this string after a successful unique match. Defaults
to a single space.

=back

=cut

# Not an instance method
sub apply
{
   my $class = shift;
   my ( $entry, %opts ) = @_;

   my $plugin = $class->new( entry => $entry, %opts );

   $entry->bind_keys(
      Tab => sub { $plugin->key_complete },
   );

   # Need to disable style-applied keypress binding so this takes effect
   $entry->set_style( '<Tab>' => "" );
}

field $_ignore_case       :param //= 0;
field $_use_popup         :param //= 1;
field $_append_after_word :param //= " ";

field $_gen_words :param = undef;

ADJUST :params (
   :$words = undef,
) {
   if( $words and !$_gen_words ) {
      $_gen_words = sub { return $words->@* };
   }

   $_gen_words or
      croak "Require either 'gen_words' or 'words'";
}

field $_entry :param;

field $_popup_window;

method key_complete
{
   my ( $partial ) = substr( $_entry->text, 0, $_entry->position ) =~ m/(\S*)$/;
   my $plen = length $partial or return 1;

   my $match = $_ignore_case ? qr/^\Q$partial\E/i : qr/^\Q$partial\E/;
   my @completions = grep { $_ =~ $match } $_gen_words->(
      word    => $partial,
      wordpos => $_entry->position - $plen,
      entry   => $_entry,
   );
   @completions or return 1;

   # Find the common prefix of all the matches
   my $add = $completions[0];
   foreach my $s ( @completions[1 .. $#completions] ) {
      my $diffpos = 1;
      if( $_ignore_case ) {
         $diffpos++ while fc substr( $add, 0, $diffpos ) eq fc substr( $s, 0, $diffpos );
      }
      else {
         $diffpos++ while    substr( $add, 0, $diffpos ) eq    substr( $s, 0, $diffpos );
      }

      return 1 if $diffpos == 1;

      $add = substr( $add, 0, $diffpos - 1 );
   }

   if( @completions == 1 ) {
      # No other completions, so we have a complete match
      $add .= $_append_after_word;
   }

   $_entry->text_splice( $_entry->position - $plen, $plen, $add );

   return 1 if @completions < 2;
   return 1 unless $_use_popup;

   # Split matches on next letter
   my %next;
   foreach ( @completions ) {
      my $l = substr( $_, $plen, 1 );
      push @{ $next{$l} }, $_;
   }

   my @possibles = map {
      @{ $next{$_} } == 1 ? $next{$_}[0]
                          : substr( $next{$_}[0], 0, $plen + 1 ) . "..."
   } sort keys %next;

   # Popup above, unless there's no room at which point, go below
   my $popup_line = ( $_entry->window->abs_top >= @possibles ) ? -(scalar @possibles) : +1;
   my $popup = $_entry->make_popup_at_cursor(
      $popup_line, -$plen,
      scalar @possibles, max( map { textwidth($_) } @possibles ),
   );

   # TODO: Some style stuff here
   $popup->pen->chattrs({ bg => 'green', fg => 'black' });

   $popup->bind_event( expose => sub ( $win, $, $info, @ ) {
      my $rb = $info->rb;

      foreach my $line ( 0 .. $#possibles ) {
         my $str = $possibles[$line];

         $rb->goto( $line, 0 );

         $rb->text( substr( $str, 0, $plen + 1 ), PEN_UNDER );
         $rb->text( substr( $str, $plen + 1 ) ) if length $str > $plen + 1;
         $rb->erase_to( $win->cols );
      }
   } );
   $popup->bind_event( key => sub ( $win, $, $info, @ ) {
      my $redo_complete;

      my $str = $info->str;

      if( $info->type eq "text" ) {
         $_entry->text_splice( $_entry->position, 0, $str );
         $redo_complete++;
      }
      elsif( $str eq "Backspace" ) {
         $_entry->text_splice( $_entry->position - 1, 1, "" );
         $redo_complete++;
      }
      elsif( $str eq "Escape" ) {
         # OK, just dismiss
      }
      else {
         # TODO: Handle at least Enter, maybe arrows to select?
         print STDERR "TODO: Unsure how to handle key $str in popup menu\n";
      }

      $popup->hide;
      undef $_popup_window;
      $_entry->take_focus;

      $self->key_complete if $redo_complete;
      return 1;
   } );
   $popup->cursor_at( 0, $plen );
   $popup->take_focus;

   $popup->show;

   $_popup_window = $popup;

   return 1;
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
