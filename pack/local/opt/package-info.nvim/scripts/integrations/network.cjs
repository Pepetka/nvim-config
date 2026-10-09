const { Network: Controller } = require("../controller.cjs");
const { storage } = require("./cache.cjs");
const { digest } = require("./managers.cjs");
class Network extends Controller {
  /** @param {import("../types").NetworkOptions} [options] */
  constructor(options = {}) {
    super({
      ...options,
      storage: storage(options.cacheDir, Date.now, options),
      now: Date.now,
      digest,
    });
  }
}
module.exports = { Network };
