/**
 * Package entry (fixes the dangling "module": "src/index.ts" in
 * package.json — D-M4-24). Consumers may still deep-import; this surface
 * is the supported public API of the M4 front end.
 *
 * Byte-string model: every API that accepts or returns string DATA
 * (source text, string literal values) is latin1 char-per-byte — read
 * files with `buf.toString('latin1')`.
 */

export { Lexer, tokenize, parseNumberLiteral } from './lexer';
export type { NumberParseResult } from './lexer';
export { LuauSyntaxError } from './errors';
export { parse } from './parser';
export type { ParseOptions } from './parser';
export { print, quoteString } from './printer';
export { analyze } from './analysis';
export type {
  AnalysisResult, CaptureInfo, ConstEntry, FunctionUnit,
} from './analysis';
export type * from './ast';
