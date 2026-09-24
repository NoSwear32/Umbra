import { ReactNode } from "react";
import { TrendDownIcon, TrendUpIcon } from "./icons";

export function StatCard({
  label,
  value,
  change,
  trend = "up",
  icon,
  accent = "cyan",
}: {
  label: string;
  value: string;
  change: string;
  trend?: "up" | "down";
  icon: ReactNode;
  accent?: "cyan" | "emerald" | "gold";
}) {
  const accentMap = {
    cyan: "from-cyan/15 text-cyan border-cyan/25",
    emerald: "from-emerald/15 text-emerald border-emerald/25",
    gold: "from-gold/15 text-gold border-gold/25",
  } as const;

  return (
    <div className="panel panel-hover relative overflow-hidden p-5">
      <div
        className={`pointer-events-none absolute -right-8 -top-8 h-32 w-32 rounded-full bg-gradient-to-br ${accentMap[accent]} to-transparent blur-2xl opacity-60`}
      />
      <div className="relative flex items-start justify-between">
        <div
          className={`flex h-10 w-10 items-center justify-center rounded-xl border bg-gradient-to-br ${accentMap[accent]} to-transparent`}
        >
          <span className="h-5 w-5">{icon}</span>
        </div>
        <div
          className={`flex items-center gap-1 rounded-full px-2 py-1 text-xs font-medium ${
            trend === "up" ? "text-emerald bg-emerald-soft" : "text-gold bg-gold-soft"
          }`}
        >
          {trend === "up" ? (
            <TrendUpIcon className="h-3.5 w-3.5" />
          ) : (
            <TrendDownIcon className="h-3.5 w-3.5" />
          )}
          {change}
        </div>
      </div>
      <div className="relative mt-4">
        <div className="text-2xl font-bold tracking-tight text-ink sm:text-3xl">{value}</div>
        <div className="mt-1 text-sm text-ink-dim">{label}</div>
      </div>
    </div>
  );
}
