"use client";

import { useState } from "react";
import { OrbVisualization } from "./OrbVisualization";
import { PlayIcon, PauseIcon, RefreshIcon } from "./icons";

const modes = ["Deep Focus", "Ambient", "Recovery"];

export function OrbWorkspace() {
  const [running, setRunning] = useState(true);
  const [mode, setMode] = useState(modes[0]);

  return (
    <div className="panel panel-hover flex flex-col items-center p-8 text-center">
      <div className="mb-1 flex items-center gap-2 rounded-full border border-border-accent bg-cyan-soft px-3 py-1 text-xs font-medium text-cyan">
        <span className="h-1.5 w-1.5 rounded-full bg-cyan animate-pulse-glow" />
        {running ? "Session in progress" : "Session paused"}
      </div>

      <OrbVisualization active={running} />

      <div className="mt-2 text-4xl font-bold tracking-tight text-ink">24:18</div>
      <p className="mt-1 text-sm text-ink-dim">{mode} session · goal 30:00</p>

      <div className="mt-6 flex items-center gap-3">
        <button
          onClick={() => setRunning((v) => !v)}
          className="btn-primary px-6"
        >
          {running ? <PauseIcon className="h-4 w-4" /> : <PlayIcon className="h-4 w-4" />}
          {running ? "Pause" : "Resume"}
        </button>
        <button className="btn-secondary px-5">
          <RefreshIcon className="h-4 w-4" />
          Reset
        </button>
      </div>

      <div className="mt-7 flex w-full flex-wrap items-center justify-center gap-2 border-t border-border-soft pt-5">
        {modes.map((m) => (
          <button
            key={m}
            onClick={() => setMode(m)}
            className={`rounded-full px-3.5 py-1.5 text-xs font-medium transition-all ${
              mode === m
                ? "bg-cyan-soft text-cyan border border-border-accent"
                : "text-ink-dim border border-border hover:border-white/20 hover:text-ink"
            }`}
          >
            {m}
          </button>
        ))}
      </div>
    </div>
  );
}
