"use client";

import Link from "next/link";
import { useEffect, useRef } from "react";
import { UserIcon, SettingsIcon, PaletteIcon, SignOutIcon, GridIcon } from "./icons";

const items = [
  { label: "Account", href: "/account", icon: UserIcon },
  { label: "Profile", href: "/account", icon: GridIcon },
  { label: "Settings", href: "/settings", icon: SettingsIcon },
  { label: "Appearance", href: "/settings?tab=appearance", icon: PaletteIcon },
];

export function AccountMenu({
  onClose,
  anchor = "sidebar",
}: {
  onClose: () => void;
  anchor?: "sidebar" | "header";
}) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function handler(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        onClose();
      }
    }
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, [onClose]);

  return (
    <div
      ref={ref}
      className={`absolute z-50 w-60 overflow-hidden rounded-xl2 border border-border bg-surface-raised shadow-card ${
        anchor === "sidebar" ? "bottom-full left-3 mb-2" : "right-0 top-full mt-2"
      }`}
    >
      <div className="p-1.5">
        {items.map((item) => {
          const Icon = item.icon;
          return (
            <Link
              key={item.label}
              href={item.href}
              onClick={onClose}
              className="flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm text-ink-dim transition-colors hover:bg-white/5 hover:text-ink"
            >
              <Icon className="h-4 w-4" />
              {item.label}
            </Link>
          );
        })}
      </div>
      <div className="border-t border-border p-1.5">
        <button
          onClick={onClose}
          className="flex w-full items-center gap-3 rounded-lg px-3 py-2.5 text-left text-sm text-gold transition-colors hover:bg-gold-soft"
        >
          <SignOutIcon className="h-4 w-4" />
          Sign out
        </button>
      </div>
    </div>
  );
}
