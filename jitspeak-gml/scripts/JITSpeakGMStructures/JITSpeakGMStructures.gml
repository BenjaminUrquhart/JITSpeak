// Thank you YYC headers

function RefThing(thing_ptr, refcount = 0x7f000000, _size = 0) constructor {
	buffer = buffer_create(0x10, buffer_fixed, 1)
	buffer_poke(buffer, 0x00, buffer_u64, int64(thing_ptr))
	buffer_poke(buffer, 0x08, buffer_u32, refcount)
	buffer_poke(buffer, 0x0c, buffer_u32, _size)
	
	static get_ptr = function() {
		return buffer_get_address(buffer)	
	}
	
	static thing = function() {
		return ptr(buffer_peek(buffer, 0x00, buffer_u64))	
	}
	
	static ref_count = function() {
		return buffer_peek(buffer, 0x08, buffer_u32)
	}
	
	static size = function() {
		return buffer_peek(buffer, 0x0c, buffer_u32)
	}
	
	static free = function() {
		buffer_delete(buffer)	
	}
}

function RefString(str) : RefThing(pointer_null, 0x7f000000, string_byte_length(str)) constructor {
	str_buffer = jitspeak_str_to_buff(str)
	buffer_poke(buffer, 0x00, buffer_u64, int64(buffer_get_address(str_buffer)))
	
	static thing = function() {
		return toString()	
	}
	
	static toString = function() {
		return buffer_peek(str_buffer, 0, buffer_string)
	}
}

function RValue(_val, _flags = 0, _type = RValueKind.UNSET) constructor {
	buffer = buffer_create(0x10, buffer_fixed, 1)
	string_ref = undefined
	
	if is_ptr(_val) {
		_val = int64(_val)
	}
	else if is_struct(_val) {
		_val = int64(ptr(_val))	
	}
	else if is_string(_val) {
		string_ref = new RefString(_val)
		_val = int64(string_ref.get_ptr())
	}
	
	buffer_write(buffer, buffer_u64, _val)
	buffer_write(buffer, buffer_u32, _flags)
	buffer_write(buffer, buffer_u32, _type)
	
	static value = function() {
		return buffer_peek(buffer, 0x00, buffer_u64)
	}
	
	static flags = function() {
		return buffer_peek(buffer, 0x08, buffer_u32)	
	}
	
	static type = function() {
		return buffer_peek(buffer, 0x0c, buffer_u32)	
	}
	
	static get_ptr = function() {
		return buffer_get_address(buffer)	
	}
	
	static free = function() {
		buffer_delete(buffer)
		buffer = undefined
		
		if !is_undefined(string_ref) {
			string_ref.free()	
		}
	}
	
	static toString = function() {
		return $"{jitspeak_to_hex(value())} (flags={flags()}, type={type()})"
	}
}

