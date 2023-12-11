command: set_current_effect
command: set_stepsize
command: set_jumpsize
command: set_parameter
command: cancel
cancel: /.+Escape/
foo: /./
set_current_effect: 'f' effect_id 'Enter' {::set_current_op($item{effect_id}) }
set_hotkey_mode: 'o' hotkey_mode { $::mode->{hotkey_mode} = $item{hotkey_mode} }
hotkey_mode: /[jmp]/
effect_id: lower_case_effect_id { $return = uc $item{lower_case_effect_id} }
lower_case_effect_id: /[a-z]+/
set_stepsize: 'm' digit          { ::set_stepsize( $item{digit})  }
set_stepsize: 'm-' digit         { ::set_stepsize(-$item{digit})  }
set_parameter: '=' value 'Enter' { ::set_stepsize( $item{value})  }
set_jumpsize: 't' value 'Enter' {$::config->{hotkey_playback_jumpsize_seconds} = $item{value}}
digit: /\d/
value: /[+-]?([\d_]+(\.\d*)?|\.\d+)([eE][+-]?\d+)?/
