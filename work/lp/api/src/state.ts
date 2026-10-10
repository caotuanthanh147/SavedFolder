export interface RateDecision {
  ok: boolean;
  retryAfterSec: number;
}

export interface RateLimiter {
  hit(bucket: string, limit: number, windowSec: number): Promise<RateDecision>;
  blocked(bucket: string, limit: number, windowSec: number): Promise<RateDecision>;
}

export interface NonceStore {
  seen(nonce: string, expiresAtSec: number): Promise<boolean>;
}

interface BucketState {
  hits: number[];
}

export class MemoryRateLimiter implements RateLimiter {
  private readonly buckets = new Map<string, BucketState>();

  private trimmed(bucket: string, windowSec: number): BucketState {
    const nowSec = Date.now() / 1000;
    let st = this.buckets.get(bucket);
    if (!st) {
      st = { hits: [] };
      this.buckets.set(bucket, st);
    }
    st.hits = st.hits.filter((t) => nowSec - t < windowSec);
    return st;
  }

  async hit(bucket: string, limit: number, windowSec: number): Promise<RateDecision> {
    const st = this.trimmed(bucket, windowSec);
    if (st.hits.length >= limit) {
      return { ok: false, retryAfterSec: Math.max(1, Math.ceil(windowSec - (Date.now() / 1000 - st.hits[0]))) };
    }
    st.hits.push(Date.now() / 1000);
    return { ok: true, retryAfterSec: 0 };
  }

  async blocked(bucket: string, limit: number, windowSec: number): Promise<RateDecision> {
    const st = this.trimmed(bucket, windowSec);
    if (st.hits.length >= limit) {
      return { ok: false, retryAfterSec: Math.max(1, Math.ceil(windowSec - (Date.now() / 1000 - st.hits[0]))) };
    }
    return { ok: true, retryAfterSec: 0 };
  }
}

export class MemoryNonceStore implements NonceStore {
  private readonly seenNonces = new Map<string, number>();

  async seen(nonce: string, expiresAtSec: number): Promise<boolean> {
    const nowSec = Date.now() / 1000;
    for (const [n, exp] of this.seenNonces) {
      if (exp < nowSec - 3600) this.seenNonces.delete(n);
    }
    if (this.seenNonces.has(nonce)) return true;
    this.seenNonces.set(nonce, expiresAtSec);
    return false;
  }
}
