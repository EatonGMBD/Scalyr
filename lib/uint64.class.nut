@include once __PATH__ + "/helperFunctions.nut"
/*//1450489318530 = 151B7E68C82
local num = BigFromHexString("151B7E68C82");
server.log(num.toString())
server.log("1450489318530")*/
/**
	C-like unsigned 64 bits integers in Javascript
	Copyright (C) 2013, Pierre Curto
	MIT license
 */
class uint64 {

/**
 * Ported from https://github.com/pierrec/js-cuint/blob/master/lib/uint64.js
 * //TODO: BUG: there are some performance things that can make this better - look at the original class for some inspiration (just need to cache some things like uint64(0), uint64(10), etc.)
 * //It would also be nice to make this work with Hex and binary, but maybe save that for another day
 */

  static _createStringValues = [];
  static _largestQuickStringNumber = [];

 	_remainder = null;
 	_a00 = null;
 	_a16 = null;
 	_a32 = null;
 	_a48 = null;

 	minus = null;
 	sub = null;
 	plus = null;
 	mul = null;
 	times = null;
 	valueOf = null;
 	toJSON = null;
  _string = null; //holds the most up to date string representation of the uint64 (so we don't have to do uint64 _encode math when we want the string)

  static function _initCreateStringValues() {
    local zero = uint64(0);
    local pow10 = uint64(1);

    for (local exp = 0; exp < 19; ++exp) {
      local values = [zero];
      values.push(pow10);
      for (local mul = 2; mul <= 9; ++mul) {
        values.push(pow10.mul(mul));
      }
      _createStringValues.push(values);
      pow10 = pow10.mul(10);
    }

    _createStringValues.push([zero, pow10]);
    _largestQuickStringNumber.push(uint64("9000000000000000000"));
  }

 	/**
 	 *	Represents an unsigned 64 bits integer
 	 * @constructor
 	 * @param {Number} first low bits (8)
 	 * @param {Number} second low bits (8)
 	 * @param {Number} first high bits (8)
 	 * @param {Number} second high bits (8)
 	 * or
 	 * @param {Number} low bits (32)
 	 * @param {Number} high bits (32)
 	 * or
 	 * @param {String|Number} integer as a string 		 | integer as a number
 	 * @param {Number|Undefined} radix (optional, default=10)
 	 * @return
 	 */
 	constructor(a00=null, a16=null, a32=null, a48=null) {
 		this.minus      = this.subtract;
 		this.sub        = this.subtract;
 		this.plus       = this.add;
 		this.times      = this.multiply;
 		this.mul        = this.multiply;
 		this._remainder = null

 		if(a00 instanceof uint64){
 			this._a00 = a00._a00;
 			this._a16 = a00._a16;
 			this._a32 = a00._a32;
 			this._a48 = a00._a48;
 			this._remainder = a00._remainder;
            this._string = a00._string;
 			return this;
 		}

 		if(a00 == null){
            this._a00 = 0;
            this._a16 = 0;
            this._a32 = 0;
            this._a48 = 0;
            this._string = "0";
            return this;
 		}

 		if(typeof a00 == "float" || typeof a16 == "float" || typeof a32 == "float" || typeof a48 == "float"){
	        throw "Invalid float argument to uint64"
 		}

 		if (typeof a00 == "string") {
            return fromString(a00, a16)
        }

 		if (typeof a00 == "blob" || typeof a00 == "array"){	//
 			if(a00.len() == 4){	// Assume UINT32 blob
 				this._a48 = a00[0].tointeger()
 				this._a32 = a00[1].tointeger()
 				this._a16 = a00[2].tointeger()
 				this._a00 = a00[3].tointeger()
 			} else if(a00.len() == 8){	// Assume //TODO: what kind of endianness? uint64 blob
 				this._a48 = a00[0] << 8 | a00[1] & 0xFF
 				this._a32 = a00[2] << 8 | a00[3] & 0xFF
 				this._a16 = a00[4] << 8 | a00[5] & 0xFF
 				this._a00 = a00[6] << 8 | a00[7] & 0xFF
            }
 			return this
 		}

 		if (a16 == null) {
            return fromNumber(a00)
        }

 		if (a32 == null) {
 			this._a00 = a00 & 0xFFFF
 			this._a16 = a00 >>> 16
 			this._a32 = a16 & 0xFFFF
 			this._a48 = a16 >>> 16
 			return this
 		}

 		return this
 	}

    function remainder(){
        if(this._remainder == null) {
            return uint64(0);
        }

        return _remainder
    }


 	/**
 	 * Set the current _uint64_ object from a 32-bit signed number
 	 * @method fromNumber
 	 * @param {Number} number
 	 * @return ThisExpression
 	 */
 	function fromNumber (value) {
        if (typeof value != "integer") {
            throw "Input must be an integer, received \""+(typeof value)+"\"";
        }

        this._a00 = value & 0xFFFF
        this._a16 = value >>> 16
        this._a32 = 0
        this._a48 = 0

        this._string = value.tostring();
        return this;
 	}

 	/**
 	 * Set the current _uint64_ object from a string
 	 * @method fromString
 	 * @param {String} integer as a string
 	 * @return ThisExpression
 	 */
 	function fromString (s, radix=10) {

    if (s.find(".") != null) {
      throw "Error only integers are supported, \""+s+"\" is considered a float due to the \".\""
    }

    this._a00 = 0
 		this._a16 = 0
 		this._a32 = 0
 		this._a48 = 0

 		/*
 			In Javascript, bitwise operators only operate on the first 32 bits
 			of a number, even though parseInt() encodes numbers with a 53 bits
 			mantissa.
 			Therefore uint64(<Number>) can only work on 32 bits.
 			The radix maximum value is 36 (as per ECMA specs) (26 letters + 10 digits)
 			maximum input value is m = 32bits as 1 = 2^32 - 1
 			So the maximum substring length n is:
 			36^(n+1) - 1 = 2^32 - 1
 			36^(n+1) = 2^32
 			(n+1)ln(36) = 32ln(2)
 			n = 32ln(2)/ln(36) - 1
 			n = 5.189644915687692
 			n = 5
 		 */

    local tenTo5 = uint64();
    tenTo5._a00 = 0x86A0;
    tenTo5._a16 = 0x0001;

    local that = clone(this)
 		for (local i = 0, len = s.len(); i < len; i += 5) {
 			local size = min(5, len - i)
 			local value = s.slice(i, i + size).tointeger()
      that = that.multiply(size < 5 ? uint64(math.pow(10, size).tointeger()) : tenTo5).add(value)
 		}

    this._a00 = that._a00
    this._a16 = that._a16
    this._a32 = that._a32
    this._a48 = that._a48

    this._string = s;

 		return this
 	}

 	/**
 	 * Convert this _uint64_ to a number (last 32 bits are dropped)
 	 * @method toNumber
 	 * @return {Number} the converted uint64
 	 */
 	function toNumber() {
 		return (this._a16 << 16) | this._a00
 	}

  //NOTE: This is VERY expensive and slow but we won't get to these numbers before imp has a native uint64 implementation
  //      We have a gap in the else branch (base10 quick createString implementation) between the "_largestQuickStringNumber" and the actual maximum uint64 number
  function createStringOld() {
    local radixUint = uint64(10) //TODO: Why is the first check this > 10? This seems like it's supposed to be the radix comparison rather than the number to the radix

    if ( !this.gt(radixUint) ) return this.toNumber().tostring()

    local self = clone(this)
    local res = array(64)
    local i;
    for (i = 63; i >= 0; i--) {
      self = self.div(radixUint)
      res[i] = self._remainder.toNumber().tostring()
      if ( !self.gt(radixUint) ) break
    }
    res[i-1] = self.toNumber().tostring()

    return res.reduce(function(previousValue, currentValue){
        if(previousValue == null && currentValue == null)
            return ""
        if(currentValue == null)
            return ""
        return (previousValue.tostring() + currentValue.tostring());
    })
  }

  /**
 	 * Convert this _uint64_ to a string
 	 * @method createString
 	 * @param {Number} radix (optional, default=10)
 	 * @return {String} the converted uint64
 	 */
  function createString() {
    local cloned = uint64(this);

    //NOTE: This is VERY expensive and slow but we won't get to these numbers before imp has a native uint64 implementation
    //      We have a gap in the else branch (base10 quick createString implementation) between the "_largestQuickStringNumber" and the actual maximum uint64 number
    if(cloned.gt(uint64._largestQuickStringNumber[0])){
   		return createStringOld();
    } else {
      local str = "";
      local exp = 18;

      while (exp >= 0) {
        local mul = 1;

        while (mul < 10 && cloned.gte_u64(_createStringValues[exp][mul])) {
          mul++;
        }
        mul--;

         //server.log("[uint64][createString] exp: "+exp+" mul: "+mul)


        if (mul > 0 || str != "")
          str = str+mul;

        cloned = cloned.sub(_createStringValues[exp][mul]);
        exp--;
      }

      if(str == ""){
        str = "0"
      }

      return str;
    }
  }

 	/**
 	 * Returns the string representation of the uint64
 	 * @method toString
 	 * @return {String} the converted uint64
 	 */
 	function toString() {
    if (this._string == null) {
      this._string = this.createString();
    }

    return this._string;
 	}

 	/**
 	 * Add two _uint64_. The current _uint64_ stores the result
 	 * @method add
 	 * @param {Object} other uint64
 	 * @return ThisExpression
 	 */
 	function add(other) {
 		other = uint64(other);   //Work of a clone so that things are nice and immutable (and numbers assigned to temporary variables behave like a sane person would expect at the cost of performance/RAM)

 		local a00 = this._a00 + other._a00

 		local a16 = a00 >>> 16
 		a16 += this._a16 + other._a16

 		local a32 = a16 >>> 16
 		a32 += this._a32 + other._a32

 		local a48 = a32 >>> 16
 		a48 += this._a48 + other._a48

 		other._a00 = a00 & 0xFFFF
 		other._a16 = a16 & 0xFFFF
 		other._a32 = a32 & 0xFFFF
 		other._a48 = a48 & 0xFFFF

    other._string = null;

        /*if(a48 > 0xFFFF)
            server.error("WARNING - POSITIVE OVERFLOW IN uint64 ADD")*/

 		return other
 	}

 	/**
 	 * Subtract two _uint64_. The current _uint64_ stores the result
 	 * @method subtract
 	 * @param {Object} other uint64
 	 * @return ThisExpression
 	 */
 	function subtract(other) {
        /*if(this.lt(other))
            server.error("WARNING - NEGATIVE OVERFLOW IN uint64 subtract")*/

    return this.add( uint64(other).negate()); //Don't need to worry about any cloning / being immutable here, these functions make the necessary copies
 	}

 	/**
 	 * Multiply two _uint64_. The current _uint64_ stores the result
 	 * @method multiply
 	 * @param {Object} other uint64
 	 * @return ThisExpression
 	 */
 	function multiply(other) {
 		/*
 			a = a00 + a16 + a32 + a48
 			b = b00 + b16 + b32 + b48
 			a*b = (a00 + a16 + a32 + a48)(b00 + b16 + b32 + b48)
 				= a00b00 + a00b16 + a00b32 + a00b48
 				+ a16b00 + a16b16 + a16b32 + a16b48
 				+ a32b00 + a32b16 + a32b32 + a32b48
 				+ a48b00 + a48b16 + a48b32 + a48b48

 			a16b48, a32b32, a48b16, a48b32 and a48b48 overflow the 64 bits
 			so it comes down to:
 			a*b	= a00b00 + a00b16 + a00b32 + a00b48
 				+ a16b00 + a16b16 + a16b32
 				+ a32b00 + a32b16
 				+ a48b00
 				= a00b00
 				+ a00b16 + a16b00
 				+ a00b32 + a16b16 + a32b00
 				+ a00b48 + a16b32 + a32b16 + a48b00
 		 */
 		other = uint64(other)

 		local a00 = this._a00
 		local a16 = this._a16
 		local a32 = this._a32
 		local a48 = this._a48
 		local b00 = other._a00
 		local b16 = other._a16
 		local b32 = other._a32
 		local b48 = other._a48

 		local c00 = a00 * b00

 		local c16 = c00 >>> 16
 		c16 += a00 * b16
 		local c32 = c16 >>> 16
 		c16 = c16 & 0xFFFF
 		c16 += a16 * b00

 		c32 += c16 >>> 16
 		c32 += a00 * b32
 		local c48 = c32 >>> 16
 		c32 = c32 & 0xFFFF
 		c32 += a16 * b16
 		c48 += c32 >>> 16
 		c32 = c32 & 0xFFFF
 		c32 += a32 * b00

 		c48 += c32 >>> 16
 		c48 += a00 * b48
 		c48 = c48 & 0xFFFF
 		c48 += a16 * b32
 		c48 = c48 & 0xFFFF
 		c48 += a32 * b16
 		c48 = c48 & 0xFFFF
 		c48 += a48 * b00

 		other._a00 = c00 & 0xFFFF
 		other._a16 = c16 & 0xFFFF
 		other._a32 = c32 & 0xFFFF
 		other._a48 = c48 & 0xFFFF

    other._string = null;

 		return other
 	}

 	/**
 	 * Divide two _uint64_. The current _uint64_ stores the result.
 	 * The _remainder is made available as the __remainder_ property on
 	 * the _uint64_ object. It can be null, meaning there are no _remainder.
 	 * @method div
 	 * @param {Object} other uint64
 	 * @return ThisExpression
 	 */
 	function div(other) {
 		other = uint64(other)
 		if ( (other._a16 == 0) && (other._a32 == 0) && (other._a48 == 0) ) {
 			if (other._a00 == 0) throw Error("division by zero")

 			// other == 1, return this
 			if (other._a00 == 1) {
 				this._remainder = null
 				return this
 			}
 		}

 		// other > this: 0
 		if ( other.gt(this) ) {
 			other._remainder = clone(this)
 			other._a00 = 0
 			other._a16 = 0
 			other._a32 = 0
 			other._a48 = 0
      other._string = "0"
 			return other
 		}
 		// other == this: 1
 		if ( this.eq(other) ) {
 			other._remainder = null
 			other._a00 = 1
 			other._a16 = 0
 			other._a32 = 0
 			other._a48 = 0
      other._string = "1";
 			return other
 		}

 		// Shift the divisor left until it is higher than the dividend
 		local i = -1
 		while ( !this.lt(other) ) {
 			// High bit can overflow the default 16bits
 			// Its ok since we right shift after this loop
 			// The overflown bit must be kept though
 			other = other.shiftLeft(1, true)
 			i++
 		}
 		// Set the _remainder
 		local remainder = clone(this)
 		// Initialize the current result to 0
 		local a00 = 0
 		local a16 = 0
 		local a32 = 0
 		local a48 = 0
 		for (; i >= 0; i--) {
 			other = other.shiftRight(1)
 			// If shifted divisor is smaller than the dividend
 			// then subtract it from the dividend
 			if ( !remainder.lt(other) ) {
 				remainder = remainder.subtract(other)

 				// Update the current result
 				if (i >= 48) {
 					a48 = a48 | (1 << (i - 48))
 				} else if (i >= 32) {
 					a32 = a32 | (1 << (i - 32))
 				} else if (i >= 16) {
 					a16 = a16 | (1 << (i - 16))
 				} else {
 					a00 = a00 | (1 << i)
 				}
 			}
 		}

    other._remainder = remainder
    other._a00 = a00
    other._a16 = a16
    other._a32 = a32
    other._a48 = a48

    other._string = null;

 		return other
 	}

 	/**
 	 * Negate the current _uint64_
 	 * @method negate
 	 * @return ThisExpression
 	 */
 	function negate() {
    local cloned = clone(this);
 		local v = ( ~cloned._a00 & 0xFFFF ) + 1
 		cloned._a00 = v & 0xFFFF
 		v = (~cloned._a16 & 0xFFFF) + (v >>> 16)
 		cloned._a16 = v & 0xFFFF
 		v = (~cloned._a32 & 0xFFFF) + (v >>> 16)
 		cloned._a32 = v & 0xFFFF
 		cloned._a48 = (~cloned._a48 + (v >>> 16)) & 0xFFFF

        cloned._string = null;

 		return cloned
 	}

 	/**

 	 * @method eq
 	 * @param {Object} other uint64
 	 * @return {Boolean}
 	 */
 	function eq(other) {
    other = uint64(other)
 		return (this._a48 == other._a48) && (this._a00 == other._a00)
 			 && (this._a32 == other._a32) && (this._a16 == other._a16)
 	}

 	/**
 	 * Greater than (strict)
 	 * @method gt
 	 * @param {Object} other uint64
 	 * @return {Boolean}
 	 */
 	function gt(other) {
    other = uint64(other)
 		if (this._a48 > other._a48) return true
 		if (this._a48 < other._a48) return false
 		if (this._a32 > other._a32) return true
 		if (this._a32 < other._a32) return false
 		if (this._a16 > other._a16) return true
 		if (this._a16 < other._a16) return false
 		return this._a00 > other._a00
 	}

 	/**
 	 * Less than (strict)
 	 * @method lt
 	 * @param {Object} other uint64
 	 * @return {Boolean}
 	 */
 	function lt(other) {
    other = uint64(other)
 		if (this._a48 < other._a48) return true
 		if (this._a48 > other._a48) return false
 		if (this._a32 < other._a32) return true
 		if (this._a32 > other._a32) return false
 		if (this._a16 < other._a16) return true
 		if (this._a16 > other._a16) return false
 		return this._a00 < other._a00
 	}

 	//TODO: Look into implementing a cmp function that everything can use for code space?
 	function lte(other) {
 		return this.eq(other) || this.lt(other)
 	}

 	function gte(other) {
 		return this.eq(other) || this.gt(other)
 	}

 	/**

 	 * @method eq
 	 * @param {Object} other uint64
 	 * @return {Boolean}
 	 */
 	function eq_u64(other) {
 		return (this._a48 == other._a48) && (this._a00 == other._a00)
 			 && (this._a32 == other._a32) && (this._a16 == other._a16)
 	}

 	/**
 	 * Greater than (strict)
 	 * @method gt
 	 * @param {Object} other uint64
 	 * @return {Boolean}
 	 */
 	function gt_u64(other) {
 		if (this._a48 > other._a48) return true
 		if (this._a48 < other._a48) return false
 		if (this._a32 > other._a32) return true
 		if (this._a32 < other._a32) return false
 		if (this._a16 > other._a16) return true
 		if (this._a16 < other._a16) return false
 		return this._a00 > other._a00
 	}

 	/**
 	 * Less than (strict)
 	 * @method lt
 	 * @param {Object} other uint64
 	 * @return {Boolean}
 	 */
 	function lt_u64(other) {
 		if (this._a48 < other._a48) return true
 		if (this._a48 > other._a48) return false
 		if (this._a32 < other._a32) return true
 		if (this._a32 > other._a32) return false
 		if (this._a16 < other._a16) return true
 		if (this._a16 > other._a16) return false
 		return this._a00 < other._a00
 	}

 	//TODO: Look into implementing a cmp function that everything can use for code space?
 	function lte_u64(other) {
 		return this.eq_u64(other) || this.lt_u64(other)
 	}

 	function gte_u64(other) {
 		return this.eq_u64(other) || this.gt_u64(other)
 	}

 	/**
 	 * Bitwise OR
 	 * @method or
 	 * @param {Object} other uint64
 	 * @return ThisExpression
 	 */
 	function or(other) {
 		other = uint64(other)
 		other._a00 = this._a00 | other._a00
 		other._a16 = this._a16 | other._a16
 		other._a32 = this._a32 | other._a32
 		other._a48 = this._a48 | other._a48

    other._string = null;

 		return other
 	}

 	/**
 	 * Bitwise AND
 	 * @method and
 	 * @param {Object} other uint64
 	 * @return ThisExpression
 	 */
 	function and(other) {
 		other = uint64(other)
 		other._a00 = this._a00 & other._a00
 		other._a16 = this._a16 & other._a16
 		other._a32 = this._a32 & other._a32
 		other._a48 = this._a48 & other._a48

    other._string = null;

 		return other
 	}

 	/**
 	 * Bitwise XOR
 	 * @method xor
 	 * @param {Object} other uint64
 	 * @return ThisExpression
 	 */
 	function xor(other) {
 		other = uint64(other)
 		other._a00 = this._a00 ^ other._a00
 		other._a16 = this._a16 ^ other._a16
 		other._a32 = this._a32 ^ other._a32
 		other._a48 = this._a48 ^ other._a48

    other._string = null;

 		return other
 	}

 	/**
 	 * Bitwise NOT
 	 * @method not
 	 * @return ThisExpression
 	 */
 	function not() {
    local cloned = clone(this)
 		cloned._a00 = ~this._a00 & 0xFFFF
 		cloned._a16 = ~this._a16 & 0xFFFF
 		cloned._a32 = ~this._a32 & 0xFFFF
 		cloned._a48 = ~this._a48 & 0xFFFF

    cloned._string = null;

 		return cloned
 	}

 	/**
 	 * Bitwise shift right
 	 * @method shiftRight
 	 * @param {Number} number of bits to shift
 	 * @return ThisExpression
 	 */
 	function shiftRight(n) {
    local cloned = clone(this)
 		n %= 64
 		if (n >= 48) {
 			cloned._a00 = cloned._a48 >> (n - 48)
 			cloned._a16 = 0
 			cloned._a32 = 0
 			cloned._a48 = 0
 		} else if (n >= 32) {
 			n -= 32
 			cloned._a00 = ( (cloned._a32 >> n) | (cloned._a48 << (16-n)) ) & 0xFFFF
 			cloned._a16 = (cloned._a48 >> n) & 0xFFFF
 			cloned._a32 = 0
 			cloned._a48 = 0
 		} else if (n >= 16) {
 			n -= 16
 			cloned._a00 = ( (cloned._a16 >> n) | (cloned._a32 << (16-n)) ) & 0xFFFF
 			cloned._a16 = ( (cloned._a32 >> n) | (cloned._a48 << (16-n)) ) & 0xFFFF
 			cloned._a32 = (cloned._a48 >> n) & 0xFFFF
 			cloned._a48 = 0
 		} else {
 			cloned._a00 = ( (cloned._a00 >> n) | (cloned._a16 << (16-n)) ) & 0xFFFF
 			cloned._a16 = ( (cloned._a16 >> n) | (cloned._a32 << (16-n)) ) & 0xFFFF
 			cloned._a32 = ( (cloned._a32 >> n) | (cloned._a48 << (16-n)) ) & 0xFFFF
 			cloned._a48 = (cloned._a48 >> n) & 0xFFFF
 		}

    cloned._string = null;

 		return cloned
 	}

 	/**
 	 * Bitwise shift left
 	 * @method shiftLeft
 	 * @param {Number} number of bits to shift
 	 * @param {Boolean} allow overflow
 	 * @return ThisExpression
 	 */
 	function shiftLeft(n, allowOverflow) {
    local cloned = clone(this)
    n %= 64
 		if (n >= 48) {
 			cloned._a48 = cloned._a00 << (n - 48)
 			cloned._a32 = 0
 			cloned._a16 = 0
 			cloned._a00 = 0
 		} else if (n >= 32) {
 			n -= 32
 			cloned._a48 = (cloned._a16 << n) | (cloned._a00 >> (16-n))
 			cloned._a32 = (cloned._a00 << n) & 0xFFFF
 			cloned._a16 = 0
 			cloned._a00 = 0
 		} else if (n >= 16) {
 			n -= 16
 			cloned._a48 = (cloned._a32 << n) | (cloned._a16 >> (16-n))
 			cloned._a32 = ( (cloned._a16 << n) | (cloned._a00 >> (16-n)) ) & 0xFFFF
 			cloned._a16 = (cloned._a00 << n) & 0xFFFF
 			cloned._a00 = 0
 		} else {
 			cloned._a48 = (cloned._a48 << n) | (cloned._a32 >> (16-n))
 			cloned._a32 = ( (cloned._a32 << n) | (cloned._a16 >> (16-n)) ) & 0xFFFF
 			cloned._a16 = ( (cloned._a16 << n) | (cloned._a00 >> (16-n)) ) & 0xFFFF
 			cloned._a00 = (cloned._a00 << n) & 0xFFFF
 		}
 		if (!allowOverflow) {
 			cloned._a48 = cloned._a48 & 0xFFFF
 		}

    cloned._string = null;

 		return cloned
 	}

 	/**
 	 * Bitwise rotate left
 	 * @method rotl
 	 * @param {Number} number of bits to rotate
 	 * @return ThisExpression
 	 */
 	function rotl(n) {
 		n %= 64
 		if (n == 0) return this

    local cloned = clone(this)
 		if (n >= 32) {
 			// A.B.C.D
 			// B.C.D.A rotl(16)
 			// C.D.A.B rotl(32)
 			local v = cloned._a00
 			cloned._a00 = cloned._a32
 			cloned._a32 = v
 			v = cloned._a48
 			cloned._a48 = cloned._a16
 			cloned._a16 = v
 			if (n == 32) return cloned
 			n -= 32
 		}

 		local high = (cloned._a48 << 16) | cloned._a32
 		local low = (cloned._a16 << 16) | cloned._a00

 		local _high = (high << n) | (low >>> (32 - n))
 		local _low = (low << n) | (high >>> (32 - n))

 		cloned._a00 = _low & 0xFFFF
 		cloned._a16 = _low >>> 16
 		cloned._a32 = _high & 0xFFFF
 		cloned._a48 = _high >>> 16

    cloned._string = null;

 		return cloned
 	}

 	/**
 	 * Bitwise rotate right
 	 * @method rotr
 	 * @param {Number} number of bits to rotate
 	 * @return ThisExpression
 	 */
 	function rotr(n) {
 		n %= 64
 		if (n == 0) return this

    local cloned = clone(this)
 		if (n >= 32) {
 			// A.B.C.D
 			// D.A.B.C rotr(16)
 			// C.D.A.B rotr(32)
 			local v = cloned._a00
 			cloned._a00 = cloned._a32
 			cloned._a32 = v
 			v = cloned._a48
 			cloned._a48 = cloned._a16
 			cloned._a16 = v
 			if (n == 32) return cloned
 			n -= 32
 		}

 		local high = (cloned._a48 << 16) | cloned._a32
 		local low = (cloned._a16 << 16) | cloned._a00

 		local _high = (high >>> n) | (low << (32 - n))
 		local _low = (low >>> n) | (high << (32 - n))

 		cloned._a00 = _low & 0xFFFF
 		cloned._a16 = _low >>> 16
 		cloned._a32 = _high & 0xFFFF
 		cloned._a48 = _high >>> 16

    cloned._string = null;

 		return cloned
 	}

 	/**
 	 * Used with JSONEncoder.encode to allow for properly JSONizing big numbers
 	 * @method _serialize
 	 * @return {[type]}   [description]
 	 */
 	 function _serializeRaw(){
 		 return this.toString();
 	 }

   function _tostring(){
     return format("%.4X %.4X %.4X %.4X - r=%d", this._a00, this._a16, this._a32 ,this._a48, this.remainder().toNumber())
   }
 }

 uint64._initCreateStringValues();
