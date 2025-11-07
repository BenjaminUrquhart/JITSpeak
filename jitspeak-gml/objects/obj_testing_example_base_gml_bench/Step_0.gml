
//# feather use syntax-errors

if (gmlFunc == undefined) {
    exit;
}

if (frame < runTime) {
    var countTotal_ = countTotal;

    var expectTime = get_timer() + game_get_speed(gamespeed_microseconds);
    while (get_timer() < expectTime) {
        gmlFunc();
        countTotal_ += 1;
    }

    countTotal = countTotal_;
    frame += 1;

    if (frame >= runTime) {
        addLog("Catspeak avg. n = " + string(countTotal / runTime));
        countTotal = 0;

        addLog("running JITSpeak...", "boring");
    }
} else if (frame < runTime * 2) {
    var countTotal_ = countTotal;

    var expectTime = get_timer() + game_get_speed(gamespeed_microseconds);
    while (get_timer() < expectTime) {
        jitFunc();
        countTotal_ += 1;
    }

    countTotal = countTotal_;
    frame += 1;

    if (frame >= runTime * 2) {
        addLog("JITSpeak avg. n = " + string(countTotal / runTime));
        countTotal = 0;

        addLog("running GML...", "boring");
    }
} else if (frame < runTime * 3) {
    if (nativeFunc == undefined) {
        addLog("skipping GML test");
        frame = runTime * 3;
    } else {
        var countTotal_ = countTotal;

        var expectTime = get_timer() + game_get_speed(gamespeed_microseconds);
        while (get_timer() < expectTime) {
            nativeFunc();
            countTotal_ += 1;
        }

        countTotal = countTotal_;
        frame += 1;
    }

    if (frame >= runTime * 3) {
        if (nativeFunc != undefined) {
            addLog("GML avg. n = " + string(countTotal / runTime));
        }
        countTotal = 0;

        addLog("running compiler...", "boring");
    }
} else if (frame < runTime * 4) {
    var countTotal_ = countTotal;

    var expectTime = get_timer() + game_get_speed(gamespeed_microseconds);
    while (get_timer() < expectTime) {
        Catspeak.parseString(code);

        countTotal_ += 1;
    }

    countTotal = countTotal_;
    frame += 1;

    if (frame >= runTime * 4) {
        addLog("Parse avg. n = " + string(countTotal / runTime));
        countTotal = 0;
    }
} else if (frame < runTime * 5) {
    var countTotal_ = countTotal;

    var ir = Catspeak.parseString(code);
    var expectTime = get_timer() + game_get_speed(gamespeed_microseconds);
    while (get_timer() < expectTime) {
        Catspeak.compile(ir);

        countTotal_ += 1;
    }

    countTotal = countTotal_;
    frame += 1;

    if (frame >= runTime * 5) {
        addLog("Compile avg. n = " + string(countTotal / runTime));
        countTotal = 0;
        gmlFunc = undefined;
    }
}