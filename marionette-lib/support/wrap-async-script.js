const args = Array.prototype.slice.call(arguments, 0, arguments.length - 1);
const resolve = arguments[arguments.length - 1];

Promise
  .resolve()
  .then(() => (function() { @body })(...args))
  .then((value) => resolve({ error: null, value }))
  .catch((error) => resolve({ error: error instanceof Error ? error.message : error, value: null }));
