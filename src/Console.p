#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2011-2021 -- leonerd@leonerd.org.uk

use v5.26; # signatures
use Object::Pad 0.70 ':experimental(adjust_params)';

package Tickit::Console 0.11;
class Tickit::Console
   :isa(Tickit::Widget::VBox);

#use Tickit::Widget::Entry; # Nama provides a hacked version, don't load to avoid redefined warnings
use Tickit::Widget::Scroller 0.04;
use Tickit::Widget::Tabbed 0.003;

use Tickit::Console::Tab;

use Scalar::Util qw( weaken );

=head1 NAME

C<Tickit::Console> - build full-screen console-style applications

=head1 SYNOPSIS

   my $console = Tickit::Console->new;

   Tickit->new( root => $console )->run;

=head1 DESCRIPTION

A C<Tickit::Console> instance is a subclass of L<Tickit::Widget::VBox>
intended to help building a full-screen console-style application which
presents the user with one or more scrollable text areas, selectable as tabs
on a ribbon, with a text entry area at the bottom of the screen for entering
commands or other data. As a L<Tickit::Widget> subclass it can be added
anywhere within a widget tree, though normally it would be used as the root
widget for a L<Tickit> instance.

=cut

=head1 CONSTRUCTOR

=cut

=head2 new

   $console = Tickit::Console->new( %args )

Returns a new instance of a C<Tickit::Console>. Takes the following named
arguments:

=over 8

=item on_line => CODE

Callback to invoke when a line of text is entered in the entry widget.

   $on_line->( $active_tab, $text )

=item tab_class => STRING

Optional. If set, gives a class name (which should be a subclass of
L<Tickit::Console::Tab>) to construct newly-added tabs with. This setting
allows an application to provide new methods in tabs to change behaviours.

=item timestamp_format, datestamp_format

Optional. If supplied, these will be stored as default values to pass to the
tab constructor in the C<add_tab> method.

=back

=cut

field %_default_tab_opts;
field $_tabbed;
field $_entry;

ADJUST :params (
   :$on_line          = undef,
   :$timestamp_format = undef,
   :$datestamp_format = undef,
   :$tab_class        = "Tickit::Console::Tab",
) {
   $_default_tab_opts{timestamp_format} = $timestamp_format;
   $_default_tab_opts{datestamp_format} = $datestamp_format;

   $self->add(
      $_tabbed = Tickit::Widget::Tabbed->new(
         tab_position => "bottom",
         tab_class    => $tab_class,
      ),
      expand => 1,
   );

   $self->add(
      $_entry = Tickit::Widget::Entry->new
   );

   weaken( my $weakself = $self );
   $_entry->set_on_enter( sub ( $entry, @ ) {
      return unless $weakself;
      my $line = $entry->text;
      $entry->set_text( "" );

      my $tab = $weakself->active_tab;
      $tab->_on_line( $line ) or
         $on_line->( $tab, $line );
   } );
}

=head1 METHODS

=cut

=head2 add_tab

   $tab = $console->add_tab( %args )

Adds a new tab to the console, and returns a L<Tickit::Console::Tab> object
representing it.

Takes the following named arguments:

=over 8

=item name => STRING

Name for the tab.

=item on_line => CODE

Optional. Provides a different callback to invoke when a line of text is
entered while this tab is active. Invoked the same way as above.

=item make_widget => CODE

Optional. Gives a piece of code used to construct the actual L<Tickit::Widget>
used as this tab's child in the ribbon. A C<Tickit::Widget::Scroller> to hold
the tab's content will be passed in to this code, which should construct some
sort of widget tree with that inside it, and return it. This can be used to
apply a decorative frame, place the scroller in a split box or other layout
along with other widgets, or various other effects.

   $tab_widget = $make_widget->( $scroller )

=back

Any other named arguments are passed to the tab's constructor.

=cut

method add_tab ( %args )
{
   my $make_widget = delete $args{make_widget};

   my $scroller = Tickit::Widget::Scroller->new( gravity => "bottom" );

   my $widget = $make_widget ? $make_widget->( $scroller ) : $scroller;

   my $tab = $_tabbed->add_tab(
      $widget,
      label => delete $args{name},
      console => $self,
      scroller => $scroller,
      %_default_tab_opts,
      %args,
   );

   return $tab;
}

=head2 active_tab_index

   $index = $console->active_tab_index

=head2 active_tab

   $tab = $console->active_tab

=head2 remove_tab

   $console->remove_tab( $tab_or_index )

=head2 move_tab

   $console->move_tab( $tab_or_index, $delta )

=head2 active_tab

   $console->activate_tab( $tab_or_index )

=head2 next_tab

   $console->next_tab

=head2 prev_tab

   $console->prev_tab

These methods are all passed through to the underlying
L<Tickit::Widget::Tabbed> object.

=cut

foreach my $method (qw( active_tab_index active_tab
      remove_tab move_tab activate_tab next_tab prev_tab )) {
   no strict 'refs';
   *$method = method {
      $_tabbed->$method( @_ );
   };
}

=head2 bind_key

   $console->bind_key( $key, $code )

Installs a callback to invoke if the given key is pressed, overwriting any
previous callback for the same key. The code block is invoked as

   $code->( $console, $key )

If C<$code> is missing or C<undef>, any existing callback is removed.

=cut

field %_keybindings;

method bind_key ( $key, $code )
{
   $_keybindings{$key}[0] = $code;

   $self->_update_key_binding( $key );
}

method _update_key_binding ( $key )
{
   my $bindings = $_keybindings{$key};

   if( $bindings->[0] or $bindings->[1] ) {
      $_entry->bind_keys( $key => sub ( $entry, $key ) {
         $entry->parent->_on_key( $key );
      });
   }
   else {
      $_entry->bind_key( $key => undef );
   }
}

method _inc_key_binding ( $key )
{
   $_keybindings{$key}[1]++;
   $self->_update_key_binding( $key );
}

method _dec_key_binding ( $key )
{
   $_keybindings{$key}[1]--;
   $self->_update_key_binding( $key );
}

method _on_key ( $key )
{
   if( my $tab = $self->active_tab ) {
      return 1 if $tab->_on_key( $key );
   }

   my $code = $_keybindings{$key}[0] or return 0;
   return $code->( $self, $key );
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
