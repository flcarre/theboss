import type { Metadata, Viewport } from "next";
import { Instrument_Sans, Instrument_Serif, JetBrains_Mono, Pixelify_Sans } from "next/font/google";
import "./globals.css";

const serif = Instrument_Serif({ subsets: ["latin"], weight: "400", style: ["normal", "italic"], variable: "--font-serif" });
const sans = Instrument_Sans({ subsets: ["latin"], variable: "--font-sans" });
const mono = JetBrains_Mono({ subsets: ["latin"], weight: ["400", "600"], variable: "--font-mono" });
const pixel = Pixelify_Sans({ subsets: ["latin"], weight: ["400", "500", "600", "700"], variable: "--font-pixel" });

export const metadata: Metadata = {
  metadataBase: new URL("https://theboss-iota.vercel.app"),
  title: "The Boss — your coding agents, clocked in",
  description:
    "A macOS app that turns every Claude Code, Codex, Cursor, Pi and omp session into a pixel robot at a desk. Walk the floor, see who needs you, and teach your setup from your own corrections.",
  icons: { icon: "/assets/AppIcon.png", apple: "/assets/AppIcon.png" },
  openGraph: {
    title: "The Boss — your coding agents, clocked in",
    description: "Every coding agent session becomes a robot at a desk. Walk the floor. Approve. Teach. Clock out.",
    images: ["/assets/og.png"],
  },
  twitter: { card: "summary_large_image", images: ["/assets/og.png"] },
};

export const viewport: Viewport = { themeColor: "#100E1C" };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${serif.variable} ${sans.variable} ${mono.variable} ${pixel.variable}`}>
      <body>{children}</body>
    </html>
  );
}
