import { describe, expect, it } from "vitest";
import { parseClientMessage, SubscriptionBook, tradesFor } from "../src/subscriptions";

describe("SubscriptionBook: upstream = union of clients", () => {
  it("subscribes upstream only for the first client of a symbol", () => {
    const book = new SubscriptionBook();
    expect(book.subscribe("a", "AAPL")).toBe("subscribe-upstream");
    expect(book.subscribe("b", "AAPL")).toBe("added");
    expect(book.subscribe("a", "AAPL")).toBe("duplicate");
    expect(book.subscribe("b", "MSFT")).toBe("subscribe-upstream");
    expect(book.union().sort()).toEqual(["AAPL", "MSFT"]);
  });

  it("unsubscribes upstream only when no client needs the symbol", () => {
    const book = new SubscriptionBook();
    book.subscribe("a", "AAPL");
    book.subscribe("b", "AAPL");
    expect(book.unsubscribe("a", "AAPL")).toBe(false); // b still wants it
    expect(book.unsubscribe("b", "AAPL")).toBe(true);
    expect(book.union()).toEqual([]);
  });

  it("unsubscribing something you don't hold does nothing", () => {
    const book = new SubscriptionBook();
    book.subscribe("a", "AAPL");
    expect(book.unsubscribe("b", "AAPL")).toBe(false);
    expect(book.unsubscribe("a", "MSFT")).toBe(false);
    expect(book.union()).toEqual(["AAPL"]);
  });

  it("a leaving client releases only symbols nobody else holds", () => {
    const book = new SubscriptionBook();
    book.subscribe("a", "AAPL");
    book.subscribe("a", "TSLA");
    book.subscribe("b", "AAPL");
    expect(book.removeClient("a")).toEqual(["TSLA"]);
    expect(book.union()).toEqual(["AAPL"]);
    expect(book.symbolsOf("a").size).toBe(0);
    expect(book.removeClient("a")).toEqual([]); // twice is harmless
  });

  it("caps symbols per client", () => {
    const book = new SubscriptionBook(2, 50);
    book.subscribe("a", "A");
    book.subscribe("a", "B");
    expect(book.subscribe("a", "C")).toBe("client-limit");
    expect(book.subscribe("b", "C")).toBe("subscribe-upstream"); // others unaffected
  });

  it("caps the upstream union, but a held symbol can still be shared", () => {
    const book = new SubscriptionBook(50, 2);
    book.subscribe("a", "A");
    book.subscribe("b", "B");
    expect(book.subscribe("c", "C")).toBe("upstream-limit");
    expect(book.subscribe("c", "A")).toBe("added");
    expect(book.symbolsOf("c")).toEqual(new Set(["A"]));
  });
});

describe("parseClientMessage", () => {
  it("accepts Finnhub-style subscribe/unsubscribe", () => {
    expect(parseClientMessage('{"type":"subscribe","symbol":"BINANCE:BTCUSDT"}')).toEqual({
      type: "subscribe",
      symbol: "BINANCE:BTCUSDT",
    });
    expect(parseClientMessage('{"type":"unsubscribe","symbol":"AAPL"}')?.type).toBe(
      "unsubscribe",
    );
  });

  it("rejects anything else without throwing", () => {
    for (const raw of [
      "not json",
      "null",
      "[]",
      '{"type":"ping"}',
      '{"type":"subscribe"}',
      '{"type":"subscribe","symbol":"aapl"}',
      '{"type":"subscribe","symbol":123}',
      `{"type":"subscribe","symbol":"${"A".repeat(300)}"}`,
      new ArrayBuffer(4),
    ]) {
      expect(parseClientMessage(raw)).toBeNull();
    }
  });
});

describe("tradesFor", () => {
  const data = [
    { s: "AAPL", p: 189.42, t: 1, v: 10 },
    { s: "MSFT", p: 400.1, t: 2, v: 5 },
    "junk",
    null,
  ];

  it("keeps only the client's symbols", () => {
    expect(tradesFor(data, new Set(["AAPL"]))).toEqual([{ s: "AAPL", p: 189.42, t: 1, v: 10 }]);
    expect(tradesFor(data, new Set())).toEqual([]);
  });

  it("non-array data → nothing", () => {
    expect(tradesFor({ s: "AAPL" }, new Set(["AAPL"]))).toEqual([]);
  });
});
