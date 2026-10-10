// Minimal ambient declaration for node:sqlite (Node >= 22.5). @types/node
// (v20 in this sandbox) doesn't ship it, but `next dev` runs on a Node new
// enough to provide the module at runtime. The api/ adapter only uses
// new DatabaseSync(path) + prepare/run/all/exec — declaring exactly that.

declare module "node:sqlite" {
  interface StatementSync {
    run(...params: unknown[]): { changes: number | bigint; lastInsertRowid: number | bigint };
    all(...params: unknown[]): unknown[];
    get(...params: unknown[]): unknown;
  }
  class DatabaseSync {
    constructor(path: string, options?: { open?: boolean });
    prepare(sql: string): StatementSync;
    exec(sql: string): void;
    close(): void;
  }
}
