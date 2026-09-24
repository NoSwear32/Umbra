import { StatCard } from "@/components/StatCard";
import { ActivityTable } from "@/components/ActivityTable";
import { AccountOverviewCard } from "@/components/AccountOverviewCard";
import { NotificationsPreviewCard } from "@/components/NotificationsPreviewCard";
import { ModuleUsage } from "@/components/ModuleUsage";
import { QuickActions } from "@/components/QuickActions";
import { Sparkline } from "@/components/Sparkline";
import { AppShell } from "@/components/AppShell";
import { ActivityIcon, HeartPulseIcon, OrbIcon, SageIcon } from "@/components/icons";
import { activityTrend, sageInsights } from "@/lib/data";

export default function DashboardPage() {
  const insight = sageInsights[0];

  return (
    <AppShell title="Dashboard" subtitle="Welcome back — here's what's happening across Umbra.">
      <div className="space-y-6">
        {/* Top stat row */}
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
          <StatCard
            label="Active Sessions"
            value="248"
            change="+25%"
            trend="up"
            icon={<ActivityIcon className="h-full w-full" />}
            accent="cyan"
          />
          <StatCard
            label="Orb Activity"
            value="128"
            change="+18%"
            trend="up"
            icon={<OrbIcon className="h-full w-full" />}
            accent="cyan"
          />
          <StatCard
            label="Sage Insights"
            value="94"
            change="+12%"
            trend="up"
            icon={<SageIcon className="h-full w-full" />}
            accent="emerald"
          />
          <StatCard
            label="Heart Signals"
            value="47"
            change="-4%"
            trend="down"
            icon={<HeartPulseIcon className="h-full w-full" />}
            accent="gold"
          />
        </div>

        {/* Main content grid */}
        <div className="grid grid-cols-1 gap-6 xl:grid-cols-3">
          <div className="xl:col-span-2">
            <ActivityTable />
          </div>
          <div className="space-y-6">
            <AccountOverviewCard />
            <NotificationsPreviewCard />
          </div>
        </div>

        {/* Lower section */}
        <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
          <ModuleUsage />

          <div className="panel panel-hover p-5">
            <div className="mb-3 flex items-center justify-between">
              <h3 className="text-sm font-semibold text-ink">Recent Insight</h3>
              <span className="rounded-full bg-emerald-soft px-2 py-0.5 text-[11px] font-medium text-emerald">
                {insight.tag}
              </span>
            </div>
            <div className="flex items-start gap-3">
              <div className="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-emerald-soft text-emerald">
                <SageIcon className="h-4.5 w-4.5" />
              </div>
              <div>
                <div className="text-sm font-semibold text-ink">{insight.title}</div>
                <p className="mt-1 text-sm leading-relaxed text-ink-dim">{insight.body}</p>
              </div>
            </div>
          </div>
        </div>

        <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
          <div className="panel panel-hover p-5 lg:col-span-2">
            <div className="mb-1 flex items-center justify-between">
              <h3 className="text-sm font-semibold text-ink">Activity Overview</h3>
              <span className="text-xs text-ink-faint">Last 12 weeks</span>
            </div>
            <div className="mt-3 h-40">
              <Sparkline data={activityTrend} color="#16D5D5" />
            </div>
          </div>
          <div className="flex flex-col justify-center lg:col-span-1">
            <QuickActions />
          </div>
        </div>
      </div>
    </AppShell>
  );
}
