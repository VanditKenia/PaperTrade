// Durable Object that relays live trades. It holds ONE upstream Finnhub
// WebSocket (free keys allow very few connections), subscribes it to the
// union of what clients want, and sends each client only its own symbols.

import type { Env } from "./handler";
import { parseClientMessage, SubscriptionBook, tradesFor } from "./subscriptions";

const MAX_SYMBOLS_PER_CLIENT = 50;
const MAX_BACKOFF_SECONDS = 30;

export class Relay {
  private readonly book = new SubscriptionBook(MAX_SYMBOLS_PER_CLIENT);
  private readonly clients = new Map<string, WebSocket>();
  private upstream: WebSocket | null = null;
  private connecting = false;
  private failures = 0;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private nextId = 0;

  constructor(
    private readonly state: DurableObjectState,
    private readonly env: Env,
  ) {}

  async fetch(request: Request): Promise<Response> {
    if (request.headers.get("Upgrade") !== "websocket") {
      return new Response("expected websocket", { status: 426 });
    }
    const [client, server] = Object.values(new WebSocketPair()) as [WebSocket, WebSocket];
    server.accept();
    const id = `c${this.nextId++}`;
    this.clients.set(id, server);
    server.addEventListener("message", (e) => this.onClientMessage(id, server, e.data));
    server.addEventListener("close", () => this.removeClient(id));
    server.addEventListener("error", () => this.removeClient(id));
    this.ensureUpstream();
    return new Response(null, { status: 101, webSocket: client });
  }

  private onClientMessage(id: string, socket: WebSocket, raw: unknown): void {
    const msg = parseClientMessage(raw);
    if (msg === null) return send(socket, { type: "error", msg: "invalid message" });

    if (msg.type === "unsubscribe") {
      if (this.book.unsubscribe(id, msg.symbol)) this.sendUpstream("unsubscribe", msg.symbol);
      return;
    }
    switch (this.book.subscribe(id, msg.symbol)) {
      case "subscribe-upstream":
        this.sendUpstream("subscribe", msg.symbol);
        break;
      case "client-limit":
        send(socket, { type: "error", msg: `max ${MAX_SYMBOLS_PER_CLIENT} symbols per client` });
        break;
      case "upstream-limit":
        send(socket, { type: "error", msg: "relay is at its symbol limit" });
        break;
      default: // added / duplicate: nothing to tell Finnhub
    }
  }

  private removeClient(id: string): void {
    if (!this.clients.delete(id)) return;
    for (const symbol of this.book.removeClient(id)) this.sendUpstream("unsubscribe", symbol);
    // Nobody left: drop the upstream so the object can shut down and stop
    // counting against the free plan's duration limit.
    if (this.clients.size === 0) {
      if (this.reconnectTimer !== null) clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
      this.upstream?.close(1000, "no clients");
      this.upstream = null;
    }
  }

  private ensureUpstream(): void {
    if (this.upstream !== null || this.connecting || this.reconnectTimer !== null) return;
    if (this.clients.size === 0) return;
    this.connecting = true;
    void this.connectUpstream().finally(() => (this.connecting = false));
  }

  private async connectUpstream(): Promise<void> {
    const key = this.env.FINNHUB_API_KEY;
    if (!key) return this.closeClients(1011, "proxy not configured");
    // Workers open outgoing WebSockets with fetch + Upgrade. The URL holds
    // the key: never log it.
    const url = new URL("https://ws.finnhub.io");
    url.searchParams.set("token", key);
    let socket: WebSocket | null = null;
    try {
      const res = await fetch(url, { headers: { Upgrade: "websocket" } });
      socket = res.webSocket;
    } catch {
      socket = null;
    }
    if (socket === null) return this.scheduleReconnect();

    socket.accept();
    this.upstream = socket;
    this.failures = 0;
    // A fresh connection knows nothing: subscribe to everything again.
    for (const symbol of this.book.union()) this.sendUpstream("subscribe", symbol);
    socket.addEventListener("message", (e) => this.onUpstreamMessage(e.data));
    const lost = () => {
      if (this.upstream !== socket) return; // already replaced or closed
      this.upstream = null;
      this.scheduleReconnect();
    };
    socket.addEventListener("close", lost);
    socket.addEventListener("error", lost);
  }

  // Exponential backoff (1, 2, 4 … 30 s) so a Finnhub outage or a
  // "too many connections" refusal isn't hammered.
  private scheduleReconnect(): void {
    if (this.clients.size === 0 || this.reconnectTimer !== null) return;
    const delay = Math.min(MAX_BACKOFF_SECONDS, 2 ** this.failures);
    this.failures++;
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      this.ensureUpstream();
    }, delay * 1000);
  }

  private onUpstreamMessage(raw: unknown): void {
    if (typeof raw !== "string") return;
    let msg: { type?: unknown; data?: unknown };
    try {
      msg = JSON.parse(raw) as { type?: unknown; data?: unknown };
    } catch {
      return; // a bad message never breaks the relay
    }
    if (msg.type !== "trade") return; // pings etc. stay here
    for (const [id, socket] of this.clients) {
      const data = tradesFor(msg.data, this.book.symbolsOf(id));
      if (data.length > 0) send(socket, { type: "trade", data });
    }
  }

  private sendUpstream(type: "subscribe" | "unsubscribe", symbol: string): void {
    // Not connected: the union is re-sent when the connection opens.
    if (this.upstream !== null) send(this.upstream, { type, symbol });
  }

  private closeClients(code: number, reason: string): void {
    for (const socket of this.clients.values()) socket.close(code, reason);
  }
}

function send(socket: WebSocket, message: unknown): void {
  try {
    socket.send(JSON.stringify(message));
  } catch {
    // Socket already closing; its close event cleans up.
  }
}
