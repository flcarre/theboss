import SpriteAnim from "./SpriteAnim";
import { stillUrl } from "@/lib/sprites";

export default function Moods() {
  return (
    <section className="moods" id="moods">
      <header className="section-head reveal">
        <p className="eyebrow">02 — Read the room</p>
        <h2>
          Three moods.
          <br />
          <em>Zero dashboards.</em>
        </h2>
      </header>

      <div className="moods-floor reveal">
        <figure className="mood">
          <div className="mood-sprite">
            <img className="mood-emote" src="/assets/emotes/dots.png" alt="" />
            <SpriteAnim sheet="robot_codex_typing_south" zoom={2} />
          </div>
          <figcaption>
            <span className="mood-tag tag-work">Working</span>
            <h3>Heads down.</h3>
            <p>It&rsquo;s typing. Leave it be. You can still peek at the transcript without breaking its focus.</p>
          </figcaption>
        </figure>
        <figure className="mood mood-hot">
          <div className="mood-sprite">
            <img className="mood-emote bob" src="/assets/emotes/alert.png" alt="" />
            <SpriteAnim sheet="robot_claude_alert_south" zoom={1.8} fps={7} />
          </div>
          <figcaption>
            <span className="mood-tag tag-wait">Needs you</span>
            <h3>Waving at you.</h3>
            <p>It wants to run something and needs your OK. A notification pops, the app badge ticks up, and it keeps waving until you show up.</p>
          </figcaption>
        </figure>
        <figure className="mood">
          <div className="mood-sprite">
            <img className="mood-emote float" src="/assets/emotes/sleep.png" alt="" />
            <img className="mood-still" src={stillUrl("copilot")} alt="" />
          </div>
          <figcaption>
            <span className="mood-tag tag-done">Done</span>
            <h3>Clocked out.</h3>
            <p>The work is finished. It dozes at its desk until you resume it or the session ages off the floor.</p>
          </figcaption>
        </figure>
      </div>

      <div className="whip reveal">
        <div className="whip-stage" aria-hidden="true">
          <SpriteAnim sheet="boss_whip_east" zoom={2.2} fps={11} className="whip-fox" />
          <span className="whip-crack">CRACK!</span>
        </div>
        <div className="whip-copy">
          <p className="eyebrow">And when they slack</p>
          <h3>
            Crack the <em>whip.</em>
          </h3>
          <ul>
            <li><b className="c-work">Working</b> types twice as fast. For a while.</li>
            <li><b className="c-wait">Waiting</b> jumps and drags you to its session to approve.</li>
            <li><b className="c-done">Done</b> wakes up with a start. It had already finished.</li>
          </ul>
          <p className="whip-note">Press <span className="key">F</span> in front of a desk. No robots were harmed, the whiteboard just counts the cracks.</p>
        </div>
      </div>

    </section>
  );
}
