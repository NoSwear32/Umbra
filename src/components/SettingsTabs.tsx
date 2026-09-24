"use client";

import { useSearchParams } from "next/navigation";
import { useState } from "react";
import {
  UserIcon,
  BellIcon,
  PaletteIcon,
  ShieldIcon,
  LockIcon,
} from "./icons";
import { user } from "@/lib/data";

const tabs = [
  { id: "account", label: "Account", icon: UserIcon },
  { id: "notifications", label: "Notifications", icon: BellIcon },
  { id: "appearance", label: "Appearance", icon: PaletteIcon },
  { id: "privacy", label: "Privacy", icon: ShieldIcon },
  { id: "security", label: "Security", icon: LockIcon },
] as const;

type TabId = (typeof tabs)[number]["id"];

function Toggle({ defaultChecked = false, label }: { defaultChecked?: boolean; label: string }) {
  const [checked, setChecked] = useState(defaultChecked);
  return (
    <button
      onClick={() => setChecked((v) => !v)}
      className="flex w-full items-center justify-between rounded-xl border border-border-soft bg-white/[0.02] px-4 py-3.5 text-left transition-colors hover:border-white/15"
    >
      <span className="text-sm font-medium text-ink">{label}</span>
      <span
        className={`relative h-6 w-11 shrink-0 rounded-full transition-colors ${
          checked ? "bg-cyan" : "bg-white/10"
        }`}
      >
        <span
          className={`absolute top-0.5 h-5 w-5 rounded-full bg-white shadow transition-transform ${
            checked ? "translate-x-[22px]" : "translate-x-0.5"
          }`}
        />
      </span>
    </button>
  );
}

function SectionCard({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="panel p-5">
      <h3 className="mb-4 text-sm font-semibold text-ink">{title}</h3>
      <div className="space-y-3">{children}</div>
    </div>
  );
}

const themes = ["Midnight", "Charcoal", "Deep Space"];
const accents = [
  { name: "Cyan", color: "#16D5D5" },
  { name: "Emerald", color: "#23D98A" },
  { name: "Gold", color: "#E8B95E" },
];

export function SettingsTabs() {
  const params = useSearchParams();
  const initial = (params.get("tab") as TabId) || "account";
  const [active, setActive] = useState<TabId>(tabs.some((t) => t.id === initial) ? initial : "account");
  const [theme, setTheme] = useState(themes[0]);
  const [accent, setAccent] = useState(accents[0].name);

  return (
    <div className="grid grid-cols-1 gap-6 lg:grid-cols-4">
      <nav className="flex gap-2 overflow-x-auto pb-1 lg:col-span-1 lg:flex-col lg:overflow-visible">
        {tabs.map((t) => {
          const Icon = t.icon;
          const isActive = active === t.id;
          return (
            <button
              key={t.id}
              onClick={() => setActive(t.id)}
              className={`nav-item shrink-0 ${isActive ? "nav-item-active" : ""}`}
            >
              <Icon className="h-4 w-4" />
              {t.label}
            </button>
          );
        })}
      </nav>

      <div className="space-y-6 lg:col-span-3">
        {active === "account" && (
          <SectionCard title="Account">
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <label className="block">
                <span className="mb-1.5 block text-xs font-medium text-ink-dim">Full name</span>
                <input defaultValue={user.name} className="input-field w-full" />
              </label>
              <label className="block">
                <span className="mb-1.5 block text-xs font-medium text-ink-dim">Email</span>
                <input defaultValue={user.email} className="input-field w-full" />
              </label>
            </div>
            <label className="block">
              <span className="mb-1.5 block text-xs font-medium text-ink-dim">Timezone</span>
              <select className="input-field w-full sm:w-64">
                <option>UTC-08:00 Pacific Time</option>
                <option>UTC-05:00 Eastern Time</option>
                <option>UTC+00:00 London</option>
                <option>UTC+01:00 Central Europe</option>
              </select>
            </label>
            <button className="btn-primary">Save changes</button>
          </SectionCard>
        )}

        {active === "notifications" && (
          <SectionCard title="Notifications">
            <Toggle label="Orb session summaries" defaultChecked />
            <Toggle label="Sage insight digests" defaultChecked />
            <Toggle label="Manic Heart signal alerts" defaultChecked />
            <Toggle label="Weekly product updates" />
            <Toggle label="Marketing emails" />
          </SectionCard>
        )}

        {active === "appearance" && (
          <SectionCard title="Appearance">
            <div>
              <span className="mb-2 block text-xs font-medium text-ink-dim">Theme</span>
              <div className="flex flex-wrap gap-2">
                {themes.map((t) => (
                  <button
                    key={t}
                    onClick={() => setTheme(t)}
                    className={`rounded-xl border px-4 py-2.5 text-sm font-medium transition-all ${
                      theme === t
                        ? "border-border-accent bg-cyan-soft text-cyan"
                        : "border-border text-ink-dim hover:border-white/20 hover:text-ink"
                    }`}
                  >
                    {t}
                  </button>
                ))}
              </div>
            </div>
            <div>
              <span className="mb-2 block text-xs font-medium text-ink-dim">Accent color</span>
              <div className="flex flex-wrap gap-3">
                {accents.map((a) => (
                  <button
                    key={a.name}
                    onClick={() => setAccent(a.name)}
                    className="flex items-center gap-2 rounded-xl border border-border-soft px-3 py-2 text-sm text-ink-dim transition-all hover:border-white/20"
                    style={accent === a.name ? { borderColor: a.color, color: a.color } : undefined}
                  >
                    <span className="h-3.5 w-3.5 rounded-full" style={{ backgroundColor: a.color }} />
                    {a.name}
                  </button>
                ))}
              </div>
            </div>
          </SectionCard>
        )}

        {active === "privacy" && (
          <SectionCard title="Privacy">
            <Toggle label="Share anonymized usage analytics" defaultChecked />
            <Toggle label="Allow Sage to reference journal entries" defaultChecked />
            <Toggle label="Public profile visibility" />
            <div className="rounded-xl border border-border-soft bg-white/[0.02] p-4">
              <div className="text-sm font-medium text-ink">Data export</div>
              <p className="mt-1 text-xs text-ink-faint">Download a copy of everything stored in your Umbra account.</p>
              <button className="btn-secondary mt-3">Request export</button>
            </div>
          </SectionCard>
        )}

        {active === "security" && (
          <SectionCard title="Security">
            <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-border-soft bg-white/[0.02] p-4">
              <div>
                <div className="text-sm font-medium text-ink">Two-factor authentication</div>
                <div className="text-xs text-ink-faint">Currently disabled</div>
              </div>
              <button className="btn-secondary">Enable</button>
            </div>
            <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-border-soft bg-white/[0.02] p-4">
              <div>
                <div className="text-sm font-medium text-ink">Active sessions</div>
                <div className="text-xs text-ink-faint">3 devices currently signed in</div>
              </div>
              <button className="btn-secondary">Review</button>
            </div>
            <label className="block">
              <span className="mb-1.5 block text-xs font-medium text-ink-dim">Change password</span>
              <input type="password" placeholder="New password" className="input-field w-full sm:w-80" />
            </label>
            <button className="btn-primary">Update password</button>
          </SectionCard>
        )}
      </div>
    </div>
  );
}
