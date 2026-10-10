// Bundle storage abstraction for /auth/<script_id>/payload.
// The schema stores only `script_versions.blob_ref`; the bytes live outside
// D1. Production wires an R2 bucket binding (index.ts); tests use the
// in-memory store. This is a Tier 2 decision (DECISIONS-M1.md) — the ref
// format is a plain string owned by whoever uploads builds (M13/M5).

export interface BlobStore {
  get(ref: string): Promise<Uint8Array | null>;
}

export class MemoryBlobStore implements BlobStore {
  private readonly blobs = new Map<string, Uint8Array>();

  put(ref: string, bytes: Uint8Array): void {
    this.blobs.set(ref, bytes);
  }

  delete(ref: string): void {
    this.blobs.delete(ref);
  }

  get(ref: string): Promise<Uint8Array | null> {
    return Promise.resolve(this.blobs.get(ref) ?? null);
  }
}

export interface R2ObjectLike {
  body: ArrayBuffer;
  size: number;
}

export interface R2BucketLike {
  get(key: string): Promise<R2ObjectLike | null>;
}

export class R2BlobStore implements BlobStore {
  constructor(private readonly bucket: R2BucketLike) {}

  async get(ref: string): Promise<Uint8Array | null> {
    const obj = await this.bucket.get(ref);
    if (obj === null) return null;
    return new Uint8Array(obj.body);
  }
}
