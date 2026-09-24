"use client";

import { useState } from "react";
import { PulseVisualization } from "./PulseVisualization";
import { PauseIcon, PlayIcon, RefreshIcon } from "./icons";

export function HeartWorkspace() {
  const [active, setActive] = useState(true);
  const [sensitivity, setSensitivity] = useState<"Low" | "Balanced" | "High">("Balanced");

  return (
    <div className="panel panel-hover p-6">
      <div className="mb-5 flex flex-wrap items-center justify-between gap-3">
        <div>
          <div className="text-3xl font-bold tracking-tight text-ink">62 <span className="text-base font-medium text-ink-faint">bpm avg</span></div>
          <p className="text-sm text-ink-dim">Signal stable · last calibrated 3h ago</p>
        </div>
        <div className="flex items-center gap-2">
          <button onClick={() => setActive((v) => !v)} className="btn-primary bg-gold/90 hover:bg-gold hover:shadow-none px-5">
            {active ? <PauseIcon className="h-4 w-4" /> : <PlayIcon className="h-4 w-4" />}
            {active ? "Pause" : "Resume"}
          </button>
          <button className="btn-secondary px-4">
            <RefreshIcon className="h-4 w-4" />
            Calibrate
          </button>
        </div>
      </div>

      <PulseVisualization active={active} />

      <div className="mt-5 flex flex-wrap items-center justify-between gap-3 border-t border-border-soft pt-5">
        <span className="text-sm font-medium text-ink-dim">Sensitivity</span>
        <div className="flex items-center gap-2">
          {(["Low", "Balanced", "High"] as const).map((s) => (
            <button
              key={s}
              onClick={() => setSensitivity(s)}
              className={`rounded-full px-3.5 py-1.5 text-xs font-medium transition-all ${
                sensitivity === s
                  ? "bg-gold-soft text-gold border border-gold/30"
                  : "text-ink-dim border border-border hover:border-white/20 hover:text-ink"
              }`}
            >
              {s}
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}
