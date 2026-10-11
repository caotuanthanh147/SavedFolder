/**
 * M5 public API surface.
 *
 * compile:  M4 AST (obfuscator/src/ast.ts) → Proto tree
 * container: §5.9 pack/unpack (per-build opcode permutation + per-function
 *            AEAD const pools with chained keys, doc §10.2 item 6)
 * interpreter: reference executor for differential testing (D-M5-16)
 */
export { compileProgram, CompileError, LIMITS } from './compile';
export type { Const, Proto, InsnOut, UpvalDesc, CompileResult } from './compile';
export {
  pack, unpack, MAGIC, FORMAT_VERSION,
  encodeVarint, decodeVarint, crc32, randomBytes,
  hmacSha256Raw, hkdfSha256Sync, constKeyChainRoot, constKeyChainStep, CONST_KEY_INFO,
} from './container';
export type { Manifest, PackOptions, PackResult, UnpackOptions, LoadedContainer, LoadedProto } from './container';
export {
  makeStandardEnv as makeInterpreterEnvInternal,
  runContainer, LuaTable, LuaError, truthy, typeName, formatG14,
} from './interpreter';
export type { LuaValue, LuaClosure, HostFunction } from './interpreter';
export { Op, OPCODE_COUNT, OPCODE_UNIVERSE, OP_INFO, OP_NAMES, opcodeMapFromSeed, inverseMap, sha256Raw, toHex, encodeInsn, decodeInsn } from './opcode';
export type { Insn, Shape } from './opcode';
