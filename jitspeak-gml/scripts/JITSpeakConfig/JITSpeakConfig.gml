// Contains various feature flags and toggles

// For compiler debugging
#macro JITSPEAK_DEBUG false
#macro JITSPEAK_VM_DEBUG false
#macro JITSPEAK_STACK_DEBUG false

// Attempt to treat silent crashes as normal GML exceptions.
// Catching and ignoring these is a really bad idea, as the engine
// is in an unknown state and may not work correctly afterward.
// This exists solely for error reporting, the best thing to do is
// log the exception and immediately end the game.
#macro JITSPEAK_CATCH_NATIVE_EXCEPTIONS true

// Incomplete, do not enable (99% chance things crash)
#macro JITSPEAK_COLLAPSE_CONV false


// These are the default values for the JITSpeakCompilerConfig struct.
// You can see details about what these change in that constructor.
// (It is located at the bottom of the JITSpeakCompiler GlobalScript.)

// Config variable: useDynamicGlobal
#macro JITSPEAK_DYNAMIC_GLOBAL false

// Config variable: validateFunctionCalls
#macro JITSPEAK_VALIDATE_FUNCTIONS true

// Config variable: errorOnMissingGlobals
#macro JITSPEAK_ERROR_ON_MISSING_GLOBAL false

// Config variable: allowCatspeakIndexing
/// @experimental
#macro JITSPEAK_ALLOW_CATSPEAK_INDEXING false
