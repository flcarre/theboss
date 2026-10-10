"use client";

import { useEffect, useState } from "react";

function clock() {
  return new Date().toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" });
}

export default function Header() {
  const [time, setTime] = useState("23:41");
  const [scrolled, setScrolled] = useState(false);

  useEffect(() => {
    setTime(clock());
    const id = setInterval(() => setTime(clock()), 15000);
    const onScroll = () => setScrolled(window.scrollY > 24);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => {
      clearInterval(id);
      window.removeEventListener("scroll", onScroll);
    };
  }, []);

  return (
    <header className={`bar ${scrolled ? "is-scrolled" : ""}`}>
      <a className="brand" href="#top" aria-label="The Boss, back to top">
        <img src="/assets/AppIcon.png" alt="" width={34} height={34} />
        <span>The Boss</span>
      </a>
      <nav className="bar-links" aria-label="Sections">
        <a href="#tour">The floor</a>
        <a href="#menubar">Menu bar</a>
        <a href="#staff">The staff</a>
        <a href="#rules">Learned rules</a>
        <a href="#local">Privacy</a>
      </nav>
      <div className="bar-clock" aria-hidden="true">
        <span className="dot dot-live" />
        <span suppressHydrationWarning>{time}</span>
        <span className="bar-clock-label">· 8 robots on shift</span>
      </div>
      <a className="btn btn-gold btn-sm" href="#download">Get the app</a>
    </header>
  );
}
