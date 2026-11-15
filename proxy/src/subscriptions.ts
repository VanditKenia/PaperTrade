// Bookkeeping for the WebSocket relay. Pure: no sockets, so it can be unit
// tested. The relay subscribes upstream to the union of what clients want.

export type SubscribeResult =
  | "subscribe-upstream" // first client for this symbol: tell Finnhub
  | "added" // someone already had it upstream
  | "duplicate" // this client already had it
  | "client-limit" // this client holds too many symbols
  | "upstream-limit"; // the one upstream connection is full

const SYMBOL = /^[A-Z0-9][A-Z0-9.:-]{0,29}$/;

export class SubscriptionBook {
  private readonly byClient = new Map<string, Set<string>>();
  private readonly holders = new Map<string, number>(); // symbol → clients

  constructor(
    private readonly maxPerClient = 50,
    // Finnhub free keys allow 50 symbols per connection.
    private readonly maxUpstream = 50,
  ) {}

  subscribe(client: string, symbol: string): SubscribeResult {
    const mine = this.byClient.get(client) ?? new Set<string>();
    if (mine.has(symbol)) return "duplicate";
    if (mine.size >= this.maxPerClient) return "client-limit";
    const count = this.holders.get(symbol) ?? 0;
    if (count === 0 && this.holders.size >= this.maxUpstream) {
      return "upstream-limit";
    }
    mine.add(symbol);
    this.byClient.set(client, mine);
    this.holders.set(symbol, count + 1);
    return count === 0 ? "subscribe-upstream" : "added";
  }

  // True when nobody needs [symbol] any more: unsubscribe upstream.
  unsubscribe(client: string, symbol: string): boolean {
    const mine = this.byClient.get(client);
    if (mine === undefined || !mine.delete(symbol)) return false;
    return this.release(symbol);
  }

  // A client left. Returns the symbols nobody needs any more.
  removeClient(client: string): string[] {
    const mine = this.byClient.get(client);
    this.byClient.delete(client);
    if (mine === undefined) return [];
    return [...mine].filter((s) => this.release(s));
  }

  symbolsOf(client: string): ReadonlySet<string> {
    return this.byClient.get(client) ?? new Set();
  }

  // Everything the upstream connection should be subscribed to.
  union(): string[] {
    return [...this.holders.keys()];
  }

  private release(symbol: string): boolean {
    const count = (this.holders.get(symbol) ?? 1) - 1;
    if (count > 0) {
      this.holders.set(symbol, count);
      return false;
    }
    this.holders.delete(symbol);
    return true;
  }
}

export interface ClientMessage {
  type: "subscribe" | "unsubscribe";
  symbol: string;
}

// Same JSON the app would send to Finnhub:
// {"type":"subscribe","symbol":"AAPL"}. Null for anything else.
export function parseClientMessage(raw: unknown): ClientMessage | null {
  if (typeof raw !== "string" || raw.length > 200) return null;
  let msg: unknown;
  try {
    msg = JSON.parse(raw);
  } catch {
    return null;
  }
  if (typeof msg !== "object" || msg === null) return null;
  const { type, symbol } = msg as Record<string, unknown>;
  if (type !== "subscribe" && type !== "unsubscribe") return null;
  if (typeof symbol !== "string" || !SYMBOL.test(symbol)) return null;
  return { type, symbol };
}

// The trades in a Finnhub `data` array that [symbols] cares about, so each
// client only gets what it subscribed to.
export function tradesFor(data: unknown, symbols: ReadonlySet<string>): unknown[] {
  if (!Array.isArray(data)) return [];
  return data.filter(
    (t) =>
      typeof t === "object" &&
      t !== null &&
      symbols.has((t as Record<string, unknown>).s as string),
  );
}
