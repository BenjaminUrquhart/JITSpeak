// TODO: inline these so there's no function call overhead

function jitspeak_get_index_helper(container, key) {
	//show_debug_message($"{container} {key}")
	if is_array(container) {
		return container[key]	
	}
	else if is_struct(container) || is_method(container) || typeof(container) == "struct" /* don't ask */ {
		return container[$ key]	
	}
	jitspeak_throw($"type {typeof(container)} ({container}) is not indexable (attempting to use key {key})")	
}

function jitspeak_set_index_helper(container, key, value) {
	//show_debug_message($"{container} {key} {value}")
	if is_array(container) {
		container[@ key] = value
	}
	else if is_struct(container) || is_method(container) {
		 container[$ key] = value
	}
	else {
		jitspeak_throw($"type {typeof(container)} ({container}) is not indexable (attempting to set key {key} to {value})")	
	}
}

function jitspeak_validate_function(func) {
	if is_method(func) {
		return func	
	}
	jitspeak_throw($"{func} is not a function")
}