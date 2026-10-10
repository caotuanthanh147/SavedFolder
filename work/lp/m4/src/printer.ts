/**
 * AST → Luau source printer (round-trip faithful).
 *
 * Goal: for any AST produced by this parser, `print(ast)` re-parses to a
 * structurally identical AST (locations excluded; Local identity paired
 * positionally — see tests/roundtrip.ts). Not a pretty-printer of the
 * ORIGINAL source (comments/spacing are not in the AST); it is the M6
 * transform output path and the §10.3 fuzzing round-trip oracle.
 *
 * Spec anchors:
 *  - Operator precedence/associativity mirrors Parser.cpp binaryPriority /
 *    lua.org lparser.c (the same table the parser uses — parser.ts).
 *  - Parenthesization: a Binary child gets parens iff its left priority is
 *    <= the context limit; equal-priority LEFT-ASSOCIATIVE chains (l == r)
 *    in LEFT position re-associate identically and skip the parens. Unary
 *    context = 8 (UNARY_PRIORITY). IfElse / Function literals are
 *    parenthesized in operand positions (they are not primary).
 *  - Ambiguity guards: a statement whose first token is `(` (group) or
 *    `-` (unary minus) would merge with the previous line on re-parse
 *    (call extension / subtraction) — the previous statement gets a `;`
 *    [Parser.cpp parsePrimaryExpr same-line check; Luau::transpile does
 *    the same via leading ';'].
 *  - Strings re-encode canonically (byte-string → double-quoted with
 *    \n \r \t \" \\ and \ddd otherwise); interp-string parts additionally
 *    escape ` { } so no interpolation boundary can appear.
 *  - Numbers print their preserved `raw` (byte-exact).
 *  - `f{...}` keeps the table-call form (tableCall is semantic:
 *    `f({...})` re-parses with tableCall=false); string-call args print
 *    as plain paren calls (both parse to tableCall=false — identical
 *    shape, so the round-trip comparator is unaffected).
 *  - Union/intersection members that are unions/intersections/optionals/
 *    function/typeof types print parenthesized (suffix binding).
 *  - TypeGroup prints its own parens; TypeOptional is the `?` suffix.
 */
import type {
  Attribute, BinaryOp, Block, Chunk, Expr, FunctionExpr, GenericType,
  GenericTypePack, IfStat, Local, Stat, TableItem, Type, TypePack,
} from './ast';

// ---------------------------------------------------------------------------
// Operator tables [Parser.cpp binaryPriority; identical to parser.ts]
// ---------------------------------------------------------------------------

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

const BINARY_OP_TEXT: Readonly<Record<BinaryOp, string>> = {
  Add: '+', Sub: '-', Mul: '*', Div: '/', FloorDiv: '//', Mod: '%',
  Pow: '^', Concat: '..',
  CompareNe: '~=', CompareEq: '==', CompareLt: '<', CompareLe: '<=',
  CompareGt: '>', CompareGe: '>=',
  And: 'and', Or: 'or',
};

const UNARY_OP_TEXT: Readonly<Record<'Not' | 'Minus' | 'Len', string>> = {
  Not: 'not ', Minus: '-', Len: '#',
};

// ---------------------------------------------------------------------------
// Entry
// ---------------------------------------------------------------------------

/** Print a parsed chunk to Luau source (trailing newline if non-empty). */
export function print(chunk: Chunk): string {
  const body = blockText(chunk.block, 0);
  return body === '' ? '' : body + '\n';
}

const pad = (indent: number): string => ' '.repeat(indent * 4);

// ---------------------------------------------------------------------------
// Blocks / statements
// ---------------------------------------------------------------------------

function blockText(block: Block | readonly Stat[], indent: number): string {
  // NB: the Block STATEMENT's `body` is a bare Stat[] (parser unwraps the
  // nested block); every other construct stores a Block object.
  const stats: readonly Stat[] = 'body' in block ? block.body : block;
  const lines: string[] = [];
  for (const stat of stats) {
    const text = statText(stat, indent);
    // Ambiguity guard: a statement whose first token is `(` would extend
    // the previous line's call on re-parse [Parser.cpp same-line check;
    // Luau::transpile emits the same guard]. (`-` can never start a
    // statement: ExprStat must be a call, and prefixexps don't begin with
    // a unary op.)
    if (lines.length > 0 && text.trimStart().startsWith('(')) {
      lines[lines.length - 1] += ';';
    }
    lines.push(text);
  }
  return lines.join('\n');
}

function statText(stat: Stat, indent: number): string {
  switch (stat.kind) {
    case 'Block':
      return `${pad(indent)}do\n${blockText(stat.body, indent + 1)}\n${pad(indent)}end`;
    case 'If':
      return ifText(stat, indent);
    case 'While':
      return `${pad(indent)}while ${expr(stat.condition, indent)} do\n${blockText(stat.body, indent + 1)}\n${pad(indent)}end`;
    case 'Repeat':
      return `${pad(indent)}repeat\n${blockText(stat.body, indent + 1)}\n${pad(indent)}until ${expr(stat.condition, indent)}`;
    case 'Break':
      return `${pad(indent)}break`;
    case 'Continue':
      return `${pad(indent)}continue`;
    case 'Return':
      return stat.list.length === 0
        ? `${pad(indent)}return`
        : `${pad(indent)}return ${stat.list.map((e) => expr(e, indent)).join(', ')}`;
    case 'ExprStat':
      return `${pad(indent)}${expr(stat.expr, indent)}`;
    case 'Local': {
      const vars = stat.vars.map(localDecl).join(', ');
      return stat.values.length === 0
        ? `${pad(indent)}local ${vars}`
        : `${pad(indent)}local ${vars} = ${stat.values.map((e) => expr(e, indent)).join(', ')}`;
    }
    case 'For': {
      const head = stat.step
        ? `${localDecl(stat.var)} = ${expr(stat.from, indent)}, ${expr(stat.to, indent)}, ${expr(stat.step, indent)}`
        : `${localDecl(stat.var)} = ${expr(stat.from, indent)}, ${expr(stat.to, indent)}`;
      return `${pad(indent)}for ${head} do\n${blockText(stat.body, indent + 1)}\n${pad(indent)}end`;
    }
    case 'ForIn':
      return `${pad(indent)}for ${stat.vars.map(localDecl).join(', ')} in ${stat.values.map((e) => expr(e, indent)).join(', ')} do\n${blockText(stat.body, indent + 1)}\n${pad(indent)}end`;
    case 'Assign':
      return `${pad(indent)}${stat.vars.map((e) => expr(e, indent)).join(', ')} = ${stat.values.map((e) => expr(e, indent)).join(', ')}`;
    case 'CompoundAssign':
      return `${pad(indent)}${expr(stat.var, indent)} ${BINARY_OP_TEXT[stat.op]}= ${expr(stat.value, indent)}`;
    case 'FunctionStat':
      return `${pad(indent)}${functionStatText(stat.name, stat.func, indent)}`;
    case 'LocalFunction':
      return `${pad(indent)}${functionStatText(null, stat.func, indent, stat.name.name)}`;
    case 'TypeAlias': {
      const g = genericText(stat.generics, stat.genericPacks);
      return `${pad(indent)}${stat.exported ? 'export ' : ''}type ${stat.name}${g} = ${type(stat.type)}`;
    }
    case 'TypeFunction':
      // AST-only node (the parser rejects the syntax; kitchen-sink fixture)
      return `${pad(indent)}${stat.exported ? 'export ' : ''}type ${stat.name} = ${functionText(stat.body, indent)}`;
  }
}

function ifText(stat: Extract<Stat, { kind: 'If' }>, indent: number): string {
  const parts: string[] = [];
  let cur: Extract<Stat, { kind: 'If' }> | null = stat;
  let first = true;
  while (cur) {
    parts.push(`${pad(indent)}${first ? 'if' : 'elseif'} ${expr(cur.condition, indent)} then`);
    parts.push(blockText(cur.thenbody, indent + 1));
    const elsebody: Block | IfStat | null = cur.elsebody;
    if (elsebody === null) {
      parts.push(`${pad(indent)}end`);
      return parts.filter((p) => p !== '').join('\n');
    }
    if (elsebody.kind === 'If') {
      cur = elsebody;
      first = false;
      continue;
    }
    parts.push(`${pad(indent)}else`);
    parts.push(blockText(elsebody, indent + 1));
    parts.push(`${pad(indent)}end`);
    return parts.filter((p) => p !== '').join('\n');
  }
  /* c8 ignore next */
  throw new Error('unreachable: if chain');
}

/** `function a.b.c:d() ... end`; localName non-null ⇒ `local function f`.
 *  The name chain keeps its `:` ops — a `:` method name re-inserts `self`
 *  on re-parse, so params must NOT materialize it. */
function functionStatText(name: Expr | null, func: FunctionExpr, indent: number, localName?: string): string {
  const g = genericText(func.generics, func.genericPacks);
  const gp = g ? `<${g}>` : '';
  const head = name
    ? `function ${functionNameText(name)}${gp}(${paramList(func)})${retAnn(func)}`
    : `function ${localName ?? ''}${gp}(${paramList(func)})${retAnn(func)}`;
  const attrs = attributes(func.attributes);
  const prefix = localName === undefined ? attrs : `${attrs}local `;
  return `${prefix}${head}\n${blockText(func.body, indent + 1)}\n${pad(indent)}end`;
}

/** Rebuild a function-name chain with its `.`/`:` ops intact. */
function functionNameText(e: Expr): string {
  if (e.kind === 'IndexName') {
    const base = functionNameText(e.expr);
    return e.op === ':' ? `${base}:${e.index}` : `${base}.${e.index}`;
  }
  return expr(e, 0);
}

// ---------------------------------------------------------------------------
// Expressions (indent threads through for multi-line function literals)
// ---------------------------------------------------------------------------

function expr(e: Expr, indent: number, limit = 0): string {
  switch (e.kind) {
    case 'Group':
      return `(${expr(e.expr, indent)})`;
    case 'Nil':
      return 'nil';
    case 'Bool':
      return e.value ? 'true' : 'false';
    case 'Number':
      return e.raw;
    case 'Int':
      return e.raw;
    case 'String':
      return quoteString(e.value);
    case 'InterpString':
      return interpText(e, indent);
    case 'LocalExpr':
      return e.local.name;
    case 'Global':
      return e.name;
    case 'Vararg':
      return '...';
    case 'Call':
      return callText(e, indent);
    case 'IndexName':
      return `${postfixBase(e.expr)}.${e.index}`;
    case 'IndexExpr':
      return `${postfixBase(e.expr)}[${expr(e.index, indent)}]`;
    case 'Function':
      return functionText(e, indent);
    case 'Table':
      return tableText(e, indent);
    case 'Unary':
      return unaryText(e, indent, limit);
    case 'Binary':
      return binaryText(e, indent, limit);
    case 'TypeAssertion':
      return `${assertionOperand(e.expr, indent)} :: ${type(e.annotation)}`;
    case 'IfElse':
      return ifElseText(e, indent, limit);
    case 'Instantiate':
      return `${postfixBase(e.expr)}<<${e.typeArguments.map(typeOrPack).join(', ')}>>`;
  }
}

/** Call/index base: non-postfix shapes get parens (Group self-emits). */
function postfixBase(e: Expr): string {
  switch (e.kind) {
    case 'LocalExpr':
    case 'Global':
    case 'Vararg':
    case 'IndexName':
    case 'IndexExpr':
    case 'Call':
    case 'Group':
      return expr(e, 0);
    default:
      return `(${expr(e, 0)})`;
  }
}

/** Assertion operand: `::` binds at the simple-expr level. */
function assertionOperand(e: Expr, indent: number): string {
  switch (e.kind) {
    case 'LocalExpr':
    case 'Global':
    case 'Vararg':
    case 'IndexName':
    case 'IndexExpr':
    case 'Call':
    case 'TypeAssertion':
    case 'Group':
      return expr(e, indent);
    default:
      return `(${expr(e, indent)})`;
  }
}

function callText(e: Extract<Expr, { kind: 'Call' }>, indent: number): string {
  const funcText =
    e.func.kind === 'IndexName' && e.func.op === ':'
      ? `${postfixBase(e.func.expr)}:${e.func.index}`
      : postfixBase(e.func);
  if (e.tableCall && e.args.length === 1 && e.args[0]!.kind === 'Table') {
    return `${funcText}${tableText(e.args[0] as Extract<Expr, { kind: 'Table' }>, indent)}`;
  }
  return `${funcText}(${e.args.map((a) => expr(a, indent)).join(', ')})`;
}

function unaryText(e: Extract<Expr, { kind: 'Unary' }>, indent: number, limit: number): string {
  // the unary's operand is complete (nothing follows inside it); the
  // unary's own exposure to `followed` is handled by operand()
  const text = `${UNARY_OP_TEXT[e.op]}${expr(e.expr, indent, UNARY_PRIORITY)}`;
  return limit < UNARY_PRIORITY ? text : `(${text})`;
}

function binaryText(e: Extract<Expr, { kind: 'Binary' }>, indent: number, limit: number): string {
  const [l] = BINARY_PRIORITY[e.op];
  return l <= limit ? `(${binaryInner(e, indent, false)})` : binaryInner(e, indent, false);
}

/** The un-wrapped `left op right`. `followed` = an operator token will
 *  follow this text (outside any parens) — propagates to the RIGHT spine
 *  only (the left child is always followed by this node's own operator). */
function binaryInner(e: Extract<Expr, { kind: 'Binary' }>, indent: number, followed: boolean): string {
  const [l, r] = BINARY_PRIORITY[e.op];
  // `x :: T < y` is unparseable bare (parseSimpleType eats `<` after a
  // type as generic parameters) — parenthesize the Lt's left when its
  // tail is an assertion [parser.cpp parseSimpleType Less check]
  const ltGuard = e.op === 'CompareLt' && tailIsAssertion(e.left);
  const leftText = ltGuard ? `(${expr(e.left, indent)})` : operand(e.left, l, true, indent, true);
  return `${leftText} ${BINARY_OP_TEXT[e.op]} ${operand(e.right, r, false, indent, followed)}`;
}

/** Rightmost-printed path ends in a `::` assertion. */
function tailIsAssertion(e: Expr): boolean {
  if (e.kind === 'TypeAssertion') return true;
  if (e.kind === 'Binary') return tailIsAssertion(e.right);
  if (e.kind === 'Unary') return tailIsAssertion(e.expr);
  return false;
}

/** Rightmost-printed path of an expression: the only place a bare IfElse
 *  is legal (a branch would otherwise absorb whatever follows). */
function tailHasIfElse(e: Expr): boolean {
  switch (e.kind) {
    case 'IfElse':
      return true;
    case 'Binary':
      return tailHasIfElse(e.right);
    case 'Unary':
      return tailHasIfElse(e.expr);
    default:
      return false; // Group isolates; atoms cannot contain an IfElse
  }
}

/** Binary/unary/other child in operand position. `followed` = an
 *  operator token will follow this operand's text outside any parens. */
function operand(e: Expr, limit: number, isLeft: boolean, indent: number, followed: boolean): string {
  if (e.kind === 'IfElse') {
    // An if-else expr's branches absorb any following operator
    // (`if c then x else y .. b` puts `.. b` INSIDE the else-branch), so
    // it may print bare ONLY as the un-followed rightmost tail.
    return isLeft || followed ? `(${expr(e, indent)})` : expr(e, indent);
  }
  if (e.kind === 'Binary') {
    const [cl, cr] = BINARY_PRIORITY[e.op];
    // no parens when the child binds tighter, OR it is an equal-priority
    // LEFT-ASSOCIATIVE chain in the left slot (re-parse re-associates
    // identically — adding parens would inject a Group node and BREAK the
    // round-trip: `a - b - c` must not print as `(a - b) - c`). EXCEPTION:
    // when followed, a bare IfElse on the right spine defeats the
    // re-association identity (the branch absorbs what follows).
    const ok =
      (cl > limit || (cl === limit && isLeft && cl === cr)) &&
      !(followed && tailHasIfElse(e));
    return ok ? binaryInner(e, indent, followed) : `(${binaryInner(e, indent, false)})`;
  }
  if (e.kind === 'Unary' && followed && tailHasIfElse(e)) {
    return `(${expr(e, indent, limit)})`;
  }
  // Function literals and if-else exprs are valid BARE operands in the
  // un-followed tail (`f or function() end`, `a + if c then 1 else 2`):
  // parenthesizing them would inject a Group node and break the round-trip.
  // Postfix BASES still parenthesize them (postfixBase) — there the
  // original AST carries the Group already.
  return expr(e, indent, limit);
}

function ifElseText(e: Extract<Expr, { kind: 'IfElse' }>, _limit: number, indent: number): string {
  // NEVER self-parenthesize: if-else exprs are valid bare operands of
  // binary AND unary operators (`a + if c then 1 else 2`, `#if c then t
  // else u` — parseSimpleExpr) and bare nest unambiguously (an `else`
  // binds to the nearest unmatched `then`). Wrapping at nonzero limits
  // injects Group nodes on re-parse and breaks the round-trip — the
  // assertion/postfix contexts that DO need parens wrap explicitly
  // (assertionOperand / postfixBase).
  const cond = e.conditionLocal
    ? `local ${e.conditionLocal.name} = ${expr(e.condition, indent)}`
    : expr(e.condition, indent);
  return `if ${cond} then ${expr(e.trueExpr, indent)} else ${expr(e.falseExpr, indent)}`;
}

function functionText(f: FunctionExpr, indent: number): string {
  const g = genericText(f.generics, f.genericPacks);
  const head = `${attributes(f.attributes)}function${g ? `<${g}>` : ''}(${paramList(f)})${retAnn(f)}`;
  const body = blockText(f.body, indent + 1);
  return body === '' ? `${head} end` : `${head}\n${body}\n${pad(indent)}end`;
}

function tableText(e: Extract<Expr, { kind: 'Table' }>, indent: number): string {
  if (e.items.length === 0) return '{}';
  return `{ ${e.items.map((it) => tableItemText(it, indent)).join(', ')} }`;
}

function tableItemText(it: TableItem, indent: number): string {
  if (it.kind === 'List') return expr(it.value, indent);
  if (it.kind === 'Record') {
    const key = it.key;
    if (key && key.kind === 'String' && isIdentifierName(key.value)) {
      return `${key.value} = ${expr(it.value, indent)}`;
    }
    if (key) return `[${expr(key, indent)}] = ${expr(it.value, indent)}`;
    return expr(it.value, indent);
  }
  // General: [expr] = value
  return `[${expr(it.key!, indent)}] = ${expr(it.value, indent)}`;
}

function interpText(e: Extract<Expr, { kind: 'InterpString' }>, indent: number): string {
  let out = '`';
  for (let i = 0; i < e.expressions.length; i++) {
    out += escapeInterpPart(e.strings[i] ?? '');
    out += `{${expr(e.expressions[i]!, indent)}}`;
  }
  out += escapeInterpPart(e.strings[e.strings.length - 1] ?? '');
  return out + '`';
}

// ---------------------------------------------------------------------------
// Bindings / functions
// ---------------------------------------------------------------------------

function localDecl(v: Local): string {
  return v.annotation ? `${v.name}: ${type(v.annotation)}` : v.name;
}

function paramList(f: FunctionExpr): string {
  const parts: string[] = [];
  // `self` is NOT materialized: it exists only via a `:` method name
  // (FunctionExpr.self) and re-appears on re-parse of the `:` form.
  for (const a of f.args) parts.push(localDecl(a));
  if (f.vararg) {
    if (f.varargAnnotation) {
      // `...: T` — the annotation is the variadic pack's INNER type (the
      // `...` marker is already printed); a generic pack keeps its own
      // ellipsis (`...: T...`).
      const ann = f.varargAnnotation;
      parts.push(`...: ${ann.kind === 'TypePackVariadic' ? type(ann.type) : typePack(ann)}`);
    } else {
      parts.push('...');
    }
  }
  return parts.join(', ');
}

function retAnn(f: FunctionExpr): string {
  return f.returnAnnotation ? `: ${typePack(f.returnAnnotation)}` : '';
}

function attributes(attrs: readonly Attribute[]): string {
  return attrs.map((a) => `@${a.name} `).join('');
}

function genericText(generics: readonly GenericType[], packs: readonly GenericTypePack[]): string {
  if (generics.length === 0 && packs.length === 0) return '';
  const parts: string[] = [];
  for (const g of generics) {
    parts.push(g.defaultValue ? `${g.name} = ${type(g.defaultValue)}` : g.name);
  }
  for (const p of packs) {
    parts.push(p.defaultValue ? `${p.name}... = ${typePack(p.defaultValue)}` : `${p.name}...`);
  }
  return parts.join(', ');
}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

function type(t: Type): string {
  switch (t.kind) {
    case 'TypeReference': {
      const base = t.prefix ? `${t.prefix}.${t.name}` : t.name;
      return t.parameters ? `${base}<${t.parameters.map(typeOrPack).join(', ')}>` : base;
    }
    case 'TypeTable': {
      const parts: string[] = t.props.map((p) => `${isIdentifierName(p.name) ? p.name : `[${quoteString(p.name)}]`}: ${type(p.type)}`);
      if (t.indexer) parts.push(`[${type(t.indexer.indexType)}]: ${type(t.indexer.resultType)}`);
      return parts.length ? `{ ${parts.join(', ')} }` : '{}';
    }
    case 'FunctionType': {
      const g = genericText(t.generics, t.genericPacks);
      const args = t.argTypes.types.map((a, i) => {
        const n = t.argNames[i];
        return n ? `${isIdentifierName(n.name) ? n.name : `[${quoteString(n.name)}]`}: ${type(a)}` : type(a);
      });
      if (t.argTypes.tail) args.push(typePack(t.argTypes.tail));
      return `${attributes(t.attributes)}${g ? `<${g}>` : ''}(${args.join(', ')}) -> ${typePack(t.returnTypes)}`;
    }
    case 'TypeofType':
      return `typeof(${expr(t.expr, 0)})`;
    case 'TypeOptional':
      return `${typeOperand(t.type)}?`;
    case 'TypeUnion':
      return t.types.map(typeOperand).join(' | ');
    case 'TypeIntersection':
      return t.types.map(typeOperand).join(' & ');
    case 'TypeSingletonBool':
      return t.value ? 'true' : 'false';
    case 'TypeSingletonString':
      return quoteString(t.value);
    case 'TypeGroup':
      return `(${type(t.type)})`;
  }
}

/** Union/intersection member — parenthesize suffix-binding shapes. */
function typeOperand(t: Type): string {
  switch (t.kind) {
    case 'TypeUnion':
    case 'TypeIntersection':
    case 'TypeOptional':
    case 'FunctionType':
    case 'TypeofType':
      return `(${type(t)})`;
    default:
      return type(t);
  }
}

function typeOrPack(t: Type | TypePack): string {
  return (t as { kind: string }).kind.startsWith('TypePack')
    ? typePack(t as TypePack)
    : type(t as Type);
}

function typePack(p: TypePack): string {
  switch (p.kind) {
    case 'TypePackExplicit': {
      const parts = p.typeList.types.map((t) => type(t));
      if (p.typeList.tail) parts.push(typePack(p.typeList.tail));
      if (p.typeList.types.length === 1 && !p.typeList.tail) return parts[0]!;
      return `(${parts.join(', ')})`;
    }
    case 'TypePackVariadic':
      return `...${type(p.type)}`;
    case 'TypePackGeneric':
      return `${p.name}...`;
  }
}

// ---------------------------------------------------------------------------
// Escaping / name helpers
// ---------------------------------------------------------------------------

/** Byte-string → canonical double-quoted Luau literal. */
export function quoteString(value: string): string {
  let out = '"';
  for (let i = 0; i < value.length; i++) {
    const b = value.charCodeAt(i);
    if (b === 0x22) out += '\\"';
    else if (b === 0x5c) out += '\\\\';
    else if (b === 0x0a) out += '\\n';
    else if (b === 0x0d) out += '\\r';
    else if (b === 0x09) out += '\\t';
    else if (b >= 0x20 && b <= 0x7e) out += String.fromCharCode(b);
    else out += '\\' + String(b).padStart(3, '0');
  }
  return out + '"';
}

/** Interp-string literal part: ` { } must never appear raw. */
function escapeInterpPart(part: string): string {
  let out = '';
  for (let i = 0; i < part.length; i++) {
    const b = part.charCodeAt(i);
    if (b === 0x60 || b === 0x7b || b === 0x7d) out += '\\' + String(b).padStart(3, '0');
    else if (b === 0x5c) out += '\\\\';
    else if (b === 0x0a) out += '\\n';
    else if (b === 0x0d) out += '\\r';
    else if (b === 0x09) out += '\\t';
    else if (b >= 0x20 && b <= 0x7e) out += String.fromCharCode(b);
    else out += '\\' + String(b).padStart(3, '0');
  }
  return out;
}

const IDENT_RE = /^[A-Za-z_][A-Za-z0-9_]*$/;
const RESERVED = new Set([
  'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function',
  'if', 'in', 'local', 'nil', 'not', 'or', 'repeat', 'return', 'then',
  'true', 'until', 'while',
]);

function isIdentifierName(name: string): boolean {
  return IDENT_RE.test(name) && !RESERVED.has(name) && name !== '__proto__';
}

export { BINARY_PRIORITY, UNARY_PRIORITY, BINARY_OP_TEXT };
