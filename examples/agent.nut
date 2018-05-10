@include __PATH__ + "./../Scalyr.agent.lib.nut"

const SCALYR_API_KEY = "<your key goes here>";

local scalyr = Scalyr(SCALYR_API_KEY);

function log() {
    local logStr = " [ ] " + time() + " log";
    scalyr.log(logStr);
    server.log(logStr);

    imp.wakeup(1, log);
}

log();

