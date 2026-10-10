"use client";

// Hand-rolled SVG chart primitives (M11 s3) — zero chart dependencies.
// All sizing is viewBox-relative so charts stay responsive; colors use the
// emerald/teal/amber/rose/stone palette (project rule: no blue/indigo).

import { useState } from "react";

export interface ChartPoint {
  label: string;
  value: number;
  sublabel?: string;
}

/* ---------- Sparkline (stat cards) ---------- */

export function Sparkline({
  values,
  className = "",
  stroke = "var(--color-chart-2)",
  fill = "var(--color-chart-2)",
}: {
  values: number[];
  className?: string;
  stroke?: string;
  fill?: string;
}): React.JSX.Element | null {
  if (values.length < 2) return null;
  const w = 120;
  const h = 34;
  const max = Math.max(...values, 1);
  const step = w / (values.length - 1);
  const pts = values.map((v, i) => `${(i * step).toFixed(1)},${(h - 3 - (v / max) * (h - 8)).toFixed(1)}`);
  const line = `M ${pts.join(" L ")}`;
  const area = `${line} L ${w},${h} L 0,${h} Z`;
  const id = `spark-${stroke.replace(/[^a-z0-9]/gi, "")}`;
  return (
    <svg viewBox={`0 0 ${w} ${h}`} className={`h-8 w-full ${className}`} preserveAspectRatio="none" aria-hidden>
      <defs>
        <linearGradient id={id} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={fill} stopOpacity="0.28" />
          <stop offset="100%" stopColor={fill} stopOpacity="0.02" />
        </linearGradient>
      </defs>
      <path d={area} fill={`url(#${id})`} stroke="none" />
      <path d={line} fill="none" stroke={stroke} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

/* ---------- Stacked activity bar chart (audit actions/day) ---------- */

const BAR_PALETTE = ["var(--color-chart-2)", "var(--color-chart-1)", "var(--color-chart-4)", "var(--color-chart-5)"];

export function ActivityBarChart({
  data,
  series,
}: {
  data: ChartPoint[];
  series: { name: string; values: number[] }[];
}): React.JSX.Element {
  const [hover, setHover] = useState<number | null>(null);
  const w = 720;
  const h = 200;
  const padL = 34;
  const padB = 26;
  const padT = 10;
  const max = Math.max(1, ...data.map((d) => d.value));
  const niceMax = Math.ceil(max / 5) * 5 || 5;
  const gridLines = 4;
  const barW = Math.max(6, (w - padL - 8) / data.length - 4);
  const x = (i: number) => padL + i * ((w - padL - 8) / data.length) + 2;

  return (
    <div className="relative">
      <svg viewBox={`0 0 ${w} ${h}`} className="w-full" role="img" aria-label="audit actions per day">
        {/* grid */}
        {Array.from({ length: gridLines + 1 }).map((_, i) => {
          const y = padT + (i * (h - padT - padB)) / gridLines;
          return (
            <g key={i}>
              <line x1={padL} x2={w - 4} y1={y} y2={y} stroke="var(--border)" strokeWidth="1" strokeDasharray={i === gridLines ? "0" : "3 4"} />
              <text x={padL - 6} y={y + 3.5} textAnchor="end" fontSize="9" fill="var(--muted-foreground)" className="tabular-nums">
                {Math.round(niceMax - (i * niceMax) / gridLines)}
              </text>
            </g>
          );
        })}
        {/* bars (stacked) */}
        {data.map((d, i) => {
          const total = series.reduce((acc, s) => acc + (s.values[i] ?? 0), 0);
          if (total === 0) {
            return <rect key={i} x={x(i)} y={h - padB} width={barW} height={2} rx={1} fill="var(--muted)" opacity={0.5} />;
          }
          let acc = 0;
          return (
            <g
              key={i}
              onMouseEnter={() => setHover(i)}
              onMouseLeave={() => setHover(null)}
            >
              <rect x={x(i) - 3} y={padT} width={barW + 6} height={h - padT - padB} fill="transparent" />
              {series.map((s, si) => {
                const v = s.values[i] ?? 0;
                if (v === 0) return null;
                const bh = (v / niceMax) * (h - padT - padB);
                const y = h - padB - acc - bh;
                acc += bh;
                return (
                  <rect
                    key={si}
                    x={x(i)}
                    y={y}
                    width={barW}
                    height={Math.max(2, bh)}
                    rx={2}
                    fill={BAR_PALETTE[si % BAR_PALETTE.length]}
                    opacity={hover === null || hover === i ? 1 : 0.35}
                    className="transition-opacity"
                  />
                );
              })}
            </g>
          );
        })}
        {/* x labels */}
        {data.map((d, i) => (
          <text
            key={i}
            x={x(i) + barW / 2}
            y={h - padB + 14}
            textAnchor="middle"
            fontSize="9"
            fill={hover === i ? "var(--foreground)" : "var(--muted-foreground)"}
          >
            {d.label}
          </text>
        ))}
      </svg>
      {/* hover tooltip */}
      {hover !== null && data[hover] && (
        <div
          className="pointer-events-none absolute top-1 z-10 min-w-36 rounded-md border bg-popover px-2.5 py-2 text-xs shadow-lg"
          style={{ left: `${(hover + 0.5) * (100 / data.length)}%`, transform: "translateX(-50%)" }}
        >
          <p className="mb-1 font-medium">{data[hover].sublabel ?? data[hover].label}</p>
          {series.map((s, i) =>
            s.values[hover] ? (
              <p key={i} className="flex items-center justify-between gap-3 text-muted-foreground">
                <span className="flex items-center gap-1.5">
                  <span className="inline-block h-2 w-2 rounded-sm" style={{ background: BAR_PALETTE[i % BAR_PALETTE.length] }} />
                  {s.name}
                </span>
                <span className="font-mono tabular-nums text-foreground">{s.values[hover]}</span>
              </p>
            ) : null,
          )}
        </div>
      )}
    </div>
  );
}

/* ---------- Donut chart (key tier distribution) ---------- */

const DONUT_COLORS: Record<string, string> = {
  paid: "var(--color-chart-2)",
  lifetime: "#0d9488",
  free: "var(--color-chart-4)",
  reseller: "var(--color-chart-5)",
  other: "var(--muted-foreground)",
};

export function DonutChart({
  segments,
  centerLabel,
  centerValue,
}: {
  segments: { name: string; value: number }[];
  centerLabel: string;
  centerValue: string | number;
}): React.JSX.Element {
  const total = segments.reduce((a, s) => a + s.value, 0);
  const size = 150;
  const r = 58;
  const c = 2 * Math.PI * r;
  let offset = 0;
  return (
    <div className="flex flex-wrap items-center justify-center gap-6">
      <div className="relative" style={{ width: size, height: size }}>
        <svg viewBox={`0 0 ${size} ${size}`} className="-rotate-90" role="img" aria-label={`${centerLabel} distribution`}>
          <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--muted)" strokeWidth="16" />
          {total > 0 &&
            segments.map((s, i) => {
              const frac = s.value / total;
              const el = (
                <circle
                  key={i}
                  cx={size / 2}
                  cy={size / 2}
                  r={r}
                  fill="none"
                  stroke={DONUT_COLORS[s.name] ?? DONUT_COLORS.other}
                  strokeWidth="16"
                  strokeDasharray={`${frac * c} ${c}`}
                  strokeDashoffset={-offset * c}
                  strokeLinecap="butt"
                  className="transition-all duration-500"
                />
              );
              offset += frac;
              return el;
            })}
        </svg>
        <div className="absolute inset-0 flex flex-col items-center justify-center">
          <p className="text-2xl font-semibold tabular-nums leading-none">{centerValue}</p>
          <p className="mt-1 text-[10px] uppercase tracking-wider text-muted-foreground">{centerLabel}</p>
        </div>
      </div>
      <ul className="space-y-1.5">
        {segments.map((s) => (
          <li key={s.name} className="flex items-center gap-2 text-sm">
            <span className="inline-block h-2.5 w-2.5 rounded-sm" style={{ background: DONUT_COLORS[s.name] ?? DONUT_COLORS.other }} />
            <span className="capitalize">{s.name}</span>
            <span className="font-mono text-xs tabular-nums text-muted-foreground">
              {s.value} · {total === 0 ? 0 : Math.round((s.value / total) * 100)}%
            </span>
          </li>
        ))}
      </ul>
    </div>
  );
}

/* ---------- Horizontal meter (protocol / health rows) ---------- */

export function Meter({ value, max, className = "" }: { value: number; max: number; className?: string }): React.JSX.Element {
  const pct = max <= 0 ? 0 : Math.min(100, (value / max) * 100);
  return (
    <div className={`h-1.5 w-full overflow-hidden rounded-full bg-muted ${className}`}>
      <div
        className="h-full rounded-full bg-gradient-to-r from-emerald-500 to-teal-500 transition-all duration-500"
        style={{ width: `${pct}%` }}
      />
    </div>
  );
}
