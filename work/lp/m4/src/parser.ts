/**
 * Strict Luau parser: token stream → AST.
 *
 * Spec: luau-lang/luau Ast/src/Parser.cpp @ master (fetched 2026-10-10; MIT —
 * used as a SPEC: grammar, contextual-keyword disambiguation, operator
 * precedence table, scope/binding rules, error conditions. No code copied).
 *
 * Behavioral notes (details + rationale in DECISIONS-M4.md):
 *  - Strict fail-loud: every condition the reference turns into a soft
 *    report()/error-node becomes ONE fatal LuauSyntaxError (ast.ts note 2).
 *  - Contextual keywords (continue / type / export type / declare) are
 *    resolved exactly like the reference: parse a primary expression first;
 *    a bare Global-or-Local named `type`/`export`/`continue` that is not
 *    part of a call or assignment is the keyword form (getIdentifier covers
 *    locals too).
 *  - Operator precedence = the Lua 5.1 priority table (Parser.cpp
 *    binaryPriority, identical to lua.org lparser.c): + - 6/6, * / // % 7/7,
 *    ^ 10/9 (right), .. 5/4 (right), comparisons 3/3, and 2/2, or 1/1,
 *    unary 8.
 *  - `&&` `||` `!=` `!` are confusables: hard errors with the reference's
 *    "did you mean" messages (adjacency + priority rules mirrored).
 *  - Scope tracking mirrors the reference parser (name→Local map with
 *    shadow chains on a stack): locals bind AFTER right-hand sides;
 *    `local function f` binds f before its body; repeat/until sees body
 *    locals; for-loop vars bind after from/to/step|iterators; function
 *    args + the inserted `self` bind inside the body scope.
 *  - break/continue require loopDepth > 0 (tracked per function); `...`
 *    requires a vararg function context.
 *  - Type grammar: parseTypeSuffix implements the flat union/intersection
 *    suffix loop — mixing `|` and `&` (incl. via `?`) is an error, exactly
 *    like the reference. `T?` is our Optional wrapper (ast.ts note 4) where
 *    the reference pushes a union marker part.
 *  - `;` is only a statement SEPARATOR (consumed after a statement);
 *    the reference parseStat has no empty-statement case, so leading
 *    semicolons are syntax errors.
 *  - Recursion limit 1000 (FInt::LuauRecursionLimit default).
 *  - Unsupported reference/experimental syntax gets a clear error
 *    (D-M4-12): declare/extern, const, export-value, `if local` conditions,
 *    read/write table props, attribute arguments `@[name(args)]`, method
 *    call type arguments `a:m<<T>>()`.
 */

import { LuauSyntaxError } from './errors';
import { parseNumberLiteral, tokenize } from './lexer';
import { TokenType, tokenTypeName } from './tokens';
import type { Location, Position, Token } from './tokens';
import type {
  ArgumentName, Attribute, BinaryOp, Block, Chunk, Expr, FunctionExpr,
  GenericType, GenericTypePack, IfStat, Local, Stat, TableIndexer, TableProp,
  Type, TypePack, UnaryOp,
} from './ast';

// ---------------------------------------------------------------------------
// Operator tables [Parser.cpp binaryPriority; lua.org lparser.c priority[]]
// ---------------------------------------------------------------------------

/** [op] = { left, right } — higher binds tighter; right < left ⇒ right-assoc. */
const BINARY_PRIORITY: Readonly<Record<BinaryOp, readonly [number, number]>> = {
  Add: [6, 6], Sub: [6, 6],
  Mul: [7, 7], Div: [7, 7], FloorDiv: [7, 7], Mod: [7, 7],
  Pow: [10, 9],
  Concat: [5, 4],
  CompareNe: [3, 3], CompareEq: [3, 3], CompareLt: [3, 3],
  CompareLe: [3, 3], CompareGt: [3, 3], CompareGe: [3, 3],
  And: [2, 2], Or: [1, 1],
};

const UNARY_PRIORITY = 8;
const RECURSION_LIMIT = 1000;

const BINARY_TOKENS: Readonly<Partial<Record<TokenType, BinaryOp>>> = {
  [TokenType.Plus]: 'Add', [TokenType.Minus]: 'Sub',
  [TokenType.Star]: 'Mul', [TokenType.Slash]: 'Div',
  [TokenType.DoubleSlash]: 'FloorDiv', [TokenType.Percent]: 'Mod',
  [TokenType.Caret]: 'Pow', [TokenType.DotDot]: 'Concat',
  [TokenType.TildeEqual]: 'CompareNe', [TokenType.Equal]: 'CompareEq',
  [TokenType.Less]: 'CompareLt', [TokenType.LessEqual]: 'CompareLe',
  [TokenType.Greater]: 'CompareGt', [TokenType.GreaterEqual]: 'CompareGe',
  [TokenType.And]: 'And', [TokenType.Or]: 'Or',
};

const COMPOUND_TOKENS: Readonly<Partial<Record<TokenType, BinaryOp>>> = {
  [TokenType.PlusAssign]: 'Add', [TokenType.MinusAssign]: 'Sub',
  [TokenType.StarAssign]: 'Mul', [TokenType.SlashAssign]: 'Div',
  [TokenType.DoubleSlashAssign]: 'FloorDiv', [TokenType.PercentAssign]: 'Mod',
  [TokenType.CaretAssign]: 'Pow', [TokenType.ConcatAssign]: 'Concat',
};

/** Attribute names accepted by the reference (kAttributeEntries; the
 *  debugnoinline entry is Debug-flag-gated and excluded here). */
const KNOWN_ATTRIBUTES = new Set(['checked', 'native', 'deprecated']);

function isTypeFollow(t: TokenType): boolean {
  return t === TokenType.Pipe || t === TokenType.QuestionMark || t === TokenType.Amp;
}

function isStringToken(t: TokenType): boolean {
  return t === TokenType.QuotedString || t === TokenType.RawString;
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

interface FunctionContext {
  vararg: boolean;
  loopDepth: number;
}

interface Binding {
  name: string;
  location: Location;
  annotation?: Type;
}

interface ScopeEntry {
  local: Local;
  prev: Local | undefined;
}

export interface ParseOptions {
  /** Max recursion depth (reference FInt::LuauRecursionLimit default 1000). */
  recursionLimit?: number;
}

export class Parser {
  private readonly tokens: readonly Token[];
  private readonly recursionLimit: number;
  private pos = 0;
  private recursion = 0;

  /** Scope: name → innermost Local (shadow chain on the stack). */
  private readonly localMap = new Map<string, Local>();
  private readonly localStack: ScopeEntry[] = [];

  /** Per-function context (vararg / loop depth). */
  private readonly functionStack: FunctionContext[] = [{ vararg: false, loopDepth: 0 }];

  constructor(tokens: readonly Token[], options?: ParseOptions) {
    this.tokens = tokens;
    this.recursionLimit = options?.recursionLimit ?? RECURSION_LIMIT;
  }

  // -- token plumbing ------------------------------------------------------

  private get current(): Token {
    return this.tokens[this.pos]!;
  }

  /** Lookahead by n tokens (0 = current). Never runs past the Eof sentinel. */
  private peek(n = 1): Token {
    const i = Math.min(this.pos + n, this.tokens.length - 1);
    return this.tokens[i]!;
  }

  private advance(): Token {
    const t = this.current;
    if (t.type !== TokenType.Eof) this.pos++;
    return t;
  }

  /** Current token type, read through a method call so TS cannot carry a
   *  stale `this.current.type` narrowing across advance()/parse*() calls —
   *  TS does not invalidate property-path narrowing on method calls (a
   *  known soundness hole); every curType() below is a genuine fresh read
   *  of the post-advance token. */
  private curType(): TokenType {
    return this.current.type;
  }

  /** End position of the most recently consumed token. */
  private get prevEnd(): Position {
    const i = Math.max(this.pos - 1, 0);
    return this.tokens[i]!.location.end;
  }

  // -- errors --------------------------------------------------------------

  private error(message: string, at: Token | Location = this.current): never {
    const location = 'type' in at ? at.location : at;
    throw new LuauSyntaxError(message, location);
  }

  private describe(t: Token): string {
    return t.type === TokenType.Eof ? '<eof>' : tokenTypeName(t.type);
  }

  private expect(type: TokenType, context: string): Token {
    if (this.current.type !== type) {
      this.error(`expected ${tokenTypeName(type)} when parsing ${context}, got ${this.describe(this.current)}`);
    }
    return this.advance();
  }

  /** Closing-token expect with "to match" reporting (expectMatchAndConsume). */
  private expectMatch(type: TokenType, open: Token, context: string): Token {
    if (this.current.type !== type) {
      this.error(
        `expected ${tokenTypeName(type)} when parsing ${context} ` +
          `(to close ${tokenTypeName(open.type)} at line ${open.location.start.line}), ` +
          `got ${this.describe(this.current)}`,
      );
    }
    return this.advance();
  }

  private guard(): void {
    if (++this.recursion > this.recursionLimit) {
      this.error('exceeded allowed recursion depth');
    }
  }
  private unguard(): void {
    this.recursion--;
  }

  // -- scope ---------------------------------------------------------------

  private pushLocal(binding: Binding): Local {
    const local: Local = {
      kind: 'Local',
      location: binding.location,
      name: binding.name,
      annotation: binding.annotation,
    };
    this.localStack.push({ local, prev: this.localMap.get(binding.name) });
    this.localMap.set(binding.name, local);
    return local;
  }

  private saveLocals(): number {
    return this.localStack.length;
  }

  private restoreLocals(mark: number): void {
    while (this.localStack.length > mark) {
      const { local, prev } = this.localStack.pop()!;
      if (prev) this.localMap.set(local.name, prev);
      else this.localMap.delete(local.name);
    }
  }

  private lookupLocal(name: string): Local | undefined {
    return this.localMap.get(name);
  }

  // -- location helpers ------------------------------------------------------

  private loc(start: Position, end: Position): Location {
    return { start, end };
  }
  private locToToken(start: Position, token: Token): Location {
    return { start, end: token.location.end };
  }
  private locToNode(start: Position, node: { location: Location }): Location {
    return { start, end: node.location.end };
  }
  private locToPrev(start: Position): Location {
    return { start, end: this.prevEnd };
  }

  // =========================================================================
  // Chunk / blocks / statements
  // =========================================================================

  parseChunk(): Chunk {
    const block = this.parseBlock();
    if (this.current.type !== TokenType.Eof) {
      this.error(`expected <eof> when parsing chunk, got ${this.describe(this.current)}`);
    }
    return { kind: 'Chunk', location: this.loc(block.location.start, this.current.location.end), block };
  }

  private blockFollow(): boolean {
    switch (this.current.type) {
      case TokenType.Eof:
      case TokenType.Else:
      case TokenType.Elseif:
      case TokenType.End:
      case TokenType.Until:
        return true;
      default:
        return false;
    }
  }

  /** Scoped block (locals die at the end). */
  private parseBlock(): Block {
    const mark = this.saveLocals();
    const block = this.parseBlockNoScope();
    this.restoreLocals(mark);
    return block;
  }

  /** Block without popping locals (repeat/until bodies). */
  private parseBlockNoScope(): Block {
    const start = this.prevEnd;
    const stats: Stat[] = [];
    while (!this.blockFollow()) {
      this.guard();
      const stat = this.parseStat();
      this.unguard();
      if (this.current.type === TokenType.Semicolon) this.advance();
      stats.push(stat);
      // return/break/continue must be the last statement of a block
      // [Parser.cpp isStatLast + parseBlockNoScope break]
      if (stat.kind === 'Return' || stat.kind === 'Break' || stat.kind === 'Continue') break;
    }
    return { kind: 'Block', location: this.loc(start, this.current.location.start), body: stats };
  }

  private parseStat(): Stat {
    switch (this.current.type) {
      case TokenType.If: return this.parseIf();
      case TokenType.While: return this.parseWhile();
      case TokenType.Do: return this.parseDo();
      case TokenType.For: return this.parseFor();
      case TokenType.Repeat: return this.parseRepeat();
      case TokenType.Function: return this.parseFunctionStat([]);
      case TokenType.Local: return this.parseLocal([], this.current);
      case TokenType.Return: return this.parseReturn();
      case TokenType.Break: return this.parseBreak();
      case TokenType.Attribute:
      case TokenType.AttributeOpen:
        return this.parseAttributeStat();
      default:
        return this.parseExprStatement();
    }
  }

  /** Reference parseStat default case: parse a primary expression, then
   *  decide call / assignment / contextual keyword. */
  private parseExprStatement(): Stat {
    const expr = this.parsePrimaryExpr(true);

    if (expr.kind === 'Call') {
      return { kind: 'ExprStat', location: expr.location, expr };
    }

    if (this.current.type === TokenType.Comma || this.current.type === TokenType.Assign) {
      return this.parseAssignment(expr);
    }

    const compound = COMPOUND_TOKENS[this.current.type];
    if (compound) {
      return this.parseCompoundAssignment(expr, compound);
    }

    // Not a call or an assignment: contextual keyword forms. The identifier
    // test covers locals as well as globals [Ast.cpp getIdentifier].
    const ident = expr.kind === 'Global' ? expr.name : expr.kind === 'LocalExpr' ? expr.local.name : null;

    if (ident === 'type') {
      return this.parseTypeAlias(false, expr.location);
    }

    if (ident === 'export') {
      if (this.current.type === TokenType.Name && this.current.value === 'type') {
        this.advance(); // consume `type`
        return this.parseTypeAlias(true, expr.location);
      }
      // `export local/const/function` value syntax: unsupported (D-M4-12)
      if (
        this.current.type === TokenType.Local || this.current.type === TokenType.Function ||
        (this.current.type === TokenType.Name && this.current.value === 'const')
      ) {
        this.error('export value syntax is not supported by this parser (only `export type`)');
      }
    }

    if (ident === 'continue') {
      return this.parseContinue(expr.location);
    }

    if (ident === 'const' && this.current.type === TokenType.Name) {
      this.error('const declarations are not supported by this parser');
    }

    if (ident === 'declare') {
      if (this.current.type === TokenType.Function) {
        this.error('declare syntax is not supported by this parser');
      }
      if (
        this.current.type === TokenType.Name &&
        (this.peek().type === TokenType.Colon ||
          this.peek().type === TokenType.DoubleColon ||
          this.current.value === 'class' ||
          this.current.value === 'extern')
      ) {
        this.error('declare syntax is not supported by this parser');
      }
    }

    this.error('Incomplete statement: expected assignment or a function call', expr.location);
  }

  // -- control flow ---------------------------------------------------------

  private parseIf(): IfStat {
    const start = this.advance().location.start; // if / elseif
    const condition = this.parseExpr();
    this.expect(TokenType.Then, 'if statement');
    const thenbody = this.parseBlock();
    if (this.current.type === TokenType.Elseif) {
      const elsebody = this.parseIf();
      return { kind: 'If', location: this.locToNode(start, elsebody), condition, thenbody, elsebody };
    }
    let elsebody: Block | null = null;
    if (this.current.type === TokenType.Else) {
      this.advance();
      elsebody = this.parseBlock();
    }
    const end = this.expect(TokenType.End, 'if statement');
    return { kind: 'If', location: this.locToToken(start, end), condition, thenbody, elsebody };
  }

  private parseWhile(): Stat {
    const start = this.advance().location.start;
    const condition = this.parseExpr();
    this.expect(TokenType.Do, 'while loop');
    this.functionStack[this.functionStack.length - 1]!.loopDepth++;
    const body = this.parseBlock();
    this.functionStack[this.functionStack.length - 1]!.loopDepth--;
    const end = this.expect(TokenType.End, 'while loop');
    return { kind: 'While', location: this.locToToken(start, end), condition, body };
  }

  private parseRepeat(): Stat {
    const start = this.advance().location.start;
    const mark = this.saveLocals();
    this.functionStack[this.functionStack.length - 1]!.loopDepth++;
    // No scope pop: the `until` condition sees the body's locals
    // [Lua 5.1 manual §3.3.4; Parser.cpp parseRepeat uses parseBlockNoScope]
    const body = this.parseBlockNoScope();
    this.functionStack[this.functionStack.length - 1]!.loopDepth--;
    this.expect(TokenType.Until, 'repeat loop');
    const condition = this.parseExpr();
    this.restoreLocals(mark);
    return { kind: 'Repeat', location: this.locToNode(start, condition), condition, body };
  }

  private parseDo(): Stat {
    const start = this.advance().location.start; // do
    const body = this.parseBlock();
    const end = this.expect(TokenType.End, 'do block');
    return { kind: 'Block', location: this.locToToken(start, end), body: body.body };
  }

  private parseFor(): Stat {
    const start = this.advance().location.start; // for
    const first = this.parseBinding();

    if (this.current.type === TokenType.Assign) {
      this.advance();
      const from = this.parseExpr();
      this.expect(TokenType.Comma, 'index range');
      const to = this.parseExpr();
      let step: Expr | null = null;
      if (this.curType() === TokenType.Comma) {
        this.advance();
        step = this.parseExpr();
      }
      this.expect(TokenType.Do, 'for loop');
      const mark = this.saveLocals();
      this.functionStack[this.functionStack.length - 1]!.loopDepth++;
      const loopVar = this.pushLocal(first); // binds AFTER from/to/step
      const body = this.parseBlock();
      this.functionStack[this.functionStack.length - 1]!.loopDepth--;
      this.restoreLocals(mark);
      const end = this.expect(TokenType.End, 'for loop');
      return { kind: 'For', location: this.locToToken(start, end), var: loopVar, from, to, step, body };
    }

    const names: Binding[] = [first];
    while (this.current.type === TokenType.Comma) {
      this.advance();
      names.push(this.parseBinding());
    }
    this.expect(TokenType.In, 'for loop');
    const values: Expr[] = this.parseExprList();
    this.expect(TokenType.Do, 'for loop');
    const mark = this.saveLocals();
    this.functionStack[this.functionStack.length - 1]!.loopDepth++;
    const vars = names.map((b) => this.pushLocal(b)); // bind AFTER iterators
    const body = this.parseBlock();
    this.functionStack[this.functionStack.length - 1]!.loopDepth--;
    this.restoreLocals(mark);
    const end = this.expect(TokenType.End, 'for loop');
    return { kind: 'ForIn', location: this.locToToken(start, end), vars, values, body };
  }

  private parseReturn(): Stat {
    const start = this.advance().location.start; // return
    const list: Expr[] = [];
    if (!this.blockFollow() && this.current.type !== TokenType.Semicolon) {
      list.push(...this.parseExprList());
    }
    const location = list.length ? this.locToNode(start, list[list.length - 1]!) : this.locToPrev(start);
    return { kind: 'Return', location, list };
  }

  private parseBreak(): Stat {
    const t = this.advance();
    if (this.functionStack[this.functionStack.length - 1]!.loopDepth === 0) {
      this.error('break statement must be inside a loop', t.location);
    }
    return { kind: 'Break', location: t.location };
  }

  private parseContinue(location: Location): Stat {
    if (this.functionStack[this.functionStack.length - 1]!.loopDepth === 0) {
      this.error('continue statement must be inside a loop', location);
    }
    return { kind: 'Continue', location };
  }

  // -- local / assignment -----------------------------------------------------

  private parseLocal(attributes: readonly Attribute[], localToken: Token): Stat {
    this.advance(); // local

    if (this.current.type === TokenType.Function) {
      const fnToken = this.advance();
      const nameToken = this.expect(TokenType.Name, 'variable name');
      const binding: Binding = { name: nameToken.value!, location: nameToken.location };
      const { func, funLocal } = this.parseFunctionBody(false, fnToken, binding.name, binding, attributes);
      return {
        kind: 'LocalFunction',
        location: this.locToToken(localToken.location.start, this.tokens[this.pos - 1]!),
        name: funLocal!,
        func,
      };
    }

    if (attributes.length > 0) {
      this.error(`expected 'function' after local declaration with attribute, got ${this.describe(this.current)}`);
    }

    const names: Binding[] = [this.parseBinding()];
    while (this.current.type === TokenType.Comma) {
      this.advance();
      names.push(this.parseBinding());
    }

    const values: Expr[] = [];
    if (this.current.type === TokenType.Assign) {
      this.advance();
      values.push(...this.parseExprList());
    }

    // Locals bind AFTER the right-hand side [Parser.cpp parseLocal]
    const vars = names.map((b) => this.pushLocal(b));
    const endPos = values.length ? values[values.length - 1]!.location.end : this.prevEnd;
    return {
      kind: 'Local',
      location: this.loc(localToken.location.start, endPos),
      vars,
      values,
    };
  }

  private isLValue(expr: Expr): boolean {
    return (
      expr.kind === 'LocalExpr' || expr.kind === 'Global' ||
      expr.kind === 'IndexName' || expr.kind === 'IndexExpr'
    );
  }

  private parseAssignment(initial: Expr): Stat {
    if (!this.isLValue(initial)) {
      this.error('Assigned expression must be a variable or a field', initial.location);
    }
    const vars: Expr[] = [initial];
    while (this.current.type === TokenType.Comma) {
      this.advance();
      const expr = this.parsePrimaryExpr(true);
      if (!this.isLValue(expr)) {
        this.error('Assigned expression must be a variable or a field', expr.location);
      }
      vars.push(expr);
    }
    this.expect(TokenType.Assign, 'assignment');
    const values = this.parseExprList();
    return {
      kind: 'Assign',
      location: this.loc(initial.location.start, values[values.length - 1]!.location.end),
      vars,
      values,
    };
  }

  private parseCompoundAssignment(initial: Expr, op: BinaryOp): Stat {
    if (!this.isLValue(initial)) {
      this.error('Assigned expression must be a variable or a field', initial.location);
    }
    this.advance(); // op token
    const value = this.parseExpr();
    return {
      kind: 'CompoundAssign',
      location: this.locToNode(initial.location.start, value),
      op,
      var: initial,
      value,
    };
  }

  // -- functions ------------------------------------------------------------

  /** funcname ::= Name {'.' Name} [':' Name] — lvalue chain + hasself. */
  private parseFunctionName(): { expr: Expr; hasself: boolean; debugname: string } {
    const start = this.current.location.start;
    let debugname = '';
    if (this.current.type === TokenType.Name) debugname = this.current.value!;
    let expr = this.parseNameExpr('function name');
    while (this.current.type === TokenType.Dot) {
      this.advance();
      const nameToken = this.expect(TokenType.Name, 'field name');
      debugname = nameToken.value!;
      expr = { kind: 'IndexName', location: this.locToToken(start, nameToken), expr, index: debugname, op: '.' };
      this.guard();
    }
    this.unguard();
    let hasself = false;
    if (this.current.type === TokenType.Colon) {
      this.advance();
      const nameToken = this.expect(TokenType.Name, 'method name');
      debugname = nameToken.value!;
      expr = { kind: 'IndexName', location: this.locToToken(start, nameToken), expr, index: debugname, op: ':' };
      hasself = true;
    }
    return { expr, hasself, debugname };
  }

  private parseFunctionStat(attributes: readonly Attribute[]): Stat {
    const start = this.current.location.start;
    const fnToken = this.advance(); // function
    const { expr, hasself, debugname } = this.parseFunctionName();
    if (!this.isLValue(expr)) {
      this.error('Assigned expression must be a variable or a field', expr.location);
    }
    const { func } = this.parseFunctionBody(hasself, fnToken, debugname, null, attributes);
    return {
      kind: 'FunctionStat',
      location: this.locToPrev(start),
      name: expr,
      func,
    };
  }

  /**
   * funcbody ::= ['<' generics '>'] '(' [parlist] ')' [':' ReturnType] block end
   * Returns the function expression plus (for `local function f`) the Local
   * binding, pushed before the body so the function can recurse.
   */
  private parseFunctionBody(
    hasself: boolean,
    fnToken: Token,
    debugname: string | null,
    localName: Binding | null,
    attributes: readonly Attribute[],
  ): { func: FunctionExpr; funLocal: Local | null } {
    const start = attributes.length ? attributes[0]!.location.start : fnToken.location.start;

    const generics = this.parseGenericTypeList(false);

    const openParen = this.expect(TokenType.LeftParen, 'function');
    let vararg = false;
    let varargAnnotation: TypePack | undefined;
    const args: Binding[] = [];
    if (this.current.type !== TokenType.RightParen) {
      const result = this.parseBindingList(true);
      args.push(...result.bindings);
      vararg = result.vararg;
      varargAnnotation = result.varargAnnotation;
    }
    this.expectMatch(TokenType.RightParen, openParen, 'function parameter list');

    let returnAnnotation: TypePack | undefined;
    if (this.current.type === TokenType.Colon || this.current.type === TokenType.Arrow) {
      if (this.current.type === TokenType.Arrow) {
        this.error("Function return type annotations are written after ':' instead of '->'");
      }
      this.advance();
      returnAnnotation = this.parseReturnType();
      if (this.curType() === TokenType.Comma) {
        this.error("Expected a statement, got ','; did you forget to wrap the list of return types in parentheses?");
      }
    }

    let funLocal: Local | null = null;
    if (localName) funLocal = this.pushLocal(localName);

    const mark = this.saveLocals();
    this.functionStack.push({ vararg, loopDepth: 0 });

    let self: Local | null = null;
    if (hasself) {
      self = this.pushLocal({ name: 'self', location: fnToken.location });
    }
    const argLocals = args.map((b) => this.pushLocal(b));

    const body = this.parseBlock();

    this.functionStack.pop();
    this.restoreLocals(mark);

    const end = this.expect(TokenType.End, 'function');
    const func: FunctionExpr = {
      kind: 'Function',
      location: this.locToToken(start, end),
      attributes,
      generics: generics.generics,
      genericPacks: generics.genericPacks,
      self,
      args: argLocals,
      vararg,
      varargAnnotation,
      returnAnnotation,
      body,
      debugname,
    };
    return { func, funLocal };
  }

  // -- attributes -------------------------------------------------------------

  private parseAttributes(): Attribute[] {
    const attrs: Attribute[] = [];
    while (this.current.type === TokenType.Attribute || this.current.type === TokenType.AttributeOpen) {
      if (this.current.type === TokenType.Attribute) {
        const token = this.advance();
        this.validateAttribute(token.value ?? '', attrs);
        attrs.push({ kind: 'Attribute', location: token.location, name: token.value ?? '' });
      } else {
        const open = this.advance(); // @[
        if (this.curType() !== TokenType.RightBracket) {
          for (;;) {
            const nameToken = this.expect(TokenType.Name, 'attribute name');
            // Attribute ARGUMENTS (`@[deprecated("msg")]`) are new-master
            // syntax with literal-argument validation — unsupported (D-M4-12)
            if (
              isStringToken(this.curType()) ||
              this.curType() === TokenType.LeftBrace ||
              this.curType() === TokenType.LeftParen
            ) {
              this.error('attribute arguments are not supported by this parser');
            }
            this.validateAttribute(nameToken.value!, attrs);
            attrs.push({ kind: 'Attribute', location: nameToken.location, name: nameToken.value! });
            if (this.curType() === TokenType.Comma) this.advance();
            else break;
          }
        }
        this.expectMatch(TokenType.RightBracket, open, 'attribute list');
      }
    }
    return attrs;
  }

  private validateAttribute(name: string, existing: readonly Attribute[]): void {
    if (name === '') this.error('Attribute name is missing');
    if (!KNOWN_ATTRIBUTES.has(name)) this.error(`Invalid attribute '@${name}'`);
    if (existing.some((a) => a.name === name)) this.error(`Cannot duplicate attribute '@${name}'`);
  }

  /** attributes function ... | attributes local ... [Parser.cpp parseAttributeStat] */
  private parseAttributeStat(): Stat {
    const attributes = this.parseAttributes();
    switch (this.current.type) {
      case TokenType.Function:
        return this.parseFunctionStat(attributes);
      case TokenType.Local:
        return this.parseLocal(attributes, this.current);
      default:
        if (this.current.type === TokenType.Name && (this.current.value === 'const' || this.current.value === 'export')) {
          this.error('attribute on const/export statements is not supported by this parser');
        }
        this.error(`expected 'function' or 'local' after attribute, got ${this.describe(this.current)}`);
    }
  }

  // =========================================================================
  // Expressions
  // =========================================================================

  private parseExprList(): Expr[] {
    const list: Expr[] = [this.parseExpr()];
    while (this.current.type === TokenType.Comma) {
      this.advance();
      if (this.curType() === TokenType.RightParen) {
        this.error("Expected expression after ',' but got ')' instead");
      }
      list.push(this.parseExpr());
    }
    return list;
  }

  private parseUnaryOp(): UnaryOp | null {
    switch (this.current.type) {
      case TokenType.Not: return 'Not';
      case TokenType.Minus: return 'Minus';
      case TokenType.Hash: return 'Len';
      default: return null;
    }
  }

  /** `&&` `||` `!=` adjacency confusables [Parser.cpp checkBinaryConfusables]. */
  private checkBinaryConfusables(limit: number): BinaryOp | null {
    const curr = this.current;
    if (curr.type !== TokenType.Amp && curr.type !== TokenType.Pipe && curr.type !== TokenType.Bang) return null;
    const next = this.peek();
    const adjacent =
      curr.location.end.offset === next.location.start.offset &&
      curr.location.end.line === next.location.start.line;
    if (curr.type === TokenType.Amp && next.type === TokenType.Amp && adjacent && BINARY_PRIORITY.And[0] > limit) {
      this.advance();
      this.error("Unexpected '&&'; did you mean 'and'?", this.loc(curr.location.start, next.location.end));
    }
    if (curr.type === TokenType.Pipe && next.type === TokenType.Pipe && adjacent && BINARY_PRIORITY.Or[0] > limit) {
      this.advance();
      this.error("Unexpected '||'; did you mean 'or'?", this.loc(curr.location.start, next.location.end));
    }
    // `!=` lexes as Bang immediately followed by the single-`=` Assign token
    // (`==` is TokenType.Equal — a different sequence).
    if (curr.type === TokenType.Bang && next.type === TokenType.Assign && adjacent && BINARY_PRIORITY.CompareNe[0] > limit) {
      this.advance();
      this.error("Unexpected '!='; did you mean '~='?", this.loc(curr.location.start, next.location.end));
    }
    return null;
  }

  /** subexpr → (asexp | unop subexpr) { binop subexpr } [Lua 5.1 lparser.c] */
  private parseExpr(limit = 0): Expr {
    this.guard();
    const start = this.current.location.start;
    let expr: Expr;

    const uop = this.parseUnaryOp();
    if (uop === null && this.current.type === TokenType.Bang) {
      this.error("Unexpected '!'; did you mean 'not'?");
    }
    if (uop !== null) {
      this.advance();
      const sub = this.parseExpr(UNARY_PRIORITY);
      expr = { kind: 'Unary', location: this.locToNode(start, sub), op: uop, expr: sub };
    } else {
      expr = this.parseAssertionExpr();
    }

    for (;;) {
      let op = BINARY_TOKENS[this.current.type] ?? null;
      if (op === null) op = this.checkBinaryConfusables(limit);
      if (op === null || BINARY_PRIORITY[op][0] <= limit) break;
      this.advance();
      const right = this.parseExpr(BINARY_PRIORITY[op][1]);
      expr = { kind: 'Binary', location: this.locToNode(start, right), op, left: expr, right };
    }

    this.unguard();
    return expr;
  }

  /** asexp → simpleexp ['::' Type] */
  private parseAssertionExpr(): Expr {
    const start = this.current.location.start;
    const expr = this.parseSimpleExpr();
    if (this.current.type === TokenType.DoubleColon) {
      this.advance();
      const annotation = this.parseType();
      return { kind: 'TypeAssertion', location: this.locToNode(start, annotation), expr, annotation };
    }
    return expr;
  }

  private parseSimpleExpr(): Expr {
    this.guard();
    try {
      switch (this.current.type) {
        case TokenType.Attribute:
        case TokenType.AttributeOpen:
          return this.parseAttributedFunction();
        case TokenType.Nil: {
          const t = this.advance();
          return { kind: 'Nil', location: t.location };
        }
        case TokenType.True:
        case TokenType.False: {
          const t = this.advance();
          return { kind: 'Bool', location: t.location, value: t.type === TokenType.True };
        }
        case TokenType.Function: {
          const fnToken = this.advance();
          return this.parseFunctionBody(false, fnToken, null, null, []).func;
        }
        case TokenType.Number:
          return this.parseNumberExpr();
        case TokenType.QuotedString:
        case TokenType.RawString:
        case TokenType.InterpStringSimple: {
          const t = this.advance();
          return { kind: 'String', location: t.location, value: t.value ?? '' };
        }
        case TokenType.InterpStringBegin:
          return this.parseInterpString();
        case TokenType.DotDotDot: {
          const t = this.advance();
          if (!this.functionStack[this.functionStack.length - 1]!.vararg) {
            this.error("Cannot use '...' outside of a vararg function", t.location);
          }
          return { kind: 'Vararg', location: t.location };
        }
        case TokenType.LeftBrace:
          return this.parseTableConstructor();
        case TokenType.If:
          return this.parseIfElseExpr();
        default:
          return this.parsePrimaryExpr(false);
      }
    } finally {
      this.unguard();
    }
  }

  private parseNumberExpr(): Expr {
    const t = this.advance();
    const result = parseNumberLiteral(t.value ?? '');
    if ('error' in result) this.error(result.error, t.location);
    if (result.kind === 'int64') {
      return { kind: 'Int', location: t.location, value: result.value, raw: t.value! };
    }
    return { kind: 'Number', location: t.location, value: result.value, raw: t.value! };
  }

  /** NAME | '(' expr ')' */
  private parsePrefixExpr(): Expr {
    if (this.current.type === TokenType.LeftParen) {
      const open = this.advance();
      const expr = this.parseExpr();
      const close = this.expectMatch(TokenType.RightParen, open, 'expression');
      return { kind: 'Group', location: this.locToToken(open.location.start, close), expr };
    }
    return this.parseNameExpr('expression');
  }

  private parseNameExpr(context: string): Expr {
    const t = this.current;
    if (t.type !== TokenType.Name) {
      this.error(`expected name when parsing ${context}, got ${this.describe(t)}`);
    }
    this.advance();
    const local = this.lookupLocal(t.value!);
    if (local) return { kind: 'LocalExpr', location: t.location, local };
    return { kind: 'Global', location: t.location, name: t.value! };
  }

  /** primaryexp → prefixexp {'.' Name | '[' exp ']' | ':' Name funcargs | funcargs | '<<' types '>>'} */
  private parsePrimaryExpr(asStatement: boolean): Expr {
    const start = this.current.location.start;
    let expr = this.parsePrefixExpr();
    for (;;) {
      this.guard();
      let keepGoing: boolean;
      switch (this.current.type) {
        case TokenType.Dot: {
          this.advance();
          const nameToken = this.expect(TokenType.Name, 'field name');
          expr = {
            kind: 'IndexName',
            location: this.locToToken(start, nameToken),
            expr,
            index: nameToken.value!,
            op: '.',
          };
          keepGoing = true;
          break;
        }
        case TokenType.LeftBracket: {
          const open = this.advance();
          const index = this.parseExpr();
          const close = this.expectMatch(TokenType.RightBracket, open, 'index expression');
          expr = { kind: 'IndexExpr', location: this.locToToken(start, close), expr, index };
          keepGoing = true;
          break;
        }
        case TokenType.Colon: {
          expr = this.parseMethodCall(start, expr);
          keepGoing = true;
          break;
        }
        case TokenType.LeftParen:
        case TokenType.LeftBrace:
        case TokenType.QuotedString:
        case TokenType.RawString:
          expr = this.parseFunctionArgs(expr, false);
          keepGoing = true;
          break;
        case TokenType.Less:
          if (this.peek().type === TokenType.Less) {
            expr = this.parseInstantiateExpr(start, expr);
            keepGoing = true;
          } else {
            keepGoing = false;
          }
          break;
        default:
          keepGoing = false;
          break;
      }
      this.unguard();
      if (!keepGoing) return expr;
    }
  }

  /** expr '<<' TypeList '>>' explicit instantiation (rare). */
  private parseInstantiateExpr(start: Position, expr: Expr): Expr {
    this.advance(); // '<'
    this.advance(); // '<'
    const typeArguments = this.parseTypeParamList();
    this.expect(TokenType.Greater, 'type instantiation');
    const close = this.expect(TokenType.Greater, 'type instantiation');
    return { kind: 'Instantiate', location: this.locToToken(start, close), expr, typeArguments };
  }

  /** ':' NAME funcargs — the IndexName keeps op ':' and the Call gets self. */
  private parseMethodCall(start: Position, expr: Expr): Expr {
    this.advance(); // ':'
    const nameToken = this.expect(TokenType.Name, 'method name');
    const func: Expr = {
      kind: 'IndexName',
      location: this.locToToken(start, nameToken),
      expr,
      index: nameToken.value!,
      op: ':',
    };
    if (this.current.type === TokenType.Less && this.peek().type === TokenType.Less) {
      this.error('type arguments on method calls are not supported by this parser');
    }
    return this.parseFunctionArgs(func, true);
  }

  /** args ::= '(' [explist] ')' | tableconstructor | String */
  private parseFunctionArgs(func: Expr, self: boolean): Expr {
    if (this.current.type === TokenType.LeftParen) {
      if (func.location.end.line !== this.current.location.start.line) {
        this.error(
          'Ambiguous syntax: this looks like an argument list for a function call, but could also be a start of ' +
            "new statement; use ';' to separate statements",
        );
      }
      const open = this.advance();
      const args: Expr[] = [];
      if (this.curType() !== TokenType.RightParen) {
        args.push(...this.parseExprList());
      }
      const close = this.expectMatch(TokenType.RightParen, open, 'function call');
      return { kind: 'Call', location: this.locToToken(func.location.start, close), func, args, self, tableCall: false };
    }
    if (this.current.type === TokenType.LeftBrace) {
      const table = this.parseTableConstructor();
      return {
        kind: 'Call',
        location: this.locToNode(func.location.start, table),
        func,
        args: [table],
        self,
        tableCall: true,
      };
    }
    if (isStringToken(this.current.type)) {
      const t = this.advance();
      const arg: Expr = { kind: 'String', location: t.location, value: t.value ?? '' };
      return { kind: 'Call', location: this.locToToken(func.location.start, t), func, args: [arg], self, tableCall: false };
    }
    this.error(`Expected '(', '{' or <string> when parsing function call, got ${this.describe(this.current)}`);
  }

  /** tableconstructor ::= '{' [fieldlist] '}' */
  private parseTableConstructor(): Expr {
    const open = this.expect(TokenType.LeftBrace, 'table literal');
    const items: {
      kind: 'List' | 'Record' | 'General';
      key: Expr | null;
      value: Expr;
    }[] = [];
    while (this.current.type !== TokenType.RightBrace) {
      if (this.current.type === TokenType.LeftBracket) {
        const bracket = this.advance();
        const key = this.parseExpr();
        this.expectMatch(TokenType.RightBracket, bracket, 'table field');
        this.expect(TokenType.Assign, 'table field');
        const value = this.parseExpr();
        items.push({ kind: 'General', key, value });
      } else if (this.current.type === TokenType.Name && this.peek().type === TokenType.Assign) {
        const nameToken = this.advance();
        this.expect(TokenType.Assign, 'table field');
        const key: Expr = { kind: 'String', location: nameToken.location, value: nameToken.value! };
        let value = this.parseExpr();
        // { name = function() ... } propagates the field name as debugname
        // [Parser.cpp parseTableConstructor] — clone, never mutate nodes.
        if (value.kind === 'Function' && value.debugname === null) {
          value = { ...value, debugname: nameToken.value! };
        }
        items.push({ kind: 'Record', key, value });
      } else {
        const value = this.parseExpr();
        items.push({ kind: 'List', key: null, value });
      }
      if (this.current.type === TokenType.Comma || this.current.type === TokenType.Semicolon) {
        this.advance();
      } else if (this.curType() !== TokenType.RightBrace) {
        break;
      }
    }
    const close = this.expectMatch(TokenType.RightBrace, open, 'table literal');
    return { kind: 'Table', location: this.locToToken(open.location.start, close), items };
  }

  /** `if c then a else b` (+ elseif chains nesting into falseExpr). */
  private parseIfElseExpr(): Expr {
    const start = this.advance().location.start; // if / elseif
    const condition = this.parseExpr();
    this.expect(TokenType.Then, 'if then else expression');
    const trueExpr = this.parseExpr();
    let falseExpr: Expr;
    if (this.current.type === TokenType.Elseif) {
      falseExpr = this.parseIfElseExpr();
    } else {
      this.expect(TokenType.Else, 'if then else expression');
      falseExpr = this.parseExpr();
    }
    return { kind: 'IfElse', location: this.locToNode(start, falseExpr), condition, trueExpr, falseExpr };
  }

  /** Backtick string: sections arrive as Begin/Mid/End tokens (lexer-driven). */
  private parseInterpString(): Expr {
    const start = this.current.location.start;
    const strings: string[] = [];
    const expressions: Expr[] = [];
    let end: Token = this.current;
    for (;;) {
      const section = this.advance(); // Begin | Mid | End
      end = section;
      strings.push(section.value ?? '');
      if (section.type === TokenType.InterpStringEnd || section.type === TokenType.InterpStringSimple) break;
      if (
        this.current.type === TokenType.InterpStringMid ||
        this.current.type === TokenType.InterpStringEnd ||
        this.current.type === TokenType.Eof
      ) {
        this.error("Malformed interpolated string, expected expression inside '{}'");
      }
      expressions.push(this.parseExpr());
    }
    return {
      kind: 'InterpString',
      location: this.locToToken(start, end),
      strings,
      expressions,
    };
  }

  /** `@native function(...) ... end` as an expression. */
  private parseAttributedFunction(): Expr {
    const attributes = this.parseAttributes();
    const fnToken = this.expect(TokenType.Function, 'attributed function');
    return this.parseFunctionBody(false, fnToken, null, null, attributes).func;
  }

  // =========================================================================
  // Type annotations
  // =========================================================================

  private parseTypeAlias(exported: boolean, startLoc: Location): Stat {
    // `type` token already consumed by the caller.
    if (this.current.type === TokenType.Function) {
      const fnToken = this.advance();
      const nameToken = this.expect(TokenType.Name, 'type function name');
      const { func } = this.parseFunctionBody(false, fnToken, nameToken.value!, null, []);
      return {
        kind: 'TypeFunction',
        location: this.locToPrev(startLoc.start),
        name: nameToken.value!,
        nameLocation: nameToken.location,
        body: func,
        exported,
      };
    }

    const nameToken = this.expect(TokenType.Name, 'type name');
    const generics = this.parseGenericTypeList(true);
    this.expect(TokenType.Assign, 'type alias');
    const type = this.parseType();
    return {
      kind: 'TypeAlias',
      location: this.loc(startLoc.start, type.location.end),
      name: nameToken.value!,
      nameLocation: nameToken.location,
      generics: generics.generics,
      genericPacks: generics.genericPacks,
      type,
      exported,
    };
  }

  /** Type ::= [simpletype] suffix — suffix loop handles '|', '?', '&'. */
  private parseType(): Type {
    this.guard();
    try {
      const begin = this.current.location.start;
      let type: Type | null = null;
      if (this.current.type !== TokenType.Pipe && this.current.type !== TokenType.Amp) {
        type = this.parseSimpleType(false).type;
      }
      return this.parseTypeSuffix(type, begin);
    } finally {
      this.unguard();
    }
  }

  /**
   * Flat union/intersection suffix loop [Parser.cpp parseTypeSuffix].
   * `?` wraps the previous part in Optional (ast.ts note 4 — the reference
   * pushes a union marker instead); mixing `|` with `&` (directly or via
   * `?`) is an error, exactly like the reference.
   */
  private parseTypeSuffix(type: Type | null, begin: Position): Type {
    const parts: Type[] = type ? [type] : [];
    let isUnion = false;
    let isIntersection = false;

    for (;;) {
      if (this.current.type === TokenType.Pipe) {
        this.advance();
        parts.push(this.parseSimpleType(false).type);
        isUnion = true;
      } else if (this.current.type === TokenType.QuestionMark) {
        const q = this.advance();
        const last = parts.pop();
        if (!last) this.error("Unexpected '?' at the start of a type annotation", q.location);
        parts.push({ kind: 'TypeOptional', location: q.location, type: last });
        isUnion = true;
      } else if (this.current.type === TokenType.Amp) {
        this.advance();
        parts.push(this.parseSimpleType(false).type);
        isIntersection = true;
      } else if (this.current.type === TokenType.DotDotDot) {
        this.error("Unexpected '...' after type annotation");
      } else {
        break;
      }
    }

    if (isUnion && isIntersection) {
      this.error('Mixing union and intersection types is not allowed; consider wrapping in parentheses.');
    }
    // A lone `T?` is the Optional wrapper itself (ast.ts note 4) — never a
    // one-element union. Multi-part suffixes always have length >= 2.
    if (parts.length === 1) return parts[0]!;
    const end = parts[parts.length - 1]!.location.end;
    if (isUnion) return { kind: 'TypeUnion', location: this.loc(begin, end), types: parts };
    return { kind: 'TypeIntersection', location: this.loc(begin, end), types: parts };
  }

  private parseSimpleType(allowPack: false): { type: Type; pack?: undefined };
  private parseSimpleType(allowPack: true): { type: Type | null; pack?: TypePack };
  private parseSimpleType(allowPack: boolean): { type: Type | null; pack?: TypePack } {
    this.guard();
    try {
      switch (this.current.type) {
        case TokenType.Attribute:
        case TokenType.AttributeOpen:
          this.error('attributes are not allowed in this type annotation context');
          break;
        case TokenType.Nil: {
          const t = this.advance();
          return { type: { kind: 'TypeReference', location: t.location, prefix: null, name: 'nil', parameters: null } };
        }
        case TokenType.True:
        case TokenType.False: {
          const t = this.advance();
          return { type: { kind: 'TypeSingletonBool', location: t.location, value: t.type === TokenType.True } };
        }
        case TokenType.QuotedString:
        case TokenType.RawString: {
          const t = this.advance();
          return { type: { kind: 'TypeSingletonString', location: t.location, value: t.value ?? '' } };
        }
        case TokenType.InterpStringBegin:
        case TokenType.InterpStringSimple:
          this.error('Interpolated string literals cannot be used as types');
          break;
        case TokenType.Name: {
          const nameToken = this.advance();
          // `typeof(expr)` — contextual in type position [Parser.cpp parseSimpleType]
          if (nameToken.value === 'typeof') {
            const open = this.expect(TokenType.LeftParen, 'typeof type');
            const expr = this.parseExpr();
            const close = this.expectMatch(TokenType.RightParen, open, 'typeof type');
            return { type: { kind: 'TypeofType', location: this.locToToken(nameToken.location.start, close), expr } };
          }
          if (this.curType() === TokenType.Dot) {
            this.advance();
            const fieldToken = this.expect(TokenType.Name, 'field name');
            if (this.curType() === TokenType.DotDotDot) {
              this.error("Unexpected '...' after type name; type pack is not allowed in this context");
            }
            let parameters: (Type | TypePack)[] | null = null;
            if (this.curType() === TokenType.Less) parameters = this.parseTypeParams();
            return {
              type: {
                kind: 'TypeReference',
                location: this.locToToken(nameToken.location.start, fieldToken),
                prefix: nameToken.value!,
                name: fieldToken.value!,
                parameters,
              },
            };
          }
          if (this.curType() === TokenType.DotDotDot) {
            this.error("Unexpected '...' after type name; type pack is not allowed in this context");
          }
          let parameters: (Type | TypePack)[] | null = null;
          if (this.curType() === TokenType.Less) parameters = this.parseTypeParams();
          return {
            type: {
              kind: 'TypeReference',
              location: parameters ? this.locToPrev(nameToken.location.start) : nameToken.location,
              prefix: null,
              name: nameToken.value!,
              parameters,
            },
          };
        }
        case TokenType.LeftBrace:
          return { type: this.parseTableType() };
        case TokenType.LeftParen:
        case TokenType.Less:
          return this.parseFunctionType(allowPack);
        case TokenType.Function:
          this.error(
            "Using 'function' as a type annotation is not supported, consider replacing with a function type " +
              "annotation e.g. '(...any) -> ...any'",
          );
          break;
        default:
          this.error(`Expected type, got ${this.describe(this.current)}`);
      }
    } finally {
      this.unguard();
    }
  }

  /** TypeList with optional leading argument names + pack tail. */
  private parseTypeList(types: Type[], names: (ArgumentName | null)[]): TypePack | null {
    for (;;) {
      if (this.shouldParseTypePack()) return this.parseTypePack();
      if (this.current.type === TokenType.Name && this.peek().type === TokenType.Colon) {
        const nameToken = this.advance();
        names.push({ name: nameToken.value!, location: nameToken.location });
        this.advance(); // ':'
      } else if (names.length > 0) {
        names.push(null);
      }
      types.push(this.parseType());
      if (this.curType() !== TokenType.Comma) break;
      this.advance();
      if (this.current.type === TokenType.RightParen) {
        this.error("Expected type after ',' but got ')' instead");
      }
    }
    return null;
  }

  /**
   * `(` params `)` + optional `->` return — the function-type / group / pack
   * disambiguation [Parser.cpp parseFunctionType]. The single-paren-type
   * unwrap rule follows the master direction (Group only when a suffix
   * follows): D-M4-14.
   */
  private parseFunctionType(allowPack: false): { type: Type; pack?: undefined };
  private parseFunctionType(allowPack: true): { type: Type | null; pack?: TypePack };
  private parseFunctionType(allowPack: boolean): { type: Type | null; pack?: TypePack };
  private parseFunctionType(allowPack: boolean): { type: Type | null; pack?: TypePack } {
    const begin = this.current.location.start;
    let forceFunctionType = this.current.type === TokenType.Less;

    const generics = this.parseGenericTypeList(false);

    const openParen = this.expect(TokenType.LeftParen, 'function parameters');
    const params: Type[] = [];
    const names: (ArgumentName | null)[] = [];
    let varargTail: TypePack | null = null;
    if (this.current.type !== TokenType.RightParen) {
      varargTail = this.parseTypeList(params, names);
    }
    this.expectMatch(TokenType.RightParen, openParen, 'function type');

    if (names.length > 0) forceFunctionType = true;
    const returnTypeIntroducer = this.current.type === TokenType.Arrow || this.current.type === TokenType.Colon;

    // Not a function at all — a parenthesized type / one-element pack.
    if (params.length === 1 && varargTail === null && !forceFunctionType && !returnTypeIntroducer) {
      if (allowPack) {
        return {
          type: null,
          pack: {
            kind: 'TypePackExplicit',
            location: this.locToPrev(begin),
            typeList: { types: params, tail: null },
          },
        };
      }
      return { type: params[0]! }; // D-M4-14: `(T)` unwraps unless a suffix follows
    }
    if (!forceFunctionType && !returnTypeIntroducer && allowPack) {
      return {
        type: null,
        pack: {
          kind: 'TypePackExplicit',
          location: this.locToPrev(begin),
          typeList: { types: params, tail: varargTail },
        },
      };
    }

    const fnType = this.parseFunctionTypeTail(begin, generics.generics, generics.genericPacks, params, names, varargTail);
    return { type: fnType };
  }

  private parseFunctionTypeTail(
    begin: Position,
    generics: readonly GenericType[],
    genericPacks: readonly GenericTypePack[],
    params: readonly Type[],
    paramNames: readonly (ArgumentName | null)[],
    varargTail: TypePack | null,
  ): Type {
    if (this.current.type === TokenType.Colon) {
      this.error("Return types in function type annotations are written after '->' instead of ':'");
    } else if (
      this.current.type !== TokenType.Arrow &&
      generics.length === 0 && genericPacks.length === 0 && params.length === 0
    ) {
      this.error("Expected '->' after '()' when parsing function type; did you mean 'nil'?");
    } else {
      this.expect(TokenType.Arrow, 'function type');
    }
    const returnTypes = this.parseReturnType();
    return {
      kind: 'FunctionType',
      location: this.locToPrev(begin),
      attributes: [],
      generics,
      genericPacks,
      argTypes: { types: params, tail: varargTail },
      argNames: paramNames,
      returnTypes,
    };
  }

  /** ReturnType ::= Type | '(' TypeList ')' | '(' TypeList ')' '->' ReturnType */
  private parseReturnType(): TypePack {
    const begin = this.current.location.start;
    if (this.current.type !== TokenType.LeftParen) {
      if (this.shouldParseTypePack()) return this.parseTypePack();
      const type = this.parseType();
      return { kind: 'TypePackExplicit', location: type.location, typeList: { types: [type], tail: null } };
    }

    const open = this.advance();
    const types: Type[] = [];
    const names: (ArgumentName | null)[] = [];
    let varargTail: TypePack | null = null;
    if (this.curType() !== TokenType.RightParen) {
      varargTail = this.parseTypeList(types, names);
    }
    this.expectMatch(TokenType.RightParen, open, 'return type');

    if (this.curType() === TokenType.Arrow) {
      const tail = this.parseFunctionTypeTail(begin, [], [], types, names, varargTail);
      return {
        kind: 'TypePackExplicit',
        location: this.locToPrev(begin),
        typeList: { types: [tail], tail: null },
      };
    }

    if (names.length === 0 && types.length === 1) {
      const inner = varargTail === null && isTypeFollow(this.current.type)
        ? ({ kind: 'TypeGroup', location: this.locToPrev(begin), type: types[0]! } as Type)
        : types[0]!;
      const returnType = this.parseTypeSuffix(inner, begin);
      return {
        kind: 'TypePackExplicit',
        location: this.locToPrev(begin),
        typeList: { types: [returnType], tail: varargTail },
      };
    }

    return {
      kind: 'TypePackExplicit',
      location: this.locToPrev(begin),
      typeList: { types, tail: varargTail },
    };
  }

  private shouldParseTypePack(): boolean {
    return (
      this.current.type === TokenType.DotDotDot ||
      (this.current.type === TokenType.Name && this.peek().type === TokenType.DotDotDot)
    );
  }

  /** `...T` variadic | `a...` generic pack. */
  private parseTypePack(): TypePack {
    if (this.current.type === TokenType.DotDotDot) {
      const start = this.advance().location.start;
      const type = this.parseType();
      return { kind: 'TypePackVariadic', location: this.locToNode(start, type), type };
    }
    if (this.current.type === TokenType.Name && this.peek().type === TokenType.DotDotDot) {
      const nameToken = this.advance();
      const dots = this.advance();
      return { kind: 'TypePackGeneric', location: this.locToToken(nameToken.location.start, dots), name: nameToken.value! };
    }
    this.error('internal error: parseTypePack called without a pack start');
  }

  /** Tail of `...: T` / `...: a...` in parameter lists. */
  private parseVariadicArgumentTypePack(): TypePack {
    if (this.current.type === TokenType.Name && this.peek().type === TokenType.DotDotDot) {
      const nameToken = this.advance();
      const dots = this.advance();
      return { kind: 'TypePackGeneric', location: this.locToToken(nameToken.location.start, dots), name: nameToken.value! };
    }
    const type = this.parseType();
    return { kind: 'TypePackVariadic', location: type.location, type };
  }

  /** '<' [T {',' T}] '>' — type arguments on type references. */
  private parseTypeParams(): (Type | TypePack)[] {
    this.expect(TokenType.Less, 'type parameters');
    const params = this.parseTypeParamList();
    this.expect(TokenType.Greater, 'type parameters');
    return params;
  }

  /** The list between `<`/`<<` and the closing `>`/`>>` (not consumed). */
  private parseTypeParamList(): (Type | TypePack)[] {
    const params: (Type | TypePack)[] = [];
    for (;;) {
      if (this.shouldParseTypePack()) {
        params.push(this.parseTypePack());
      } else if (this.current.type === TokenType.LeftParen) {
        const begin = this.current.location.start;
        const simple = this.parseSimpleType(true);
        if (simple.pack) {
          // `(T)` + type-follow ⇒ parenthesized type, not a pack
          // [Parser.cpp parseTypeParams quirk]
          if (
            simple.pack.kind === 'TypePackExplicit' &&
            simple.pack.typeList.tail === null &&
            simple.pack.typeList.types.length === 1 &&
            isTypeFollow(this.current.type)
          ) {
            const inner = simple.pack.typeList.types[0]!;
            const group: Type = { kind: 'TypeGroup', location: this.locToPrev(begin), type: inner };
            params.push(this.parseTypeSuffix(group, begin));
          } else {
            params.push(simple.pack);
          }
        } else {
          params.push(this.parseTypeSuffix(simple.type, begin));
        }
      } else if (this.current.type === TokenType.Pipe || this.current.type === TokenType.Amp) {
        // leading-separator union/intersection inside parameters
        params.push(this.parseTypeSuffix(null, this.current.location.start));
      } else {
        const begin = this.current.location.start;
        const simple = this.parseSimpleType(false);
        params.push(this.parseTypeSuffix(simple.type, begin));
      }
      if (this.curType() === TokenType.Comma) {
        this.advance();
        if (this.current.type === TokenType.Greater) {
          this.error("Expected type after ',' but got '>' instead");
        }
      } else break;
    }
    return params;
  }

  /** Generics with optional defaults and trailing `...` packs. */
  private parseGenericTypeList(withDefaultValues: boolean): {
    generics: GenericType[];
    genericPacks: GenericTypePack[];
  } {
    const generics: GenericType[] = [];
    const genericPacks: GenericTypePack[] = [];
    if (this.current.type !== TokenType.Less) return { generics, genericPacks };

    this.advance(); // '<'
    let seenPack = false;
    let seenDefault = false;
    for (;;) {
      const nameToken = this.expect(TokenType.Name, 'generic name');
      const isPack = this.curType() === TokenType.DotDotDot || seenPack;

      if (isPack) {
        seenPack = true;
        if (this.curType() !== TokenType.DotDotDot) {
          this.error('Generic types come before generic type packs');
        }
        this.advance(); // '...'
        let defaultValue: TypePack | undefined;
        if (withDefaultValues && this.curType() === TokenType.Assign) {
          this.advance();
          seenDefault = true;
          if (this.shouldParseTypePack()) defaultValue = this.parseTypePack();
          else {
            const simple = this.parseSimpleType(true);
            if (simple.type) this.error("Expected type pack after '=', got type");
            defaultValue = simple.pack!;
          }
        } else if (seenDefault) {
          this.error('Expected default type pack after type pack name');
        }
        genericPacks.push({ name: nameToken.value!, location: nameToken.location, defaultValue });
      } else {
        let defaultValue: Type | undefined;
        if (withDefaultValues && this.curType() === TokenType.Assign) {
          this.advance();
          seenDefault = true;
          defaultValue = this.parseType();
        } else if (seenDefault) {
          this.error('Expected default type after type name');
        }
        generics.push({ name: nameToken.value!, location: nameToken.location, defaultValue });
      }

      if (this.curType() === TokenType.Comma) {
        this.advance();
        if (this.curType() === TokenType.Greater) {
          this.error("Expected type after ',' but got '>' instead");
        }
      } else break;
    }
    this.expect(TokenType.Greater, 'generic type list');
    return { generics, genericPacks };
  }

  /** TableType: props, string-named props, indexer, array desugar. */
  private parseTableType(): Type {
    const open = this.expect(TokenType.LeftBrace, 'table type');
    const props: TableProp[] = [];
    let indexer: TableIndexer | null = null;

    while (this.current.type !== TokenType.RightBrace) {
      if (this.current.type === TokenType.LeftBracket) {
        const bracket = this.advance();
        if (isStringToken(this.current.type) && this.peek().type === TokenType.RightBracket) {
          const strToken = this.advance();
          this.expectMatch(TokenType.RightBracket, bracket, 'table type');
          this.expect(TokenType.Colon, 'table field');
          const type = this.parseType();
          if ((strToken.value ?? '').includes('\0')) {
            this.error('String literal contains malformed escape sequence or \\0', strToken.location);
          }
          props.push({ name: strToken.value ?? '', location: strToken.location, type });
        } else {
          const indexType = this.parseType();
          this.expectMatch(TokenType.RightBracket, bracket, 'table type');
          this.expect(TokenType.Colon, 'table type');
          const resultType = this.parseType();
          if (indexer) this.error('Cannot have more than one table indexer');
          indexer = { indexType, resultType, location: this.locToPrev(bracket.location.start) };
        }
      } else if (
        props.length === 0 && indexer === null &&
        !(this.current.type === TokenType.Name && this.peek().type === TokenType.Colon)
      ) {
        // {T} desugars to {[number]: T} [Parser.cpp parseTableType]
        const resultType = this.parseType();
        const numberRef: Type = {
          kind: 'TypeReference',
          location: open.location,
          prefix: null,
          name: 'number',
          parameters: null,
        };
        indexer = { indexType: numberRef, resultType, location: resultType.location };
        if (this.current.type === TokenType.Comma || this.current.type === TokenType.Semicolon) this.advance();
        break;
      } else {
        const nameToken = this.expect(TokenType.Name, 'table field');
        this.expect(TokenType.Colon, 'table field');
        const type = this.parseType();
        props.push({ name: nameToken.value!, location: nameToken.location, type });
      }

      if (this.current.type === TokenType.Comma || this.current.type === TokenType.Semicolon) {
        this.advance();
      } else if (this.curType() !== TokenType.RightBrace) {
        break;
      }
    }
    const close = this.expectMatch(TokenType.RightBrace, open, 'table type');
    return {
      kind: 'TypeTable',
      location: this.locToToken(open.location.start, close),
      props,
      indexer,
      isExact: false,
    };
  }

  // -- bindings ---------------------------------------------------------------

  private parseBinding(): Binding {
    const t = this.current;
    if (t.type !== TokenType.Name) {
      this.error(`expected name when parsing variable name, got ${this.describe(t)}`);
    }
    this.advance();
    let annotation: Type | undefined;
    if (this.current.type === TokenType.Colon) {
      this.advance();
      annotation = this.parseType();
    }
    return { name: t.value!, location: t.location, annotation };
  }

  /** bindinglist ::= (binding | '...') {',' ...} — vararg must be last. */
  private parseBindingList(allowDot3: boolean): {
    bindings: Binding[];
    vararg: boolean;
    varargAnnotation?: TypePack;
  } {
    const bindings: Binding[] = [];
    for (;;) {
      if (this.current.type === TokenType.DotDotDot && allowDot3) {
        this.advance();
        let varargAnnotation: TypePack | undefined;
        if (this.curType() === TokenType.Colon) {
          this.advance();
          varargAnnotation = this.parseVariadicArgumentTypePack();
        }
        return { bindings, vararg: true, varargAnnotation };
      }
      bindings.push(this.parseBinding());
      if (this.current.type !== TokenType.Comma) break;
      this.advance();
    }
    return { bindings, vararg: false };
  }
}

/** Parse a Luau source (latin1 byte-string model) into a Chunk. */
export function parse(source: string, options?: ParseOptions): Chunk {
  return new Parser(tokenize(source), options).parseChunk();
}
