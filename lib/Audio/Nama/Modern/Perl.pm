package Audio::Nama::Modern::Perl;

=head1 NAME

Modern::Perl - enable all of the features of Modern Perl with one command

=head1 VERSION

Version 1.03

=cut

our $VERSION = '1.03';

use 5.010_000;

use strict;
use warnings;

use mro     ();
use feature ();

sub import {
    warnings->import();
    strict->import();
    feature->import( ':5.10' );
    mro::set_mro( scalar caller(), 'c3' );
}

=head1 SYNOPSIS

Modern Perl programs use several modules to enable additional features of Perl
and of the CPAN.  Instead of copying and pasting all of these C<use> lines,
instead write only one:

    use Modern::Perl;

For now, this only enables the L<strict> and L<warnings> pragmas, as well as
all of the features available in Perl 5.10.  It also enables C3 method
resolution order; see C<perldoc mro> for an explanation.  In the future, it
will include additional CPAN modules which have proven useful and stable.

See L<http://www.modernperlbooks.com/mt/2009/01/toward-a-modernperl.html> for
more information, and L<http://www.modernperlbooks.com/> for further discussion
of Modern Perl and its implications.

=head1 AUTHOR

chromatic, C<< <chromatic at wgz.org> >>

=head1 BUGS

None reported.

Please report any bugs or feature requests to C<bug-modern-perl at
rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Modern-Perl>.  I will be
notified, and then you'll automatically be notified of progress on your bug as
I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Modern::Perl

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Modern-Perl>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Modern-Perl>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Modern-Perl>

=item * Search CPAN

L<http://search.cpan.org/dist/Modern-Perl/>

=back

=head1 ACKNOWLEDGEMENTS

Damian Conway (inspiration from L<Toolkit>), Florian Ragwitz
(L<B::Hooks::Parser>, so I didn't have to write it myself), chocolateboy (for
suggesting that I don't even need L<B::Hooks::Parser>, at least for now),
Damien Learns Perl, David Moreno, and Evan Carroll for reporting bugs and
requesting features.

=head1 COPYRIGHT & LICENSE

Copyright 2009 chromatic, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl 5.10 itself.

=cut

1; # End of Modern::Perl
