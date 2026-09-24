import { AppShell } from "@/components/AppShell";
import { SageChat } from "@/components/SageChat";
import { sageInsights, sageConversations } from "@/lib/data";
import { BookmarkIcon, SparklesIcon } from "@/components/icons";

const tagColor: Record<string, string> = {
  Trend: "text-cyan bg-cyan-soft",
  Alert: "text-gold bg-gold-soft",
  Digest: "text-emerald bg-emerald-soft",
};

export default function SagePage() {
  return (
    <AppShell title="Sage" subtitle="Conversational insight, reflections, and saved notes.">
      <div className="grid grid-cols-1 gap-6 xl:grid-cols-3">
        <div className="xl:col-span-2">
          <SageChat />
        </div>

        <div className="space-y-6">
          <div className="panel panel-hover p-5">
            <h3 className="mb-4 text-sm font-semibold text-ink">Recent Insights</h3>
            <div className="space-y-3">
              {sageInsights.map((i) => (
                <div key={i.id} className="rounded-xl border border-border-soft p-3.5 transition-colors hover:border-white/15">
                  <div className="mb-1.5 flex items-center justify-between">
                    <span className="flex items-center gap-1.5 text-sm font-medium text-ink">
                      <SparklesIcon className="h-3.5 w-3.5 text-emerald" />
                      {i.title}
                    </span>
                    <span className={`rounded-full px-2 py-0.5 text-[10px] font-semibold ${tagColor[i.tag]}`}>
                      {i.tag}
                    </span>
                  </div>
                  <p className="text-xs leading-relaxed text-ink-dim">{i.body}</p>
                </div>
              ))}
            </div>
          </div>

          <div className="panel panel-hover p-5">
            <h3 className="mb-4 text-sm font-semibold text-ink">Saved Conversations</h3>
            <div className="space-y-1">
              {sageConversations.map((c) => (
                <button
                  key={c.id}
                  className="flex w-full items-center justify-between gap-2 rounded-lg px-2.5 py-2.5 text-left transition-colors hover:bg-white/[0.04]"
                >
                  <div className="flex items-center gap-2.5 min-w-0">
                    <BookmarkIcon className="h-4 w-4 shrink-0 text-ink-faint" />
                    <div className="min-w-0">
                      <div className="truncate text-sm text-ink">{c.title}</div>
                      <div className="text-xs text-ink-faint">{c.messages} messages</div>
                    </div>
                  </div>
                  <span className="shrink-0 text-xs text-ink-faint">{c.time}</span>
                </button>
              ))}
            </div>
          </div>
        </div>
      </div>
    </AppShell>
  );
}
