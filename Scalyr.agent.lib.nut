// MIT License
//
// Copyright (c) 2018 Electric Imp
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//

//
// The class that implements the agent side inetgration with the Scalyr
//

class Scalyr {

    _apiKey = null;
    _queue  = null;
    _timer  = null;
    _apiURL = null;

    constructor(apiKey) {
        const DUMP_LOGS_PERIOD_SEC = 15;
        const SCALYR_API_URL = "https://www.scalyr.com/api/uploadLogs?token=%s";

        _queue = [];
        _apiKey = apiKey;
        _apiURL = format(SCALYR_API_URL, apiKey);
    }

    function log(log) {
        _queue.append(log);
        if (!_timer) {
            _timer = imp.wakeup(DUMP_LOGS_PERIOD_SEC, _processQueue.bindenv(this));
        }
    }

    // ------------------------ Private functions ------------------------

    function _processResponse(resp) {
        // TODO: handle response
        // server.log("Request to Scaler done: " + resp.body);
    }

    function _processQueue() {
        local body = "";
        foreach (log in _queue) {
            body += log + "\n";
        }
        // server.log("sending...: \n" + body);
        local request = http.post(_apiURL, {"Content-Type": "text/plain"}, body);
        request.sendasync(_processResponse);
        _timer = null;
    }
}