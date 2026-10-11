/** Smoke: one fixture through the full M5→M6 pipeline on real lua5.4. */
import { describe, expect, test } from 'bun:test';
import { FIXTURES } from '../../compiler/tests/fixtures';
import { buildProtected, runLua, runnerScript } from './helpers';

describe('smoke', () => {
  test('first fixture end-to-end', () => {
    const fixture = FIXTURES[0]!;
    const p = buildProtected(fixture, { dispatch: 'chain' });
    const out = runLua(
      { 'runtime.lua': p.emit.lua, 'main.lua': runnerScript(p) },
      'main.lua',
    );
    expect(out.length).toBeGreaterThan(0);
    console.log('dispatch:', p.emit.dispatch, 'bytes:', p.emit.lua.length);
    console.log(out);
  });
});
