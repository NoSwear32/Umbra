"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { BellIcon, OrbIcon, SageIcon, HeartPulseIcon, SparklesIcon, CheckIcon } from "./icons";
import { notifications as initialNotifications, NotificationItem } from "@/lib/data";

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

export function NotificationsDropdown({ onClose }: { onClose: () => void }) {
  const ref = useRef<HTMLDivElement>(null);
  const [items, setItems] = useState<NotificationItem[]>(initialNotifications);

  useEffect(() => {
    function handler(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        onClose();
      }
    }
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, [onClose]);

  const unreadCount = items.filter((n) => !n.read).length;

  return (
    <div
      ref={ref}
      className="absolute right-0 top-full z-50 mt-2 w-[360px] overflow-hidden rounded-xl2 border border-border bg-surface-raised shadow-card"
    >
      <div className="flex items-center justify-between border-b border-border px-4 py-3.5">
        <div className="flex items-center gap-2">
          <span className="text-sm font-semibold text-ink">Notifications</span>
          {unreadCount > 0 && (
            <span className="rounded-full bg-cyan-soft px-1.5 py-0.5 text-[11px] font-semibold text-cyan">
              {unreadCount} new
            </span>
          )}
        </div>
        <button
          onClick={() => setItems((prev) => prev.map((n) => ({ ...n, read: true })))}
          className="flex items-center gap-1 text-xs font-medium text-ink-dim transition-colors hover:text-cyan"
        >
          <CheckIcon className="h-3.5 w-3.5" />
          Mark all as read
        </button>
      </div>
      <div className="max-h-[360px] overflow-y-auto">
        {items.map((n) => {
          const Icon = iconMap[n.kind];
          return (
            <button
              key={n.id}
              onClick={() =>
                setItems((prev) =>
                  prev.map((x) => (x.id === n.id ? { ...x, read: true } : x))
                )
              }
              className={`flex w-full items-start gap-3 border-b border-border-soft px-4 py-3.5 text-left transition-colors hover:bg-white/[0.03] ${
                !n.read ? "bg-cyan-soft/30" : ""
              }`}
            >
              <div className={`mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-lg ${colorMap[n.kind]}`}>
                <Icon className="h-4 w-4" />
              </div>
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2">
                  <span className="truncate text-sm font-medium text-ink">{n.title}</span>
                  {!n.read && <span className="h-1.5 w-1.5 shrink-0 rounded-full bg-cyan" />}
                </div>
                <p className="mt-0.5 line-clamp-2 text-xs text-ink-dim">{n.body}</p>
                <span className="mt-1 block text-[11px] text-ink-faint">{n.time}</span>
              </div>
            </button>
          );
        })}
      </div>
      <div className="border-t border-border p-2">
        <Link
          href="/settings?tab=notifications"
          onClick={onClose}
          className="block rounded-lg px-3 py-2 text-center text-xs font-medium text-ink-dim transition-colors hover:bg-white/5 hover:text-ink"
        >
          Notification settings
        </Link>
      </div>
    </div>
  );
}

export function NotificationsTrigger() {
  const [open, setOpen] = useState(false);
  const unread = initialNotifications.filter((n) => !n.read).length;

  return (
    <div className="relative">
      <button
        onClick={() => setOpen((v) => !v)}
        className="relative flex h-10 w-10 items-center justify-center rounded-xl border border-border bg-white/[0.03] text-ink-dim transition-all hover:border-white/20 hover:bg-white/[0.06] hover:text-ink"
        aria-label="Notifications"
      >
        <BellIcon className="h-[18px] w-[18px]" />
        {unread > 0 && (
          <span className="absolute -right-1 -top-1 flex h-4 w-4 items-center justify-center rounded-full bg-gold text-[10px] font-bold text-base">
            {unread}
          </span>
        )}
      </button>
      {open && <NotificationsDropdown onClose={() => setOpen(false)} />}
    </div>
  );
}
