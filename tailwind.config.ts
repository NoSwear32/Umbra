import type { Config } from "tailwindcss";

const config: Config = {
  darkMode: "class",
  content: ["./src/**/*.{js,ts,jsx,tsx,mdx}"],
  theme: {
    extend: {
      colors: {
        base: {
          DEFAULT: "#0B0F10",
          alt: "#0E1415",
        },
        surface: {
          DEFAULT: "#111A1B",
          raised: "#142021",
          hover: "#162223",
        },
        border: {
          DEFAULT: "rgba(255,255,255,0.08)",
          soft: "rgba(255,255,255,0.05)",
          accent: "rgba(22,213,213,0.35)",
        },
        cyan: {
          DEFAULT: "#16D5D5",
          soft: "rgba(22,213,213,0.12)",
        },
        emerald: {
          DEFAULT: "#23D98A",
          soft: "rgba(35,217,138,0.12)",
        },
        gold: {
          DEFAULT: "#E8B95E",
          soft: "rgba(232,185,94,0.12)",
        },
        ink: {
          DEFAULT: "#EAF2F2",
          dim: "#9FB0B1",
          faint: "#63797A",
        },
      },
      fontFamily: {
        sans: [
          "Inter",
          "Geist",
          "-apple-system",
          "BlinkMacSystemFont",
          "Segoe UI",
          "sans-serif",
        ],
      },
      borderRadius: {
        xl2: "20px",
      },
      boxShadow: {
        glow: "0 0 0 1px rgba(22,213,213,0.15), 0 8px 30px -8px rgba(22,213,213,0.25)",
        card: "0 4px 24px -8px rgba(0,0,0,0.5)",
      },
      backgroundImage: {
        "grid-glow":
          "radial-gradient(circle at 20% 0%, rgba(22,213,213,0.08), transparent 40%), radial-gradient(circle at 80% 20%, rgba(35,217,138,0.06), transparent 40%)",
      },
    },
  },
  plugins: [],
};

export default config;
