import Link from "next/link";
import { OrbIcon, SageIcon, HeartPulseIcon } from "./icons";

const actions = [
  { label: "Open Orb", href: "/orb", icon: OrbIcon, accent: "text-cyan bg-cyan-soft border-cyan/25" },
  { label: "Ask Sage", href: "/sage", icon: SageIcon, accent: "text-emerald bg-emerald-soft border-emerald/25" },
  {
    label: "Open Manic Heart",
    href: "/manic-heart",
    icon: HeartPulseIcon,
    accent: "text-gold bg-gold-soft border-gold/25",
  },
];

export function QuickActions() {
  return (
    <div className="panel panel-hover p-5">
      <h3 className="mb-4 text-sm font-semibold text-ink">Quick Actions</h3>
      <div className="grid grid-cols-1 gap-2.5">
        {actions.map((a) => {
          const Icon = a.icon;
          return (
            <Link
              key={a.label}
              href={a.href}
              className={`group flex items-center gap-3 rounded-xl border px-3.5 py-3 text-sm font-medium transition-all duration-200 hover:shadow-glow ${a.accent}`}
            >
              <Icon className="h-4.5 w-4.5" />
              {a.label}
            </Link>
          );
        })}
      </div>
    </div>
  );
}
