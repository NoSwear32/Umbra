"use client";

import Link from "next/link";
import { useState } from "react";
import { SearchIcon, SettingsIcon, MenuIcon, ChevronDownIcon } from "./icons";
import { Avatar } from "./Avatar";
import { AccountMenu } from "./AccountMenu";
import { NotificationsTrigger } from "./NotificationsDropdown";
import { user } from "@/lib/data";

export function Header({
  title,
  subtitle,
  onOpenMobile,
}: {
  title: string;
  subtitle?: string;
  onOpenMobile: () => void;
}) {
  const [accountOpen, setAccountOpen] = useState(false);

  return (
    <header className="sticky top-0 z-30 flex items-center gap-3 border-b border-border bg-base/80 px-4 py-4 backdrop-blur-md sm:px-6 lg:px-8">
      <button
        onClick={onOpenMobile}
        className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl border border-border bg-white/[0.03] text-ink-dim hover:bg-white/[0.06] hover:text-ink lg:hidden"
      >
        <MenuIcon className="h-5 w-5" />
      </button>

      <div className="min-w-0 flex-1">
        <h1 className="truncate text-xl font-bold tracking-tight text-ink sm:text-2xl">{title}</h1>
        {subtitle && <p className="mt-0.5 hidden text-sm text-ink-dim sm:block">{subtitle}</p>}
      </div>

      <div className="hidden flex-1 justify-center md:flex md:max-w-md">
        <div className="relative w-full">
          <SearchIcon className="pointer-events-none absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-ink-faint" />
          <input
            type="text"
            placeholder="Search Umbra..."
            className="input-field w-full pl-10"
          />
        </div>
      </div>

      <div className="flex shrink-0 items-center gap-2 sm:gap-3">
        <NotificationsTrigger />
        <Link
          href="/settings"
          className="hidden h-10 w-10 items-center justify-center rounded-xl border border-border bg-white/[0.03] text-ink-dim transition-all hover:border-white/20 hover:bg-white/[0.06] hover:text-ink sm:flex"
          aria-label="Settings"
        >
          <SettingsIcon className="h-[18px] w-[18px]" />
        </Link>
        <div className="relative">
          <button
            onClick={() => setAccountOpen((v) => !v)}
            className="flex items-center gap-2 rounded-xl border border-border bg-white/[0.03] p-1 pr-2 transition-all hover:border-white/20 hover:bg-white/[0.06]"
          >
            <Avatar initials={user.avatarInitials} size={32} online />
            <ChevronDownIcon
              className={`hidden h-3.5 w-3.5 text-ink-faint transition-transform sm:block ${
                accountOpen ? "rotate-180" : ""
              }`}
            />
          </button>
          {accountOpen && (
            <AccountMenu onClose={() => setAccountOpen(false)} anchor="header" />
          )}
        </div>
      </div>
    </header>
  );
}
