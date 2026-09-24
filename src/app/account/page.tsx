import { AppShell } from "@/components/AppShell";
import { Avatar } from "@/components/Avatar";
import { user } from "@/lib/data";
import { CreditCardIcon, LockIcon, ShieldIcon, UserIcon } from "@/components/icons";

export default function AccountPage() {
  return (
    <AppShell title="Account" subtitle="Manage your profile, plan, and account preferences.">
      <div className="grid grid-cols-1 gap-6 xl:grid-cols-3">
        <div className="panel panel-hover flex flex-col items-center p-6 text-center xl:col-span-1">
          <Avatar initials={user.avatarInitials} size={84} online />
          <h2 className="mt-4 text-lg font-bold text-ink">{user.name}</h2>
          <p className="text-sm text-ink-faint">{user.handle}</p>
          <span className="mt-3 inline-flex items-center gap-1.5 rounded-full border border-emerald/30 bg-emerald-soft px-3 py-1 text-xs font-medium text-emerald">
            <ShieldIcon className="h-3.5 w-3.5" />
            {user.status}
          </span>

          <div className="mt-6 grid w-full grid-cols-2 gap-2.5 text-left">
            <div className="rounded-xl border border-border-soft bg-white/[0.02] p-3">
              <div className="text-[11px] uppercase tracking-wide text-ink-faint">Plan</div>
              <div className="mt-1 text-sm font-semibold text-cyan">{user.plan}</div>
            </div>
            <div className="rounded-xl border border-border-soft bg-white/[0.02] p-3">
              <div className="text-[11px] uppercase tracking-wide text-ink-faint">Member since</div>
              <div className="mt-1 text-sm font-semibold text-ink">{user.memberSince}</div>
            </div>
          </div>

          <button className="btn-secondary mt-6 w-full">Upload new photo</button>
        </div>

        <div className="space-y-6 xl:col-span-2">
          <div className="panel panel-hover p-5">
            <div className="mb-4 flex items-center gap-2.5">
              <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-cyan-soft text-cyan">
                <UserIcon className="h-4.5 w-4.5" />
              </div>
              <h3 className="text-sm font-semibold text-ink">Profile details</h3>
            </div>
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <label className="block">
                <span className="mb-1.5 block text-xs font-medium text-ink-dim">Full name</span>
                <input defaultValue={user.name} className="input-field w-full" />
              </label>
              <label className="block">
                <span className="mb-1.5 block text-xs font-medium text-ink-dim">Username</span>
                <input defaultValue={user.handle} className="input-field w-full" />
              </label>
              <label className="block sm:col-span-2">
                <span className="mb-1.5 block text-xs font-medium text-ink-dim">Email address</span>
                <input defaultValue={user.email} className="input-field w-full" />
              </label>
            </div>
            <button className="btn-primary mt-4">Save changes</button>
          </div>

          <div className="panel panel-hover p-5">
            <div className="mb-4 flex items-center gap-2.5">
              <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-emerald-soft text-emerald">
                <CreditCardIcon className="h-4.5 w-4.5" />
              </div>
              <h3 className="text-sm font-semibold text-ink">Billing</h3>
            </div>
            <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-border-soft bg-white/[0.02] p-4">
              <div>
                <div className="text-sm font-semibold text-ink">{user.plan}</div>
                <div className="text-xs text-ink-faint">$24/month · renews Oct 24, 2026</div>
              </div>
              <button className="btn-secondary">Manage billing</button>
            </div>
          </div>

          <div className="panel panel-hover p-5">
            <div className="mb-4 flex items-center gap-2.5">
              <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-gold-soft text-gold">
                <LockIcon className="h-4.5 w-4.5" />
              </div>
              <h3 className="text-sm font-semibold text-ink">Security</h3>
            </div>
            <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-border-soft bg-white/[0.02] p-4">
              <div>
                <div className="text-sm font-semibold text-ink">Two-factor authentication</div>
                <div className="text-xs text-ink-faint">Add an extra layer of security to your account</div>
              </div>
              <button className="btn-secondary">Enable</button>
            </div>
          </div>
        </div>
      </div>
    </AppShell>
  );
}
