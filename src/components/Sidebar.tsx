"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useState } from "react";
import {
  GridIcon,
  OrbIcon,
  SageIcon,
  HeartPulseIcon,
  PanelLeftIcon,
  ChevronDownIcon,
  XIcon,
} from "./icons";
import { Avatar } from "./Avatar";
import { AccountMenu } from "./AccountMenu";
import { user } from "@/lib/data";

const navItems = [
  { href: "/dashboard", label: "Dashboard", icon: GridIcon },
  { href: "/orb", label: "Orb", icon: OrbIcon },
  { href: "/sage", label: "Sage", icon: SageIcon },
  { href: "/manic-heart", label: "Manic Heart", icon: HeartPulseIcon },
];

export function Sidebar({
  mobileOpen,
  onCloseMobile,
}: {
  mobileOpen: boolean;
  onCloseMobile: () => void;
}) {
  const pathname = usePathname();
  const [collapsed, setCollapsed] = useState(false);
  const [accountOpen, setAccountOpen] = useState(false);

  return (
    <>
      {mobileOpen && (
        <div
          className="fixed inset-0 z-40 bg-black/60 backdrop-blur-sm lg:hidden"
          onClick={onCloseMobile}
        />
      )}
      <aside
        className={`fixed inset-y-0 left-0 z-50 flex h-full flex-col border-r border-border bg-base-alt transition-all duration-300 lg:sticky lg:top-0 lg:z-auto lg:translate-x-0 ${
          collapsed ? "lg:w-[84px]" : "lg:w-[248px]"
        } ${mobileOpen ? "w-[260px] translate-x-0" : "w-[260px] -translate-x-full lg:translate-x-0"}`}
      >
        <div className="flex items-center justify-between px-4 py-5">
          <div className="flex items-center gap-2.5 overflow-hidden">
            <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-gradient-to-br from-cyan to-emerald shadow-glow">
              <span className="text-sm font-black text-base">U</span>
            </div>
            {!collapsed && (
              <span className="whitespace-nowrap text-lg font-bold tracking-tight text-ink">
                Umbra
              </span>
            )}
          </div>
          <button
            onClick={() => setCollapsed((v) => !v)}
            className="hidden h-8 w-8 shrink-0 items-center justify-center rounded-lg text-ink-dim transition-colors hover:bg-white/5 hover:text-ink lg:flex"
            aria-label="Collapse sidebar"
          >
            <PanelLeftIcon className="h-4.5 w-4.5" />
          </button>
          <button
            onClick={onCloseMobile}
            className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg text-ink-dim hover:bg-white/5 hover:text-ink lg:hidden"
            aria-label="Close menu"
          >
            <XIcon className="h-4.5 w-4.5" />
          </button>
        </div>

        <nav className="flex-1 space-y-1 overflow-y-auto px-3 py-2">
          {navItems.map((item) => {
            const active = pathname === item.href || pathname?.startsWith(item.href + "/");
            const Icon = item.icon;
            return (
              <Link
                key={item.href}
                href={item.href}
                onClick={onCloseMobile}
                className={`nav-item ${active ? "nav-item-active" : ""} ${
                  collapsed ? "lg:justify-center" : ""
                }`}
                title={collapsed ? item.label : undefined}
              >
                <Icon className="h-[18px] w-[18px] shrink-0" />
                {!collapsed && <span className="truncate">{item.label}</span>}
              </Link>
            );
          })}
        </nav>

        <div className="relative border-t border-border p-3">
          <button
            onClick={() => setAccountOpen((v) => !v)}
            className={`flex w-full items-center gap-2.5 rounded-xl px-2 py-2 text-left transition-colors hover:bg-white/5 ${
              collapsed ? "lg:justify-center" : ""
            }`}
          >
            <Avatar initials={user.avatarInitials} size={34} online />
            {!collapsed && (
              <>
                <div className="min-w-0 flex-1">
                  <div className="truncate text-sm font-semibold text-ink">{user.name}</div>
                  <div className="truncate text-xs text-ink-faint">{user.handle}</div>
                </div>
                <ChevronDownIcon
                  className={`h-4 w-4 shrink-0 text-ink-faint transition-transform ${
                    accountOpen ? "rotate-180" : ""
                  }`}
                />
              </>
            )}
          </button>
          {accountOpen && (
            <AccountMenu onClose={() => setAccountOpen(false)} anchor="sidebar" />
          )}
        </div>
      </aside>
    </>
  );
}
