"use client";

import { FormEvent, useState } from "react";
import { SageIcon, SendIcon, MicIcon, SparklesIcon } from "./icons";
import { Avatar } from "./Avatar";
import { user } from "@/lib/data";

interface Message {
  id: string;
  role: "user" | "sage";
  text: string;
}

const initialMessages: Message[] = [
  {
    id: "m1",
    role: "sage",
    text: "Good afternoon. I noticed your focus sessions have been longer this week — want a quick summary?",
  },
  {
    id: "m2",
    role: "user",
    text: "Yes, give me the highlights.",
  },
  {
    id: "m3",
    role: "sage",
    text: "You logged 11h 42m of focus time across 18 sessions, up 9% from last week. Your best window is 9–11 AM. I'd suggest protecting that block on your calendar.",
  },
];

export function SageChat() {
  const [messages, setMessages] = useState<Message[]>(initialMessages);
  const [draft, setDraft] = useState("");

  function handleSubmit(e: FormEvent) {
    e.preventDefault();
    const trimmed = draft.trim();
    if (!trimmed) return;
    const userMsg: Message = { id: `u-${Date.now()}`, role: "user", text: trimmed };
    setMessages((prev) => [...prev, userMsg]);
    setDraft("");
    setTimeout(() => {
      setMessages((prev) => [
        ...prev,
        {
          id: `s-${Date.now()}`,
          role: "sage",
          text: "Noted — I'll factor that into your next insight digest.",
        },
      ]);
    }, 600);
  }

  return (
    <div className="panel flex h-[560px] flex-col p-5">
      <div className="mb-4 flex items-center gap-3 border-b border-border-soft pb-4">
        <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-emerald-soft text-emerald">
          <SageIcon className="h-5 w-5" />
        </div>
        <div>
          <div className="text-sm font-semibold text-ink">Sage</div>
          <div className="text-xs text-ink-faint">Your ambient insight companion</div>
        </div>
      </div>

      <div className="flex-1 space-y-4 overflow-y-auto pr-1">
        {messages.map((m) => (
          <div key={m.id} className={`flex items-start gap-3 ${m.role === "user" ? "flex-row-reverse" : ""}`}>
            {m.role === "sage" ? (
              <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-emerald-soft text-emerald">
                <SparklesIcon className="h-4 w-4" />
              </div>
            ) : (
              <Avatar initials={user.avatarInitials} size={32} />
            )}
            <div
              className={`max-w-[75%] rounded-2xl px-4 py-2.5 text-sm leading-relaxed ${
                m.role === "sage"
                  ? "rounded-tl-sm bg-white/[0.04] text-ink border border-border-soft"
                  : "rounded-tr-sm bg-cyan-soft text-ink border border-border-accent"
              }`}
            >
              {m.text}
            </div>
          </div>
        ))}
      </div>

      <form onSubmit={handleSubmit} className="mt-4 flex items-center gap-2 border-t border-border-soft pt-4">
        <button
          type="button"
          className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl border border-border text-ink-dim transition-colors hover:bg-white/5 hover:text-ink"
          aria-label="Voice input"
        >
          <MicIcon className="h-4.5 w-4.5" />
        </button>
        <input
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          placeholder="Ask Sage anything..."
          className="input-field flex-1"
        />
        <button type="submit" className="btn-primary shrink-0 px-4" aria-label="Send">
          <SendIcon className="h-4 w-4" />
        </button>
      </form>
    </div>
  );
}
