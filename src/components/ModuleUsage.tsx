import { moduleUsage } from "@/lib/data";

export function ModuleUsage() {
  return (
    <div className="panel panel-hover p-5">
      <div className="mb-4 flex items-center justify-between">
        <h3 className="text-sm font-semibold text-ink">Module Usage</h3>
        <span className="text-xs text-ink-faint">Last 30 days</span>
      </div>
      <div className="space-y-4">
        {moduleUsage.map((m) => (
          <div key={m.name}>
            <div className="mb-1.5 flex items-center justify-between text-sm">
              <span className="font-medium text-ink">{m.name}</span>
              <span className="text-ink-dim">
                {m.percent}% <span className="text-ink-faint">· {m.sessions} sessions</span>
              </span>
            </div>
            <div className="h-2 w-full overflow-hidden rounded-full bg-white/[0.06]">
              <div
                className="h-full rounded-full transition-all duration-700"
                style={{
                  width: `${m.percent}%`,
                  background: `linear-gradient(90deg, ${m.color}99, ${m.color})`,
                  boxShadow: `0 0 12px 0 ${m.color}55`,
                }}
              />
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
