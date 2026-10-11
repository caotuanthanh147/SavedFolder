import type { Location } from './tokens';

/** Strict fail-loud syntax error (no recovery — one error per parse). */
export class LuauSyntaxError extends Error {
  readonly location: Location;

  constructor(message: string, location: Location) {
    super(`${location.start.line}:${location.start.column}: ${message}`);
    this.name = 'LuauSyntaxError';
    this.location = location;
  }
}
