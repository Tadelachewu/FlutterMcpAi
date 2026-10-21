// Regenerates test/fixtures/engine_parity.json from the original TypeScript engine (read-only import).
//
//   MCPAI_DIR=../McpAi node ../McpAi/node_modules/tsx/dist/cli.mjs tool/gen_engine_parity.mts test/fixtures/engine_parity.json
//
// The corpus is the spec's test vectors plus deterministic random expressions; the Dart test
// (test/engine_parity_test.dart) requires identical result strings or error codes.
import { writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

const root = resolve(process.env.MCPAI_DIR ?? "../McpAi");
const load = (rel: string) => import(pathToFileURL(resolve(root, rel)).href);
const { tryEvaluateExpression } = await load("src/lib/calculator/expression.ts");
const { Decimal } = await load("src/lib/calculator/decimal.ts");

// decimal.js tanh never finishes for |x| ≳ 1e6 (tanh(1e5) already takes ~0.3 s and returns exactly 1).
// Short-circuit it in this process only, to the value it returns anyway, so generation terminates.
const proto = Decimal.prototype;
const originalTanh = proto.tanh;
proto.tanh = proto.hyperbolicTangent = function (this: typeof Decimal.prototype) {
  if (this.abs().gt(1000)) return new Decimal(this.isNegative() ? -1 : 1);
  return originalTanh.call(this);
};

let seed = 20261020;
const rand = () => {
  seed = (seed * 1103515245 + 12345) & 0x7fffffff;
  return seed / 0x7fffffff;
};
const pick = <T,>(xs: T[]): T => xs[Math.floor(rand() * xs.length)]!;

const numbers = () =>
  pick([
    () => String(Math.floor(rand() * 20)),
    () => String(Math.floor(rand() * 1000)),
    () => (rand() * 10).toFixed(Math.floor(rand() * 4) + 1),
    () => `0.${Math.floor(rand() * 1000)}`,
    () => pick(["0.1", "0.2", "0.3", "0.5", "1.5", "2.5", "-2.5", "1e5", "1e-5", "3e10", "1e20", "1e-12", ".5"]),
    () => pick(["pi", "e", "pi/6", "pi/4", "pi/2", "2*pi"]),
    () => String(pick([0, 30, 45, 60, 90, 120, 135, 180, 270, 360, 720, -30, -90, 1e3])),
  ])();

const fns1 = ["sqrt", "cbrt", "abs", "floor", "ceil", "round", "sin", "cos", "tan", "asin", "acos", "atan",
  "sinh", "cosh", "tanh", "asinh", "acosh", "atanh", "ln", "log", "log2", "exp", "log10", "arctan"];
const fns2 = ["root", "nCr", "nPr", "log"];

function expr(depth: number): string {
  if (depth <= 0 || rand() < 0.3) return numbers();
  const r = rand();
  if (r < 0.35) return `${expr(depth - 1)} ${pick(["+", "-", "*", "/", "%", "^"])} ${expr(depth - 1)}`;
  if (r < 0.65) return `${pick(fns1)}(${expr(depth - 1)})`;
  if (r < 0.75) return `${pick(fns2)}(${expr(depth - 1)}, ${expr(depth - 1)})`;
  if (r < 0.85) return `(${expr(depth - 1)})`;
  if (r < 0.92) return `-${expr(depth - 1)}`;
  return `${String(Math.floor(rand() * 12))}!`;
}

const fixed = [
  "125 * 24", "(100 + 50) * 4", "0.1 + 0.2", "1/3", "2 ^ 3 ^ 2", "-2 ^ 2", "(-2) ^ 2", "-7 % 3", "sqrt(2)",
  "10 ^ 400", "2 ^ 100000", "sin(30)", "cos(60)", "tan(45)", "sin(270)", "asin(0.5)", "atan(1)",
  "sin(30)^2+cos(30)^2", "sin(pi)", "cos(pi)", "sin(pi/6)", "tanh(1)", "pi", "e", "ln(e)", "log(1000)",
  "log10(0.01)", "log(8,2)", "log2(1024)", "5!", "0!", "-3!", "2^3!", "(2+3)!", "3!!", "nCr(52,5)", "nPr(5,2)",
  "cbrt(-27)", "root(16,4)", "root(-8,3)", "abs(-4.5)", "floor(-2.5)", "ceil(2.1)", "tan(90)", "asin(2)", "ln(0)",
  "log(8,1)", "2.5!", "171!", "exp(1000)", "root(-16,2)", "nCr(2,5)", "sqrt(-4)", "1,000", "2(3)", "2pi", "sin 30",
  "(2+3", "2+3)", "()", "1.2.3", "5e", "alert(1)", "constructor", "2 + x", "170!", "exp(690)", "exp(-700)",
  "2^0.5", "10^25", "10^-8", "1e-301", "0^0", "0.5^9999.5", "1.0000001^10000", "nCr(1000,500)", "nPr(100,50)",
  "sin(1e15)", "tan(pi/2)", "cos(pi/2)", "acos(-1)", "atanh(0.999999)", "asinh(-1e-20)", "ln(1.0000000000000001)",
  "log(1e-300)", "sinh(700)", "cosh(-700)", "tanh(-60)", "exp(1e-30)", "root(2, 0.5)", "root(27, -3)",
  "1e300 * 10", "1e-200 * 1e-200", "123456789012345678901234567890 + 1", "7.5 % 2", "-7.5 % -2",
];

type Case = { expr: string; unit: "degrees" | "radians"; result?: string; code?: string };
const cases: Case[] = [];
const add = (e: string, unit: "degrees" | "radians") => {
  const out = tryEvaluateExpression(e, { angleUnit: unit });
  cases.push(out.ok ? { expr: e, unit, result: out.value.result } : { expr: e, unit, code: out.error.code });
};
for (const e of fixed) for (const u of ["degrees", "radians"] as const) add(e, u);
for (let i = 0; i < 3000; i++) add(expr(3), rand() < 0.5 ? "degrees" : "radians");

writeFileSync(process.argv[2] ?? "test/fixtures/engine_parity.json", JSON.stringify(cases).replace(/\},\{/g, "},\n{"));
const ok = cases.filter((c) => c.result !== undefined).length;
console.log(`cases=${cases.length} ok=${ok} errors=${cases.length - ok}`);
