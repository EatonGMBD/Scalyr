/**
 * [min description]
 * @method min
 * @param  {[type]} ... [description]
 * @return {[type]}     [description]
 */
function min(...) {
    local minimum = vargv[0]
    for(local i = 1; i< vargv.len(); i++) {
    	if (vargv[i] < minimum) {
          minimum  = vargv[i];
        }
    }
    return minimum;
}
