@include once __PATH__ + "./../Scalyr.agent.lib.nut"

const AGENT_HOST_LOOKUP_URL = "http://localhost:32737"
const SCALYR_API_KEY = "@{SCALYR_API_KEY}";

Scalyr.init({
	"apiWriteLogsToken" : SCALYR_API_KEY,
	"sessionInfo"		: {
		"serverHost"	: http.jsondecode(http.get(AGENT_HOST_LOOKUP_URL).sendsync().body).host,	// This is NOT documented, and may not be supported forever but it will tell you what impCloud server you are running on in <2ms
		"agentID"		: split(http.agenturl(), "/")[2],
        "deploymentID"	: __EI.DEPLOYMENT_ID	// `impt build info -b THIS_VALUE` will tell you everything you want to know about Product/Device Group/etc.
	}
	// "logLevel"			: SCALYR_SEV.DEBUG
});

g_Counter <- 0
function loop(){
	server.log("Adding events... g_Counter = " + g_Counter)

	Promise.all([
		Scalyr.addEvent({
			"counter"		: g_Counter++,
			"freeMemory" 	: imp.getmemoryfree()
			"evt"			: 1
		}),

		Scalyr.addEvent({
			"counter"		: g_Counter++,
			"freeMemory" 	: imp.getmemoryfree()
			"evt"			: 2
		})
	]).then(function(data){
		server.log("Scalyr logs sent successfully!")
	})


	imp.wakeup(5.0, loop)
}

loop()

