export function Avatar({
  initials,
  size = 36,
  online = false,
}: {
  initials: string;
  size?: number;
  online?: boolean;
}) {
  return (
    <div className="relative shrink-0" style={{ width: size, height: size }}>
      <div
        className="flex h-full w-full items-center justify-center rounded-full bg-gradient-to-br from-cyan/30 to-emerald/20 border border-border-accent text-ink font-semibold"
        style={{ fontSize: size * 0.38 }}
      >
        {initials}
      </div>
      {online && (
        <span className="absolute -bottom-0.5 -right-0.5 h-3 w-3 rounded-full bg-emerald border-2 border-surface" />
      )}
    </div>
  );
}
