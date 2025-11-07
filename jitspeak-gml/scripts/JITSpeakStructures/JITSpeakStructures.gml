function JITSpeakAssemblyBuilder() constructor {
	buffer = buffer_create(4, buffer_grow, 4)
	
	patchDepth = -1
	patchStack = []
	
	static emit = function(opcode, arg0 = 0, arg1 = 0, arg2 = 0, __dbgArg = undefined) {
		// These arguments are pretty much always types.
		// The exceptions are control flow instructions but those use a different code path.
		if(arg0 == VMArgType.WITH_MARKER || arg1 == VMArgType.WITH_MARKER) {
			jitspeak_throw("WITH_MARKER leaked into instruction")	
		}
		if JITSPEAK_VM_DEBUG {
			jitspeak_log($"{jitspeak_vm_opcode_to_string(opcode)} {jitspeak_vm_arg_to_string(arg0)}, {jitspeak_vm_arg_to_string(arg1)} {arg2}", __dbgArg ?? "", "|", jitspeak_find_compiler_trace())	
		}
		buffer_write(buffer, buffer_u32, (opcode << 24) | ((((arg1 << 4) & 0xf0) | (arg0 & 0xf)) << 16) | (arg2 & 0xffff))
	}
	
	static emitLarge = function(opcode, arg0 = 0, arg1 = 0, arg2 = 0, type = buffer_u32, largeArg = undefined) {
		if is_undefined(largeArg) {
			jitspeak_throw("Missing large argument")
		}
		var argString = undefined
		if JITSPEAK_VM_DEBUG {
            argString = JITSpeak.stringTable.lookup(largeArg);
			switch opcode {
				case VMOpcode.PUSH:
				case VMOpcode.PUSHGLB:
				case VMOpcode.PUSHLOC:
				case VMOpcode.PUSHBLTN:
				case VMOpcode.POP: argString = jitspeak_variable_get_name(largeArg); break;
                    
                    
                case VMOpcode.CALL: if arg0 == VMArgType.INT argString = script_get_name(largeArg); break;
			}
		}
		emit(opcode, arg0, arg1, arg2, argString ?? largeArg)
		buffer_write(buffer, type, largeArg)
	}
	
	static emitExt = function(extopcode) {
		emit(VMOpcode.BREAK, VMArgType.ERROR, VMArgType.ERROR, extopcode)	
	}
	
	static emitRValue = function(val, flags, kind) {
		emit(VMOpcode.PUSHI, VMArgType.ERROR, 0, kind)
		emit(VMOpcode.PUSHI, VMArgType.ERROR, 0, flags)
		emitLarge(VMOpcode.PUSH, VMArgType.LONG, 0, 0, buffer_u64, int64(val))
	}
	
	static emitSwap = function(swapType, numAbove, numBelow = numAbove) {
		emit(VMOpcode.DUP, swapType, 0, 0x8000 | ((numBelow & 0xf) << 11) | (numAbove & 0x7ff))
	}
	
	static emitPlaceholder = function() {
		if JITSPEAK_VM_DEBUG jitspeak_log("<jump placeholder>")
		buffer_write(buffer, buffer_u32, 0xDEADC0DE)
		return position() - 4
	}
	
	static emitJump = function(opcode, dest) {
		if JITSPEAK_VM_DEBUG jitspeak_log(jitspeak_vm_opcode_to_string(opcode), dest, "|", jitspeak_find_compiler_trace())
		buffer_write(buffer, buffer_u32, __formatJump(opcode, position(), dest))
	}
	
	static startPatching = function() {
		patchDepth++
		patchStack[patchDepth] = []
		return patchDepth
	}
	
	static addPatch = function(inst = undefined, index = -1) {
		array_push(patchStack[index == -1 ? patchDepth : index], { inst, pos: position() })
		emitPlaceholder()
	}
	
	static finishPatching = function(opcode, dest) {
		var patches = patchStack[patchDepth]
		var len = array_length(patches)
		for(var i = 0; i < len; i++) {
			var patch = patches[i]
			patchJump(patch.inst ?? opcode, patch.pos, dest)	
		}
		patchDepth--
	}
	
	static patchJump = function(opcode, pos, dest) {
		buffer_poke(buffer, pos, buffer_u32, __formatJump(opcode, pos, dest))
	}
	
	// only used to collapse useless conv instructions for now
	static peekTop = function(largeArgKind = undefined) {
		var pos = position()
		
		var largeArg = 0;
		if !is_undefined(largeArgKind) {
			pos -= buffer_sizeof(largeArgKind)
			largeArg = buffer_peek(buffer, pos, largeArgKind)
		}
		
		pos -= 4
		var top = buffer_peek(buffer, pos, buffer_u32)
		
		return {
			opcode: (top >> 24) & 0xff,
			arg0:   (top >> 16) & 0xf,
			arg1:   (top >> 20) & 0xf,
			arg2:   top & 0xffff,
			large:  largeArg
		}
		
	}
	
	static size = function() {
		return buffer_get_size(buffer)	
	}
	
	static position = function() {
		return buffer_tell(buffer)	
	}
	
	static free = function() {
		buffer_delete(buffer)	
	}
	
	static trim = function() {
		buffer_resize(buffer, buffer_get_used_size(buffer))	
	}
	
	static __formatJump = function(opcode, pos, dest) {
		return (opcode << 24) | (((dest - pos) / 4) & 0x7fffff)
	}
}

function JITSpeakStringTable() constructor {
	table = ds_map_create()
    ptrLookup = ds_map_create()
	
	static get = function(str) {
		var ref = table[? str]
		if is_undefined(ref) {
			ref = new RefString(str)
            ptrLookup[? int64(ref.get_ptr())] = str
			table[? str] = ref
		}
		return ref
	}
    
    static lookup = function(pointer) {
        return ptrLookup[? int64(pointer)]
    }
	
	static lookupAlwaysStr = function(pointer) {
		return lookup(pointer) ?? $"<missing string at {jitspeak_to_hex(pointer)}>"	
	}
	
	struct_set_from_hash(self, jitspeak_find_dispose(), function() {
		var strings = ds_map_values_to_array(table)
		var len = array_length(table)
		for(var i = 0; i < len; i++) {
			strings[i].free()	
		}
        ds_map_destroy(ptrLookup)
		ds_map_destroy(table)
	})
}

function JITSpeakStack(_stack = undefined, _size = 0) constructor {
	stack = _stack ?? ds_list_create()
	size = _size
	
	static peek = function() {
		return size > 0 ? stack[| size - 1] : jitspeak_throw("empty stack")	
	}
	
	static push = function(val) {
		if JITSPEAK_STACK_DEBUG {
			jitspeak_log("push", jitspeak_vm_arg_to_string(val), __asDebugArray(), jitspeak_find_compiler_trace())	
		}
		stack[| size++] = val	
	}
	
	static pop = function(count = 1, get = false) {
		if size < 1 {
			jitspeak_throw("empty stack")
		}
		else if size < count {
			jitspeak_throw($"stack too small (popping {count} elements, but only contains {size})")	
		}
		size -= count
		
		if JITSPEAK_STACK_DEBUG {
			jitspeak_log("pop", count, "value(s)", jitspeak_find_compiler_trace())
			
			var popped = array_create(count)
			for(var i = 0; i < count; i++) {
				popped[@ i] = jitspeak_vm_arg_to_string(stack[| size + i])
			}
			
			jitspeak_log("popped:   ", popped)
			jitspeak_log("remaining:", __asDebugArray())
		}
		
		if get {
			if count == 1 {
				return stack[| size]	
			}
			
			var out = array_create(count)
			for(var i = 0; i < count; i++) {
				out[@ i] = stack[| size + i]	
			}
			return out
		}
	}
	
	static set = function(val, index = size - 1) {
		if JITSPEAK_STACK_DEBUG {
			jitspeak_log("set", jitspeak_vm_arg_to_string(val), __asDebugArray(), jitspeak_find_compiler_trace())	
		}
		stack[| index] = val
	}
	
	static clear = function() {
		size = 0
	}
	
	static __asDebugArray = function() {
		var contents = array_create(size)
		for(var i = 0; i < size; i++) {
			contents[@ size - i - 1] = jitspeak_vm_arg_to_string(stack[| i])
		}
		return contents
	}
	
	
	static clone = function() {
		var clone = ds_list_create()
		ds_list_copy(clone, stack)
		return new JITSpeakStack(clone, size)
	}
	
    // This is like bad.
	struct_set_from_hash(self, jitspeak_find_dispose(), function() {
		ds_list_destroy(stack)
	})
}

function JITSpeakLoopContext(loopStart, patchIndex, withIndex = -1) constructor {
    self.loopStart = loopStart
    self.patchIndex = patchIndex
    self.withIndex = withIndex
}

// Makes it easier to see when debugging the runtime.
function JITSpeakGlobals() constructor {}