package ::TkTickitBridge;

use v5.36;
use Carp qw(croak);
use Scalar::Util qw(blessed weaken);
use Tickit ();
use Tk qw(Ev);

our $VERSION = '0.001';

use constant {
	TK_SHIFT_MASK   => 0x0001,
	TK_CONTROL_MASK => 0x0004,
	TK_ALT_MASK     => 0x0008,
};

my %SPECIAL_KEY = (
	BackSpace    => 'Backspace',
	Return       => 'Enter',
	KP_Enter     => 'Enter',
	Escape       => 'Escape',
	Tab          => 'Tab',
	ISO_Left_Tab => 'Tab',
	space        => 'Space',
	Up           => 'Up',
	Down         => 'Down',
	Left         => 'Left',
	Right        => 'Right',
	Insert       => 'Insert',
	Delete       => 'Delete',
	Prior        => 'PageUp',
	Next         => 'PageDown',
	Home         => 'Home',
	End          => 'End',
);

sub new ($class, %args) {
	my $term = $args{term}
		// croak 'TkTickitBridge requires term';
	my $widget = $args{widget}
		// croak 'TkTickitBridge requires widget';

	croak 'term must provide emit_key()'
		unless blessed($term) && $term->can('emit_key');
	croak 'widget must provide bind() and afterIdle()'
		unless blessed($widget)
			&& $widget->can('bind')
			&& $widget->can('afterIdle');

	my $self = bless {
		term          => $term,
		widget        => $widget,
		queue         => [],
		drain_pending => 0,
		shift_mask    => $args{shift_mask}   // TK_SHIFT_MASK,
		control_mask  => $args{control_mask} // TK_CONTROL_MASK,
		alt_mask      => $args{alt_mask}     // TK_ALT_MASK,
		consume       => $args{consume}      // 1,
		on_error      => $args{on_error}
			// sub ($message) { warn "$message\n" },
	}, $class;

	weaken($self->{widget});
	return $self;
}

sub install ($self) {
	my $widget = $self->{widget}
		// croak 'Tk widget has already been destroyed';

	# %K = keysym, %A = produced character, %s = modifier-state mask.
	$widget->bind(
		'all',
		'<KeyPress>' => [
			sub ($widget, $keysym, $char, $state) {
				return $self->_on_tk_key($keysym, $char, $state);
			},
			Ev('K'), Ev('A'), Ev('s'),
		],
	);

	return $self;
}

sub enqueue ($self, %event) {
	croak "Unknown Tickit key type '$event{type}'"
		unless ($event{type} // '') =~ /\A(?:text|key)\z/;
	croak 'A Tickit key event requires str'
		unless defined $event{str} && length $event{str};

	push $self->{queue}->@*, {
		type => $event{type},
		str  => $event{str},
		mod  => $event{mod} // 0,
	};

	$self->_schedule_drain;
	return;
}

sub pending ($self) {
	return scalar $self->{queue}->@*;
}

sub drain ($self) {
	$self->{drain_pending} = 0;

	# Detach the batch so keys enqueued by a handler are delivered later.
	my $batch = $self->{queue};
	$self->{queue} = [];

	for my $event ($batch->@*) {
		my $ok = eval {
			$self->{term}->emit_key(
				type => $event->{type},
				str  => $event->{str},
				mod  => $event->{mod},
			);
			1;
		};

		$self->{on_error}->("Unable to inject Tk key into Tickit: $@")
			unless $ok;
	}

	$self->_schedule_drain if $self->pending;
	return;
}

sub _on_tk_key ($self, $keysym, $char, $state) {
	my $event = $self->_translate($keysym, $char, $state);
	return unless $event;

	$self->enqueue($event->%*);
	return $self->{consume} ? Tk->break : undef;
}

sub _translate ($self, $keysym, $char, $state) {
	$keysym //= '';
	$char   //= '';
	$state  //= 0;

	my $mod = 0;
	$mod |= Tickit::MOD_SHIFT() if $state & $self->{shift_mask};
	$mod |= Tickit::MOD_CTRL()  if $state & $self->{control_mask};
	$mod |= Tickit::MOD_ALT()   if $state & $self->{alt_mask};

	if (my $name = $SPECIAL_KEY{$keysym}) {
		$mod |= Tickit::MOD_SHIFT() if $keysym eq 'ISO_Left_Tab';
		return { type => 'key', str => $name, mod => $mod };
	}

	if ($keysym =~ /\AF(\d+)\z/) {
		return { type => 'key', str => "F$1", mod => $mod };
	}

	if (length($char) && $char !~ /[\x00-\x1f\x7f]/) {
		if (!($mod & (Tickit::MOD_CTRL() | Tickit::MOD_ALT()))) {
			return { type => 'text', str => $char, mod => 0 };
		}

		$mod &= ~Tickit::MOD_SHIFT();
		return { type => 'key', str => $char, mod => $mod };
	}

	if (($mod & Tickit::MOD_CTRL()) && $keysym =~ /\A[A-Za-z]\z/) {
		$mod &= ~Tickit::MOD_SHIFT();
		return { type => 'key', str => lc($keysym), mod => $mod };
	}

	return;
}

sub _schedule_drain ($self) {
	return if $self->{drain_pending};
	return unless $self->pending;

	my $widget = $self->{widget};
	return unless $widget;

	$self->{drain_pending} = 1;
	$widget->afterIdle(sub { $self->drain });
	return;
}

1;
