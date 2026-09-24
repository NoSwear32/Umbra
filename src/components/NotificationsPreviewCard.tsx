import Link from "next/link";
import { notifications } from "@/lib/data";
import { OrbIcon, SageIcon, HeartPulseIcon, SparklesIcon } from "./icons";

const iconMap = {
  orb: OrbIcon,
  sage: SageIcon,
  heart: HeartPulseIcon,
  system: SparklesIcon,
};

const colorMap = {
  orb: "text-cyan bg-cyan-soft",
  sage: "text-emerald bg-emerald-soft",
  heart: "text-gold bg-gold-soft",
  system: "text-ink-dim bg-white/5",
};

export function NotificationsPreviewCard() {
  const preview = notifications.slice(0, 3);
  return (
    <div className="panel panel-hover p-5">
      <div className="mb-4 flex items-center justify-between">
        <h3 className="text-sm font-semibold text-ink">Notifications</h3>
        <Link href="/settings?tab=notifications" className="text-xs font-medium text-cyan hover:underline">
          See all
        </Link>
      </div>
      <div className="space-y-3">
        {preview.map((n) => {
          const Icon = iconMap[n.kind];
          return (
            <div key={n.id} className="flex items-start gap-3">
              <div className={`mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-lg ${colorMap[n.kind]}`}>
                <Icon className="h-4 w-4" />
              </div>
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-1.5">
                  <span className="truncate text-sm font-medium text-ink">{n.title}</span>
                  {!n.read && <span className="h-1.5 w-1.5 shrink-0 rounded-full bg-cyan" />}
                </div>
                <p className="mt-0.5 line-clamp-1 text-xs text-ink-faint">{n.body}</p>
              </div>
              <span className="shrink-0 text-[11px] text-ink-faint">{n.time}</span>
            </div>
          );
        })}
      </div>
    </div>
  );
}
