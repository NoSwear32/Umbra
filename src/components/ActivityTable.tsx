import { activityRows } from "@/lib/data";
import { StatusPill } from "./StatusPill";
import { OrbIcon, SageIcon, HeartPulseIcon, DotsIcon } from "./icons";

const moduleIcon = {
  Orb: OrbIcon,
  Sage: SageIcon,
  "Manic Heart": HeartPulseIcon,
};

const moduleColor = {
  Orb: "text-cyan bg-cyan-soft",
  Sage: "text-emerald bg-emerald-soft",
  "Manic Heart": "text-gold bg-gold-soft",
};

export function ActivityTable() {
  return (
    <div className="panel p-5">
      <div className="mb-4 flex items-center justify-between">
        <div>
          <h3 className="text-sm font-semibold text-ink">Recent Activity</h3>
          <p className="text-xs text-ink-faint">Total {activityRows.length} events this week</p>
        </div>
        <button className="text-xs font-medium text-cyan hover:underline">See all</button>
      </div>

      {/* Desktop table */}
      <div className="hidden overflow-x-auto md:block">
        <table className="w-full text-left text-sm">
          <thead>
            <tr className="border-b border-border text-xs uppercase tracking-wide text-ink-faint">
              <th className="pb-3 font-medium">Activity</th>
              <th className="pb-3 font-medium">Module</th>
              <th className="pb-3 font-medium">Status</th>
              <th className="pb-3 font-medium">Date</th>
              <th className="pb-3 pr-2 text-right font-medium">Details</th>
            </tr>
          </thead>
          <tbody>
            {activityRows.map((row) => {
              const Icon = moduleIcon[row.module];
              return (
                <tr
                  key={row.id}
                  className="border-b border-border-soft transition-colors last:border-0 hover:bg-white/[0.02]"
                >
                  <td className="py-3.5 pr-4 font-medium text-ink">{row.activity}</td>
                  <td className="py-3.5 pr-4">
                    <span
                      className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-medium ${moduleColor[row.module]}`}
                    >
                      <Icon className="h-3.5 w-3.5" />
                      {row.module}
                    </span>
                  </td>
                  <td className="py-3.5 pr-4">
                    <StatusPill status={row.status} />
                  </td>
                  <td className="py-3.5 pr-4 text-ink-dim">{row.date}</td>
                  <td className="py-3.5 pl-2 text-right text-ink-faint">
                    <span className="mr-2">{row.details}</span>
                    <button className="inline-flex h-7 w-7 items-center justify-center rounded-lg hover:bg-white/5">
                      <DotsIcon className="h-4 w-4" />
                    </button>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      {/* Mobile cards */}
      <div className="space-y-3 md:hidden">
        {activityRows.map((row) => {
          const Icon = moduleIcon[row.module];
          return (
            <div key={row.id} className="rounded-xl border border-border-soft p-3.5">
              <div className="flex items-start justify-between gap-2">
                <span className="text-sm font-medium text-ink">{row.activity}</span>
                <StatusPill status={row.status} />
              </div>
              <div className="mt-2 flex items-center justify-between text-xs">
                <span
                  className={`inline-flex items-center gap-1.5 rounded-full px-2 py-0.5 font-medium ${moduleColor[row.module]}`}
                >
                  <Icon className="h-3 w-3" />
                  {row.module}
                </span>
                <span className="text-ink-faint">{row.date}</span>
              </div>
              <p className="mt-1.5 text-xs text-ink-faint">{row.details}</p>
            </div>
          );
        })}
      </div>
    </div>
  );
}
