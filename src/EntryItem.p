#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2011-2023 -- leonerd@leonerd.org.uk

use v5.26;
use warnings;
use Object::Pad 0.800 ':experimental(adjust_params)';

package Tickit::Widget::Scroller::Item::Entry 0.32;
class Tickit::Widget::Scroller::Item::Entry
   :strict(params);

use Tickit::Utils qw( textwidth cols2chars );

=head1 NAME

C<Tickit::Widget::Scroller::Item::Entry> - add static text to a Scroller

=head1 SYNOPSIS

   use Tickit::Widget::Scroller;
   use Tickit::Widget::Scroller::Item::Entry;

   my $scroller = Tickit::Widget::Scroller->new;

   $scroller->push(
      Tickit::Widget::Scroller::Item::Entry->new( "Hello world" )
   );

=head1 DESCRIPTION

This implementation of L<Tickit::Widget::Scroller::Item> displays a simple
static piece of text. It will be wrapped on whitespace (characters matching
the C</\s/> regexp pattern).

=cut

=head1 CONSTRUCTOR

=cut

=head2 new

   $item = Tickit::Widget::Scroller::Item::Entry->new( $text, %opts );

Constructs a new text item, containing the given string of text. Once
constructed, the item is immutable.

The following options are recognised in C<%opts>:

=over 4

=item indent => INT

If the text item needs to wrap, indent the second and subsequent lines by this
amount. Does not apply to the first line.

=item margin_left => INT

=item margin_right => INT

I<Since version 0.30.>

A number of columns to leave blank at the left and right edge of the item.
This applies outside of any additional space added by C<indent>.

=item margin => INT

I<Since version 0.30.>

Shortcut to setting both C<margin_left> and C<margin_right> to the same value.

=item pen => Tickit::Pen

A pen to set for rendering the item, including erasing its background. This
will not be set while erasing area required for its margin.

=back

=cut

sub BUILDARGS ( $class, $text, %opts ) { return ( text => $text, %opts ) }

field $_indent       :param = undef;
field $_margin_left         = 0;
field $_margin_right        = 0;
field @_chunks;
field $_pen          :param = undef;

field $_width; # width for which the @_lineruns are valid
field @_lineruns;

ADJUST :params (
   :$margin_left  = undef,
   :$margin_right = undef,
   :$margin       = undef,
   :$text         = undef,
) {
   $margin_left  //= $margin;
   $margin_right //= $margin;

   $_margin_left  = $margin_left  if defined $margin_left;
   $_margin_right = $margin_right if defined $margin_right;

   @_chunks = $self->_build_chunks_for( $text );
}

=head1 METHODS

=cut

=head2 chunks

   @chunks = $item->chunks;

Returns the chunks of text displayed by this item. Each chunk is represented
by an ARRAY reference of three fields, giving the text string, its width in
columns, and various options

   [ $text, $width, %opts ]

Recognised options are:

=over 8

=item pen => Tickit::Pen

Pen to render the chunk with.

=item linebreak => BOOL

If true, force a linebreak after this chunk; the next one starts on the
following line.

=back

=cut

method _build_chunks_for ( $text )
{
   my @lines = split m/\n/, $text, -1;
   @lines or @lines = ( "" ); # if blank
   my $lastline = pop @lines;
   return ( map { [ $_, textwidth( $_ ), linebreak => 1 ] } @lines ),
            [ $lastline, textwidth( $lastline ) ];
}

method chunks { @_chunks }

method height_for_width ( $width )
{
   # Just pretend the width doesn't include the margins
   $width -= ( $_margin_left + $_margin_right );

   $_width = $width;

   my @chunks = $self->chunks;
   undef @_lineruns;
   push @_lineruns, my $thisline = [];

   my $line_remaining = $width;

   while( @chunks ) {
      my $chunk = shift @chunks;
      my ( $text, $textwidth, %opts ) = @$chunk;

      if( $textwidth <= $line_remaining ) {
         push @$thisline, [ $text =~ s/\xA0/ /gr, $textwidth, $opts{pen} ];
         $line_remaining -= $textwidth;
      }
      else {
         # Split this chunk at most $line_remaining chars
         my $eol_ch = cols2chars $text, $line_remaining;

         if( $eol_ch < length $text && substr( $text, $eol_ch, 1 ) =~ m/[\S\xA0]/ ) {
            # TODO: This surely must be possible without substr()ing a temporary
            if( substr( $text, 0, $eol_ch ) =~ m/[\S\xA0]+$/ and
                ( $-[0] > 0 or @$thisline ) ) {
               $eol_ch = $-[0];
            }
         }

         my $partial_text = substr( $text, 0, $eol_ch );
         my $partial_chunk = [ $partial_text =~ s/\xA0/ /gr, textwidth( $partial_text ), $opts{pen} ];
         push @$thisline, $partial_chunk;

         my $bol_ch = pos $text = $eol_ch;
         $text =~ m/\G\s+/g and $bol_ch = $+[0];

         my $remaining_text = substr( $text, $bol_ch );
         my $remaining_chunk = [ $remaining_text, textwidth( $remaining_text ), %opts ];
         unshift @chunks, $remaining_chunk;

         $line_remaining = 0;
      }

      if( ( $line_remaining == 0 or $opts{linebreak} ) and @chunks ) {
         push @_lineruns, $thisline = [];
         $line_remaining = $width - ( $_indent || 0 );
      }
   }

   return scalar @_lineruns;
}

method render ( $rb, %args )
{
   my $cols = $args{width};

   # Rechunk if width changed
   $self->height_for_width( $cols ) if $cols != $_width;

   foreach my $lineidx ( $args{firstline} .. $args{lastline} ) {
      my $indent = ( $lineidx && $_indent ) ? $_indent : 0;

      $rb->goto( $lineidx, 0 );
      $rb->erase( $_margin_left ) if $_margin_left;

      if( $_pen ) {
         $rb->savepen;
         $rb->setpen( $_pen );
      }
      $rb->erase( $indent ) if $indent;

      foreach my $chunk ( $_lineruns[$lineidx]->@* ) {
         my ( $text, $width, $chunkpen ) = @$chunk;
         $rb->text( $text, $chunkpen );
      }

      if( $_pen ) {
         $rb->erase_to( $cols - $_margin_right );
         $rb->restore;
         $rb->erase_to( $cols ) if $_margin_right;
      }
      else {
         $rb->erase_to( $cols );
      }
   }
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
