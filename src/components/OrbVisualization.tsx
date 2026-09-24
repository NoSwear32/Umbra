"use client";

export function OrbVisualization({ active = true }: { active?: boolean }) {
  return (
    <div className="relative flex h-72 w-72 items-center justify-center sm:h-80 sm:w-80">
      <div className="absolute inset-0 rounded-full bg-cyan/10 blur-3xl animate-pulse-glow" />
      <svg viewBox="0 0 200 200" className="relative h-full w-full">
        <defs>
          <radialGradient id="orbCore" cx="50%" cy="45%" r="60%">
            <stop offset="0%" stopColor="#8FFcFC" />
            <stop offset="35%" stopColor="#16D5D5" />
            <stop offset="100%" stopColor="#0B4B4B" />
          </radialGradient>
          <linearGradient id="ringGrad" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" stopColor="#16D5D5" />
            <stop offset="100%" stopColor="#23D98A" />
          </linearGradient>
        </defs>

        <g className={active ? "animate-orb-spin" : ""} style={{ transformOrigin: "100px 100px" }}>
          <circle
            cx="100"
            cy="100"
            r="92"
            fill="none"
            stroke="url(#ringGrad)"
            strokeWidth="1"
            strokeOpacity="0.35"
            strokeDasharray="2 6"
          />
        </g>
        <g
          className={active ? "animate-orb-spin-reverse" : ""}
          style={{ transformOrigin: "100px 100px" }}
        >
          <circle
            cx="100"
            cy="100"
            r="78"
            fill="none"
            stroke="#16D5D5"
            strokeWidth="1"
            strokeOpacity="0.25"
            className="animate-dash-flow"
          />
        </g>

        <circle cx="100" cy="100" r="58" fill="url(#orbCore)" className={active ? "animate-pulse-glow" : ""} />
        <ellipse cx="82" cy="80" rx="18" ry="10" fill="white" opacity="0.25" />
      </svg>
    </div>
  );
}
