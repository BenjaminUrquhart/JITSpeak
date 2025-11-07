function jitspeak_method_lookup(name) {
	return method(undefined, jitspeak_method_lookup_index(name))
}

function jitspeak_method_lookup_index(name) {
	static funcs = undefined;
	
	if is_undefined(funcs) {
		funcs = ds_map_create()
		
		var index = 0
		while true {
			var n = script_get_name(index)
			
			if string_pos("<", n) break;
			
			funcs[? n] = index
			index++
		}
	}
	return funcs[? name]
}

function jitspeak_str_to_buff(str) {
	static cache = ds_map_create()
	
	if ds_map_exists(cache, str) {
		return cache[? str]
	}
	
	var len = string_byte_length(str)
	var buff = buffer_create(len + 1, buffer_fixed, 1)
	buffer_write(buff, buffer_string, str)
	
	cache[? str] = buff
	
	return buff
}

function jitspeak_find_dispose() {
	
	// This is stupid
	
	static hash = -1
	static ref = ref_create(self, "@@Dispose@@")
	
	if hash == -1 {	
		var test_hash = 100000
		var test = {}
		
		// Listen it's gotta be in there somewhere
		while true {
			struct_set_from_hash(test, test_hash, undefined)
			var names = struct_get_names(test)
			struct_remove_from_hash(test, test_hash)
			
			if array_length(names) > 0 && names[0] == "@@Dispose@@" {
				hash = test_hash
				break
			}
			test_hash++
		}
	}
	
	return hash
}

function jitspeak_unimplemented(thing) {
	jitspeak_throw("Unimplemented: " + string(thing))
}

function jitspeak_throw(msg) {
	throw {
		message: msg,
		stacktrace: debug_get_callstack()
	}
}

function jitspeak_log() {
	if argument_count > 0 {
		var out = "[JITSpeak]: "
		for(var i = 0; i < argument_count; i++) {
			out += string(argument[i])
			if i != argument_count - 1 {
				out += " "	
			}
		}
		show_debug_message(out)
	}
	else {
		show_debug_message("[JITSpeak]: <no log message provided>")	
	}
}

function jitspeak_parse_runtime_version() {
	static version = undefined
	
	if is_undefined(version) {
		var str = GM_runtime_version
		var fields = array_create(4, 0)
		var index = 0
		
		var pos = string_pos(".", str)
		do {
			fields[index++] = real(pos ? string_copy(str, 1, pos) : str)
			if !pos break;
			
			str = string_delete(str, 1, pos)
			pos = string_pos(".", str)
		} until(!string_byte_length(str))
		
		// idk if this is the versioning scheme
		version = {
			major: fields[0],
			minor: fields[1],
			revision: fields[2],
			build: fields[3],
			
			toString: function() {
				return $"{major}.{minor}.{revision}.{build}"	
			}
		}
	}
	return version
}

function jitspeak_runtime_is_at_least(major, minor, revision, build) {
	static version = jitspeak_parse_runtime_version()
	
	if version.major > major {
		return true	
	}
	else if version.major == major {
		var minor_ok = false
		
		// This fails for LTS betas but at that point just use monthly/regular beta?
		var is_beta = version.minor >= 100
		var check_beta = minor >= 100
		
		if is_beta == check_beta {
			minor_ok = version.minor >= minor
		}
		else if is_beta {
			minor_ok = floor(version.minor / 100) >= minor
		}
		else if check_beta {
			minor_ok = version.minor > floor(minor / 100)	
		}
		
		if minor_ok {
			return version.revision >= revision && version.build >= build	
		}
	}
	
	return false
}

function jitspeak_to_hex(data) {
	var as_ptr = ptr(data)
	return as_ptr == pointer_null ? "0000000000000000" : string(as_ptr)
}

function jitspeak_double_as_bytes(num) {
	return jitspeak_convert(num, buffer_f64, buffer_u64)
}

function jitspeak_int32(num) {
	return jitspeak_convert(int64(num), buffer_u64, buffer_s32)
}

function jitspeak_convert(val, from, to) {
	static conv = buffer_create(8, buffer_fixed, 1)
	buffer_poke(conv, 0, from, val)
	return buffer_peek(conv, 0, to)
}

function jitspeak_struct_merge(dst, src) {
	var names = struct_get_names(src)
	var len = struct_names_count(src)
	for(var i = 0; i < len; i++) {
		dst[$ names[i]] = src[$ names[i]]	
	}
}

function jitspeak_variable_get_name(hash) {
	static dummy = {}
	
	try {
		hash &= 0xffffff
		struct_set_from_hash(dummy, hash, 0)
		var names = struct_get_names(dummy)
		return array_length(names) ? names[0] : undefined
	}
	finally {
		struct_remove_from_hash(dummy, hash)
	}
}

function jitspeak_expression_debug_string(expr) {
	var out = {}
	
	var names = variable_struct_get_names(expr)
	var len = array_length(names)
	for(var i = 0; i < len; i++) {
		var val = expr[$ names[i]]
		if names[i] == "dbg" {
			continue;	
		}
		else if names[i] == "type" {
			out[$ names[i]] = jitspeak_catspeak_term_to_string(val)
		}
		else if is_struct(val) {
			out[$ names[i]] = jitspeak_catspeak_term_to_string(val.type)
		}
		else if is_array(val) {
			var arrLen = array_length(val)
			var arr = array_create(arrLen)
			for(var j = 0; j < arrLen; j++) {
				arr[j] = is_array(val[j]) ? val[j] : jitspeak_catspeak_term_to_string(val[j].type)
			}
			out[$ names[i]] = arr
		}
		else {
			out[$ names[i]] = val
		}
	}
	
	return string(out)
}

function jitspeak_find_compiler_trace() {
	var stack = debug_get_callstack()
	var len = array_length(stack)
	for(var i = 0; i < len; i++) {
		if is_string(stack[i]) && string_pos("compileExpression", stack[i]) {
			return stack[i]
		}
	}
	return "<no trace>"
}

function jitspeak_disassemble(buffer) {
	
	static buffer_read_vmtype = function(buffer, type) {
		switch type {
			case VMArgType.DOUBLE: return buffer_read(buffer, buffer_f64)
			case VMArgType.FLOAT:  return buffer_read(buffer, buffer_f32)
			
			case VMArgType.BOOL:
			case VMArgType.INT:    return buffer_read(buffer, buffer_s32)
			
			case VMArgType.LONG:   return buffer_read(buffer, buffer_u64)
			case VMArgType.STRING: return JITSpeak.stringTable.lookupAlwaysStr(buffer_read(buffer, buffer_u64))
		}
	}
	
	var blocks = ds_list_create()
	var len = buffer_get_size(buffer)
	
	buffer_seek(buffer, buffer_seek_start, 0)
	while buffer_tell(buffer) < len {
		var pos = buffer_tell(buffer)
		if ds_list_find_index(blocks, pos) != -1 {
			show_debug_message("")
		}
		
		var inst = buffer_read(buffer, buffer_u32)
		
		var opcode = inst >> 24
		var arg0 = (inst >> 16) & 0xf
		var arg1 = (inst >> 20) & 0xf
		var arg2 = jitspeak_convert(inst & 0xffff, buffer_u64, buffer_s16)
		
		var opStr = "???"
		
		// fallthroughs are intentional
		switch opcode {
			
			case VMOpcode.POPENV: {
				if arg0 == VMArgType.ERROR && arg1 == VMArgType.DOUBLE {
					opStr = string_lower(jitspeak_vm_opcode_to_string(opcode)) + " <drop>"
					break
				}
			}
			
			case VMOpcode.B:
			case VMOpcode.BT:
			case VMOpcode.BF:
			case VMOpcode.PUSHENV: {
				var dest = pos + (inst & 0x7fffff) * 4
				opStr = string_lower($"{jitspeak_vm_opcode_to_string(opcode)} {dest}")
				ds_list_add(blocks, buffer_tell(buffer))
				ds_list_add(blocks, dest)
			} break;
			
			
			default: {
				var largeArg = ""
				var arg2Formatted = ""
				
				switch opcode {
					case VMOpcode.PUSH: {
						if arg0 != VMArgType.VARIABLE {
							largeArg = buffer_read_vmtype(buffer, arg1 == VMArgType.STRING ? arg1 : arg0)
							break
						}
					}
					
					case VMOpcode.POP:
					case VMOpcode.PUSHLOC: 
					case VMOpcode.PUSHBLTN: largeArg = $"{string_lower(jitspeak_vm_obj_to_string(arg2))}.{jitspeak_variable_get_name(buffer_read(buffer, buffer_u32))}"; break;
					
					case VMOpcode.CALL: {
						var func = buffer_read(buffer, buffer_u32)
						
						if arg0 == VMArgType.INT {
							arg2Formatted = script_get_name(func)
						}
						else {
							arg2Formatted = "[stacktop]"	
						}
						arg2Formatted += $"(argc={arg2})"
					} break;
					
					
					default : arg2Formatted = string(arg2) + " "
				}
				
				opStr = string_lower($"{jitspeak_vm_opcode_to_string(opcode)}.{jitspeak_vm_arg_to_chr(arg0)}.{jitspeak_vm_arg_to_chr(arg1)} ") + $"{arg2Formatted}{largeArg}"
			} break;
		
			}
		
			show_debug_message($"[{pos}]: {opStr}")
	}
	
	ds_list_destroy(blocks)
}

function jitspeak_vm_obj_to_string(obj) {
	// TODO
	return object_exists(obj) ? object_get_name(obj) : string(obj)
}

// JITSpeak functions don't have indexes (scary), so this function is a wrapper around
// them so they work correctly with catspeak_get_index (and by extension, catspeak_execute_ext).
function __catspeak_jitspeak_wrapper__() {
	/*
	static getSelf = function() { return native.getSelf() }
	static setSelf = function(newSelf) { native.setSelf(newSelf) }
	
	static getGlobals = function() { return native.getGlobals() }
	static setGlobals = function(newGlobals) { native.setGlobals(newSelf) }
	*/
	
	var args = array_create(argument_count)
	for(var i = 0; i < argument_count; i++) {
		args[@ i] = argument[i]
	}
	
	return __catspeak_script_execute_ext_fixed(native, args)
}

// The following functions were (mostly) automatically generated
function jitspeak_catspeak_term_to_string(term) {
	switch term {
	case CatspeakTerm.VALUE: return "VALUE";
	case CatspeakTerm.ARRAY: return "ARRAY";
	case CatspeakTerm.STRUCT: return "STRUCT";
	case CatspeakTerm.BLOCK: return "BLOCK";
	case CatspeakTerm.IF: return "IF";
	case CatspeakTerm.AND: return "AND";
	case CatspeakTerm.OR: return "OR";
	case CatspeakTerm.LOOP: return "LOOP";
	case CatspeakTerm.WITH: return "WITH";
	case CatspeakTerm.MATCH: return "MATCH";
	case CatspeakTerm.USE: return "USE";
	case CatspeakTerm.RETURN: return "RETURN";
	case CatspeakTerm.BREAK: return "BREAK";
	case CatspeakTerm.CONTINUE: return "CONTINUE";
	case CatspeakTerm.THROW: return "THROW";
	case CatspeakTerm.OP_BINARY: return "OP_BINARY";
	case CatspeakTerm.OP_UNARY: return "OP_UNARY";
	case CatspeakTerm.CALL: return "CALL";
	case CatspeakTerm.CALL_NEW: return "CALL_NEW";
	case CatspeakTerm.SET: return "SET";
	case CatspeakTerm.INDEX: return "INDEX";
	case CatspeakTerm.PROPERTY: return "PROPERTY";
	case CatspeakTerm.LOCAL: return "LOCAL";
	case CatspeakTerm.GLOBAL: return "GLOBAL";
	case CatspeakTerm.FUNCTION: return "FUNCTION";
	case CatspeakTerm.PARAMS: return "PARAMS";
	case CatspeakTerm.PARAMS_COUNT: return "PARAMS_COUNT";
	case CatspeakTerm.SELF: return "SELF";
	case CatspeakTerm.OTHER: return "OTHER";
	case CatspeakTerm.CATCH: return "CATCH";
	default: return "UNKNOWN_" + string(term);
	}
}

function jitspeak_vm_arg_to_string(arg) {
	switch arg {
	case VMArgType.DOUBLE: return "DOUBLE";
	case VMArgType.FLOAT: return "FLOAT";
	case VMArgType.INT: return "INT";
	case VMArgType.LONG: return "LONG";
	case VMArgType.BOOL: return "BOOL";
	case VMArgType.VARIABLE: return "VARIABLE";
	case VMArgType.STRING: return "STRING";
	case VMArgType.STRING_PATCH: return "STRING_PATCH";
	case VMArgType.DELETE: return "DELETE";
	case VMArgType.UNDEFINED: return "UNDEFINED";
	case VMArgType.PTR: return "PTR";
	case VMArgType.ERROR: return "ERROR";
	case VMArgType.WITH_MARKER: return "WITH_MARKER";
	default: return "UNKNOWN_" + string(arg);
	}
}

function jitspeak_vm_arg_to_chr(arg) {
	return string_char_at(jitspeak_vm_arg_to_string(arg), 1)
}

function jitspeak_vm_opcode_to_string(opcode) {
	switch opcode {
	case VMOpcode.CONV: return "CONV";
	case VMOpcode.MUL: return "MUL";
	case VMOpcode.DIV: return "DIV";
	case VMOpcode.REM: return "REM";
	case VMOpcode.MOD: return "MOD";
	case VMOpcode.ADD: return "ADD";
	case VMOpcode.SUB: return "SUB";
	case VMOpcode.AND: return "AND";
	case VMOpcode.OR: return "OR";
	case VMOpcode.XOR: return "XOR";
	case VMOpcode.NEG: return "NEG";
	case VMOpcode.NOT: return "NOT";
	case VMOpcode.SHL: return "SHL";
	case VMOpcode.SHR: return "SHR";
	case VMOpcode.CMP: return "CMP";
	case VMOpcode.POP: return "POP";
	case VMOpcode.DUP: return "DUP";
	case VMOpcode.RET: return "RET";
	case VMOpcode.EXIT: return "EXIT";
	case VMOpcode.POPZ: return "POPZ";
	case VMOpcode.B: return "B";
	case VMOpcode.BT: return "BT";
	case VMOpcode.BF: return "BF";
	case VMOpcode.PUSHENV: return "PUSHENV";
	case VMOpcode.POPENV: return "POPENV";
	case VMOpcode.PUSH: return "PUSH";
	case VMOpcode.PUSHLOC: return "PUSHLOC";
	case VMOpcode.PUSHGLB: return "PUSHGLB";
	case VMOpcode.PUSHBLTN: return "PUSHBLTN";
	case VMOpcode.PUSHI: return "PUSHI";
	case VMOpcode.CALL: return "CALL";
	case VMOpcode.CALLV: return "CALLV";
	case VMOpcode.BREAK: return "BREAK";
	default: return "UNKNOWN_" + string(opcode);
	}
}