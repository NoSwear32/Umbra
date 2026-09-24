import { Status } from "@/lib/data";

const styles: Record<Status, string> = {
  Active: "bg-emerald-soft text-emerald border border-emerald/30",
  Complete: "bg-cyan-soft text-cyan border border-cyan/30",
  Processing: "bg-gold-soft text-gold border border-gold/30",
};

const dot: Record<Status, string> = {
  Active: "bg-emerald",
  Complete: "bg-cyan",
  Processing: "bg-gold",
};

export function StatusPill({ status }: { status: Status }) {
  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-medium ${styles[status]}`}
    >
      <span className={`h-1.5 w-1.5 rounded-full ${dot[status]} ${status === "Active" ? "animate-pulse-glow" : ""}`} />
      {status}
    </span>
  );
}
