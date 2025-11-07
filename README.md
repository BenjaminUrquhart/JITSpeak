# JITSpeak

A Catspeak to Gamemaker VM bytecode Just-In-Time compiler. 

*This project is more of a prototype than anything, please do not use in production.*

# How to use
Simply set your `codegenType` to `JITSpeakCompilerWrapper`:
```gml
var env = new CatspeakEnvironment()
env.codegenType = JITSpeakCompilerWrapper

// compile and run Catspeak scripts like normal
```

You may also use the global `JITSpeak` struct directly, which will use the default `Catspeak` global environment to compile your code:
```gml
var ir = Catspeak.parseString(@' "Hello from JITSpeak" ')
var func = JITSpeak.compile(ir)

show_message(func()) // Hello from JITSpeak
```

# Configuration
You can tweak the settings used for compilation by creating and using a new `JITSpeakCompiler` yourself:
```gml
var env = new CatspeakEnvironment()
var ir = env.parseString("thisVariableDoesntExist")

var config = new JITSpeakConfig({
  errorOnMissingGlobals: true
})

var compiler = new JITSpeakCompiler(env, config)
var func = compiler.compile(ir)

try {
  show_message(func()) // Error - Variable thisVariableDoesntExist not set before reading it
}
catch (e) {
  // Changed my mind, let's not do that
  compiler.config.errorOnMissingGlobals = false
  func = compiler.compile(ir)
  show_message(func()) // undefined, like in Catspeak
}
```
The default values for each option can be found in the `JITSpeakConfig` GlobalScript.

# Feature progress
JITSpeak supports a majority of Catspeak functionality, however some features are either unimplemented at this time or incomplete.

**Unimplemented Features:**
- `match` expressions
- `catch` expressions

**Partially supported features:**
- `with` loops - simple loops work, mileage may vary with more complex logic
- `catspeak_get_index` - requires the `allowCatspeakIndexing` config option. Currently, this breaks the self/global getters and setters when enabled.
