command : set_current_effect
foo: /./
set_current_effect: effect_id '<Enter>' {::set_current_op($item{effect_id}) }
effect_id: lower_case_effect_id { $return = uc $item{lower_case_effect_id} }
lower_case_effect_id: /[a-z]+/
