/**
 * AST node types for the strict Luau parser.
 *
 * Node set and field shapes derive from the reference implementation
 * (luau-lang/luau Ast/include/Luau/Ast.h @ master, fetched 2026-10-10; MIT —
 * used as a SPEC, no code copied) with these deliberate divergences, each
 * safe for an obfuscator front end and documented in DECISIONS-M4:
 *
 *  1. Discriminated unions on a `kind` literal instead of C++ class RTTI.
 *  2. NO Error nodes (AstExprError / AstStatError / AstTypeError): this
 *     parser is strict fail-loud with a single error — there is never a
 *     recovered tree containing error nodes.
 *  3. Syntax-shape flags that only affect re-printing canonically are
 *     dropped (hasDo/hasEnd/hasThen/hasElse, keyword locations). The printer
 *     always emits the canonical form (`do ... end`, `end`, `else`), so
 *     parse → print → parse yields identical ASTs without them.
 *  4. `T?` is a wrapper node `TypeOptional { type }` instead of the
 *     reference's union-marker `AstTypeOptional` (same accepted grammar:
 *     `T??` = Optional{Optional{T}}, `T? | U` = Union{Optional{T}, U}).
 *  5. Kind strings equal the TS interface names where possible; where the
 *     reference overloads a name (AstTypeFunction vs AstStatTypeFunction)
 *     the annotation kind is 'FunctionType' and the statement kind is
 *     'TypeFunction' — registries must stay disjoint (tested).
 *  6. Number literals keep their raw source text (`raw`) so the printer can
 *     reproduce them byte-exactly; `value` is the parsed double.
 *  7. String values are byte-strings (latin1 model, see lexer.ts).
 *  8. `declare` statements (DeclareGlobal/DeclareFunction/DeclareClass/
 *     DeclareExternType) are not in the node set yet — executor-target
 *     scripts do not use them; the parser rejects them with a clear error
 *     (documented limitation, see DECISIONS-M4 D-M4-7).
 *  9. `Local` is an identity object (unique per binding site); scope
 *     resolution binds Name references to it (semantic analysis, item 2).
 */

import type { Location } from './tokens';

export interface NodeBase {
  readonly location: Location;
}

// ---------------------------------------------------------------------------
// Locals and attributes
// ---------------------------------------------------------------------------

/** A binding site. Identity is significant: two locals named `x` in
 *  different scopes are different objects. */
export interface Local extends NodeBase {
  readonly kind: 'Local';
  readonly name: string;
  readonly annotation?: Type;
}

/** `@native`, `@checked`, ... (reference: AstAttr) */
export interface Attribute extends NodeBase {
  readonly kind: 'Attribute';
  readonly name: string;
}

// ---------------------------------------------------------------------------
// Expressions
// ---------------------------------------------------------------------------

export interface GroupExpr extends NodeBase {
  readonly kind: 'Group';
  readonly expr: Expr;
}

export interface NilExpr extends NodeBase {
  readonly kind: 'Nil';
}

export interface BoolExpr extends NodeBase {
  readonly kind: 'Bool';
  readonly value: boolean;
}

/** Double literal (reference: AstExprConstantNumber). */
export interface NumberExpr extends NodeBase {
  readonly kind: 'Number';
  readonly value: number;
  /** Raw source text (kept for byte-exact re-printing). */
  readonly raw: string;
}

/** Int64 literal `42i` / `0xFFi` (reference: AstExprConstantInteger). */
export interface IntExpr extends NodeBase {
  readonly kind: 'Int';
  readonly value: bigint;
  readonly raw: string;
}

/** Quoted / long / unquoted(table key) string (value = byte-string). */
export interface StringExpr extends NodeBase {
  readonly kind: 'String';
  readonly value: string;
}

/** `` `a{x}b{y}c` `` — strings.length === expressions.length + 1. */
export interface InterpStringExpr extends NodeBase {
  readonly kind: 'InterpString';
  readonly strings: readonly string[];
  readonly expressions: readonly Expr[];
}

export interface LocalExpr extends NodeBase {
  readonly kind: 'LocalExpr';
  readonly local: Local;
}

export interface GlobalExpr extends NodeBase {
  readonly kind: 'Global';
  readonly name: string;
}

export interface VarargExpr extends NodeBase {
  readonly kind: 'Vararg';
}

export interface CallExpr extends NodeBase {
  readonly kind: 'Call';
  readonly func: Expr;
  readonly args: readonly Expr[];
  /** true for `a:b()` — func is the IndexName with `:` op, arg `self` inserted. */
  readonly self: boolean;
  /** true for `f{...}` single table-argument call syntax. */
  readonly tableCall: boolean;
}

export interface IndexNameExpr extends NodeBase {
  readonly kind: 'IndexName';
  readonly expr: Expr;
  readonly index: string;
  /** `.` or `:` */
  readonly op: '.' | ':';
}

export interface IndexExpr extends NodeBase {
  readonly kind: 'IndexExpr';
  readonly expr: Expr;
  readonly index: Expr;
}

export interface FunctionExpr extends NodeBase {
  readonly kind: 'Function';
  readonly attributes: readonly Attribute[];
  readonly generics: readonly GenericType[];
  readonly genericPacks: readonly GenericTypePack[];
  readonly self: Local | null;
  readonly args: readonly Local[];
  readonly vararg: boolean;
  readonly varargAnnotation?: TypePack;
  readonly returnAnnotation?: TypePack;
  readonly body: Block;
  /** Name as written after `function` for stack-trace fidelity (may be null
   *  for anonymous functions; statements know their own names). */
  readonly debugname: string | null;
}

export type TableItemKind = 'List' | 'Record' | 'General';

export interface TableItem {
  readonly kind: TableItemKind;
  /** null for List items; StringExpr for Record; arbitrary for General. */
  readonly key: Expr | null;
  readonly value: Expr;
}

export interface TableExpr extends NodeBase {
  readonly kind: 'Table';
  readonly items: readonly TableItem[];
}

export type UnaryOp = 'Not' | 'Minus' | 'Len';

export interface UnaryExpr extends NodeBase {
  readonly kind: 'Unary';
  readonly op: UnaryOp;
  readonly expr: Expr;
}

export type BinaryOp =
  | 'Add' | 'Sub' | 'Mul' | 'Div' | 'FloorDiv' | 'Mod' | 'Pow' | 'Concat'
  | 'CompareEq' | 'CompareNe' | 'CompareLt' | 'CompareLe' | 'CompareGt' | 'CompareGe'
  | 'And' | 'Or';

export interface BinaryExpr extends NodeBase {
  readonly kind: 'Binary';
  readonly op: BinaryOp;
  readonly left: Expr;
  readonly right: Expr;
}

/** `expr :: annotation` */
export interface TypeAssertionExpr extends NodeBase {
  readonly kind: 'TypeAssertion';
  readonly expr: Expr;
  readonly annotation: Type;
}

/** `if c then a else b` (and the `if local x = c then a else b` binding form). */
export interface IfElseExpr extends NodeBase {
  readonly kind: 'IfElse';
  readonly condition: Expr;
  readonly trueExpr: Expr;
  readonly falseExpr: Expr;
  /** Bound when the condition declares a local (`if local x = ...`). */
  readonly conditionLocal?: Local;
}

/** `f<<T>>` explicit instantiation (rare; parser support planned with the
 *  type-argument grammar). */
export interface InstantiateExpr extends NodeBase {
  readonly kind: 'Instantiate';
  readonly expr: Expr;
  readonly typeArguments: readonly (Type | TypePack)[];
}

export type Expr =
  | GroupExpr
  | NilExpr
  | BoolExpr
  | NumberExpr
  | IntExpr
  | StringExpr
  | InterpStringExpr
  | LocalExpr
  | GlobalExpr
  | VarargExpr
  | CallExpr
  | IndexNameExpr
  | IndexExpr
  | FunctionExpr
  | TableExpr
  | UnaryExpr
  | BinaryExpr
  | TypeAssertionExpr
  | IfElseExpr
  | InstantiateExpr;

// ---------------------------------------------------------------------------
// Statements
// ---------------------------------------------------------------------------

export interface Block extends NodeBase {
  readonly kind: 'Block';
  readonly body: readonly Stat[];
}

export interface IfStat extends NodeBase {
  readonly kind: 'If';
  readonly condition: Expr;
  readonly thenbody: Block;
  /** Block for `else`, IfStat for `elseif` chains, null otherwise. */
  readonly elsebody: Block | IfStat | null;
}

export interface WhileStat extends NodeBase {
  readonly kind: 'While';
  readonly condition: Expr;
  readonly body: Block;
}

export interface RepeatStat extends NodeBase {
  readonly kind: 'Repeat';
  /** Scope note: `until` sees the body's locals (Lua 5.1 manual §2.4.4). */
  readonly condition: Expr;
  readonly body: Block;
}

export interface BreakStat extends NodeBase {
  readonly kind: 'Break';
}

export interface ContinueStat extends NodeBase {
  readonly kind: 'Continue';
}

export interface ReturnStat extends NodeBase {
  readonly kind: 'Return';
  readonly list: readonly Expr[];
}

export interface ExprStat extends NodeBase {
  readonly kind: 'ExprStat';
  readonly expr: Expr;
}

export interface LocalStat extends NodeBase {
  readonly kind: 'Local';
  readonly vars: readonly Local[];
  readonly values: readonly Expr[];
}

export interface ForStat extends NodeBase {
  readonly kind: 'For';
  readonly var: Local;
  readonly from: Expr;
  readonly to: Expr;
  readonly step: Expr | null;
  readonly body: Block;
}

export interface ForInStat extends NodeBase {
  readonly kind: 'ForIn';
  readonly vars: readonly Local[];
  readonly values: readonly Expr[];
  readonly body: Block;
}

export interface AssignStat extends NodeBase {
  readonly kind: 'Assign';
  readonly vars: readonly Expr[];
  readonly values: readonly Expr[];
}

export interface CompoundAssignStat extends NodeBase {
  readonly kind: 'CompoundAssign';
  readonly op: BinaryOp;
  readonly var: Expr;
  readonly value: Expr;
}

/** `function a.b.c:d() ... end` */
export interface FunctionStat extends NodeBase {
  readonly kind: 'FunctionStat';
  readonly name: Expr; // IndexName chain, possibly with `:` op
  readonly func: FunctionExpr;
}

/** `local function f() ... end` */
export interface LocalFunctionStat extends NodeBase {
  readonly kind: 'LocalFunction';
  readonly name: Local;
  readonly func: FunctionExpr;
}

/** `type X = ...` / `export type X = ...` */
export interface TypeAliasStat extends NodeBase {
  readonly kind: 'TypeAlias';
  readonly name: string;
  readonly nameLocation: Location;
  readonly generics: readonly GenericType[];
  readonly genericPacks: readonly GenericTypePack[];
  readonly type: Type;
  readonly exported: boolean;
}

/** `type X = function() ... end` (type function, Luau master). */
export interface TypeFunctionStat extends NodeBase {
  readonly kind: 'TypeFunction';
  readonly name: string;
  readonly nameLocation: Location;
  readonly body: FunctionExpr;
  readonly exported: boolean;
}

export type Stat =
  | Block
  | IfStat
  | WhileStat
  | RepeatStat
  | BreakStat
  | ContinueStat
  | ReturnStat
  | ExprStat
  | LocalStat
  | ForStat
  | ForInStat
  | AssignStat
  | CompoundAssignStat
  | FunctionStat
  | LocalFunctionStat
  | TypeAliasStat
  | TypeFunctionStat;

/** Root of a parsed file. */
export interface Chunk extends NodeBase {
  readonly kind: 'Chunk';
  readonly block: Block;
}

// ---------------------------------------------------------------------------
// Types (annotations — parsed, never checked)
// ---------------------------------------------------------------------------

export interface GenericType {
  readonly name: string;
  readonly location: Location;
  /** `T = DefaultType` default value. */
  readonly defaultValue?: Type;
}

export interface GenericTypePack {
  readonly name: string;
  readonly location: Location;
  /** `P = ...T` default pack value (master generics-with-defaults). */
  readonly defaultValue?: TypePack;
}

/** Reference: AstTypeList — head types plus an optional tail pack. */
export interface TypeList {
  readonly types: readonly Type[];
  readonly tail: TypePack | null;
}

/** `Name` / `Prefix.Name` / `Name<Args>` */
export interface ReferenceType extends NodeBase {
  readonly kind: 'TypeReference';
  readonly prefix: string | null;
  readonly name: string;
  readonly parameters: readonly (Type | TypePack)[] | null;
}

export interface TableProp {
  readonly name: string;
  readonly location: Location;
  readonly type: Type;
}

export interface TableIndexer {
  readonly indexType: Type;
  readonly resultType: Type;
  readonly location: Location;
}

/** `{ x: T, [K]: V }` — {T} arrays desugar to `{[number]: T}`. isExact is
 *  reserved for the exact-table `{| |}` syntax: REMOVED from reference
 *  master (replaced by default-exact direction under a Debug flag, off in
 *  release) — always false here (D-M4-16). */
export interface TableType extends NodeBase {
  readonly kind: 'TypeTable';
  readonly props: readonly TableProp[];
  readonly indexer: TableIndexer | null;
  readonly isExact: boolean;
}

export interface ArgumentName {
  readonly name: string;
  readonly location: Location;
}

/** `(a: T) -> R` */
export interface FunctionType extends NodeBase {
  readonly kind: 'FunctionType';
  readonly attributes: readonly Attribute[];
  readonly generics: readonly GenericType[];
  readonly genericPacks: readonly GenericTypePack[];
  readonly argTypes: TypeList;
  readonly argNames: readonly (ArgumentName | null)[];
  readonly returnTypes: TypePack;
}

/** `typeof(expr)` */
export interface TypeofType extends NodeBase {
  readonly kind: 'TypeofType';
  readonly expr: Expr;
}

/** `T?` (see header note 4). */
export interface OptionalType extends NodeBase {
  readonly kind: 'TypeOptional';
  readonly type: Type;
}

/** `A | B` */
export interface UnionType extends NodeBase {
  readonly kind: 'TypeUnion';
  readonly types: readonly Type[];
}

/** `A & B` */
export interface IntersectionType extends NodeBase {
  readonly kind: 'TypeIntersection';
  readonly types: readonly Type[];
}

/** `true` / `false` singleton type. */
export interface SingletonBoolType extends NodeBase {
  readonly kind: 'TypeSingletonBool';
  readonly value: boolean;
}

/** `"lit"` singleton type (value = byte-string). */
export interface SingletonStringType extends NodeBase {
  readonly kind: 'TypeSingletonString';
  readonly value: string;
}

/** `(T)` */
export interface GroupType extends NodeBase {
  readonly kind: 'TypeGroup';
  readonly type: Type;
}

export type Type =
  | ReferenceType
  | TableType
  | FunctionType
  | TypeofType
  | OptionalType
  | UnionType
  | IntersectionType
  | SingletonBoolType
  | SingletonStringType
  | GroupType;

// ---------------------------------------------------------------------------
// Type packs
// ---------------------------------------------------------------------------

/** `(A, B, ...C)` */
export interface ExplicitTypePack extends NodeBase {
  readonly kind: 'TypePackExplicit';
  readonly typeList: TypeList;
}

/** `...T` */
export interface VariadicTypePack extends NodeBase {
  readonly kind: 'TypePackVariadic';
  readonly type: Type;
}

/** `...T` generic pack name (as written: `Ts` in `<T..., Ts...>` hmm — the
 *  generic pack name includes no dots; the parser adds them contextually). */
export interface GenericTypePackNode extends NodeBase {
  readonly kind: 'TypePackGeneric';
  readonly name: string;
}

export type TypePack =
  | ExplicitTypePack
  | VariadicTypePack
  | GenericTypePackNode;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

export const EXPR_KINDS = [
  'Group', 'Nil', 'Bool', 'Number', 'Int', 'String', 'InterpString',
  'LocalExpr', 'Global', 'Vararg', 'Call', 'IndexName', 'IndexExpr',
  'Function', 'Table', 'Unary', 'Binary', 'TypeAssertion', 'IfElse',
  'Instantiate',
] as const satisfies readonly (Expr['kind'])[];

export const STAT_KINDS = [
  'Block', 'If', 'While', 'Repeat', 'Break', 'Continue', 'Return',
  'ExprStat', 'Local', 'For', 'ForIn', 'Assign', 'CompoundAssign',
  'FunctionStat', 'LocalFunction', 'TypeAlias', 'TypeFunction',
] as const satisfies readonly (Stat['kind'])[];

export const TYPE_KINDS = [
  'TypeReference', 'TypeTable', 'FunctionType', 'TypeofType', 'TypeOptional',
  'TypeUnion', 'TypeIntersection', 'TypeSingletonBool', 'TypeSingletonString',
  'TypeGroup',
] as const satisfies readonly (Type['kind'])[];

export const TYPE_PACK_KINDS = [
  'TypePackExplicit', 'TypePackVariadic', 'TypePackGeneric',
] as const satisfies readonly (TypePack['kind'])[];

/** Discriminator check used by the parser and tests. */
export function isExpr(node: Expr | Stat | Type): node is Expr {
  return (EXPR_KINDS as readonly string[]).includes(node.kind);
}
export function isStat(node: Expr | Stat | Type): node is Stat {
  return (STAT_KINDS as readonly string[]).includes(node.kind);
}
export function isType(node: Expr | Stat | Type): node is Type {
  return (TYPE_KINDS as readonly string[]).includes(node.kind);
}
