@include once "github:electricimp/Promise/Promise.lib.nut@v4.0.0"
@include once "github:deldrid1/PrettyPrinter/PrettyPrinter.singleton.nut@v1.0.2"

@include once __PATH__ + "/lib/UUIDGenerator.singleton.nut"	//TODO: Replace lib folder with dedicated repos...

enum SCALYR_SEV {
    VERBOSE, // 0
	DEBUG,
    TRACE,
    INFO,
    WARNING,
    ERROR,
    FATAL	// 6
}

Scalyr <- {
	//----------------------------------\\
	// ------ "Public" variables ----- \\
    //----------------------------------\\
	maxAPIFrequency 				= 10,		// In Seconds, this is essentially a lock-out timer that will prevent messages from being fired until it is expired (at which point it will send the next in the queue)

    logDebug 						= false,	// Debug control flag, when true, class will log all HTTP traffic

	//----------------------------------\\
	// ------ "Private" variables ----- \\
    //----------------------------------\\
	_baseUrl 		   				= null, 	// Scalyr host base url (may change with 307 responses)

	_apiWriteLogsToken 				= null,		// "Write Logs" API token obtained from https://www.scalyr.com/keys.

	_nanoTick 		   				= 0,		// Counter that increments by 1, % 1000 to ensure that we are sending always increasing nanosecond timestamps

	_session 	       				= null,		// session is an arbitrary string which should uniquely define the lifetime of the process which is uploading events. An easy way to generate the session parameter is to generate a UUID at process startup and store the value in a global variable. Do not create a new session identifier for each request; if you create too many session identifiers, Scalyr may be forced to rate-limit your account. However, you should use a different session for each server or process, as timestamps must be in-order within a session.
	_sessionInfo 	   				= null, 	// _sessionInfo is optional. It can be used to specify fields associated with the uploading process. These fields can then be used when querying the uploaded events.
												// You should generally specify at least a serverHost field, containing your hostname or some other stable server identifier. Scalyr uses this value to organize events from different servers.
												// _sessionInfo should remain the same for all API invocations that share a session value. If not, Scalyr might ignore the changes to sessionInfo and associate the original sessionInfo with all events for that session.

    _arrayEvents  					= [],		// Array of events, containing the data generated by addEvent and response promises, and sent to Scalyr using _sendAddEvents
	_timerSendAddEvents 			= null,		// "Next tick" timer to ensure we send events as fast as possible, but if we stack multiple calls in a single sync flow we only make a single HTTP request
	_lockOutTimerSendAddEvents      = null,		// Lockout timer to rate limit our sending to Scalyr to no faster than this.maxAPIFrequency

    _defaultHeaders = {							// REST headers
        "Content-Type": "application/json"
    }

	// Scalyr singleton initializer.
	//
	// Parameters:
	//     options : Table            Key-value table with the configuration options.
	//
	//
	// Returns:                         Scalyr singleton
    init = function(options){
		// server.log("Scalyr.init called")
        // Required Options
		this._apiWriteLogsToken 	= options.apiWriteLogsToken

        // Optional configuration (we will generate these if they are not provided)
        this._baseUrl       		= "baseUrl" 	in options ? options.baseUrl 		: "https://www.scalyr.com/"
		this._sessionInfo 			= "sessionInfo" in options ? options.sessionInfo 	: 	{
																								// "serverHost"	    : http.jsondecode(http.get(AGENT_HOST_LOOKUP_URL).sendsync().body).host,	// This is NOT documented, and may not be supported forever but it will tell you what impCloud server you are running on in <2ms
																								"idAgent"		    : split(http.agenturl(), "/")[2],
																								"idProduct"         : __EI.PRODUCT_ID,
																								"productName"       : __EI.PRODUCT_NAME,
																								"idDeviceGroup"     : __EI.DEVICEGROUP_ID,
																								"deviceGroupName"   : __EI.DEVICEGROUP_NAME,
																								"deviceGroupType"   : __EI.DEVICEGROUP_TYPE,
																								"idDeployment"	    : __EI.DEPLOYMENT_ID	// `impt build info -b THIS_VALUE` will tell you everything you want to know about Product/Device Group/etc. (i.e. the info above)
																							}

		if("logLevel" in options && options.logLevel <= SCALYR_SEV.DEBUG){
			this.logDebug = true;
		}

		this._baseUrl = this._urlNormalize(this._baseUrl)
		this._session = UUIDGenerator.v1(imp.configparams.deviceid.slice(4))

		server.log("Scalyr initialized with Session ID " + this._session)

		return this;
    }


	// The attrs field specifies the "content" of the event. A simple event might contain only a single text field:
	// The "sev" (severity) field should range from 0 to 6, and identifies the importance of this event, using the classic scale "finest, finer, fine, info, warning, error, fatal". This field is optional (defaults to 3 / info).
	addEvent = function(attrs, severityEnum = SCALYR_SEV.INFO, flatten=true){
		// server.log("Scalyr.addEvent called")

        return Promise(function(fulfill, reject){
            local event = {
                // "thread": 												// "identifier for this server thread (optional)",
                "ts"    : this._timestamp()									// event timestamp (nanoseconds since 1/1/1970).  Note that the timestamp is specified as a string, not a number. This is because some JSON packages convert all numbers to floating-point, and a standard 64-bit floating point value does not have sufficient resolution for a nanosecond timestamp. Scalyr uses timestamps internally to identify events, so the ts field must be strictly increasing — each event must have a larger timestamp than the preceding event. This applies to all /addEvents invocations for a given session; each session (identified by the session parameter to /addEvents) has an independent timestamp sequence. So one easy way to ensure valid timestamps is for each client to keep track of the last timestamp it used, and ensure that the next timestamp it generates is at least 1 (nanosecond) larger.
                // "type" : eventType										// The type field indicates a "normal" event, or the beginning or end of an event pair. A normal event has type 0, start events have type 1, and end events have type 2. This field is optional (defaults to 0).
                "sev"   : severityEnum										// The "sev" (severity) field should range from 0 to 6, and identifies the importance of this event, using the classic scale "finest, finer, fine, info, warning, error, fatal". This field is optional (defaults to 3 / info).
                "attrs" : flatten==true ? _flattenTable(attrs) : attrs		// The attrs field specifies the "content" of the event. A simple event might contain only a single text field, However, it's better to break out individual components so that they can be queried on later.  Note that numeric values should be passed as JSON numbers, not quoted strings.
            }

            this._arrayEvents.push({
                "fulfill": fulfill,
				"reject": reject,
                "event": event
            });

            if(this._timerSendAddEvents == null && this._lockOutTimerSendAddEvents == null){
                // Send on the "next tick" so that multiple sync calls to addEvent all get sent in a single HTTPS request using our greedy, lockout timer strategy
                this._timerSendAddEvents = imp.wakeup(0.0, this._sendAddEvents.bindenv(this))
                // this._sendAddEvents will set this._timerSendAddEvents = null upon execution
            }

            //TODO: We should revisit this logic.  Probably now that we have added promises, we could use the .finally to kick off the next send instaed of the lockout timer to optimize speed of logging into Scalyr while limiting us to no more than 1 request "in flight" at a time.  Maybe this is the strategy if maxAPIFrequency is 0 / null?
            // The flow of our execution goes like this:
            // 1) Scalyr.addEvent is called 1 or multiple times in single-threaded sync code and events are added to this._arrayEvents
            // 2) this._timerSendAddEvents above expires on the "next tick" (i.e. as soon as the sync executing Squirrel code releases the thread) and this._sendAddEvents will be called exactly once
            // 3) Assuming there is no lockout timer running, this._sendAddEvents creates  this._lockOutTimerSendAddEvents and sends the HTTPS message containing all of the this._arrayEvents events to Scalyr
            // 4) Scalyr.addEvent can be called 1 or multiple times again
            // 5) Step 2 is repeated
            // 6) Now the lockout timer will prevent this._sendAddEvents from sending anything to Scalyr
            // 7) 4-6 will be repeated as many times as necessary until the this._lockOutTimerSendAddEvents expires
            // 8) When this._lockOutTimerSendAddEvents expires, this._onLockoutTimerExpiredSendAddEvents will be called
            // 9) this._onLockoutTimerExpiredSendAddEvents clears the this._onLockoutTimerExpiredSendAddEvents and calls this._sendAddEvents assuming this._timerSendAddEvents (otherwise it will call when it is ready)


        }.bindenv(this))
	}


    //Normalize the trailing "/" in a url - make sure it is included
    _urlNormalize = function(url){
		// server.log("Scalyr._urlNormalize called")
        return url[url.len()-1] == '/' ? url : url + "/"
    }

	/**
	* Moves nested tables/arrays to the root of a table
	* @method _flattenTable
	* @param  {[table]}     container   table to flatten
	* @param  {[string]}    delimitter  string to seperate keys
	* @param  {[table]}     result      the flattened table
	* @param  {[string]}    path        path of parent keys
	* @param  {[integer]}   level       nested level
	* @returns                          the flatted table
	*
	* local t = {
				a = {
					b = {
						c = {
							d = {
								e = "e",
							}
						}
					}
				}
			};
		_flattenTable(t) -> { a_b_c_d_e = "e"}
	*/
	_flattenTable <- function(container, delimitter = "_", result = {}, path = "", level=0){
		if (level >= 32) {
			throw "cyclic data structure detected";
		}

		switch(typeof(container)){
			case "table":
			case "array":
				foreach( k,v in container){
					local newPath = level > 0 ? path + delimitter + k : k;
					local newResult = _flattenTable(v, delimitter, result, newPath, level + 1);  // recursion is fun :)
					if(typeof(newResult) != "table" && typeof(newResult) != "array")    // We want a leafy thing - don't store empty tables to get to the actual data points in the thing we are returning (otherwise JSONEncoder will bomb out with circular references)
						result[newPath] <- newResult;
				}
				return result;
			case "blob":
				return clone(container);
			default:
				return container;
		}
	}

	// Return an event timestamp as a string (nanoseconds since 1/1/1970)
	_timestamp = function(){
		// server.log("Scalyr._timestamp called")
		local ts = date();
		this._nanoTick = (this._nanoTick + 1) % 1000
		return format("%d%06d%03d", ts.time, ts.usec, this._nanoTick);
	}

	// https://www.scalyr.com/help/api#addEvents
	//NOTE: the request body can be at most 3,000,000 bytes in length. Longer requests will be rejected. To avoid problems, if you have a large number of event records to upload, you should issue them in batches well below the 3,000,000 byte limit.
	// {
	//   "token": "xxx",
	//   "session": "149d8290-7871-11e1-b0c4-0800200c9a66",
	//   "sessionInfo": {
	//     "serverType": "frontend",
	//     "serverId": "prod-front-2"},
	//   "events": [
	//     {
	//       "thread": "1",
	//       "ts": "1332851837424000000",
	//       "type": 0,
	//       "sev": 3,
	//       "attrs": {
	//         "message": "record retrieved",
	//         "recordId": 39217,
	//         "latency": 19.4,
	//         "length": 39207
	//       }
	//     }
	//   ],
	//   "threads": [
	//     {"id": 1, "name": "request handler thread"},
	//     {"id": 2, "name": "background processing thread"}
	//   ]
	// }
	_sendAddEvents = function(){
		// server.log("Scalyr._sendAddEvents called")
		this._timerSendAddEvents = null // Signal to this.addEvent, that it should allow scheduling another "next tick" timer to fire this function

		if (this._lockOutTimerSendAddEvents == null) {
            this._lockOutTimerSendAddEvents = imp.wakeup(this.maxAPIFrequency, this._onLockoutTimerExpiredSendAddEvents.bindenv(this));
        } else {
			return	// if we are locked out, no need to proceed
		}

		local url = this._baseUrl + "addEvents"

        local events = []
        local sentEventsCounter = this._arrayEvents.len()
        for(local i=0; i<sentEventsCounter; i++) events.push(this._arrayEvents[i].event)

		local body = {
			"token"			: this._apiWriteLogsToken,
			"session"		: this._session,
			"sessionInfo"	: this._sessionInfo,
			"events"		: events
			// "threads"	// threads is optional. If present, it should contain a series of objects of the form {"id": "...", "name": "..."}, one for each unique thread ID appearing in the events list. This is used to associate a readable name with each thread.
		}

		if(typeof body.sessionInfo != "table" || body.sessionInfo.len() == 0){
			// If there isn't anything interesting to send, don't send anything
			delete body.sessionInfo
		}

		return this._createRequestPromise("POST", url, this._defaultHeaders, body)
            .then(function(data){
                for(local i=0; i< sentEventsCounter; i++) this._arrayEvents[i].fulfill(data)
            }.bindenv(this))
            .fail(function(err){
                for(local i=0; i< sentEventsCounter; i++) this._arrayEvents[i].reject(err)
            }.bindenv(this))
            .finally(function(dummy){
                this._arrayEvents = this._arrayEvents.slice(sentEventsCounter);	// Clean up our Events array, since this data has now been sent (successfully or not, we've notified upstream via the promise)
            }.bindenv(this))
	}

	_onLockoutTimerExpiredSendAddEvents = function(){
		// server.log("Scalyr._onLockoutTimerExpiredSendAddEvents called")
		this._lockOutTimerSendAddEvents = null
		if(this._timerSendAddEvents == null && this._arrayEvents.len() > 0)
			this._sendAddEvents()

	}

	_logAndThrowFailureFactory = function(requestTable){
		return function(responseOrError){
			server.error("SCALYR REQUEST ERROR...")

			server.error("REQUEST: >>>")
			PrettyPrinter.print(requestTable)

			server.error("RESPONSE OR ERROR: <<<")
			PrettyPrinter.print(responseOrError)

			throw responseOrError //Allow upstream code to handle this
		}
	}

	// return a Promise
    _createRequestPromise = function(method, url, headers, body = "", returnFullResponseOnSuccess = false, bodyEncoder = http.jsonencode.bindenv(http)) {
		// server.log("Scalyr._createRequestPromise called")
		local reqTable = {
			"method": method,
			"url": url,
			"headers": headers,
			"body": body
		}

        return Promise(function (resolve, reject) {
            if(logDebug == true){
                server.log("SCALYR HTTPS SENDING >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>")
                PrettyPrinter.print(reqTable)	//TODO: should this support passing in an encoder?
				server.log(">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>")
            }

            local request = http.request(method, url, headers, bodyEncoder(body))
            request.setvalidation(VALIDATE_USING_SYSTEM_CA_CERTS);
            request.sendasync(this._createResponseHandler(resolve, reject, returnFullResponseOnSuccess).bindenv(this));
        }.bindenv(this))
		.fail(_logAndThrowFailureFactory(reqTable).bindenv(this));
    }


	// Per https://www.scalyr.com/help/api#format:
	// The response will always include a "status" property, indicating whether the operation succeeded or failed. Status codes are hierarchical, with slash-delimited components. For example, "error/client" and "error/server" both indicate that the operation failed, but one indicates that the problem was the client's fault and the other the server's fault. New status values may be added in the future, but they will generally extend (refine) existing values. So when checking the status value, always be prepared for extra text — check startsWith() instead of equals(). Each method may list one or more responses specific to that method. In addition, the following responses are possible for all methods:

	// Response if the request is somehow incorrect ("your fault"):
	// {
	//   "status":  "error/client",
	//   "message": "a human-readable message"
	// }

	// Response if the server experiences an internal error while processing the request ("Scaylr's fault"):
	// {
	//   "status":  "error/server",
	//   "message": "a human-readable message"
	// }
	// If the server is overloaded, or for some other reason is temporarily unable to process the request, it will return a status of "error/server/backoff". When this status is returned, you may wish to retry the request after a short delay. You should also retry after a delay in the case of server errors (5xx status code), 429 status code ("Too Many Requests"), or a request timeout.
	// Note that new status values, in particular new error statuses, may be added in the future. Please treat any unexpected status value like "error".

	// Handle Responses for the Request Promise
	_createResponseHandler = function(onSuccess, onError, returnFullResponseOnSuccess) {
        return function (res) {
            try {
            	if(logDebug == true){
                    server.log("SCALYR HTTPS RESPONSE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<")
                    PrettyPrinter.print(res)
					server.log("<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<")
                }

                if (res.body && res.body.len() > 0) {
                    try {
                        res.body = http.jsondecode(res.body);
                    } catch(ex) {
                        // Unable to decode as JSON
                    }
                }

                if (res.statuscode >= 200 && res.statuscode < 300) {
                    onSuccess(returnFullResponseOnSuccess == true ? res : res.body);
                // } else if (resp.statuscode == 307 && "location" in resp.headers) {  // Deal with redirects
                //     local location = resp.headers["location"];
                //     local p = location.find(".microsoft.com");
                //     p = location.find("/", p);
                //     endpoint = location.slice(0, p);
                // } else if (res.statuscode == 28 || res.statuscode == 429 || res.statuscode == 503) { //TODO: Implement backoff/retry here if required
                    // onError(res);
                // } else if (res.statuscode == 400) { // Bad Request - Event data has incorrect format
                //     onError(res);
                // } else if (res.statuscode == 401) { // Unauthorized - Invalid access key
                //     onError(res);
                // } else if (res.statuscode == 404) { // Not found - Incorrect endpoint
                //     onError(res);
                // } else if (res.statuscode == 413) { // Payload Too Large - Array or event exceeds size limits
                //     onError(res);
                } else {
                    onError(res); //onError, always return raw
                }
            } catch (err) {
                onError(err);
            }
        }
    }
}
