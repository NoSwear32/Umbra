"use client";

export function PulseVisualization({ active = true }: { active?: boolean }) {
  return (
    <div className="relative flex h-64 w-full items-center justify-center overflow-hidden rounded-xl2 border border-border-soft bg-white/[0.02] sm:h-72">
      <div className="absolute inset-0 bg-gradient-to-t from-gold/5 via-transparent to-transparent" />

      <svg viewBox="0 0 100 20" className="pointer-events-none absolute inset-0 h-full w-full opacity-15" preserveAspectRatio="none">
        {Array.from({ length: 10 }).map((_, i) => (
          <line key={`v${i}`} x1={i * 10} y1={0} x2={i * 10} y2={20} stroke="#E8B95E" strokeWidth="0.05" />
        ))}
        {Array.from({ length: 5 }).map((_, i) => (
          <line key={`h${i}`} x1={0} y1={i * 4} x2={100} y2={i * 4} stroke="#E8B95E" strokeWidth="0.05" />
        ))}
      </svg>

      <div className={`z-10 mb-4 ${active ? "animate-heartbeat" : ""}`} style={{ transformOrigin: "center" }}>
        <svg width="72" height="72" viewBox="0 0 24 24" fill="none">
          <path
            d="M12.1 5.4c-1.4-1.9-4.2-2.5-6-1-2 1.6-2.3 4.5-.6 6.5L12 18l6.5-7.1c1.7-2 1.4-4.9-.6-6.5-1.8-1.5-4.6-.9-6 1Z"
            fill="url(#heartGrad)"
            stroke="#E8B95E"
            strokeWidth="1"
          />
          <defs>
            <linearGradient id="heartGrad" x1="0" y1="0" x2="1" y2="1">
              <stop offset="0%" stopColor="#E8B95E" stopOpacity="0.7" />
              <stop offset="100%" stopColor="#E8B95E" stopOpacity="0.15" />
            </linearGradient>
          </defs>
        </svg>
      </div>

      <svg viewBox="0 0 400 60" className="absolute bottom-6 left-0 w-full px-4" preserveAspectRatio="none">
        <path
          d="M0 30 L60 30 L75 10 L90 50 L105 30 L160 30 L175 15 L190 45 L205 30 L400 30"
          fill="none"
          stroke="#E8B95E"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
          className={active ? "animate-dash-flow" : ""}
          strokeDasharray="6 4"
          opacity="0.9"
        />
      </svg>

      <div className="absolute right-4 top-4 flex items-center gap-1.5 rounded-full border border-gold/30 bg-gold-soft px-2.5 py-1 text-xs font-medium text-gold">
        <span className="h-1.5 w-1.5 rounded-full bg-gold animate-pulse-glow" />
        {active ? "Monitoring" : "Paused"}
      </div>
    </div>
  );
}
