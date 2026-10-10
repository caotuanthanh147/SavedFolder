/**
 * Token model for the strict Luau lexer.
 *
 * Spec sources (see RESEARCH-M4.md):
 *  - Reserved words: luau-lang/luau Ast/src/Lexer.cpp kReserved (checked
 *    2026-10-10): exactly the Lua 5.1 set — `continue`, `type`, `export` are
 *    NOT reserved; they are contextual keywords handled by the parser.
 *  - Operators/punctuation: Lexer.cpp next() switch (AddAssign..DoubleColon),
 *    including `//` FloorDiv and `..=` ConcatAssign.
 *  - String tokens: QuotedString / RawString (long strings) / InterpString*
 *    per readQuotedString / readLongString / readInterpolatedStringSection.
 */

/** 1-based line, 0-based column (Luau Position convention). */
export interface Position {
  readonly line: number;
  readonly column: number;
  readonly offset: number;
}

export interface Location {
  readonly start: Position;
  readonly end: Position;
}

export enum TokenType {
  Eof,
  Name,
  Number,
  QuotedString,
  RawString,

  InterpStringBegin,
  InterpStringMid,
  InterpStringEnd,
  InterpStringSimple,

  Attribute,
  AttributeOpen,

  // Reserved words (Lua 5.1 set, verbatim from Lexer.cpp kReserved)
  And,
  Break,
  Do,
  Else,
  Elseif,
  End,
  False,
  For,
  Function,
  If,
  In,
  Local,
  Nil,
  Not,
  Or,
  Repeat,
  Return,
  Then,
  True,
  Until,
  While,

  // Punctuation & operators
  LeftParen,
  RightParen,
  LeftBrace,
  RightBrace,
  LeftBracket,
  RightBracket,
  DoubleColon,
  Semicolon,
  Colon,
  Comma,
  Dot,
  DotDot,
  DotDotDot,
  ConcatAssign,
  Plus,
  PlusAssign,
  Minus,
  MinusAssign,
  Star,
  StarAssign,
  Slash,
  SlashAssign,
  DoubleSlash,
  DoubleSlashAssign,
  Percent,
  PercentAssign,
  Caret,
  CaretAssign,
  Hash,
  Equal,
  Tilde,
  TildeEqual,
  Less,
  LessEqual,
  Greater,
  GreaterEqual,
  Assign,
  Amp,
  Pipe,
  Bang,
  QuestionMark,
}

export interface Token {
  readonly type: TokenType;
  readonly location: Location;
  /**
   * Payload depends on type:
   *  - Name / Attribute: identifier text
   *  - Number: raw literal text (validate with parseNumberLiteral)
   *  - QuotedString / RawString / InterpString*: decoded byte-string value
   *    (each char code is a byte 0..255; `\u{...}` expands to UTF-8 bytes)
   */
  readonly value?: string;
}

const RESERVED: Readonly<Record<string, TokenType>> = {
  and: TokenType.And,
  break: TokenType.Break,
  do: TokenType.Do,
  else: TokenType.Else,
  elseif: TokenType.Elseif,
  end: TokenType.End,
  false: TokenType.False,
  for: TokenType.For,
  function: TokenType.Function,
  if: TokenType.If,
  in: TokenType.In,
  local: TokenType.Local,
  nil: TokenType.Nil,
  not: TokenType.Not,
  or: TokenType.Or,
  repeat: TokenType.Repeat,
  return: TokenType.Return,
  then: TokenType.Then,
  true: TokenType.True,
  until: TokenType.Until,
  while: TokenType.While,
};

export function reservedWordType(name: string): TokenType | undefined {
  return RESERVED[name];
}

const TOKEN_NAMES: Readonly<Record<TokenType, string>> = {
  [TokenType.Eof]: '<eof>',
  [TokenType.Name]: 'name',
  [TokenType.Number]: 'number',
  [TokenType.QuotedString]: 'string',
  [TokenType.RawString]: 'string',
  [TokenType.InterpStringBegin]: 'interpolated string',
  [TokenType.InterpStringMid]: 'interpolated string',
  [TokenType.InterpStringEnd]: 'interpolated string',
  [TokenType.InterpStringSimple]: 'interpolated string',
  [TokenType.Attribute]: 'attribute',
  [TokenType.AttributeOpen]: 'attribute list',
  [TokenType.And]: "'and'",
  [TokenType.Break]: "'break'",
  [TokenType.Do]: "'do'",
  [TokenType.Else]: "'else'",
  [TokenType.Elseif]: "'elseif'",
  [TokenType.End]: "'end'",
  [TokenType.False]: "'false'",
  [TokenType.For]: "'for'",
  [TokenType.Function]: "'function'",
  [TokenType.If]: "'if'",
  [TokenType.In]: "'in'",
  [TokenType.Local]: "'local'",
  [TokenType.Nil]: "'nil'",
  [TokenType.Not]: "'not'",
  [TokenType.Or]: "'or'",
  [TokenType.Repeat]: "'repeat'",
  [TokenType.Return]: "'return'",
  [TokenType.Then]: "'then'",
  [TokenType.True]: "'true'",
  [TokenType.Until]: "'until'",
  [TokenType.While]: "'while'",
  [TokenType.LeftParen]: "'('",
  [TokenType.RightParen]: "')'",
  [TokenType.LeftBrace]: "'{'",
  [TokenType.RightBrace]: "'}'",
  [TokenType.LeftBracket]: "'['",
  [TokenType.RightBracket]: "']'",
  [TokenType.DoubleColon]: "'::'",
  [TokenType.Semicolon]: "';'",
  [TokenType.Colon]: "':'",
  [TokenType.Comma]: "','",
  [TokenType.Dot]: "'.'",
  [TokenType.DotDot]: "'..'",
  [TokenType.DotDotDot]: "'...'",
  [TokenType.ConcatAssign]: "'..='",
  [TokenType.Plus]: "'+'",
  [TokenType.PlusAssign]: "'+='",
  [TokenType.Minus]: "'-'",
  [TokenType.MinusAssign]: "'-='",
  [TokenType.Star]: "'*'",
  [TokenType.StarAssign]: "'*='",
  [TokenType.Slash]: "'/'",
  [TokenType.SlashAssign]: "'/='",
  [TokenType.DoubleSlash]: "'//'",
  [TokenType.DoubleSlashAssign]: "'//='",
  [TokenType.Percent]: "'%'",
  [TokenType.PercentAssign]: "'%='",
  [TokenType.Caret]: "'^'",
  [TokenType.CaretAssign]: "'^='",
  [TokenType.Hash]: "'#'",
  [TokenType.Equal]: "'=='",
  [TokenType.Tilde]: "'~'",
  [TokenType.TildeEqual]: "'~='",
  [TokenType.Less]: "'<'",
  [TokenType.LessEqual]: "'<='",
  [TokenType.Greater]: "'>'",
  [TokenType.GreaterEqual]: "'>='",
  [TokenType.Assign]: "'='",
  [TokenType.Amp]: "'&'",
  [TokenType.Pipe]: "'|'",
  [TokenType.Bang]: "'!'",
  [TokenType.QuestionMark]: "'?'",
};

export function tokenTypeName(type: TokenType): string {
  return TOKEN_NAMES[type];
}
