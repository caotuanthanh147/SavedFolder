import { DurableObject } from "cloudflare:workers";

interface CheckResult {
  ok: boolean;
  retryAfterSec: number;
}

export class RateCounterDO extends DurableObject {
  private async loadHits(windowSec: number): Promise<number[]> {
    const nowSec = Date.now() / 1000;
    const existing = (await this.ctx.storage.get<number[]>("hits")) ?? [];
    return existing.filter((t) => nowSec - t < windowSec);
  }

  async hit(limit: number, windowSec: number): Promise<CheckResult> {
    const storage = this.ctx.storage;
    const nowSec = Date.now() / 1000;
    const hits = await this.loadHits(windowSec);
    if (hits.length >= limit) {
      const oldest = hits[0];
      const retryAfterSec = Math.max(1, Math.ceil(windowSec - (nowSec - oldest)));
      await storage.put("hits", hits);
      return { ok: false, retryAfterSec };
    }
    hits.push(nowSec);
    await storage.put("hits", hits);
    await storage.setAlarm(Math.ceil((nowSec + windowSec) * 1000));
    return { ok: true, retryAfterSec: 0 };
  }

  async blocked(limit: number, windowSec: number): Promise<CheckResult> {
    const hits = await this.loadHits(windowSec);
    if (hits.length >= limit) {
      const oldest = hits[0];
      const retryAfterSec = Math.max(1, Math.ceil(windowSec - (Date.now() / 1000 - oldest)));
      return { ok: false, retryAfterSec };
    }
    return { ok: true, retryAfterSec: 0 };
  }

  async alarm(): Promise<void> {
    const storage = this.ctx.storage;
    const existing = (await storage.get<number[]>("hits")) ?? [];
    if (existing.length === 0) {
      await storage.deleteAll();
      return;
    }
    const newest = existing[existing.length - 1];
    if (Date.now() / 1000 - newest > 3600) await storage.deleteAll();
  }
}

export class NonceDO extends DurableObject {
  async seen(nonce: string, expiresAtSec: number): Promise<boolean> {
    const storage = this.ctx.storage;
    const nowSec = Date.now() / 1000;
    if (await storage.get(nonce)) return true;
    await storage.put(nonce, expiresAtSec);
    await storage.setAlarm(Math.ceil((nowSec + 3600) * 1000));
    return false;
  }

  async alarm(): Promise<void> {
    const storage = this.ctx.storage;
    const nowSec = Date.now() / 1000;
    const entries = await storage.list<number>();
    const stale: string[] = [];
    for (const [key, exp] of entries) {
      if (typeof exp === "number" && exp < nowSec - 3600) stale.push(key);
    }
    if (stale.length > 0) await storage.delete(stale);
    if ((await storage.list<number>()).size === 0) await storage.deleteAll();
  }
}
