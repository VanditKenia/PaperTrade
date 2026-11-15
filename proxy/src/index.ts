// Worker entry: wires the real runtime pieces into handle().

import { type CacheLike, type Env, handle } from "./handler";
import { RateLimiter } from "./rate_limit";

export { Relay } from "./relay";

// Module scope: lives as long as this isolate (see the rate_limit shortcut).
const limiter = new RateLimiter(60, 60_000);

const edgeCache: CacheLike = {
  match: (key) => caches.default.match(key),
  put: (key, response) => caches.default.put(key, response),
};

export default {
  fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    return handle(request, env, {
      fetch: (input, init) => fetch(input, init),
      cache: edgeCache,
      limiter,
      waitUntil: (p) => ctx.waitUntil(p),
    });
  },
} satisfies ExportedHandler<Env>;
