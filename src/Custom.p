# ---------------- User Customization ---------------

package ::;
use Modern::Perl;

sub setup_user_customization {
	my $filename = $file->user_customization();

	# effect aliases from .namarc
	for( keys %{$config->{alias}->{effect}} )
	{ my $longform = $config->{alias}->{effect}->{$_};
		 if(effect_index($longform))
			{
				$fx_cache->{partial_label_to_full}->{$_} =
				$fx_cache->{partial_label_to_full}->{$longform}
			}
		 else 
			{ throw("$longform: effect not found, cannot create shortcut") 
			}
 	} 
	return unless -r $filename;
	say "reading user customization file $filename";
	my %custom;
	unless (%custom = do $filename) {
		say "couldn't parse $filename: $@\n" if $@;
		return;
	}
	logpkg('debug','customization :', sub{Dumper \%custom });
	my $prompt;
	{ no warnings 'redefine';
		*prompt = $custom{prompt} if $custom{prompt};
	}
	my @commands = keys %{ $custom{commands} };
	for my $cmd(@commands){
		#my $coderef = gen_coderef($cmd,$custom{commands}{$cmd}) or next;
		$text->{user_command}->{$cmd} = $custom{commands}{$cmd};
	}
	$config->{alias}   = $custom{aliases};
}

sub gen_coderef {
	my ($cmd,$code) = @_;
	my $coderef = eval "sub{ use feature ':5.10'; no warnings 'uninitialized'; $code }";
	say("couldn't parse command $cmd: $@"), return if $@;
	$coderef
}
1;

