command: set_current_effect
command: set_stepsize
command: set_jumpsize
command: set_parameter
command: cancel
cancel: /.+Escape/
foo: /./
set_current_effect: 'f' effect_id 'Enter' {::set_current_op($item{effect_id}) }
effect_id: lower_case_effect_id { $return = uc $item{lower_case_effect_id} }
lower_case_effect_id: /[a-z]+/
set_stepsize: 'm' digit  { ::set_current_stepsize(10**$item{digit})}
set_stepsize: 'm-' digit { ::set_current_stepsize(10**-$item{digit})}
set_parameter: '=' value 'Enter' {::set_parameter_value($item{value})}
set_jumpsize: 'j' value 'Enter' {$::text->{hotkey_playback_jumpsize} = $item{value}}
digit: /\d/
value: /[+-]?([\d_]+(\.\d*)?|\.\d+)([eE][+-]?\d+)?/
