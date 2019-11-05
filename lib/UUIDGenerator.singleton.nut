// Inspired by https://github.com/kelektiv/node-uuid/blob/master/v1.js

// **`v1()` - Generate time-based UUID**
//
// Inspired by https://github.com/LiosK/UUID.js
// and http://docs.python.org/library/uuid.html

@include once __PATH__ + "/uint64.class.nut"

UUIDGenerator <- {
    _clockseq = null

    // Previous uuid creation time
    _lastMSecs = 0
    _lastNSecs = 0

    // Generate and return a RFC4122 v1 (timestamp-based) UUID.

    // * `options` - (Object) Optional uuid state to apply. Properties may include:

    //   * `node` - (Array) Node id as Array of 6 bytes (per 4.1.6). Default: Randomly generated ID.  See note 1.
    //   * `clockseq` - (Number between 0 - 0x3fff) RFC clock sequence.  Default: An internally maintained clockseq is used.
    //   * `msecs` - (Number) Time in milliseconds since unix Epoch.  Default: The current time is used.
    //   * `nsecs` - (Number between 0-9999) additional time, in 100-nanosecond units. Ignored if `msecs` is unspecified. Default: internal uuid counter is used, as per 4.2.1.2.

    // Returns `buffer`, if specified, otherwise the string form of the UUID

    v1 = function(node=null) {
        if(typeof node == "string"){
            node = hexStringToBlob(node)
        }

        local clockseq = _clockseq;
        local b = blob(16)

        // node and clockseq need to be initialized to random values if they're not
        // specified.  We do this lazily to minimize issues related to insufficient
        // system entropy.  See #189
        if (node == null || clockseq == null) {
            if (node == null) {
                // Per 4.5, create and 48-bit node id, (47 random bits + multicast bit = 1)
                node = [
                    (math.rand() % 256) | 0x01,
                    math.rand() % 256,
                    math.rand() % 256,
                    math.rand() % 256,
                    math.rand() % 256,
                    math.rand() % 256
                ];
            }
            if (clockseq == null) {
                // Per 4.2.2, randomize (14 bit) clockseq
                clockseq = ((math.rand() % 256) << 8 | (math.rand() % 256)) & 0x3fff;
            }
        }

        // UUID timestamps are 100 nano-second units since the Gregorian epoch,
        // (1582-10-15 00:00).  Squirrel numbers aren't precise enough for this, so
        // time is handled internally as 'secs' (integer seconds) 'msecs' (integer milliseconds) and 'nsecs'
        // (100-nanoseconds offset from msecs) since unix epoch, 1970-01-01 00:00.
        local d = date()
        local msecs = (uint64(d.time).mul(1000)).add(uint64(d.usec).div(1000)); //convert from seconds to milliseconds, then add in the millis (which is converted from microseconds)

        // Per 4.2.1.2, use count of uuid's generated during the current clock
        // cycle to simulate higher resolution clock
        local nsecs = _lastNSecs + 1;

        // Time since last uuid creation (in msecs)
        local dt = msecs.sub(_lastMSecs).add((nsecs - _lastNSecs)/10000);

        // Per 4.2.1.2, Bump clockseq on clock regression
        if (dt.lt(0)) {
            clockseq = clockseq + 1 & 0x3fff;
        }

        // Reset nsecs if clock regresses (new clockseq) or we've moved onto a new
        // time interval
        if (dt.lt(0) || msecs.gt(_lastMSecs)) {
            nsecs = 0;
        }

        // Per 4.2.1.2 Throw error if too many uuids are requested
        if (nsecs >= 10000) {
            throw "UUID.v1(): Can't create more than 10M uuids/sec";
        }

        _lastMSecs = msecs;
        _lastNSecs = nsecs;
        _clockseq = clockseq;

        // Per 4.1.4 - Convert from unix epoch to Gregorian epoch
        msecs = msecs.add(uint64("12219292800000"));

        local bitmask33 = uint64("4294967296") //0x100000000

        // `time_low`
        local tl = ((msecs.and(0xfffffff)).mul(10000).add(nsecs)).div(bitmask33).remainder();

        tl = tl == null ? 0 : tl.toString().tointeger()    //Pull out the remainder into a native 32-bit integer
        b[0] = tl >>> 24 & 0xff;
        b[1] = tl >>> 16 & 0xff;
        b[2] = tl >>> 8 & 0xff;
        b[3] = tl & 0xff;

        // `time_mid`
        local tmh = (msecs.mul(10000).div(bitmask33)).and(0xfffffff).toString().tointeger();

        b[4] = tmh >>> 8 & 0xff;
        b[5] = tmh & 0xff;

        // `time_high_and_version`
        b[6] = tmh >>> 24 & 0xf | 0x10; // include version
        b[7] = tmh >>> 16 & 0xff;

        // `clock_seq_hi_and_reserved` (Per 4.2.2 - include variant)
        b[8] = clockseq >>> 8 | 0x80;

        // `clock_seq_low`
        b[9] = clockseq & 0xff;

        // `node`
        for (local n = 10; n < 16; ++n) {
            b[n] = node[n-10];
        }

        local uuid = ""
        for(local i = 0; i < b.len(); i++){
            uuid = uuid + format("%.2x", b[i]);
        }

        return uuid.slice(0,8) + "-" + uuid.slice(8,12) + "-" + uuid.slice(12,16) + "-" + uuid.slice(16,20) + "-" + uuid.slice(20)
    }

    hexStringToBlob = function(str){
        if(str.len() %2 != 0)   throw "Must provide an even number of hex character to process"

        local hex = blob(str.len()/2)
        for(local i = 0; i< str.len(); i+=2) {
            // convert ascii nibble to 0-255;
            local nibble_hi = str.tolower()[i] - '0';
            if (nibble_hi > 9)
                nibble_hi = ((nibble_hi & 0x1f) - 7);

            local nibble_lo = str.tolower()[i+1] - '0'
            if (nibble_lo > 9)
                nibble_lo = ((nibble_lo & 0x1f) - 7);

           hex[i/2] = (nibble_hi << 4) | nibble_lo
        }
        return hex;
    }
}

// server.log(UUID.v1(imp.configparams.deviceid.slice(4)))
