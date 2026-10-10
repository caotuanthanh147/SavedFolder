/**
 * Strict Luau lexer.
 *
 * Behavioral spec (all checked against the reference implementation,
 * luau-lang/luau @ master, files Ast/src/Lexer.cpp + Ast/src/Parser.cpp,
 * fetched 2026-10-10 — MIT; used as a SPEC, no code copied):
 *
 *  - Whitespace: ' ' \t \v \f \r skipped; ONLY '\n' advances the line counter.
 *  - Comments: `--` to end of line; `--[[ ]]` / `--[=[ ]=]` level blocks
 *    (unterminated = error). `---` doc comments are skipped the same way.
 *  - Names: ASCII [A-Za-z_][A-Za-z0-9_]* only; bytes >= 0x80 outside
 *    strings/comments are errors (readUtf8Error).
 *  - Numbers: skip pattern = [0-9._]* then optional e/E[+-] then [A-Za-z0-9_]*;
 *    `.5` lexes as a number (Lexer.cpp case '.'). Validation per
 *    Parser.cpp parseNumber/parseDouble: strip `_`; trailing `i` => int64;
 *    `0b` binary / `0x` hex as u64 bit patterns (hex/binary have NO p- or
 *    e-exponents); otherwise strtod-shape decimal (digits [. digits] [exp]),
 *    trailing junk = malformed.
 *  - Quoted strings (' or "): no bare \r \n \0 (error). Escapes
 *    (Lexer.cpp fixupQuotedString): \<newline> (LF; CRLF collapses),
 *    \xHH (exactly 2 hex), \z (skip whitespace), \u{1..16 hex} (UTF-8
 *    encode, must be <= 0x10FFFF, non-empty), \ddd (1-3 digits, <= 255),
 *    \a\b\f\n\r\t\v, any other char maps to itself.
 *  - Long strings ([[ ]], [=[ ]=], ...): raw bytes; first newline (\n or
 *    \r\n) skipped; newlines normalized to \n; standalone \r kept as a byte
 *    (fixupMultilineString). Unterminated = error.
 *  - Interpolated strings (`backtick`): sections split at `{` (expression
 *    start) and resumed after the matching `}`; `{{` = error; `\u{` does
 *    NOT start an expression; bare \r \n \0 inside = error; escapes decoded
 *    like quoted strings (Parser.cpp parseInterpString runs the same
 *    fixupQuotedString on each section).
 *  - Brace tracking (Lexer.cpp cases '{' / '}'): '{' inside an interpolation
 *    context pushes Normal; '}' pops and, when it closes an interpolation
 *    section, resumes the section lexer (InterpStringMid/End).
 *  - Attributes: `@name` (Lexer.cpp case '@'), `@[` opens an attribute list.
 *  - Operators incl. Luau additions: `//`, `//=` floor-div, `+= -= *= /= %=`
 *    `^=` `..=` compound assigns, `::` double colon; single `&` `|` `!` `?`
 *    `~` tokens (combined into `&&`/`||`/`!=` by the PARSER with an adjacency
 *    check — checkBinaryConfusables — so the lexer must NOT fuse them).
 *
 * Byte-string model: the source must be a "latin1-style" JS string where each
 * char code is one byte (read files via buf.toString('latin1')). Decoded
 * string values use the same model; `\u{...}` expands to UTF-8 bytes, each
 * byte one char code, mirroring Luau's toUtf8-into-byte-buffer.
 */

import { LuauSyntaxError } from './errors';
import { reservedWordType, TokenType } from './tokens';
import type { Position, Token } from './tokens';

const EOF_CHAR = -1;

function isDigit(ch: number): boolean {
  return ch >= 0x30 && ch <= 0x39;
}
function isHexDigit(ch: number): boolean {
  return isDigit(ch) || (ch >= 0x61 && ch <= 0x66) || (ch >= 0x41 && ch <= 0x46);
}
function isAlpha(ch: number): boolean {
  return (ch >= 0x61 && ch <= 0x7a) || (ch >= 0x41 && ch <= 0x5a);
}
function isNameChar(ch: number): boolean {
  return isAlpha(ch) || isDigit(ch) || ch === 0x5f; // '_'
}
function isSpace(ch: number): boolean {
  return ch === 0x20 || ch === 0x09 || ch === 0x0a || ch === 0x0b || ch === 0x0c || ch === 0x0d;
}

/** UTF-8 encode a code point into the byte-string model. Returns [] if invalid. */
function utf8Encode(codePoint: number): number[] {
  if (codePoint < 0x80) return [codePoint];
  if (codePoint < 0x800) return [0xc0 | (codePoint >> 6), 0x80 | (codePoint & 0x3f)];
  if (codePoint < 0x10000)
    return [0xe0 | (codePoint >> 12), 0x80 | ((codePoint >> 6) & 0x3f), 0x80 | (codePoint & 0x3f)];
  if (codePoint < 0x110000)
    return [
      0xf0 | (codePoint >> 18),
      0x80 | ((codePoint >> 12) & 0x3f),
      0x80 | ((codePoint >> 6) & 0x3f),
      0x80 | (codePoint & 0x3f),
    ];
  return [];
}

function unescapeChar(ch: number): number {
  switch (ch) {
    case 0x61: return 0x07; // \a
    case 0x62: return 0x08; // \b
    case 0x66: return 0x0c; // \f
    case 0x6e: return 0x0a; // \n
    case 0x72: return 0x0d; // \r
    case 0x74: return 0x09; // \t
    case 0x76: return 0x0b; // \v
    default: return ch;
  }
}

/** Result of number literal validation (mirrors ConstantNumberParseResult). */
export type NumberParseResult =
  | { kind: 'double'; value: number }
  | { kind: 'int64'; value: bigint }
  | { error: string };

/**
 * Validate + convert a raw number literal per Parser.cpp parseNumber.
 * `raw` is the token text exactly as lexed (may contain `_` separators).
 */
export function parseNumberLiteral(raw: string): NumberParseResult {
  let text = '';
  for (let i = 0; i < raw.length; i++) {
    if (raw.charCodeAt(i) !== 0x5f) text += raw[i]; // strip '_'
  }
  if (text.length === 0) return { error: 'malformed number' };

  const int64Suffix = text.charCodeAt(text.length - 1) === 0x69; // 'i'
  if (int64Suffix) text = text.slice(0, -1);
  if (text.length === 0) return { error: 'malformed number' };

  const lower = text.toLowerCase();
  if (lower.startsWith('0x') || lower.startsWith('0b')) {
    // hex / binary integer bit patterns (at least one digit after prefix)
    const isHex = lower.startsWith('0x');
    const digits = text.slice(2);
    if (digits.length === 0) return { error: 'malformed number' };
    for (let i = 0; i < digits.length; i++) {
      const ok = isHex ? isHexDigit(digits.charCodeAt(i)) : digits.charCodeAt(i) === 0x30 || digits.charCodeAt(i) === 0x31;
      if (!ok) return { error: 'malformed number' };
    }
    const value = BigInt(text);
    const max = int64Suffix ? 0xffffffffffffffffn : 0xffffffffffffffffn;
    if (value > max) return { error: int64Suffix ? 'integer overflow' : 'number overflow' };
    if (int64Suffix) return { kind: 'int64', value: BigInt.asIntN(64, value) };
    return { kind: 'double', value: Number(value) };
  }

  if (int64Suffix) {
    // decimal int64 (strtoll + 'i'): full decimal digits, signed 64-bit range
    if (!/^[0-9]+$/.test(text)) return { error: 'malformed integer' };
    const value = BigInt(text);
    if (value > 9223372036854775807n) return { error: 'integer overflow' };
    return { kind: 'int64', value };
  }

  // strtod-shape decimal: D* [. D*] ([eE] [+/-] D+)? with at least one digit
  if (!/^(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$/.test(text)) {
    return { error: 'malformed number' };
  }
  return { kind: 'double', value: Number(text) };
}

type BraceKind = 'normal' | 'interp';

export class Lexer {
  private readonly source: string;
  private offset = 0;
  private line = 1;
  private lineStart = 0;
  private readonly braceStack: BraceKind[] = [];

  constructor(source: string) {
    this.source = source;
  }

  /** Tokenize the whole input; throws LuauSyntaxError on malformed input. */
  tokenize(): Token[] {
    const tokens: Token[] = [];
    for (;;) {
      const token = this.next();
      tokens.push(token);
      if (token.type === TokenType.Eof) break;
    }
    return tokens;
  }

  // ---- position helpers -------------------------------------------------

  private pos(at: number): Position {
    return { line: this.line, column: at - this.lineStart, offset: at };
  }
  /** C-string semantics: a NUL byte (char code 0) terminates the source. */
  private peek(ahead = 0): number {
    const i = this.offset + ahead;
    if (i >= this.source.length) return EOF_CHAR;
    const c = this.source.charCodeAt(i);
    return c === 0 ? EOF_CHAR : c;
  }
  private advance(): void {
    const ch = this.source.charCodeAt(this.offset);
    this.offset++;
    if (ch === 0x0a) {
      this.line++;
      this.lineStart = this.offset;
    }
  }
  private err(message: string, start: number): never {
    const end = Math.min(this.offset + 1, this.source.length);
    throw new LuauSyntaxError(message, {
      start: this.pos(start),
      end: this.pos(end),
    });
  }

  // ---- main loop --------------------------------------------------------

  private next(): Token {
    this.skipWhitespaceAndComments();
    const start = this.offset;
    if (this.peek() === EOF_CHAR) {
      return this.make(TokenType.Eof, start);
    }
    const ch = this.peek();

    if (isDigit(ch)) return this.readNumber(start);
    if (isAlpha(ch) || ch === 0x5f) return this.readName(start);

    switch (ch) {
      case 0x22: // '"'
      case 0x27: // '\''
        return this.readQuotedString(start);
      case 0x60: // '`'
        this.advance();
        return this.readInterpSection(start, TokenType.InterpStringBegin, TokenType.InterpStringSimple);
      case 0x5b: // '['
        return this.readLeftBracketOrLongString(start);
      case 0x2e: // '.'
        return this.readDot(start);
      case 0x2b: return this.readAssignable(start, TokenType.Plus, TokenType.PlusAssign); // +
      case 0x2d: return this.readMinus(start); // -
      case 0x2a: return this.readAssignable(start, TokenType.Star, TokenType.StarAssign); // *
      case 0x2f: return this.readSlash(start); // /
      case 0x25: return this.readAssignable(start, TokenType.Percent, TokenType.PercentAssign); // %
      case 0x5e: return this.readAssignable(start, TokenType.Caret, TokenType.CaretAssign); // ^
      case 0x3d: { // '='
        this.advance();
        if (this.peek() === 0x3d) {
          this.advance();
          return this.make(TokenType.Equal, start);
        }
        return this.make(TokenType.Assign, start);
      }
      case 0x7e: { // '~'
        this.advance();
        if (this.peek() === 0x3d) {
          this.advance();
          return this.make(TokenType.TildeEqual, start);
        }
        return this.make(TokenType.Tilde, start);
      }
      case 0x3c: { // '<'
        this.advance();
        if (this.peek() === 0x3d) {
          this.advance();
          return this.make(TokenType.LessEqual, start);
        }
        return this.make(TokenType.Less, start);
      }
      case 0x3e: { // '>'
        this.advance();
        if (this.peek() === 0x3d) {
          this.advance();
          return this.make(TokenType.GreaterEqual, start);
        }
        return this.make(TokenType.Greater, start);
      }
      case 0x3a: { // ':'
        this.advance();
        if (this.peek() === 0x3a) {
          this.advance();
          return this.make(TokenType.DoubleColon, start);
        }
        return this.make(TokenType.Colon, start);
      }
      case 0x40: // '@'
        return this.readAttribute(start);
      case 0x7b: { // '{'
        this.advance();
        if (this.braceStack.length > 0) this.braceStack.push('normal');
        return this.make(TokenType.LeftBrace, start);
      }
      case 0x7d: // '}'
        return this.readRightBrace(start);
      case 0x28:
        this.advance();
        return this.make(TokenType.LeftParen, start);
      case 0x29:
        this.advance();
        return this.make(TokenType.RightParen, start);
      case 0x5d:
        this.advance();
        return this.make(TokenType.RightBracket, start);
      case 0x3b:
        this.advance();
        return this.make(TokenType.Semicolon, start);
      case 0x2c:
        this.advance();
        return this.make(TokenType.Comma, start);
      case 0x23: // '#'
        this.advance();
        return this.make(TokenType.Hash, start);
      case 0x3f: // '?'
        this.advance();
        return this.make(TokenType.QuestionMark, start);
      case 0x26: // '&'
        this.advance();
        return this.make(TokenType.Amp, start);
      case 0x7c: // '|'
        this.advance();
        return this.make(TokenType.Pipe, start);
      case 0x21: // '!'
        this.advance();
        return this.make(TokenType.Bang, start);
      default:
        if (ch >= 0x80) this.err('Non-ASCII byte is not allowed outside strings and comments', start);
        this.err(`Unexpected character '${String.fromCharCode(ch)}'`, start);
    }
  }

  private make(type: TokenType, start: number, value?: string): Token {
    return { type, location: { start: this.pos(start), end: this.pos(this.offset) }, value };
  }

  // ---- whitespace / comments --------------------------------------------

  private skipWhitespaceAndComments(): void {
    for (;;) {
      const ch = this.peek();
      if (ch === EOF_CHAR) return;
      if (isSpace(ch)) {
        this.advance();
        continue;
      }
      if (ch === 0x2d && this.peek(1) === 0x2d) {
        // '--' comment start
        const start = this.offset;
        if (this.peek(2) === 0x5b) {
          // possible long comment: check level
          let level = 0;
          let i = this.offset + 3;
          while (this.source.charCodeAt(i) === 0x3d) {
            level++;
            i++;
          }
          if (this.source.charCodeAt(i) === 0x5b) {
            this.advance();
            this.advance();
            this.skipLongBracketBody(level, start);
            continue;
          }
        }
        // line comment: skip to \n or \r (exclusive) [readCommentBody stops at \r and \n]
        while (this.peek() !== EOF_CHAR && this.peek() !== 0x0a && this.peek() !== 0x0d) this.advance();
        continue;
      }
      return;
    }
  }

  /** Skip the body of a long-bracket construct opened with [=* level N. `this.offset` sits after the opening `[`. */
  private skipLongBracketBody(level: number, start: number): void {
    for (;;) {
      const ch = this.peek();
      if (ch === EOF_CHAR) this.err('Unfinished long comment/string', start);
      if (ch === 0x5d) {
        // ']' followed by level '='s and ']'?
        let i = this.offset + 1;
        let k = 0;
        while (k < level && this.source.charCodeAt(i) === 0x3d) {
          k++;
          i++;
        }
        if (k === level && this.source.charCodeAt(i) === 0x5d) {
          // consume everything up to and including the closing bracket
          while (this.offset <= i) this.advance();
          return;
        }
      }
      this.advance();
    }
  }

  // ---- names / numbers / attributes --------------------------------------

  private readName(start: number): Token {
    this.advance(); // first char already validated
    while (isNameChar(this.peek())) this.advance();
    const text = this.source.slice(start, this.offset);
    const reserved = reservedWordType(text);
    return this.make(reserved ?? TokenType.Name, start, reserved ? undefined : text);
  }

  private readNumber(start: number): Token {
    // skip pattern per Lexer.cpp readNumber (digits, '.', '_')
    do {
      this.advance();
    } while (isDigit(this.peek()) || this.peek() === 0x2e || this.peek() === 0x5f);
    if (this.peek() === 0x65 || this.peek() === 0x45) {
      // 'e' / 'E'
      this.advance();
      if (this.peek() === 0x2b || this.peek() === 0x2d) this.advance();
    }
    while (isNameChar(this.peek())) this.advance();
    return this.make(TokenType.Number, start, this.source.slice(start, this.offset));
  }

  private readAttribute(start: number): Token {
    this.advance(); // '@'
    if (this.peek() === 0x5b) {
      this.advance();
      return this.make(TokenType.AttributeOpen, start);
    }
    if (isAlpha(this.peek()) || this.peek() === 0x5f) {
      const nameStart = this.offset;
      this.advance();
      while (isNameChar(this.peek())) this.advance();
      return this.make(TokenType.Attribute, start, this.source.slice(nameStart, this.offset));
    }
    return this.make(TokenType.Attribute, start, '');
  }

  // ---- strings ------------------------------------------------------------

  private readLeftBracketOrLongString(start: number): Token {
    // check for long-bracket level [Lexer.cpp skipLongSeparator: '='s without
    // a closing '[' is a broken string, not a plain bracket — sep <= -2 case]
    let level = 0;
    let i = this.offset + 1;
    while (this.source.charCodeAt(i) === 0x3d) {
      level++;
      i++;
    }
    if (this.source.charCodeAt(i) !== 0x5b) {
      if (level > 0) {
        this.err('Malformed long string; expected opening bracket after [= sequence', start);
      }
      this.advance(); // plain '['
      return this.make(TokenType.LeftBracket, start);
    }
    // long string: consume opening brackets, then body, then closing brackets
    while (this.offset < i + 1) this.advance(); // through second '['
    const bodyStart = this.offset;
    let bodyEnd = -1;
    for (;;) {
      const ch = this.peek();
      if (ch === EOF_CHAR) this.err('Malformed long string; did you forget to finish it?', start);
      if (ch === 0x5d) {
        let j = this.offset + 1;
        let k = 0;
        while (k < level && this.source.charCodeAt(j) === 0x3d) {
          k++;
          j++;
        }
        if (k === level && this.source.charCodeAt(j) === 0x5d) {
          bodyEnd = this.offset;
          // consume through closing ']'
          while (this.offset <= j) this.advance();
          break;
        }
      }
      this.advance();
    }
    let body = this.source.slice(bodyStart, bodyEnd);
    // fixupMultilineString: skip first newline (\r\n or \n), normalize \r\n -> \n
    if (body.charCodeAt(0) === 0x0d && body.charCodeAt(1) === 0x0a) body = body.slice(2);
    else if (body.charCodeAt(0) === 0x0a) body = body.slice(1);
    let normalized = '';
    for (let k = 0; k < body.length; k++) {
      if (body.charCodeAt(k) === 0x0d && body.charCodeAt(k + 1) === 0x0a) {
        normalized += '\n';
        k++;
      } else {
        normalized += body[k];
      }
    }
    return this.make(TokenType.RawString, start, normalized);
  }

  private readQuotedString(start: number): Token {
    const quote = this.peek();
    this.advance();
    let value = '';
    for (;;) {
      const ch = this.peek();
      if (ch === EOF_CHAR || ch === 0x0a || ch === 0x0d) {
        this.err('Malformed string; did you forget to finish it?', start);
      }
      if (ch === quote) {
        this.advance();
        return this.make(TokenType.QuotedString, start, value);
      }
      if (ch === 0x5c) {
        value += this.readEscape(start);
        continue;
      }
      value += String.fromCharCode(ch);
      this.advance();
    }
  }

  /** Decode one backslash escape; `this.offset` is AT the backslash. */
  private readEscape(start: number): string {
    this.advance(); // '\'
    const esc = this.peek();
    if (esc === EOF_CHAR) this.err('Malformed escape sequence', start);
    this.advance();
    switch (esc) {
      case 0x0a: // \<newline> -> LF
        return '\n';
      case 0x0d: // \<CR> or \<CRLF> -> LF
        if (this.peek() === 0x0a) this.advance();
        return '\n';
      case 0x78: { // \xHH
        let code = 0;
        for (let k = 0; k < 2; k++) {
          const h = this.peek();
          if (!isHexDigit(h)) this.err('Malformed \\x escape; expected two hex digits', start);
          code = 16 * code + (isDigit(h) ? h - 0x30 : (h | 0x20) - 0x61 + 10);
          this.advance();
        }
        return String.fromCharCode(code);
      }
      case 0x7a: // \z : skip whitespace
        while (isSpace(this.peek())) this.advance();
        return '';
      case 0x75: { // \u{XXX}
        if (this.peek() !== 0x7b) this.err("Malformed \\u escape; expected '{'", start);
        this.advance();
        if (this.peek() === 0x7d) this.err("Malformed \\u escape; expected at least one hex digit", start);
        let code = 0;
        let digits = 0;
        for (;;) {
          const h = this.peek();
          if (h === 0x7d) break;
          if (!isHexDigit(h) || digits >= 16) this.err('Malformed \\u escape', start);
          code = 16 * code + (isDigit(h) ? h - 0x30 : (h | 0x20) - 0x61 + 10);
          digits++;
          this.advance();
        }
        this.advance(); // '}'
        const bytes = utf8Encode(code);
        if (bytes.length === 0) this.err('Unicode code point out of range in \\u escape', start);
        return bytes.map((b) => String.fromCharCode(b)).join('');
      }
      default: {
        if (isDigit(esc)) {
          // \ddd (1-3 digits, <= 255)
          let code = esc - 0x30;
          for (let k = 0; k < 2; k++) {
            const d = this.peek();
            if (!isDigit(d)) break;
            code = 10 * code + (d - 0x30);
            this.advance();
          }
          if (code > 255) this.err('Decimal escape out of range', start);
          return String.fromCharCode(code);
        }
        return String.fromCharCode(unescapeChar(esc));
      }
    }
  }

  // ---- interpolated strings ----------------------------------------------

  /**
   * Read a section of an interpolated string. `this.offset` is just after the
   * opening backtick (Begin) or just after the closing '}' of an expression
   * (Mid). Mirrors Lexer.cpp readInterpolatedStringSection, including the
   * `\u{` lookahead and the `{{` rejection.
   */
  private readInterpSection(start: number, formatType: TokenType, endType: TokenType): Token {
    let value = '';
    for (;;) {
      const ch = this.peek();
      if (ch === EOF_CHAR || ch === 0x0a || ch === 0x0d) {
        this.err("Malformed interpolated string; did you forget to add a '`'?", start);
      }
      if (ch === 0x60) {
        // '`' ends the string
        this.advance();
        return this.make(endType, start, value);
      }
      if (ch === 0x5c) {
        // '\u{' lookahead: the brace belongs to the escape, not an expression
        if (this.peek(1) === 0x75 && this.peek(2) === 0x7b) {
          value += this.readEscape(start);
          continue;
        }
        value += this.readEscape(start);
        continue;
      }
      if (ch === 0x7b) {
        // '{' starts an expression — but '{{' is an error
        if (this.peek(1) === 0x7b) {
          this.advance();
          this.advance();
          this.err("Double braces are not permitted within interpolated strings; did you mean '\\{'?", start);
        }
        this.braceStack.push('interp');
        this.advance();
        return this.make(formatType, start, value);
      }
      value += String.fromCharCode(ch);
      this.advance();
    }
  }

  private readRightBrace(start: number): Token {
    this.advance();
    if (this.braceStack.length === 0) {
      return this.make(TokenType.RightBrace, start);
    }
    const top = this.braceStack.pop()!;
    if (top !== 'interp') {
      return this.make(TokenType.RightBrace, start);
    }
    return this.readInterpSection(start, TokenType.InterpStringMid, TokenType.InterpStringEnd);
  }

  // ---- composite operators ------------------------------------------------

  private readAssignable(start: number, plain: TokenType, assign: TokenType): Token {
    this.advance();
    if (this.peek() === 0x3d) {
      this.advance();
      return this.make(assign, start);
    }
    return this.make(plain, start);
  }

  private readMinus(start: number): Token {
    this.advance();
    if (this.peek() === 0x3d) {
      this.advance();
      return this.make(TokenType.MinusAssign, start);
    }
    return this.make(TokenType.Minus, start);
  }

  private readSlash(start: number): Token {
    this.advance();
    if (this.peek() === 0x3d) {
      this.advance();
      return this.make(TokenType.SlashAssign, start);
    }
    if (this.peek() === 0x2f) {
      this.advance();
      if (this.peek() === 0x3d) {
        this.advance();
        return this.make(TokenType.DoubleSlashAssign, start);
      }
      return this.make(TokenType.DoubleSlash, start);
    }
    return this.make(TokenType.Slash, start);
  }

  private readDot(start: number): Token {
    this.advance();
    if (this.peek() === 0x2e) {
      this.advance();
      if (this.peek() === 0x2e) {
        this.advance();
        return this.make(TokenType.DotDotDot, start);
      }
      if (this.peek() === 0x3d) {
        this.advance();
        return this.make(TokenType.ConcatAssign, start);
      }
      return this.make(TokenType.DotDot, start);
    }
    if (isDigit(this.peek())) {
      // `.5` style number: rewind into the number skip pattern
      return this.readNumber(start);
    }
    return this.make(TokenType.Dot, start);
  }
}

/** Convenience: tokenize or throw. */
export function tokenize(source: string): Token[] {
  return new Lexer(source).tokenize();
}
