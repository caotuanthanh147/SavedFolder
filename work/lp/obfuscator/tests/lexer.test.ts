/**
 * Lexer acceptance + rejection suite.
 *
 * Every case cites an outside source (§22.1: tests must derive from a spec,
 * not restate the implementation):
 *  - [L5.1] Lua 5.1 reference manual lexical conventions / examples
 *    (lua.org/manual/5.1/manual.html#2.1)
 *  - [LuauSyntax] luau.org/syntax (Luau additions: compound assignment,
 *    string interpolation, continue, type annotations, if-expressions)
 *  - [Lexer.cpp] luau-lang/luau Ast/src/Lexer.cpp @ master (fetched
 *    2026-10-10) — exact behaviors: reserved words, number skip pattern,
 *    fixupQuotedString escapes, fixupMultilineString, interpolation brace
 *    stack, `{{` rejection
 *  - [Parser.cpp] luau-lang/luau Ast/src/Parser.cpp @ master —
 *    parseNumber/parseInteger64/parseDouble conversion rules
 */
import { describe, expect, test } from 'bun:test';
import { LuauSyntaxError } from '../src/errors';
import { Lexer, parseNumberLiteral } from '../src/lexer';
import { TokenType } from '../src/tokens';

function types(src: string): TokenType[] {
  return new Lexer(src).tokenize().map((t) => t.type);
}

function expectReject(src: string, needle?: string): void {
  let threw: unknown = null;
  try {
    new Lexer(src).tokenize();
  } catch (e) {
    threw = e;
  }
  expect(threw).toBeInstanceOf(LuauSyntaxError);
  if (needle !== undefined) {
    expect((threw as Error).message.toLowerCase()).toContain(needle.toLowerCase());
  }
}

// ---------------------------------------------------------------------------
// Names, keywords [Lexer.cpp kReserved: exactly the Lua 5.1 set]
// ---------------------------------------------------------------------------

describe('names and keywords', () => {
  test('reserved words map to keyword tokens [Lexer.cpp kReserved]', () => {
    const words = [
      'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for',
      'function', 'if', 'in', 'local', 'nil', 'not', 'or', 'repeat',
      'return', 'then', 'true', 'until', 'while',
    ];
    for (const w of words) {
      const toks = new Lexer(w).tokenize();
      expect(toks).toHaveLength(2); // keyword + Eof
      expect(toks[0].type).not.toBe(TokenType.Name);
    }
  });

  test('continue/type/export are NOT reserved [Parser.cpp: contextual names]', () => {
    for (const w of ['continue', 'type', 'export']) {
      const toks = new Lexer(w).tokenize();
      expect(toks[0].type).toBe(TokenType.Name);
      expect(toks[0].value).toBe(w);
    }
  });

  test('identifiers allow underscores and digits after first char [L5.1 §2.1]', () => {
    const toks = new Lexer('_foo9 __ a__1').tokenize();
    expect(toks.slice(0, 3).every((t) => t.type === TokenType.Name)).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Numbers [L5.1 §2.1 examples; Parser.cpp parseNumber/parseDouble]
// ---------------------------------------------------------------------------

function expectNumError(raw: string): void {
  const r = parseNumberLiteral(raw);
  expect('error' in r && typeof r.error === 'string').toBe(true);
}

describe('numbers', () => {
  test('Lua 5.1 manual numeric literal examples all lex as one Number [L5.1]', () => {
    for (const n of ['3', '3.0', '3.1416', '314.16e-2', '0.31416E1', '34e1']) {
      const toks = new Lexer(n).tokenize();
      expect(toks[0].type).toBe(TokenType.Number);
      expect(toks[0].value).toBe(n);
    }
  });

  test('hex and binary literals [LuauSyntax; Parser.cpp]', () => {
    for (const n of ['0xff', '0xFF', '0xB1', '0b1010', '0b1', '0x1']) {
      expect(new Lexer(n).tokenize()[0].type).toBe(TokenType.Number);
    }
  });

  test('digit separators with underscores [Lexer.cpp readNumber accepts _]', () => {
    const t = new Lexer('1_000_000').tokenize()[0];
    expect(t.type).toBe(TokenType.Number);
    expect(t.value).toBe('1_000_000');
  });

  test('leading-dot fractional number lexes as Number [Lexer.cpp case .]', () => {
    const t = new Lexer('.5').tokenize()[0];
    expect(t.type).toBe(TokenType.Number);
    expect(t.value).toBe('.5');
  });

  test('int64 suffix lexes and converts [Parser.cpp parseInteger64]', () => {
    const t = new Lexer('42i').tokenize()[0];
    expect(t.type).toBe(TokenType.Number);
    expect(t.value).toBe('42i');
    expect(parseNumberLiteral('42i')).toEqual({ kind: 'int64', value: 42n });
    expect(parseNumberLiteral('0xFFi')).toEqual({ kind: 'int64', value: 255n });
    expect(parseNumberLiteral('0b101i')).toEqual({ kind: 'int64', value: 5n });
  });

  test('parseNumberLiteral values [Parser.cpp parseDouble]', () => {
    expect(parseNumberLiteral('3')).toEqual({ kind: 'double', value: 3 });
    expect(parseNumberLiteral('314.16e-2')).toEqual({ kind: 'double', value: 3.1416 });
    expect(parseNumberLiteral('0x10')).toEqual({ kind: 'double', value: 16 });
    expect(parseNumberLiteral('0b101')).toEqual({ kind: 'double', value: 5 });
    expect(parseNumberLiteral('1_000')).toEqual({ kind: 'double', value: 1000 });
    expect(parseNumberLiteral('.5')).toEqual({ kind: 'double', value: 0.5 });
    expect(parseNumberLiteral('123.')).toEqual({ kind: 'double', value: 123 });
  });

  test('malformed numbers reject [Parser.cpp: trailing junk = malformed]', () => {
    // "123abc" lexes as one Number token (skip pattern) then fails conversion
    expectNumError('123abc');
    expectNumError('1e');
    expectNumError('1e+');
    expectNumError('0x');
    expectNumError('0b');
    expectNumError('0b12');
    expectNumError('0x1p4'); // no hex floats in Luau
    expectNumError('42.5i');
    expectNumError('..');
  });

  test('large hex stays exact to 2^53 then imprecise-as-double [Parser.cpp parseInteger]', () => {
    expect(parseNumberLiteral('0xFFFFFFFFFFFFFFFF')).toEqual({ kind: 'double', value: 0xffffffffffffffff }); // u64 max, no overflow for double
    expectNumError('0x10000000000000000'); // > u64
    expectNumError('9223372036854775808i'); // > i64 signed
  });
});

// ---------------------------------------------------------------------------
// Quoted strings [Lexer.cpp fixupQuotedString]
// ---------------------------------------------------------------------------

describe('quoted strings', () => {
  test('basic quoting and simple escapes [L5.1 §2.1]', () => {
    const t = new Lexer('"a\\nb\\tc\\\\d"').tokenize()[0];
    expect(t.type).toBe(TokenType.QuotedString);
    expect(t.value).toBe('a\nb\tc\\d');
  });

  test('all C-style escapes [Lexer.cpp unescape]', () => {
    const t = new Lexer('"\\a\\b\\f\\n\\r\\t\\v"').tokenize()[0];
    expect(t.value).toBe('\x07\x08\x0c\n\r\t\x0b');
  });

  test('identity escapes [Lexer.cpp default: unescape(ch) = ch]', () => {
    const t = new Lexer('"\\q\\$\\ "').tokenize();
    expect(t[0].type).toBe(TokenType.QuotedString);
    expect(t[0].value).toBe('q$ ');
    // quote escapes yield the quote itself
    expect(new Lexer('"\\""').tokenize()[0].value).toBe('"');
    expect(new Lexer("'\\''").tokenize()[0].value).toBe("'");
  });

  test('hex escape \\xHH [Lexer.cpp case x]', () => {
    expect(new Lexer('"\\x41\\x42"').tokenize()[0].value).toBe('AB');
    expectReject('"\\x4"'); // exactly two hex digits required
    expectReject('"\\xZZ"');
  });

  test('decimal escape \\ddd up to 255 [Lexer.cpp default case]', () => {
    expect(new Lexer('"\\65\\066"').tokenize()[0].value).toBe('AB');
    expectReject('"\\256"'); // > 255
    expectReject('"\\999"');
  });

  test('\\z skips following whitespace [Lexer.cpp case z]', () => {
    expect(new Lexer('"a\\z    b"').tokenize()[0].value).toBe('ab');
    expect(new Lexer('"a\\z\n\tb"').tokenize()[0].value).toBe('ab');
  });

  test('\\u{...} encodes UTF-8 bytes [Lexer.cpp case u + toUtf8]', () => {
    expect(new Lexer('"\\u{41}"').tokenize()[0].value).toBe('A');
    // U+00E9 = 2 UTF-8 bytes 0xC3 0xA9
    const e = new Lexer('"\\u{E9}"').tokenize()[0].value!;
    expect(e.charCodeAt(0)).toBe(0xc3);
    expect(e.charCodeAt(1)).toBe(0xa9);
    // U+1F600 = 4 bytes F0 9F 98 80
    const emoji = new Lexer('"\\u{1F600}"').tokenize()[0].value!;
    expect([emoji.charCodeAt(0), emoji.charCodeAt(1), emoji.charCodeAt(2), emoji.charCodeAt(3)]).toEqual([0xf0, 0x9f, 0x98, 0x80]);
    expectReject('"\\u{}"'); // at least one hex digit
    expectReject('"\\u{110000}"'); // out of range
    expectReject('"\\u41"'); // braces required
  });

  test('escaped newline becomes LF [Lexer.cpp fixupQuotedString]', () => {
    expect(new Lexer('"a\\\nb"').tokenize()[0].value).toBe('a\nb');
    expect(new Lexer('"a\\\r\nb"').tokenize()[0].value).toBe('a\nb');
  });

  test('bare newline or EOF inside string rejects [Lexer.cpp readQuotedString]', () => {
    expectReject('"unfinished', 'string');
    expectReject('"bad\nstring"', 'string');
  });

  test('single quotes work the same [L5.1]', () => {
    expect(new Lexer("'it\\'s'").tokenize()[0].value).toBe("it's");
  });

  test('bytes >= 0x80 pass through inside strings [byte-string model]', () => {
    const t = new Lexer('"\xff\xfe"').tokenize()[0];
    expect(t.value!.charCodeAt(0)).toBe(0xff);
    expect(t.value!.charCodeAt(1)).toBe(0xfe);
  });
});

// ---------------------------------------------------------------------------
// Long strings [Lexer.cpp readLongString + fixupMultilineString]
// ---------------------------------------------------------------------------

describe('long strings', () => {
  test('level-0 long string [L5.1 §2.1]', () => {
    const t = new Lexer('[[hello]]').tokenize()[0];
    expect(t.type).toBe(TokenType.RawString);
    expect(t.value).toBe('hello');
  });

  test('first newline is skipped [Lexer.cpp fixupMultilineString]', () => {
    expect(new Lexer('[[\nhello]]').tokenize()[0].value).toBe('hello');
    expect(new Lexer('[[\r\nhello]]').tokenize()[0].value).toBe('hello');
    expect(new Lexer('[[hello\nworld]]').tokenize()[0].value).toBe('hello\nworld');
  });

  test('CRLF normalized to LF inside body [Lexer.cpp fixupMultilineString]', () => {
    expect(new Lexer('[[a\r\nb]]').tokenize()[0].value).toBe('a\nb');
  });

  test('level-1 long string keeps ]] inside [L5.1 §2.1]', () => {
    const t = new Lexer('[=[a]]b' + ']=' + ']').tokenize()[0];
    expect(t.type).toBe(TokenType.RawString);
    expect(t.value).toBe('a]]b');
  });

  test('level-2 long string keeps ]=] inside [L5.1]', () => {
    expect(new Lexer('[==[x]=]y]==]').tokenize()[0].value).toBe('x]=]y');
  });

  test('unterminated long string rejects [Lexer.cpp BrokenString]', () => {
    expectReject('[[never closed', 'string');
    expectReject('[=[level mismatch]]', 'string');
  });

  test('[= without closing bracket rejects, plain [ stays a bracket [Lexer.cpp skipLongSeparator]', () => {
    // sep == -1 (no '=' at all) -> plain '['; sep <= -2 ('='s but no '[') -> broken
    expect(types('a[b')).toEqual([TokenType.Name, TokenType.LeftBracket, TokenType.Name, TokenType.Eof]);
    expectReject('a[=b', 'string');
    expectReject('a[==b', 'string');
    // comment position: --[= falls back to a line comment (readCommentBody)
    expect(types('--[= not a block\nx')).toEqual([TokenType.Name, TokenType.Eof]);
  });

  test('NUL byte acts as EOF (C-string semantics) [Lexer.cpp buffer model]', () => {
    // tokens before the NUL lex normally; the NUL terminates the source
    const toks = new Lexer('a b\0garbage').tokenize();
    expect(toks.map((t) => t.type)).toEqual([TokenType.Name, TokenType.Name, TokenType.Eof]);
    // NUL inside a string is malformed (readQuotedString case 0)
    expectReject('"a\0b"', 'string');
  });

  test('line counting continues after long string [position tracking]', () => {
    const toks = new Lexer('[[a\nb\nc]] x').tokenize();
    expect(toks.at(-2)!.type).toBe(TokenType.Name);
    expect(toks.at(-2)!.location.start.line).toBe(3);
  });
});

// ---------------------------------------------------------------------------
// Interpolated strings [Lexer.cpp readInterpolatedStringSection; LuauSyntax]
// ---------------------------------------------------------------------------

describe('interpolated strings', () => {
  test('simple string with no braces is InterpStringSimple [Lexer.cpp]', () => {
    const toks = new Lexer('`hello world`').tokenize();
    expect(toks[0].type).toBe(TokenType.InterpStringSimple);
    expect(toks[0].value).toBe('hello world');
  });

  test('begin/mid/end split across expressions [LuauSyntax]', () => {
    const toks = new Lexer('`a{x}b`').tokenize();
    expect(toks.map((t) => t.type)).toEqual([
      TokenType.InterpStringBegin, // `a{
      TokenType.Name, // x
      TokenType.InterpStringEnd, // }b`
      TokenType.Eof,
    ]);
    expect(toks[0].value).toBe('a');
    expect(toks[2].value).toBe('b');
  });

  test('multiple expressions produce Mid sections [LuauSyntax]', () => {
    const toks = new Lexer('`a{x}b{y}c`').tokenize();
    expect(toks.map((t) => t.type)).toEqual([
      TokenType.InterpStringBegin,
      TokenType.Name,
      TokenType.InterpStringMid,
      TokenType.Name,
      TokenType.InterpStringEnd,
      TokenType.Eof,
    ]);
    expect(toks[2].value).toBe('b');
    expect(toks[4].value).toBe('c');
  });

  test('nested braces inside the expression balance via the stack [Lexer.cpp braceStack]', () => {
    const toks = new Lexer('`{f({1, 2})}`').tokenize();
    expect(toks.map((t) => t.type)).toEqual([
      TokenType.InterpStringBegin,
      TokenType.Name,
      TokenType.LeftParen,
      TokenType.LeftBrace,
      TokenType.Number,
      TokenType.Comma,
      TokenType.Number,
      TokenType.RightBrace,
      TokenType.RightParen,
      TokenType.InterpStringEnd,
      TokenType.Eof,
    ]);
  });

  test('quoted string containing } inside interpolation [Parser.cpp parseInterpString]', () => {
    const toks = new Lexer('`{"}"}`').tokenize();
    expect(toks.map((t) => t.type)).toEqual([
      TokenType.InterpStringBegin,
      TokenType.QuotedString, // "}" — the } is inside the quotes
      TokenType.InterpStringEnd,
      TokenType.Eof,
    ]);
  });

  test('\\u{...} does not start an expression [Lexer.cpp lookahead]', () => {
    const toks = new Lexer('`\\u{41}`').tokenize();
    expect(toks[0].type).toBe(TokenType.InterpStringSimple);
    expect(toks[0].value).toBe('A');
  });

  test('escaped brace \\{ is literal [LuauSyntax]', () => {
    const toks = new Lexer('`a\\{b`').tokenize();
    expect(toks[0].type).toBe(TokenType.InterpStringSimple);
    expect(toks[0].value).toBe('a{b');
  });

  test('{{ rejects [Lexer.cpp BrokenInterpDoubleBrace]', () => {
    expectReject('`a{{b}`', 'double braces');
  });

  test('unfinished interpolated string rejects [Lexer.cpp BrokenString]', () => {
    expectReject('`never closed', 'string');
    expectReject('`multi\nline`', 'string');
  });

  test('escapes decode in sections [Parser.cpp fixupQuotedString on sections]', () => {
    const toks = new Lexer('`a\\tb{x}\\n`').tokenize();
    expect(toks[0].type).toBe(TokenType.InterpStringBegin);
    expect(toks[0].value).toBe('a\tb');
    expect(toks[2].type).toBe(TokenType.InterpStringEnd);
    expect(toks[2].value).toBe('\n');
  });
});

// ---------------------------------------------------------------------------
// Operators & punctuation [Lexer.cpp next() switch; LuauSyntax compound ops]
// ---------------------------------------------------------------------------

describe('operators', () => {
  test('compound assignment operators [LuauSyntax]', () => {
    for (const [src, type] of [
      ['+=', TokenType.PlusAssign],
      ['-=', TokenType.MinusAssign],
      ['*=', TokenType.StarAssign],
      ['/=', TokenType.SlashAssign],
      ['%=', TokenType.PercentAssign],
      ['^=', TokenType.CaretAssign],
      ['..=', TokenType.ConcatAssign],
    ] as const) {
      const toks = new Lexer(src).tokenize();
      expect(toks[0].type).toBe(type);
    }
  });

  test('floor division operators [Lexer.cpp case /]', () => {
    expect(new Lexer('//').tokenize()[0].type).toBe(TokenType.DoubleSlash);
    expect(new Lexer('//=').tokenize()[0].type).toBe(TokenType.DoubleSlashAssign);
  });

  test('three-char and dot family [Lexer.cpp case .]', () => {
    expect(new Lexer('...').tokenize()[0].type).toBe(TokenType.DotDotDot);
    expect(new Lexer('..').tokenize()[0].type).toBe(TokenType.DotDot);
    expect(new Lexer('.').tokenize()[0].type).toBe(TokenType.Dot);
    // '..' followed by digit: DotDot then Number ('..5' = concat + 5)
    const toks = new Lexer('..5').tokenize();
    expect(toks[0].type).toBe(TokenType.DotDot);
    expect(toks[1].type).toBe(TokenType.Number);
  });

  test('comparisons and equality [L5.1]', () => {
    expect(new Lexer('==').tokenize()[0].type).toBe(TokenType.Equal);
    expect(new Lexer('~=').tokenize()[0].type).toBe(TokenType.TildeEqual);
    expect(new Lexer('<=').tokenize()[0].type).toBe(TokenType.LessEqual);
    expect(new Lexer('>=').tokenize()[0].type).toBe(TokenType.GreaterEqual);
    expect(new Lexer('=').tokenize()[0].type).toBe(TokenType.Assign);
    expect(new Lexer('<').tokenize()[0].type).toBe(TokenType.Less);
    expect(new Lexer('>').tokenize()[0].type).toBe(TokenType.Greater);
  });

  test('single & | ! ~ ? tokens stay unfused for parser adjacency rules [Lexer.cpp]', () => {
    expect(new Lexer('&').tokenize()[0].type).toBe(TokenType.Amp);
    expect(new Lexer('|').tokenize()[0].type).toBe(TokenType.Pipe);
    expect(new Lexer('!').tokenize()[0].type).toBe(TokenType.Bang);
    expect(new Lexer('~').tokenize()[0].type).toBe(TokenType.Tilde);
    expect(new Lexer('?').tokenize()[0].type).toBe(TokenType.QuestionMark);
    // `& &` (with space) must NOT become a fused token — parser's job
    const toks = new Lexer('& &').tokenize();
    expect(toks[0].type).toBe(TokenType.Amp);
    expect(toks[1].type).toBe(TokenType.Amp);
  });

  test('double colon for type casts [LuauSyntax]', () => {
    expect(new Lexer('::').tokenize()[0].type).toBe(TokenType.DoubleColon);
    expect(new Lexer(':').tokenize()[0].type).toBe(TokenType.Colon);
  });

  test('adjacent operators split correctly [L5.1 max-munch]', () => {
    expect(types('a..b')).toEqual([TokenType.Name, TokenType.DotDot, TokenType.Name, TokenType.Eof]);
    expect(types('a...b')).toEqual([TokenType.Name, TokenType.DotDotDot, TokenType.Name, TokenType.Eof]);
    expect(types('a-=-b')).toEqual([TokenType.Name, TokenType.MinusAssign, TokenType.Minus, TokenType.Name, TokenType.Eof]);
    expect(types('a=b==c')).toEqual([TokenType.Name, TokenType.Assign, TokenType.Name, TokenType.Equal, TokenType.Name, TokenType.Eof]);
  });
});

// ---------------------------------------------------------------------------
// Comments [Lexer.cpp readCommentBody; L5.1 §2.1]
// ---------------------------------------------------------------------------

describe('comments', () => {
  test('line comments are skipped [L5.1]', () => {
    expect(types('-- hello\nx')).toEqual([TokenType.Name, TokenType.Eof]);
    expect(types('x -- trailing')).toEqual([TokenType.Name, TokenType.Eof]);
  });

  test('block comments with levels [L5.1]', () => {
    expect(types('--[[ multi\nline ]]\nx')).toEqual([TokenType.Name, TokenType.Eof]);
    expect(types('--[=[ contains ]] inside ]=]\nx')).toEqual([TokenType.Name, TokenType.Eof]);
  });

  test('doc comments --- skipped like line comments [LuauSyntax]', () => {
    expect(types('--- doc\nx')).toEqual([TokenType.Name, TokenType.Eof]);
  });

  test('unterminated block comment rejects [Lexer.cpp BrokenComment]', () => {
    expectReject('--[[ never closed', 'comment');
  });

  test('UTF-8 allowed inside comments [Lexer.cpp: comments skip raw bytes]', () => {
    expect(types('-- café ☕\nx')).toEqual([TokenType.Name, TokenType.Eof]);
  });

  test('-- followed by [ without level is still a line comment [L5.1]', () => {
    expect(types('-- [not a block]\nx')).toEqual([TokenType.Name, TokenType.Eof]);
  });
});

// ---------------------------------------------------------------------------
// Attributes [Lexer.cpp case @]
// ---------------------------------------------------------------------------

describe('attributes', () => {
  test('@name attribute token', () => {
    const t = new Lexer('@native').tokenize()[0];
    expect(t.type).toBe(TokenType.Attribute);
    expect(t.value).toBe('native');
  });

  test('@[ opens an attribute list', () => {
    expect(new Lexer('@[').tokenize()[0].type).toBe(TokenType.AttributeOpen);
  });

  test('@ alone is an empty-name attribute [Lexer.cpp]', () => {
    const t = new Lexer('@ ').tokenize()[0];
    expect(t.type).toBe(TokenType.Attribute);
    expect(t.value).toBe('');
  });
});

// ---------------------------------------------------------------------------
// Errors and positions
// ---------------------------------------------------------------------------

describe('errors and positions', () => {
  test('non-ASCII byte in code position rejects [Lexer.cpp readUtf8Error]', () => {
    expectReject('local é = 1');
  });

  test('unexpected character rejects with position', () => {
    let err: LuauSyntaxError | null = null;
    try {
      new Lexer('local $\n').tokenize();
    } catch (e) {
      err = e as LuauSyntaxError;
    }
    expect(err).toBeInstanceOf(LuauSyntaxError);
    expect(err!.location.start.line).toBe(1);
    expect(err!.location.start.column).toBe(6);
  });

  test('line/column tracking: only \\n advances lines [Lexer.cpp position model]', () => {
    const toks = new Lexer('a\n  bb\n\tccc').tokenize();
    const [a, bb, ccc] = toks;
    expect(a.location.start).toEqual({ line: 1, column: 0, offset: 0 });
    expect(bb.location.start).toEqual({ line: 2, column: 2, offset: 4 });
    expect(ccc.location.start).toEqual({ line: 3, column: 1, offset: 8 });
  });

  test('token end positions cover the full text', () => {
    const t = new Lexer('  hello').tokenize()[0];
    expect(t.location.start.offset).toBe(2);
    expect(t.location.end.offset).toBe(7);
  });

  test('empty input yields just Eof', () => {
    expect(types('')).toEqual([TokenType.Eof]);
    expect(types('   \n\t ')).toEqual([TokenType.Eof]);
  });
});

// ---------------------------------------------------------------------------
// Realistic mixed sources [L5.1 grammar examples; LuauSyntax examples]
// ---------------------------------------------------------------------------

describe('mixed realistic sources', () => {
  test('chunk with everything [L5.1 §2.5.7 example shape]', () => {
    const src = [
      '    function fib(n)',
      '      if n < 2 then return n end',
      '      return fib(n-2) + fib(n-1)',
      '    end',
      '',
      '    --[[ table of commands: ]]',
      '    local t = {"a"..\'b\', [10] = 0x41, 1e3}',
      '    for k, v in pairs(t) do print(k, v) end',
      '    local ok, err = pcall(function() error("boom") end)',
    ].join('\n');
    const toks = new Lexer(src).tokenize();
    expect(toks.at(-1)!.type).toBe(TokenType.Eof);
    // spot-check a couple of decoded values
    const hex = toks.find((t) => t.value === '0x41')!;
    expect(hex.type).toBe(TokenType.Number);
    const str = toks.find((t) => t.value === 'boom')!;
    expect(str.type).toBe(TokenType.QuotedString);
  });

  test('Luau-flavored source: types, continue, compound, interp [LuauSyntax]', () => {
    const src = [
      'export type Point = { x: number, y: number }',
      'local function sum(xs: {number}): number',
      '  local total = 0',
      '  for _, x in xs do',
      '    if x :: number < 0 then continue end',
      '    total += x',
      '  end',
      '  return total',
      'end',
      'local msg = `total={sum({1, 2})!}`',
    ].join('\n');
    const toks = new Lexer(src).tokenize();
    expect(toks.at(-1)!.type).toBe(TokenType.Eof);
    expect(toks.some((t) => t.type === TokenType.PlusAssign)).toBe(true);
    expect(toks.some((t) => t.type === TokenType.DoubleColon)).toBe(true);
    expect(toks.some((t) => t.type === TokenType.InterpStringBegin)).toBe(true);
    // `type` used as a contextual keyword stays a Name
    expect(toks[1].type).toBe(TokenType.Name);
    expect(toks[1].value).toBe('type');
  });

  // Regression (s3 corpus, Ascension.lua/TapIncremental.lua): identifiers
  // that are Object.prototype member names must lex as plain Names — a bare
  // RESERVED[name] lookup returns the inherited function (truthy!) and once
  // leaked it into token.type. [JS hazard, not a spec case — tokens.ts
  // reservedWordType own-property guard]
  test('Object.prototype member names are plain identifiers [regression: reservedWordType guard]', () => {
    for (const name of ['toString', 'constructor', 'valueOf', 'hasOwnProperty', 'isPrototypeOf', 'propertyIsEnumerable', 'toLocaleString']) {
      const toks = new Lexer(`local ${name} = 1`).tokenize();
      expect(toks[1]!.type).toBe(TokenType.Name);
      expect(toks[1]!.value).toBe(name);
    }
  });
});
