import Link from "next/link";
import { user } from "@/lib/data";
import { Avatar } from "./Avatar";
import { ShieldIcon } from "./icons";

export function AccountOverviewCard() {
  return (
    <div className="panel panel-hover p-5">
      <h3 className="mb-4 text-sm font-semibold text-ink">Account Overview</h3>
      <div className="flex items-center gap-3">
        <Avatar initials={user.avatarInitials} size={48} online />
        <div className="min-w-0">
          <div className="truncate font-semibold text-ink">{user.name}</div>
          <div className="truncate text-sm text-ink-faint">{user.email}</div>
        </div>
      </div>

      <div className="mt-4 grid grid-cols-2 gap-2.5">
        <div className="rounded-xl border border-border-soft bg-white/[0.02] p-3">
          <div className="text-[11px] uppercase tracking-wide text-ink-faint">Plan</div>
          <div className="mt-1 text-sm font-semibold text-cyan">{user.plan}</div>
        </div>
        <div className="rounded-xl border border-border-soft bg-white/[0.02] p-3">
          <div className="text-[11px] uppercase tracking-wide text-ink-faint">Status</div>
          <div className="mt-1 flex items-center gap-1.5 text-sm font-semibold text-emerald">
            <ShieldIcon className="h-3.5 w-3.5" />
            {user.status}
          </div>
        </div>
      </div>

      <Link href="/account" className="btn-secondary mt-4 w-full">
        View Account
      </Link>
    </div>
  );
}
