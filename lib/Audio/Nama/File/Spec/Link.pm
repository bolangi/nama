package File::Spec::Link;

use strict;
use warnings;

use File::Spec ();
use base q(File::Spec); 

our $VERSION = 0.072;

# over-ridden class method - just a debugging wrapper
# 
sub canonpath { 
    my($spec, $path) = @_;
    return $spec->SUPER::canonpath($path) if $path;
    require Carp;
    Carp::cluck( "canonpath: ", 
		defined $path ? "empty path" : "path undefined"  
    );
    return $path;
}
sub catdir { my $spec = shift; return @_ ? $spec->SUPER::catdir(@_) : $spec->curdir }

# new class methods - implemented via objects
# 
sub linked { 
    my $self = shift -> new(@_); 
    return unless $self -> follow; 
    return $self -> path; 
}
sub resolve { 
    my $self = shift -> new(@_); 
    return unless $self -> resolved; 
    return $self -> path; 
}
sub resolve_all { 
    my $self = shift -> new(@_); 
    return unless $self -> resolvedir; 
    return $self -> path; 
}
sub relative_to_file { 
    my($spec, $path) = splice @_, 0, 2;
    my $self = $spec -> new(@_); 
    return unless $self -> relative($path);
    return $self -> path;
}
sub chopfile {
    my $self = shift -> new(@_);
    return $self -> path if length($self -> chop); 
    return
}

# other new class methods - implemented via Cwd
# 
sub full_resolve {
    my($spec, $file) = @_;
    my $path = $spec->resolve_path($file);
    return defined $path ? $path : $spec->resolve_all($file);
}

sub resolve_path {
    my($spec, $file) = @_;
    my $path = do {
	local $SIG{__WARN__} = sub { 
	    if ($_[0] =~ /^opendir\b/			and
		$_[0] =~ /\bNot\s+a\s+directory\b/	and
	    	$Cwd::VERSION < 2.18		 	and
		not -d $file)
	    {
		warn <<WARN;
Cwd::abs_path() only works on directories, not: $file
Use Cwd v2.18 or later
WARN
	    }
	    else {
		warn $_[0]
	    }
	};
	eval { require Cwd } && Cwd::abs_path($file) 
    };
    return unless $path; 
    return $spec->file_name_is_absolute($file)
	    ? $path : $spec->abs2rel($path);
} 

# old class method - not needed
# 
sub splitlast { 
    my $self = shift -> new(@_);
    my $last_path = $self -> chop;
    return ($self -> path, $last_path);
}

# object methods: 
# 	constructor methods	new
# 	access methods		path, canonical, vol, dir 
# 	updating methods	add, pop, push, split, chop
# 				relative, follow, resolved, resolvedir  

sub new { 
    my $self = bless { }, shift; 
    $self -> split(shift) if @_; 
    return $self; 
}
sub path { 
    my $self = shift; 
    return $self -> catpath( $self->vol, $self->dir, q{} ); 
}
sub canonical { my $self = shift; return $self -> canonpath( $self -> path ); }
sub vol { my $vol = shift->{vol}; return defined $vol ? $vol : q{} } 
sub dir { my $self = shift; return $self -> catdir( $self -> dirs ); }
sub dirs { my $dirs = shift->{dirs}; return $dirs ? @{$dirs} : () }
	
sub add {
    my($self, $file) = @_;
    if( $file eq $self -> curdir ) { }
    elsif( $file eq $self -> updir ) { $self -> pop }
    else { $self -> push($file); }
    return;
}
sub pop {
    my $self = shift;
    my @dirs = $self -> dirs;
    if( not @dirs or $dirs[-1] eq $self -> updir ) {
	push @{$self->{dirs}}, $self -> updir;
    }
    elsif( length $dirs[-1] and $dirs[-1] ne $self -> curdir) {
	CORE::pop @{$self->{dirs}}
    }	
    else {
	require Carp;
	Carp::cluck( "Can't go up from ", 
			length $dirs[-1] ? $dirs[-1]: "empty dir"
	);
    }
    return;
}

sub push {
    my $self = shift;
    my $file = shift;
    CORE::push @{$self->{dirs}}, $file if length $file;
    return;
}
sub split {
    my($self, $path) = @_;
    my($vol, $dir, $file) = $self->splitpath($path, 1);
    $self->{vol} = $vol;
    $self->{dirs} = [ $self->splitdir($dir) ];
    $self->push($file);
    return;
}
sub chop {
    my $self = shift;
    my $dirs = $self->{dirs};
    my $file = '';
    while( @$dirs ) {
	last if @$dirs == 1 and not length $dirs->[0];	# path = '/'
	last if length($file = CORE::pop @$dirs);
    }
    return $file;    
}    
    
sub follow {
    my $self = shift;
    my $path = $self -> path;
    my $link = readlink $self->path;
    return $self->relative($link) if defined $link;
    require Carp;
    Carp::confess(
	"Can't readlink ", $self->path, 
    	" : ", 
	(-l $self->path ? "but it is" : "not"), 
	" a link"
    );
}
 
sub relative {
    my($self, $path) = @_;
    unless( $self->file_name_is_absolute($path) ) {
	return unless length($self->chop);
	$path = $self->catdir($self->path, $path);
    }
    # what we want to do here is just set $self->{path}
    # to be read by $self->path; but would need to 
    # unset $self->{path} whenever it becomes invalid
    $self->split($path);
    return 1;
}

sub resolved {
    my $self = shift;
    my $seen = @_ ? shift : {};
    while( -l $self->path ) {
	return if $seen->{$self->canonical}++;
	return unless $self->follow;
    }
    return 1;
}

sub resolvedir {
    my $self = shift;
    my $seen = @_ ? shift : {};
    my @path;
    while( 1 ) {
	return unless $self->resolved($seen);
	my $last = $self->chop;
	last unless length $last;
	unshift @path, $last;
    }
    $self->add($_) for @path;    
    return 1;
}

1;

__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

File::Spec::Link - Perl extension for reading and resolving symbolic links

=head1 SYNOPSIS

    use File::Spec::Link;
    my $file = File::Spec::Link->linked($link); 
    my $file = File::Spec::Link->resolve($link); 
    my $dirname = File::Spec::Link->chopfile($file);
    my $newname = File::Spec::Link->relative_to_file($path, $link);
  
    my $realname = File::Spec::Link->full_resolve($file);
    my $realname = File::Spec::Link->resolve_path($file);
    my $realname = File::Spec::Link->resolve_all($file);

=head1 DESCRIPTION

C<File::Spec::Link> is an extension to C<File::Spec>, adding methods for
resolving symbolic links; it was created to implement C<File::Copy::Link>.

=over

=item C<< linked($link) >>

Returns the filename linked to by C<$link>: by C<readlink>ing C<$link>,
and resolving that path relative to the directory of C<$link>. 

=item C<< resolve($link) >>

Returns the non-link ultimately linked to by C<$link>, by repeatedly
calling C<linked>.  Returns C<undef> if the link can not be resolved.

=item C<< chopfile($file) >>

Returns the directory of C<$file>, by splitting the path of C<$file>
and returning (the volumne and) directory parts.

=item C<< relative_to_file($path, $file) >>

Returns the path of C<$path> relative to the directory of file
C<$file>.  If C<$path> is absolute, just returns C<$path>.

=item C<< resolve_all($file) >>

Returns the filename of C<$file> with all links in the path resolved,
wihout using C<Cwd>.

=item C<< full_resolve($file) >>

Returns the filename of C<$file> with all links in the path resolved.

This sub tries to use C<Cwd::abs_path> via C<< ->resolve_path >>.

=item C<< resolve_path($file) >>

Returns the filename of C<$file> with all links in the path resolved.

This sub uses C<Cwd::abs_path> and is independent of the rest of
C<File::Spec::Link>. 

=back
 
=head2 Object methods 

=over 4

=item C<< new([$path]) >>

create new path object: stores path as a list

=item C<< path >>

returns path as a string, using catpath

=item C<< canonical >>

returns canonical path, using canonpath

=item C<< vol >>

returns volume element of path, see File::Spec->splitpath

=item C<< dir >>

returns directory element of path, as a string, see File::Spec->splitpath

=item C<< dirs >>

return list of directory components in path, see File::Spec->splitdir
	
=item C<< pop >>

remove last component of the path 

=item C<< push($file) >>

add a file component to the path, ignoring empty strings

=item C<< add($file) >>

add a component to the path:
treating C<updir> as C<pop>,
and ignoring C<curdir> and empty strings

=item C<< split($path) >>

populate a path object, using splitpath

=item C<< chop >>

remove and return a file component from path, 
an empty string returns means this was root dir.
    
=item C<< relative($path) >>

replace the path object with the supplied path,
where the new path is relative to the path object

=item C<< follow >>

follow the link, where the path object is a link 

=item C<< resolved >>

resolve the path object, by repeatedly following links
 
=item C<< resolvedir >>

resolve the links at all component levels  within the path object

=back

=head2 Other class methods

=over 4

=item C<< canonpath($path) >>

Wrapper round File::Spec::canonpath, fatal if empty input

=item C<< catdir(@dirs) >>

Wrapper round File::Spec::catdir, returns C<curdir> from empty list

=item C<< splitlast($path) >>

Get component from C<$path> (using C<chop>)
and returns remaining path and compenent, as strings.
[Not used]

=back

=head2 EXPORT

None - all subs are methods for C<File::Spec::Link>.

=head1 SEE ALSO

File::Spec(3) File::Copy::Link(3)

=head1 AUTHOR

Robin Barker, E<lt>Robin.Barker@npl.co.ukE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2003, 2005, 2006, 2007 by Robin Barker

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut

$Id: Link.pm 221 2008-06-12 12:32:23Z rmb1 $
