$hash = { 
			defaults => { qx( cat defaults.yaml ) };
			grammar => 
			qx( perl -w emit_command_headers  )
			eval qx(cat grammar) or carp("Failed to generate grammar") 
		}
