import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Umbra",
  description: "A premium AI productivity platform — Orb, Sage, and Manic Heart in one dark, focused workspace.",
  icons: {
    icon: "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'%3E%3Crect width='24' height='24' rx='6' fill='%2316D5D5'/%3E%3Ctext x='12' y='17' font-size='14' font-family='sans-serif' font-weight='800' fill='%230B0F10' text-anchor='middle'%3EU%3C/text%3E%3C/svg%3E",
  },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className="dark">
      <body className="font-sans antialiased">{children}</body>
    </html>
  );
}
