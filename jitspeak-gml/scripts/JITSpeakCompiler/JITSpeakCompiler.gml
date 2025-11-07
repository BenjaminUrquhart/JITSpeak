/// Simple wrapper to interface with Catspeak's existing codegen API.
/// You may use this by setting the `codegenType` variable of your Catspeak environment.
///
/// For example, the following code will make the default Catspeak environment use the JITSpeak compiler:
/// 
/// `Catspeak.codegenType = JITSpeakCompilerWrapper`
/// 
/// @param {Struct.CatspeakIR} ir
/// @param {Struct.CatspeakForeignInterface} interface
function JITSpeakCompilerWrapper(ir, interface = Catspeak.interface) : JITSpeakCompiler(interface) constructor {
	self.ir = ir
	
	static update = function() {
		return compile(ir)
	}
}

#macro CREATE_HASH variable_get_hash(
#macro NOARR ) | 0x80000000 | 0x20000000
#macro ASARR ) | 0x20000000


/// A mostly-complete implementation of a transpiler from Catspeak IR to Gamemaker VM bytecode.
function JITSpeakCompiler(catspeakInterface = Catspeak.interface, configuration = new JITSpeakCompilerConfig()) constructor {
	interface = catspeakInterface
	config = configuration
	
	context = undefined
    
    if JITSPEAK_DEBUG || JITSPEAK_VM_DEBUG {
        // Do this so VM tracing doesn't show the spam from creating the interface the first time.
        static __gmlInterface = __catspeak_get_gml_interface()
    }
	
	static implicitRetVar = CREATE_HASH "$$implicit_return_container$$" NOARR
    
    static localInterfaceVar = CREATE_HASH "$$interface$$" NOARR
    static localFunctionsVar = CREATE_HASH "$$funcs$$"  ASARR
	
    static localGlobalVar    = CREATE_HASH "$$global$$" NOARR  
    static tempvar           = CREATE_HASH "$$$temp$$$" NOARR
	
	/// Takes a Catspeak IR struct, and compiles it into a native Gamemaker method.
	/// 
	/// @param {Struct.CatspeakIR} ir The Catspeak IR to compile.
	// 
	/// @return {Function} The native Gamemaker method object representing the IR.
	static compile = function(ir) {
		
		if JITSPEAK_DEBUG || JITSPEAK_VM_DEBUG show_debug_message(json_stringify(ir, true))
		
		var ir_functions = ir.functions
		var count = array_length(ir_functions)
		var out = array_create(count)
	
		context = {
			argCount: 0,
			usesTempVar: false,
			implicitReturn: false,
			keepRetOnStack: false,
			
			stack: new JITSpeakStack(),
			stackStack : ds_stack_create(),
			save: function() { ds_stack_push(stackStack, stack.clone()) },
			load: function() { stack = ds_stack_pop(stackStack) },
			
			loadVerify: function(tolerance = 0) {
				var size = stack.size
				var oldStack = stack
				load()
				
				var diff = size - stack.size
				if diff > tolerance || diff < 0 {
					if tolerance {
						jitspeak_throw($"stack size mismatch: {size} is outside expected range [{stack.size}, {stack.size + tolerance}]")
					}
					else {
						jitspeak_throw($"stack size mismatch: expected {stack.size} got {size}")	
					}
				}
				return { diff, ret: diff ? oldStack.pop(diff, true) : [] }
			},
			
			loopStack: ds_stack_create(),
			stackTopType: function() { return stack.peek() },
			functions: array_create(count),
			didReturn: false,
			withCount: 0,
			globals: new JITSpeakGlobals(),
			doConv: false,
			varOp: JITSpeakVarOp.GET,
			
			reset: function() {
				withCount = 0
				didReturn = false
				usesTempVar = false
				implicitReturn = false
				keepRetOnStack = false
				
				stack.clear()
				ds_stack_clear(loopStack)
				ds_stack_clear(stackStack)
			}
		}
		
		jitspeak_struct_merge(context.globals, interface.database)
		
		if is_undefined(ir.filepath) {
			context.filepath = "jitspeak_native_"
		}
		else {
			context.filepath = ir.filepath + "-"
		}
	
		for(var i = 0; i < count; i++) {
			if JITSPEAK_DEBUG jitspeak_log("-----------------------------------------")
			out[@ i] = __compileFunction(ir_functions[i])
			
			if JITSPEAK_VM_DEBUG {
				with out[i] {
					jitspeak_disassemble(code)
				}
			}
		}
		
		if JITSPEAK_DEBUG jitspeak_log("-----------------------------------------")
		
		ds_stack_destroy(context.stackStack)
		ds_stack_destroy(context.loopStack)
		
		/*
		if config.allowCatspeakIndexing {
			// Ensure static struct is initialized
			with { native: function() {} } {
				__catspeak_jitspeak_wrapper__()	
			}
		}*/
		
		// Create native representations now to avoid unnecessary
		// cleanup if there was a transpiler error.
		for(var i = 0; i < count; i++) {
			var native = out[i].getNative()
			if  config.allowCatspeakIndexing {
				context.functions[@ i] = method({ native }, __catspeak_jitspeak_wrapper__)
				jitspeak_struct_merge(context.functions[@ i], native)
			}
			else {
				context.functions[@ i] = native
			}
			
		}
	
		return context.functions[ir.entryPoints[0]]
	}
	
	static __compileFunction = function(ir) {
		var builder = new JITSpeakAssemblyBuilder()
		var block = ir.root
	
		try {
			context.reset()
			context.argCount = ir.argCount
			__compileExpression(block, builder)
			
			if JITSPEAK_DEBUG || JITSPEAK_STACK_DEBUG {
				jitspeak_log("exited entry with", context.stack.size, "value(s) on the stack", context.stack.__asDebugArray())
				jitspeak_log("did return:", context.didReturn, "implicit return:", context.implicitReturn)
			}
			if !context.didReturn {
                var retType = VMArgType.VARIABLE
				if context.stack.size {
                    if context.stack.size > 1 {
                        // Like 70% sure the VM automatically discards extra values
                        if JITSPEAK_DEBUG || JITSPEAK_STACK_DEBUG jitspeak_log("Warning: implicit return with more than 1 value on the stack")
                    }
                    // What's the point of ret taking a type argument if everything else
                    // assumes it's always variable type smh.
                    
					//retType = context.stack.peek()
                    __doConv(builder, VMArgType.VARIABLE)
				}
				else if context.implicitReturn {
					// Need to do it this way so the stack is manageable
					builder.emitLarge(VMOpcode.PUSHLOC, VMArgType.VARIABLE, VMArgType.VARIABLE, -7, buffer_u32, implicitRetVar)
				}
				else {
					// Manually return undefined.
					// There's probably a better way to do this.
					__emitValue(undefined, builder)
				}
				builder.emit(VMOpcode.RET, retType)
			}
			builder.trim()
			
			var statics = {}
			struct_set_from_hash(statics, localGlobalVar & 0xffffff, context.globals)
			struct_set_from_hash(statics, localInterfaceVar & 0xffffff, interface)
			struct_set_from_hash(statics, localFunctionsVar & 0xffffff, context.functions)
			
			var wrapper = new JITSpeakNativeWrapper(context.filepath + buffer_md5(builder.buffer, 0, builder.size()), builder.buffer)
			wrapper.setArgumentCount(ir.argCount)
			
			wrapper.setLocalCount(ir.localCount + context.usesTempVar + context.implicitReturn)
			wrapper.setContext({ 
				globals: context.globals, 
				functions: context.functions,
				interface,
				statics,
				wrapper
			})
			
			if JITSPEAK_VM_DEBUG {
				jitspeak_log("Function name:", wrapper.__nameString)
			}
			
			return wrapper
		}
		catch(e) {
			show_debug_message(e.message)
			array_foreach(e.stacktrace, show_debug_message)
			
			throw e
		}
		finally {
			builder.free()
			builder = undefined
		}
	}
	
	// Welcome to one of the state machines of all time
	static __compileExpression = function(expr, builder, overrides = undefined, bareCall = false) {
        static NewGMLObject = jitspeak_method_lookup("@@NewGMLObject@@")
		static NewGMLArray = jitspeak_method_lookup("@@NewGMLArray@@")
		static NewObject = jitspeak_method_lookup("@@NewObject@@")
		static GetOther = jitspeak_method_lookup("@@Other@@")
		static GetSelf = jitspeak_method_lookup("@@This@@")
		
		var oldCtx;
		context.didReturn = false
		context.implicitReturn = false
		if !is_undefined(overrides) {
			oldCtx = {}
			var names = struct_get_names(overrides)
			var len = struct_names_count(overrides)
			for(var i = 0; i < len; i++) {
				oldCtx[$ names[i]] = context[$ names[i]]	
			}
			jitspeak_struct_merge(context, overrides)
		}
	
		if JITSPEAK_DEBUG jitspeak_log(jitspeak_expression_debug_string(expr))
		switch expr.type {
		case CatspeakTerm.VALUE:  __emitValue(expr.value, builder); break; 
		case CatspeakTerm.ARRAY:  __emitCall(NewGMLArray, expr.values, builder);  break;
		case CatspeakTerm.STRUCT: __emitCall(NewObject, expr.values, builder); break;
		
		case CatspeakTerm.BLOCK: {
			if JITSPEAK_DEBUG || JITSPEAK_VM_DEBUG show_debug_message("-------------------- BLOCK -------------------")
			var len = array_length(expr.terms)
			var sizeStart = context.stack.size
			var keepRetOnStack = context.keepRetOnStack
			
			// If a block ends with a break or continue, their value will override
			// the implicit return functionality anyway, so we can safely pop from
			// the stack regardless of the context.
			
			var lastType = expr.terms[len - 1].type
			if lastType == CatspeakTerm.BREAK || lastType == CatspeakTerm.CONTINUE {
				keepRetOnStack = false
			}
			
			for(var i = 0; i < len; i++) {
				var term = expr.terms[i]
				var sizeOnEntry = context.stack.size
				__compileExpression(term, builder, overrides, false)
				
				if JITSPEAK_STACK_DEBUG jitspeak_log("### entered:", sizeOnEntry, "exited:", context.stack.size)
				
				// Statements should push at most 1 value or pop at most 1 value.
				// If this triggers I've done something wrong.
				// (Function arguments do not use this codepath).
				if abs(context.stack.size - sizeOnEntry) > 1 {
					jitspeak_throw($"Statement made illegal changes to stack (on enter: {sizeOnEntry}, on exit: {context.stack.size}): {jitspeak_expression_debug_string(term)}")
				}
				
				if !keepRetOnStack && context.stack.size > sizeStart {
					__doConv(builder, VMArgType.VARIABLE)
					if i == len - 1 {
						// Implicit return
						builder.emitLarge(VMOpcode.POP, VMArgType.VARIABLE, VMArgType.VARIABLE, -7, buffer_u32, implicitRetVar)
						context.implicitReturn = true
						context.stack.pop()
					}
					if context.stack.size > sizeStart {
						// Statement left garbage on stack, pop it all off
						repeat(context.stack.size - sizeStart) {
							builder.emit(VMOpcode.POPZ, context.stack.pop(1, true))
						}
					}
				}
			}
			
			if JITSPEAK_DEBUG || JITSPEAK_VM_DEBUG show_debug_message("--------------------  END  -------------------")

		} break;
		
		case CatspeakTerm.IF: {
			
			builder.startPatching()
			
			var ctxSizeStart = context.stack.size
			
			context.keepRetOnStack = true
			__compileExpression(expr.condition, builder, { varOp: JITSpeakVarOp.GET })
			__doConv(builder, VMArgType.BOOL)
			context.stack.pop()
			builder.addPatch()
			
			var numRet = 0, maxRet = 1
			
			context.save()
			context.keepRetOnStack = true
			__compileExpression(expr.ifTrue, builder)
			var retTrue = context.loadVerify(1), retFalse = undefined
			if retTrue.diff {
				context.stack.push(retTrue.ret)
				__doConv(builder, VMArgType.VARIABLE)
			}
			else if !context.didReturn {
				__emitValue(undefined, builder, false)
			}
			else {
				numRet++
			}
			
			var patchDest = builder.position()
			
			if !is_undefined(expr.ifFalse) {
				maxRet = 2
				context.stack.pop() // only 1 value is gonna be available, don't double-push
				builder.startPatching()
				builder.addPatch()
				patchDest = builder.position()
				context.save()
				context.keepRetOnStack = true
				__compileExpression(expr.ifFalse, builder)
				retFalse = context.loadVerify(1)
				if retFalse.diff {
					context.stack.push(retFalse.ret)
					__doConv(builder, VMArgType.VARIABLE)
				}
				else if !context.didReturn {
					__emitValue(undefined, builder, false)
				}
				else {
					numRet++	
				}
				builder.finishPatching(VMOpcode.B, builder.position())
			}
			else {
				numRet++	
			}
			
			builder.finishPatching(VMOpcode.BF, patchDest)
			
			// man idk
			if ctxSizeStart == context.stack.size && numRet < maxRet {
				context.stack.push(VMArgType.VARIABLE)
			}	
			context.keepRetOnStack = false
		} break;
		
		case CatspeakTerm.AND: 
		case CatspeakTerm.OR:  __emitBinaryOp(expr, builder); break;
		
		case CatspeakTerm.LOOP: {
			
			if !is_undefined(expr.postCondition) {
				jitspeak_unimplemented("Loops with post-conditions")
			}
			
			if !is_undefined(expr.step) {
				jitspeak_unimplemented("Loops with steps")
			}
			
			var loopStart = builder.position()
			ds_stack_push(context.loopStack, new JITSpeakLoopContext(loopStart, builder.startPatching()))
			
			context.save()
			__compileExpression(expr.preCondition, builder, { varOp : JITSpeakVarOp.GET })
			__doConv(builder, VMArgType.BOOL)
			context.stack.pop()
			context.loadVerify()
			builder.addPatch()
			
			context.save()
			__compileExpression(expr.body, builder, { keepRetOnStack : true })
			var ret = context.loadVerify(1)
			if ret.diff {
				context.stack.push(ret.ret)
			}
			
			builder.emitJump(VMOpcode.B, loopStart)
			builder.finishPatching(VMOpcode.BF, builder.position())
			
			ds_stack_pop(context.loopStack)
			
		} break;
		
		case CatspeakTerm.WITH: {
			__compileExpression(expr.scope, builder, { varOp: JITSpeakVarOp.GET })
			if context.stackTopType() == VMArgType.VARIABLE {
				builder.emit(VMOpcode.PUSHI, VMArgType.ERROR, 0, -9)
			}
			else {
				__doConv(builder, VMArgType.INT)	
			}
			
			context.withCount++
			context.stack.set(VMArgType.WITH_MARKER)
			var patchIndex = builder.startPatching()
			builder.addPatch()
			
			context.keepRetOnStack = false
			var loopStart = builder.position()
			ds_stack_push(context.loopStack, new JITSpeakLoopContext(loopStart, patchIndex, context.withCount))
			__compileExpression(expr.body, builder, undefined, true)
			
			// with statements containing a single expression do not use a BLOCK node
			// and as such do not have the expected stack management that blocks provide.
			if expr.body.type != CatspeakTerm.BLOCK && context.stack.peek() != VMArgType.WITH_MARKER {
				builder.emit(VMOpcode.POPZ, VMArgType.VARIABLE)
				context.stack.pop()
			}
			
			if context.stack.peek() != VMArgType.WITH_MARKER {
				jitspeak_throw($"Stack mismatch, expected WITH_MARKER got {jitspeak_vm_arg_to_string(context.stack.peek())}")
			}
			
			context.stack.pop()
			builder.emitJump(VMOpcode.POPENV, loopStart)
			builder.finishPatching(VMOpcode.PUSHENV, builder.position())
			ds_stack_pop(context.loopStack)
			context.withCount--
			
		} break;
		
		case CatspeakTerm.MATCH: jitspeak_unimplemented("MATCH"); // TODO
		case CatspeakTerm.USE: jitspeak_unimplemented("USE"); // TODO
		
		case CatspeakTerm.RETURN: {
			__compileExpression(expr.value, builder, { varOp: JITSpeakVarOp.GET })
			__doConv(builder, VMArgType.VARIABLE)
			
			if context.withCount > 0 {
				__restoreContext(builder)
			}
			
			context.stack.pop()
			builder.emit(VMOpcode.RET, VMArgType.VARIABLE)
			context.didReturn = true
		} break;
		
		case CatspeakTerm.BREAK: {
			if !ds_stack_empty(context.loopStack) {
                var loopContext = ds_stack_top(context.loopStack)
                var inWith = context.withCount == loopContext.withIndex
				var hasValue =!is_undefined(expr.value) 
				if hasValue {
                    __compileExpression(expr.value, builder, { varOp: JITSpeakVarOp.GET })
                    __doConv(builder, VMArgType.VARIABLE)
				}
				if inWith {
					// This is probably not the correct way to do this but it's good enough.
					// Normal implicit-return behavior may not work in this state so we
					// just set the variable ourselves. At worst it's set twice, which
					// isn't great but better than either hard-crashing the runtime
					// or throwing a "variable not found" code error.
					if hasValue {
						builder.emit(VMOpcode.DUP, VMArgType.VARIABLE)
						builder.emitLarge(VMOpcode.POP, VMArgType.VARIABLE, VMArgType.VARIABLE, -7, buffer_u32, implicitRetVar)
					}
					__restoreContext(builder, 1)
				}
				context.stack.pop()
				builder.addPatch(VMOpcode.B, loopContext.patchIndex)
			}
			else {
				jitspeak_log("Warning: ignoring break outside of loop")	
			}
		} break;
		
		case CatspeakTerm.CONTINUE: {
			if !ds_stack_empty(context.loopStack) {
				builder.emitJump(VMOpcode.B, ds_stack_top(context.loopStack).loopStart)	
			}
		} break;
		
		case CatspeakTerm.THROW: jitspeak_unimplemented("THROW"); // TODO
		
		case CatspeakTerm.OP_BINARY: {
			
			var op, arg = 0, forceConv = undefined, forceConvPre = undefined;
			
			switch expr.operator {
			case CatspeakOperator.REMAINDER:  op = VMOpcode.MOD; break;
			case CatspeakOperator.MULTIPLY:   op = VMOpcode.MUL; break;
			
			case CatspeakOperator.DIVIDE:     {
				op = VMOpcode.DIV
				forceConvPre = VMArgType.INT
				forceConv = VMArgType.DOUBLE
			} break;
			
			case CatspeakOperator.DIVIDE_INT: op = VMOpcode.REM; break; 
			case CatspeakOperator.SUBTRACT:   op = VMOpcode.SUB; break; 
			case CatspeakOperator.PLUS:       op = VMOpcode.ADD; break;
			
			case CatspeakOperator.EQUAL:	     op = VMOpcode.CMP; arg = VMCmpType.EQ; break;
			case CatspeakOperator.NOT_EQUAL:     op = VMOpcode.CMP; arg = VMCmpType.NEQ; break;
			case CatspeakOperator.GREATER:       op = VMOpcode.CMP; arg = VMCmpType.GT; break;
			case CatspeakOperator.GREATER_EQUAL: op = VMOpcode.CMP; arg = VMCmpType.GTE; break;
			case CatspeakOperator.LESS:			 op = VMOpcode.CMP; arg = VMCmpType.LT; break;
			case CatspeakOperator.LESS_EQUAL:	 op = VMOpcode.CMP; arg = VMCmpType.LTE; break;
			
			case CatspeakOperator.NOT:         jitspeak_unimplemented("BINARY_NOT");
			case CatspeakOperator.BITWISE_NOT: jitspeak_unimplemented("BINARY_BITWISE_NOT");
			
			case CatspeakOperator.SHIFT_RIGHT: op = VMOpcode.SHR; break;
			case CatspeakOperator.SHIFT_LEFT:  op = VMOpcode.SHL; break;
			case CatspeakOperator.BITWISE_AND: op = VMOpcode.AND; break;
			case CatspeakOperator.BITWISE_XOR: op = VMOpcode.XOR; break;
			case CatspeakOperator.BITWISE_OR:  op = VMOpcode.OR; break;
			
			case CatspeakOperator.XOR: op = VMOpcode.XOR; forceConv = VMArgType.BOOL; break;
			
			default: jitspeak_unimplemented("OP_BINARY_" + string(expr.operator))
			}
			
			__compileExpression(expr.lhs, builder)
			if !is_undefined(forceConv) && (is_undefined(forceConvPre) || context.stackTopType() == forceConvPre) {
				__doConv(builder, forceConv)	
			}
				
			var typeLeft = context.stackTopType()
			
			__compileExpression(expr.rhs, builder)
			if !is_undefined(forceConv) && (is_undefined(forceConvPre) || context.stackTopType() == forceConvPre) {
				__doConv(builder, forceConv)	
			}
			
			var typeRight = context.stackTopType()
			
			builder.emit(op, typeRight, typeLeft, arg << 8)
			
			
			if !is_undefined(forceConv) || op == VMOpcode.CMP {
				if op == VMOpcode.CMP {
					context.stack.set(VMArgType.BOOL)
				}
				__doConv(builder, VMArgType.VARIABLE)
			}
			
			context.stack.pop(2)
			context.stack.push(VMArgType.VARIABLE)
			
		} break; // jitspeak_unimplemented("OP_BINARY");
		case CatspeakTerm.OP_UNARY: jitspeak_unimplemented("OP_UNARY"); // TODO
		
		case CatspeakTerm.CALL: __emitCall(expr.callee, expr.args, builder); break;
		
		case CatspeakTerm.CALL_NEW: {
            // Just a regular call but with an extra argument
            var len = array_length(expr.args)
            var args = array_create(len + 1)
            args[0] = expr.callee
            array_copy(args, 1, expr.args, 0, len)
            __emitCall(NewGMLObject, args, builder, bareCall)
        } break;
		
		case CatspeakTerm.SET: {
			var value = expr.value
			var target = expr.target
			
			if expr.assignType != CatspeakAssign.VANILLA {
				__compileExpression(target, builder, { varOp: JITSpeakVarOp.GET })
				__doConv(builder, VMArgType.VARIABLE)
				context.stack.pop()
			}
			
			__compileExpression(value, builder, { varOp: JITSpeakVarOp.GET })
			__doConv(builder, VMArgType.VARIABLE)
			
			context.stack.pop()
			
			switch expr.assignType {
			case CatspeakAssign.VANILLA: break;
			
			case CatspeakAssign.MULTIPLY: builder.emit(VMOpcode.MUL, VMArgType.VARIABLE, VMArgType.VARIABLE); break;
			case CatspeakAssign.DIVIDE:	  builder.emit(VMOpcode.DIV, VMArgType.VARIABLE, VMArgType.VARIABLE); break;
			case CatspeakAssign.SUBTRACT: builder.emit(VMOpcode.SUB, VMArgType.VARIABLE, VMArgType.VARIABLE); break;
			case CatspeakAssign.PLUS:	  builder.emit(VMOpcode.ADD, VMArgType.VARIABLE, VMArgType.VARIABLE); break;
			
			default: jitspeak_unimplemented("ASSIGNTYPE_" + string(expr.assignType))
			}
			
			if target.type == CatspeakTerm.INDEX {
				// it's jank time
				__compileExpression(target.key, builder, { varOp: JITSpeakVarOp.GET })
				__doConv(builder, VMArgType.VARIABLE)
				__compileExpression(target.collection, builder, { varOp: JITSpeakVarOp.GET })
				__doConv(builder, VMArgType.VARIABLE)
				builder.emitLarge(VMOpcode.CALL, VMArgType.INT, 0, 3, buffer_u32, jitspeak_set_index_helper)
				builder.emit(VMOpcode.POPZ, VMArgType.VARIABLE)
				context.stack.pop(2)
			}
			else {
                context.stack.push(VMArgType.VARIABLE)
				__compileExpression(target, builder, { varOp: JITSpeakVarOp.SET })
				//context.stack.pop()
			}
		} break;
		
		case CatspeakTerm.INDEX: {
			__compileExpression(expr.key, builder)
			__doConv(builder, VMArgType.VARIABLE)
			__compileExpression(expr.collection, builder)
			__doConv(builder, VMArgType.VARIABLE)
			builder.emitLarge(VMOpcode.CALL, VMArgType.INT, 0, 2, buffer_u32, jitspeak_get_index_helper)
			context.stack.pop()
		} break;
		
		case CatspeakTerm.PROPERTY: jitspeak_unimplemented("PROPERTY"); // TODO
		
		case CatspeakTerm.LOCAL: {
			
			// Catspeak treats arguments as local variables, while Gamemaker treats them
			// as builtins, so there's a bit of jank involved to handle translation.
			
			var isArgument = expr.idx < context.argCount
			var index = __localHash(expr.idx)
			
			if !isArgument {
				index |= 0x80000000 | 0x20000000
			}
			
			switch context.varOp {
			case JITSpeakVarOp.GET: {
				builder.emitLarge(isArgument ? VMOpcode.PUSHBLTN : VMOpcode.PUSHLOC, VMArgType.VARIABLE, VMArgType.VARIABLE, isArgument ? -6 : -7, buffer_u32, index)
				context.stack.push(VMArgType.VARIABLE)
			} break;
			
			case JITSpeakVarOp.SET:{
				__doConv(builder, VMArgType.VARIABLE)
				builder.emitLarge(VMOpcode.POP, VMArgType.VARIABLE, VMArgType.VARIABLE, isArgument ? -6 : -7, buffer_u32, index)
				context.stack.pop()
			} break;
				
			default: jitspeak_unimplemented("UNKNOWN_VAROP_" + string(context.varOp))
			}
		} break;
		
		case CatspeakTerm.GLOBAL: {
			
			// Here for organization
			static ifaceGethash = CREATE_HASH "get" NOARR
			
			var hash = CREATE_HASH expr.name NOARR
			
			// This project is also full of jank
			switch context.varOp {
			case JITSpeakVarOp.GET: {
				
				var patchPos = -1
				if(config.useDynamicGlobal || interface.exposeEverythingIDontCareIfModdersCanEditUsersSaveFilesJustLetMeDoThis) {
					// -----------------------------------------------------------------------------------
					// This basically converts the expression from:
					//
					// global.name
					//
					// To what is best represented in GML as:
					//
					// (function(name) { if !variable_struct_exists(global, name) { global[$ name] = interface.get(name) } return global[$ name] })(name)
					//
					// Where interface is the provided Catspeak interface.
					// There is no function being declared here, GML simply doesn't have the syntax to represent what I'm doing.
					// 
					// This is very slow to execute, so this code doesn't generate unless feature flagged or
					// the environment debugging flag is set (exposeEverythingIDontCareIfModdersCanEditUsersSaveFilesJustLetMeDoThis).
					// -----------------------------------------------------------------------------------
					
                    if JITSPEAK_VM_DEBUG jitspeak_log("------- BEGIN GLOBAL ACCESS -------")
                    
					// variable_struct_exists(global, name)
					__emitValue(expr.name, builder)
					__doConv(builder, VMArgType.VARIABLE)
					builder.emitLarge(VMOpcode.PUSH, VMArgType.VARIABLE, VMArgType.VARIABLE, -16, buffer_u32, localGlobalVar)
					builder.emitLarge(VMOpcode.CALL, VMArgType.INT, 0, 2, buffer_u32, variable_struct_exists)
					__doConv(builder, VMArgType.BOOL)
					builder.startPatching()
					builder.addPatch()
					
					// interface.get(name)
					__emitValue(expr.name, builder)
					__doConv(builder, VMArgType.VARIABLE)
					builder.emitLarge(VMOpcode.PUSH, VMArgType.VARIABLE, VMArgType.VARIABLE, -16, buffer_u32, localInterfaceVar)
					builder.emit(VMOpcode.DUP, VMArgType.VARIABLE)
					builder.emitLarge(VMOpcode.PUSH, VMArgType.VARIABLE, VMArgType.VARIABLE, -9, buffer_u32, ifaceGethash)
					builder.emitLarge(VMOpcode.CALL, VMArgType.VARIABLE, 0, 1, buffer_u32, 0)
					
					// global.name = <above>
					builder.emit(VMOpcode.DUP, VMArgType.VARIABLE)
					builder.emitLarge(VMOpcode.PUSH, VMArgType.VARIABLE, VMArgType.VARIABLE, -16, buffer_u32, localGlobalVar)
					builder.emitLarge(VMOpcode.POP, VMArgType.VARIABLE, VMArgType.VARIABLE, -9, buffer_u32, hash)
					
					patchPos = builder.position()
					builder.emitPlaceholder()
					
					builder.finishPatching(VMOpcode.BT, builder.position())
					
					context.stack.pop(2)
                    
                    if JITSPEAK_VM_DEBUG jitspeak_log("-------- END GLOBAL ACCESS --------")
					
                }
                if config.errorOnMissingGlobals || patchPos != -1 {
                    // Directly push the variable to the stack.
                    // Errors if it doesn't exist, just like standard Gamemaker.
                    
                    // global.name
                    builder.emitLarge(VMOpcode.PUSH, VMArgType.VARIABLE, VMArgType.VARIABLE, -16, buffer_u32, localGlobalVar)
                    builder.emitLarge(VMOpcode.PUSH, VMArgType.VARIABLE, VMArgType.VARIABLE, -9, buffer_u32, hash)
                }
                else {
                    // Use variable_struct_get instead.
                    // Slower, but doesn't error on missing variables.
                    
                    // variable_struct_get(global, name)
                    __emitValue(expr.name, builder)
					__doConv(builder, VMArgType.VARIABLE)
					builder.emitLarge(VMOpcode.PUSH, VMArgType.VARIABLE, VMArgType.VARIABLE, -16, buffer_u32, localGlobalVar)
					builder.emitLarge(VMOpcode.CALL, VMArgType.INT, 0, 2, buffer_u32, variable_struct_get)
                    context.stack.pop()
                }
                



				if(interface.isDynamicConstant(expr.name)) {
					// Dynamic constants are functions, so call the function.
					builder.emit(VMOpcode.DUP, VMArgType.VARIABLE)
					builder.emitLarge(VMOpcode.CALL, VMArgType.INT, 0, 1, buffer_u32, method_get_self)
					builder.emitSwap(VMArgType.VARIABLE, 1)
					builder.emitLarge(VMOpcode.CALL, VMArgType.VARIABLE, 0, 0, buffer_u32, 0)
				}
				
				if(patchPos != -1) {
					builder.patchJump(VMOpcode.B, patchPos, builder.position())	
				}
				
				context.stack.push(VMArgType.VARIABLE)
				
			} break;
			
			case JITSpeakVarOp.SET: {
				__doConv(builder, VMArgType.VARIABLE)
				builder.emitLarge(VMOpcode.PUSH, VMArgType.VARIABLE, VMArgType.VARIABLE, -16, buffer_u32, localGlobalVar)
				builder.emitLarge(VMOpcode.POP, VMArgType.VARIABLE, VMArgType.VARIABLE, -9, buffer_u32, hash)
				context.stack.pop()
			} break;
			
			default: jitspeak_unimplemented("UNKNOWN_VAROP_" + string(context.varOp))
			}
			
		} break;
		
		case CatspeakTerm.FUNCTION: {
			builder.emit(VMOpcode.PUSHI, VMArgType.ERROR, 0, expr.idx)
			builder.emitLarge(VMOpcode.PUSH, VMArgType.VARIABLE, VMArgType.VARIABLE, -16, buffer_u32, localFunctionsVar)
			context.stack.push(VMArgType.VARIABLE)
			
		} break; //jitspeak_unimplemented("FUNCTION");
		case CatspeakTerm.PARAMS: jitspeak_unimplemented("PARAMS"); // TODO
		case CatspeakTerm.PARAMS_COUNT: jitspeak_unimplemented("PARAMS_COUNT"); // TODO
		
		case CatspeakTerm.SELF:  __emitCall(GetSelf, [], builder);  break;
		case CatspeakTerm.OTHER: __emitCall(GetOther, [], builder); break;
		
		case CatspeakTerm.CATCH: jitspeak_unimplemented("CATCH"); // TODO
		
		default: jitspeak_unimplemented("UNKNOWN_" + string(block.type))
		}
		
		if !is_undefined(overrides) {
			jitspeak_struct_merge(context, oldCtx)	
		}
	}
	
	static __restoreContext = function(builder, countOverride = -1) {
		context.usesTempVar = true
		__doConv(builder, VMArgType.VARIABLE)
		builder.emitLarge(VMOpcode.POP, VMArgType.VARIABLE, VMArgType.VARIABLE, -7, buffer_u32, tempvar)
		context.save()
		context.stack.pop()
		repeat max(context.withCount, countOverride) {
			if context.stack.peek() != VMArgType.WITH_MARKER {
				jitspeak_throw($"Stack mismatch, expected WITH_MARKER got {jitspeak_vm_arg_to_string(context.stack.peek())}")
			}
			builder.emit(VMOpcode.POPENV, VMArgType.ERROR, VMArgType.DOUBLE)
			context.stack.pop()
		}
		builder.emitLarge(VMOpcode.PUSHLOC, VMArgType.VARIABLE, VMArgType.VARIABLE, -7, buffer_u32, tempvar)
		context.load()
	}
	
	static __emitBinaryOp = function(expr, builder) {
		builder.startPatching()
		__compileExpression(expr.eager, builder)
		__doConv(builder, VMArgType.BOOL)
		context.stack.pop()
		builder.addPatch()
		__compileExpression(expr.lazy, builder)
		__doConv(builder, VMArgType.BOOL)
		context.stack.pop()
		
		builder.emitJump(VMOpcode.B, builder.position() + 8) // Jump over the following pushi
		
		var isOr = expr.type == CatspeakTerm.OR
		
		builder.finishPatching(isOr ? VMOpcode.BT : VMOpcode.BF, builder.position())
		
		builder.emit(VMOpcode.PUSHI, VMArgType.ERROR, 0, isOr)
		context.stack.push(VMArgType.BOOL)
	}
	
	static __emitCall = function(callee, args, builder, bareCall = false) {
			var values = args
			var len = array_length(values)
			for(var i = len - 1; i >= 0; i--) {
				var val = values[i]
				context.varOp = JITSpeakVarOp.GET
				__compileExpression(val, builder)
				__doConv(builder, VMArgType.VARIABLE)
				context.stack.pop()
			}
			context.doConv = false
			context.varOp = -1
			
			if is_method(callee) {
				// We should only take this code path for compiler-generated function calls
				// and not ones found in source code. We lose the bound self but that should be fine?
				builder.emitLarge(VMOpcode.CALL, VMArgType.INT, 0, len, buffer_u32, method_get_index(callee))
				context.stack.push(VMArgType.VARIABLE)
				// Compiler-generated calls should never be bare
			}
			else {
				var type = callee.type
				context.varOp = JITSpeakVarOp.GET
				if type == CatspeakTerm.INDEX {
					// This makes sure the function is executed in the correct context
					__compileExpression(callee.collection, builder)
					__doConv(builder, VMArgType.VARIABLE)
					builder.emit(VMOpcode.DUP, VMArgType.VARIABLE)
					context.stack.pop()
					__compileExpression(callee.key, builder)
					__doConv(builder, VMArgType.VARIABLE)
					builder.emitSwap(VMArgType.VARIABLE, 1)
					builder.emitLarge(VMOpcode.CALL, VMArgType.INT, 0, 2, buffer_u32, jitspeak_get_index_helper)
				}
				else {
					// Floating function, executes in global context
					builder.emitLarge(VMOpcode.PUSH, VMArgType.VARIABLE, VMArgType.VARIABLE, -16, buffer_u32, localGlobalVar)
					__compileExpression(callee, builder)	
				}
				//context.varOp = -1

				__doConv(builder, VMArgType.VARIABLE)
				
				if config.validateFunctionCalls {
					builder.emitLarge(VMOpcode.CALL, VMArgType.INT, 0, 1, buffer_u32, jitspeak_validate_function)
				}
				
				builder.emitLarge(VMOpcode.CALL, VMArgType.VARIABLE, 0, len, buffer_u32, 0)
				
				if(bareCall) {
					builder.emit(VMOpcode.POPZ, VMArgType.VARIABLE)	
					context.stack.pop()
				}
			}
	}
	
	static __emitValue = function(value, builder, pushType = true) {
		
		static undefined_hash = variable_get_hash("undefined")
		
		var type = typeof(value)
	
		if is_real(value) && round(value) == value {
			type = "int32"
		}
	
		var convType = VMArgType.ERROR
		switch type {
		case "number": builder.emitLarge(VMOpcode.PUSH, VMArgType.DOUBLE, 0, 0, buffer_u64, jitspeak_double_as_bytes(value)); convType = VMArgType.DOUBLE; break;
		
		case "string": {
			// Strings require special handling as constants are expected to come from
			// the loaded data file, which is obviously not the case here.
			// Instead, we are going to manually create a RefString and push the pointer
			// to the VM stack, which is pretty much identical to pushing a string normally.
			var str = JITSpeak.stringTable.get(value)
			var addr = int64(str.get_ptr())
			
			// Second type argument isn't used by this instruction, so we use it instead
			// to signal this is a string and not just a long value.
			builder.emitLarge(VMOpcode.PUSH, VMArgType.LONG, VMArgType.STRING, 0, buffer_u64, addr)
		} convType = VMArgType.STRING; break;
		
		case "bool": builder.emit(VMOpcode.PUSHI, VMArgType.ERROR, 0, value); convType = VMArgType.BOOL; break;
	
		case "int32": {
			// See if we can use the "pushi" instruction
			if value <= 0x7fff && value >= -0x8000 {
				if JITSPEAK_DEBUG jitspeak_log(value, "promoted to pushi")
				builder.emit(VMOpcode.PUSHI, VMArgType.ERROR, 0, value)
			}
			else {
				builder.emit(VMOpcode.PUSH, VMArgType.INT, 0, 0, value)
			}

		} convType = VMArgType.INT; break;
		
		case "int64": builder.emitLarge(VMOpcode.PUSH, VMArgType.LONG, 0, 0, buffer_u64, value); convType = VMArgType.LONG; break;
		
		case "undefined": builder.emitLarge(VMOpcode.PUSHBLTN, VMArgType.VARIABLE, 0, -6, buffer_u32, undefined_hash); convType = VMArgType.VARIABLE; break;
		
		default: throw jitspeak_unimplemented($"type {type} for VALUE ({value})")
		}
		
		if pushType {
			context.stack.push(convType)
			if context.doConv {
				__doConv(builder, VMArgType.VARIABLE)
			}	
		}
	}
	
	static __doConv = function(builder, targetType) {
		var current = context.stack.peek()
		if current == VMArgType.ERROR || targetType == VMArgType.ERROR {
			jitspeak_throw("Attempting to convert to/from error type")	
		}
		if current == targetType {
			return;
		}
		
		if JITSPEAK_COLLAPSE_CONV {
			// TODO
			with builder {
				var lastInst = peekTop()
				if(lastInst.opcode == VMOpcode.CONV && lastInst.arg0 == targetType) {
					// We just converted this value from our target type into something else.
					// Let's not do that.
					//buffer_seek(buffer, buffer_seek_relative, -4)
				
				}
				else {
					emit(VMOpcode.CONV, current, targetType)	
				}
			}
		}	
		else {
			builder.emit(VMOpcode.CONV, current, targetType)	
		}
		
		// conv instructions already appear in vm debug, this avoids double-logging them
		if JITSPEAK_DEBUG && !JITSPEAK_VM_DEBUG jitspeak_log("conv:", jitspeak_vm_arg_to_string(current), "->", jitspeak_vm_arg_to_string(targetType))
		context.stack.set(targetType)
	}
	
	// might be better to inline this
	static __localHash = function(idx) {
		static hashes = array_create_ext(10, function(i) { return variable_get_hash("local" + string(i)) })
		static argHashes = array_create_ext(16, function(i) { return variable_get_hash("argument" + string(i)) })
		
		if idx < context.argCount {
			return argHashes[idx]	
		}
		
		var len = array_length(hashes)
		if idx >= len {
			var locNum = len
			repeat(idx - len + 1) {
				array_push(hashes, variable_get_hash("local" + string(locNum++)))
			}
		}
		return hashes[idx]
	}
}

function JITSpeakCompilerConfig(overrides = undefined) constructor {
	
	// When set, JITSpeak functions will attempt to lookup missing
	// globals using the set Catspeak interface. This is expensive and should
	// not be used unless absolutely necessary for some reason.
	// Using exposeEverythingIDontCareIfModdersCanEditUsersSaveFilesJustLetMeDoThis
	// also enables this behavior.
	useDynamicGlobal = JITSPEAK_DYNAMIC_GLOBAL
	
	/// When set, JITSpeak functions will only be able to call method references
	/// and not numbers like in GML.
	validateFunctionCalls = JITSPEAK_VALIDATE_FUNCTIONS
	
	/// When set, JITSpeak functions will error if a global variable is not set
	/// before reading it, instead of using undefined. Enabling this
	/// should provide a small performance improvement.
	errorOnMissingGlobals = JITSPEAK_ERROR_ON_MISSING_GLOBAL
	
	/// When set, JITSpeak functions will work with catspeak_get_index
	/// at the cost of a small performance penalty due to wrapping each function
	/// in a Catspeak-compatible wrapper.
	/// This is experimental and does not work correctly
	/// at the time of writing.
	/// 
	/// @experimental
	allowCatspeakIndexing = JITSPEAK_ALLOW_CATSPEAK_INDEXING
	
	if is_struct(overrides) {
		jitspeak_struct_merge(self, overrides)	
	}
}