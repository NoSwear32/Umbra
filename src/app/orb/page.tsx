import { AppShell } from "@/components/AppShell";
import { OrbWorkspace } from "@/components/OrbWorkspace";
import { orbSessions } from "@/lib/data";
import { ClockIcon, OrbIcon } from "@/components/icons";
import { StatCard } from "@/components/StatCard";

export default function OrbPage() {
  return (
    <AppShell title="Orb" subtitle="Your focused workspace for deep, ambient, and recovery sessions.">
      <div className="space-y-6">
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
          <StatCard
            label="Sessions this week"
            value="18"
            change="+22%"
            trend="up"
            icon={<OrbIcon className="h-full w-full" />}
            accent="cyan"
          />
          <StatCard
            label="Focus time"
            value="11h 42m"
            change="+9%"
            trend="up"
            icon={<ClockIcon className="h-full w-full" />}
            accent="cyan"
          />
          <StatCard
            label="Avg. session length"
            value="38 min"
            change="+4%"
            trend="up"
            icon={<OrbIcon className="h-full w-full" />}
            accent="emerald"
          />
        </div>

        <div className="grid grid-cols-1 gap-6 xl:grid-cols-3">
          <div className="xl:col-span-2">
            <OrbWorkspace />
          </div>

          <div className="panel panel-hover p-5">
            <h3 className="mb-4 text-sm font-semibold text-ink">Recent Sessions</h3>
            <div className="space-y-3">
              {orbSessions.map((s) => (
                <div
                  key={s.id}
                  className="flex items-center justify-between gap-3 rounded-xl border border-border-soft p-3 transition-colors hover:border-white/15 hover:bg-white/[0.02]"
                >
                  <div className="flex items-center gap-3">
                    <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-cyan-soft text-cyan">
                      <OrbIcon className="h-4.5 w-4.5" />
                    </div>
                    <div className="min-w-0">
                      <div className="truncate text-sm font-medium text-ink">{s.label}</div>
                      <div className="text-xs text-ink-faint">{s.when}</div>
                    </div>
                  </div>
                  <span className="shrink-0 text-xs font-medium text-ink-dim">{s.duration}</span>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </AppShell>
  );
}
