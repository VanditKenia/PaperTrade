// Fixed-window rate limiter keyed by client IP.
//
// shortcut: state lives in this Worker isolate's memory, so each isolate
// (per data center, recycled now and then) counts on its own: a soft
// limit, not an exact one. Upgrade to Cloudflare's Rate Limiting binding
// or a Durable Object if exact counts ever matter.

export interface RateLimitResult {
  allowed: boolean;
  retryAfterSeconds: number; // 0 when allowed
}

export class RateLimiter {
  private readonly windows = new Map<string, { start: number; count: number }>();

  constructor(
    private readonly limit = 60,
    private readonly windowMs = 60_000,
    private readonly now: () => number = Date.now,
  ) {}

  hit(key: string): RateLimitResult {
    const now = this.now();
    let w = this.windows.get(key);
    if (w === undefined || now - w.start >= this.windowMs) {
      w = { start: now, count: 0 };
      this.windows.set(key, w);
      this.prune(now);
    }
    w.count++;
    if (w.count <= this.limit) return { allowed: true, retryAfterSeconds: 0 };
    return {
      allowed: false,
      retryAfterSeconds: Math.ceil((w.start + this.windowMs - now) / 1000),
    };
  }

  // Keeps memory bounded when many IPs pass through: expired windows go.
  private prune(now: number): void {
    if (this.windows.size < 10_000) return;
    for (const [key, w] of this.windows) {
      if (now - w.start >= this.windowMs) this.windows.delete(key);
    }
  }
}
