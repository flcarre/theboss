import type { SoundName } from "./game/types";

const MASTER_VOLUME = 0.16;

let enabled = true;
let context: AudioContext | null = null;
let master: GainNode | null = null;

export function setSoundsEnabled(next: boolean): void {
  enabled = next;
}

function audio(): { ctx: AudioContext; out: GainNode } | null {
  if (typeof window === "undefined" || typeof window.AudioContext === "undefined") return null;
  if (!context) {
    context = new window.AudioContext();
    master = context.createGain();
    master.gain.value = MASTER_VOLUME;
    master.connect(context.destination);
  }
  if (context.state === "suspended") void context.resume();
  return master ? { ctx: context, out: master } : null;
}

export function unlockAudio(): void {
  if (enabled) audio();
}

function tone(
  ctx: AudioContext,
  out: AudioNode,
  options: { type: OscillatorType; from: number; to?: number; start: number; duration: number; peak: number; attack?: number },
): void {
  const oscillator = ctx.createOscillator();
  const envelope = ctx.createGain();
  const begin = ctx.currentTime + options.start;
  const end = begin + options.duration;
  oscillator.type = options.type;
  oscillator.frequency.setValueAtTime(options.from, begin);
  if (options.to !== undefined) oscillator.frequency.exponentialRampToValueAtTime(options.to, end);
  envelope.gain.setValueAtTime(0.0001, begin);
  envelope.gain.exponentialRampToValueAtTime(options.peak, begin + (options.attack ?? 0.004));
  envelope.gain.exponentialRampToValueAtTime(0.0001, end);
  oscillator.connect(envelope);
  envelope.connect(out);
  oscillator.start(begin);
  oscillator.stop(end + 0.02);
}

function noiseBuffer(ctx: AudioContext, seconds: number): AudioBuffer {
  const buffer = ctx.createBuffer(1, Math.ceil(ctx.sampleRate * seconds), ctx.sampleRate);
  const data = buffer.getChannelData(0);
  for (let index = 0; index < data.length; index++) data[index] = Math.random() * 2 - 1;
  return buffer;
}

function tink(ctx: AudioContext, out: AudioNode): void {
  tone(ctx, out, { type: "sine", from: 2093, start: 0, duration: 0.09, peak: 0.5 });
  tone(ctx, out, { type: "sine", from: 4186, start: 0, duration: 0.05, peak: 0.12 });
}

function pop(ctx: AudioContext, out: AudioNode): void {
  tone(ctx, out, { type: "sine", from: 720, to: 240, start: 0, duration: 0.08, peak: 0.7, attack: 0.002 });
  tone(ctx, out, { type: "triangle", from: 1400, to: 600, start: 0, duration: 0.03, peak: 0.12, attack: 0.001 });
}

function glass(ctx: AudioContext, out: AudioNode): void {
  tone(ctx, out, { type: "sine", from: 1568, start: 0, duration: 0.55, peak: 0.32 });
  tone(ctx, out, { type: "sine", from: 2349, start: 0.07, duration: 0.5, peak: 0.22 });
  tone(ctx, out, { type: "sine", from: 3136, start: 0.07, duration: 0.25, peak: 0.06 });
}

function whip(ctx: AudioContext, out: AudioNode): void {
  const begin = ctx.currentTime;
  const source = ctx.createBufferSource();
  source.buffer = noiseBuffer(ctx, 0.2);
  const filter = ctx.createBiquadFilter();
  filter.type = "bandpass";
  filter.Q.value = 1.4;
  filter.frequency.setValueAtTime(900, begin);
  filter.frequency.exponentialRampToValueAtTime(5200, begin + 0.09);
  const envelope = ctx.createGain();
  envelope.gain.setValueAtTime(0.0001, begin);
  envelope.gain.exponentialRampToValueAtTime(0.25, begin + 0.07);
  envelope.gain.exponentialRampToValueAtTime(1.1, begin + 0.095);
  envelope.gain.exponentialRampToValueAtTime(0.0001, begin + 0.2);
  source.connect(filter);
  filter.connect(envelope);
  envelope.connect(out);
  source.start(begin);
  source.stop(begin + 0.22);
}

const VOICES: Record<SoundName, (ctx: AudioContext, out: AudioNode) => void> = { tink, pop, glass, whip };

export function playSound(name: SoundName): void {
  if (!enabled) return;
  const engine = audio();
  if (!engine) return;
  VOICES[name](engine.ctx, engine.out);
}
