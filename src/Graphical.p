# ------------ Graphical Interface ------------

package ::;

#our ( 


#	);

package ::Graphical;  ## gui routines

our @ISA = '::';      ## default to root class

## The following methods belong to the Graphical interface class

sub hello {"make a window";}
sub loop {
	package ::;
	$attribs->{already_prompted} = 0;
	$term->tkRunning(1);
  	while (1) {
  		my ($user_input) = $term->readline($prompt) ;
  		::process_line( $user_input );
  	}
}

1;
__END__


