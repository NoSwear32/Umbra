import { AppShell } from "@/components/AppShell";
import { HeartWorkspace } from "@/components/HeartWorkspace";
import { StatCard } from "@/components/StatCard";
import { heartHistory } from "@/lib/data";
import { HeartPulseIcon, ActivityIcon, ShieldIcon } from "@/components/icons";

const stateColor: Record<string, string> = {
  Stable: "text-emerald bg-emerald-soft border-emerald/30",
  Elevated: "text-gold bg-gold-soft border-gold/30",
};

export default function ManicHeartPage() {
  return (
    <AppShell title="Manic Heart" subtitle="Signal monitoring and pulse-driven insight for your body's baseline.">
      <div className="space-y-6">
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
          <StatCard
            label="Heart Signals"
            value="47"
            change="-4%"
            trend="down"
            icon={<HeartPulseIcon className="h-full w-full" />}
            accent="gold"
          />
          <StatCard
            label="Stability score"
            value="92%"
            change="+3%"
            trend="up"
            icon={<ShieldIcon className="h-full w-full" />}
            accent="emerald"
          />
          <StatCard
            label="Monitored hours"
            value="6h 20m"
            change="+11%"
            trend="up"
            icon={<ActivityIcon className="h-full w-full" />}
            accent="gold"
          />
        </div>

        <div className="grid grid-cols-1 gap-6 xl:grid-cols-3">
          <div className="xl:col-span-2">
            <HeartWorkspace />
          </div>

          <div className="panel panel-hover p-5">
            <h3 className="mb-4 text-sm font-semibold text-ink">History</h3>
            <div className="space-y-3">
              {heartHistory.map((h) => (
                <div
                  key={h.id}
                  className="flex items-center justify-between gap-3 rounded-xl border border-border-soft p-3 transition-colors hover:border-white/15 hover:bg-white/[0.02]"
                >
                  <div className="flex items-center gap-3">
                    <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-gold-soft text-gold">
                      <HeartPulseIcon className="h-4.5 w-4.5" />
                    </div>
                    <div className="min-w-0">
                      <div className="truncate text-sm font-medium text-ink">{h.label}</div>
                      <div className="text-xs text-ink-faint">{h.when}</div>
                    </div>
                  </div>
                  <span
                    className={`shrink-0 rounded-full border px-2.5 py-1 text-xs font-medium ${stateColor[h.state]}`}
                  >
                    {h.state}
                  </span>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </AppShell>
  );
}
