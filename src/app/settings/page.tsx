import { Suspense } from "react";
import { AppShell } from "@/components/AppShell";
import { SettingsTabs } from "@/components/SettingsTabs";

export default function SettingsPage() {
  return (
    <AppShell title="Settings" subtitle="Configure your account, notifications, appearance, and security.">
      <Suspense fallback={null}>
        <SettingsTabs />
      </Suspense>
    </AppShell>
  );
}
