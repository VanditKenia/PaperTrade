import { describe, expect, it } from "vitest";
import { RateLimiter } from "../src/rate_limit";

describe("RateLimiter", () => {
  it("allows the limit per window, then refuses with Retry-After", () => {
    let now = 0;
    const limiter = new RateLimiter(3, 60_000, () => now);
    expect([1, 2, 3].map(() => limiter.hit("1.1.1.1").allowed)).toEqual([true, true, true]);
    now = 15_000;
    expect(limiter.hit("1.1.1.1")).toEqual({ allowed: false, retryAfterSeconds: 45 });
  });

  it("starts a fresh window after it expires", () => {
    let now = 0;
    const limiter = new RateLimiter(1, 60_000, () => now);
    limiter.hit("ip");
    expect(limiter.hit("ip").allowed).toBe(false);
    now = 60_000;
    expect(limiter.hit("ip").allowed).toBe(true);
  });

  it("counts each IP separately", () => {
    const limiter = new RateLimiter(1, 60_000, () => 0);
    expect(limiter.hit("a").allowed).toBe(true);
    expect(limiter.hit("b").allowed).toBe(true);
    expect(limiter.hit("a").allowed).toBe(false);
  });

  it("60 per minute by default in the Worker", () => {
    const limiter = new RateLimiter(60, 60_000, () => 0);
    for (let i = 0; i < 60; i++) expect(limiter.hit("ip").allowed).toBe(true);
    expect(limiter.hit("ip").allowed).toBe(false);
  });
});
