"use client";

import { useEffect, useState } from "react";

const RELEASES = "https://github.com/flcarre/theboss-releases/releases";
const latest = (file: string) => `${RELEASES}/latest/download/${file}`;

type OsId = "macos" | "windows" | "linux";

type Build = { label: string; href: string; size: string };

const PLATFORMS: { id: OsId; name: string; detail: string; builds: Build[]; firstLaunch: string }[] = [
  {
    id: "macos",
    name: "macOS",
    detail: "Apple Silicon and Intel · macOS 11+",
    builds: [{ label: "Download .dmg", href: latest("TheBoss-macOS.dmg"), size: "universal" }],
    firstLaunch:
      "Drag The Boss to Applications. The first time, right-click it and choose Open (or System Settings → Privacy & Security → Open Anyway).",
  },
  {
    id: "windows",
    name: "Windows",
    detail: "Windows 10 and 11 · 64-bit",
    builds: [{ label: "Download installer", href: latest("TheBoss-Windows-setup.exe"), size: ".exe" }],
    firstLaunch: "Run the installer, no admin rights needed. If SmartScreen shows up, click More info → Run anyway.",
  },
  {
    id: "linux",
    name: "Linux",
    detail: "x86_64 · any distro with WebKitGTK",
    builds: [
      { label: "Download AppImage", href: latest("TheBoss-Linux.AppImage"), size: "portable" },
      { label: ".deb", href: latest("TheBoss-Linux.deb"), size: "Debian, Ubuntu" },
    ],
    firstLaunch: "AppImage: chmod +x TheBoss-Linux.AppImage, then run it. Debian or Ubuntu: sudo apt install ./TheBoss-Linux.deb.",
  },
];

function detectOs(): OsId | null {
  if (typeof navigator === "undefined") return null;
  const agent = navigator.userAgent.toLowerCase();
  if (agent.includes("windows")) return "windows";
  if (agent.includes("mac")) return "macos";
  if (agent.includes("linux") && !agent.includes("android")) return "linux";
  return null;
}

export default function Install() {
  const [os, setOs] = useState<OsId | null>(null);

  useEffect(() => setOs(detectOs()), []);

  return (
    <section className="install" id="download">
      <header className="section-head reveal">
        <p className="eyebrow">07 — Clock in</p>
        <h2>
          Download it, open it,
          <br />
          <em>walk in.</em>
        </h2>
        <p className="lede">One app for macOS, Windows and Linux. Nothing to compile, no terminal, no account.</p>
      </header>

      <div className="install-grid">
        <div className="downloads">
          {PLATFORMS.map((platform) => (
            <article key={platform.id} className={`download reveal${os === platform.id ? " download-mine" : ""}`}>
              <div className="download-head">
                <h3>{platform.name}</h3>
                {os === platform.id && <span className="download-badge">Your system</span>}
              </div>
              <p className="download-detail">{platform.detail}</p>
              <div className="download-builds">
                {platform.builds.map((build, index) => (
                  <a key={build.href} className={`btn ${index === 0 ? "btn-gold" : "btn-ghost"}`} href={build.href}>
                    {build.label}
                    <small>{build.size}</small>
                  </a>
                ))}
              </div>
              <p className="download-note">{platform.firstLaunch}</p>
            </article>
          ))}
          <p className="fineprint reveal">
            Builds aren&rsquo;t signed by Apple or Microsoft yet, hence the one-time warning on first launch. Every
            version and its checksums live on the <a href={RELEASES}>releases page</a>.
          </p>
        </div>

        <div className="controls reveal">
          <h3>Controls</h3>
          <dl>
            <dt><span className="key">←↑↓→</span><span className="key">WASD</span></dt>
            <dd>Walk</dd>
            <dt><span className="key">⇧</span></dt>
            <dd>Run</dd>
            <dt><span className="key">F</span></dt>
            <dd>Crack the whip</dd>
            <dt><span className="key">Space</span><span className="key">↩</span></dt>
            <dd>Talk</dd>
            <dt><span className="key">Esc</span></dt>
            <dd>Menu</dd>
            <dt><span className="key">{os === "macos" ? "⌘1" : "Ctrl 1"}</span><span className="key">{os === "macos" ? "⌘6" : "Ctrl 6"}</span></dt>
            <dd>Jump to a screen</dd>
            <dt><span className="key">{os === "macos" ? "⌘," : "Ctrl ,"}</span></dt>
            <dd>Settings, English or French</dd>
            <dt><span className="key">Click</span></dt>
            <dd>Walk to a robot or a piece of furniture</dd>
          </dl>
        </div>
      </div>
    </section>
  );
}
