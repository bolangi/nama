command: set_current_effect
command: set_stepsize
command: set_parameter
command: cancel
cancel: /.+Escape/
foo: /./
set_current_effect: 'f' effect_id 'Enter' {::set_current_op($item{effect_id}) }
effect_id: lower_case_effect_id { $return = uc $item{lower_case_effect_id} }
lower_case_effect_id: /[a-z]+/
set_stepsize: 't' digit  { ::set_current_stepsize(10**$item{digit})}
set_stepsize: 't-' digit { ::set_current_stepsize(10**-$item{digit})}
set_parameter: 'p' value 'Enter' {::set_parameter($item{value})}
digit: /\d/
value: /[+-]?([\d_]+(\.\d*)?|\.\d+)([eE][+-]?\d+)?/
