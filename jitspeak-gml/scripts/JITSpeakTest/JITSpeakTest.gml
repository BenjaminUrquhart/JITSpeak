/*
catspeak_force_init()

Catspeak.interface.exposeFunction("test", function() {
	throw "test"	
})
var test = Catspeak.compile(Catspeak.parseString(@'
do { test() } catch { return "threw" }
'))

var result = test()

show_message(result)

game_end()*/