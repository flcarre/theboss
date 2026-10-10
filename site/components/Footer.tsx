export default function Footer() {
  return (
    <footer className="foot">
      <div className="foot-sky">
        <img src="/assets/skyline.png" alt="A pixel city at night, one office floor still lit" />
        <div className="foot-copy">
          <p className="foot-big">
            Go home.
            <br />
            <em>They&rsquo;ve got this.</em>
          </p>
          <a className="btn btn-gold" href="#download">Get The Boss</a>
        </div>
      </div>
      <div className="foot-meta">
        <span className="foot-brand">
          <img src="/assets/AppIcon.png" alt="" width={22} height={22} /> The Boss · v0.1.0
        </span>
        <span>Pixel art made with PixelLab · Inspired by Blume</span>
      </div>
    </footer>
  );
}
