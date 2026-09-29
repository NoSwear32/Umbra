#!/usr/bin/env python3
"""
Generates every sound of Spire Sprint from scratch: no samples, no recordings, nothing borrowed.

    python3 tools/generate_audio.py            # writes assets/audio/*.wav
    python3 tools/generate_audio.py --report   # also prints level / loop statistics

Everything is additive / subtractive synthesis with numpy (band-limited saw and pulse
oscillators, sine and bell partials, filtered noise, exponential envelopes) and a fixed random
seed, so the output is bit-for-bit reproducible. The two music tracks are composed in code:
chord progressions, bass lines, arpeggios and melodies are written out below; all effects
(delay, low-pass filters) are circular, so the tracks loop without a click or a gap.

Format: 22.05 kHz, mono, 16 bit PCM WAV. Music files carry a "smpl" chunk that marks the loop
(Godot's WAV importer reads it and turns looping on automatically).
"""
import argparse
import os
import struct
import sys

import numpy as np

SR = 22050
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio")
TAU = 2.0 * np.pi


# ---------------------------------------------------------------------------------------------
# Oscillators
# ---------------------------------------------------------------------------------------------
def _t(seconds):
    return np.arange(int(round(seconds * SR))) / SR


def _phase(freq):
    """Phase (in cycles) for a frequency in Hz that may change over time."""
    freq = np.asarray(freq, dtype=np.float64)
    return np.cumsum(freq / SR)


def _polyblep(t, dt):
    out = np.zeros_like(t)
    m = t < dt
    x = t[m] / dt[m]
    out[m] = x + x - x * x - 1.0
    m = t > 1.0 - dt
    x = (t[m] - 1.0) / dt[m]
    out[m] = x * x + x + x + 1.0
    return out


def sine(freq):
    return np.sin(TAU * _phase(freq))


def triangle(freq):
    p = _phase(freq) % 1.0
    return 4.0 * np.abs(p - 0.5) - 1.0


def saw(freq):
    freq = np.asarray(freq, dtype=np.float64)
    p = _phase(freq) % 1.0
    dt = np.clip(freq / SR, 1e-6, 0.49)
    return 2.0 * p - 1.0 - _polyblep(p, dt)


def pulse(freq, duty=0.5):
    freq = np.asarray(freq, dtype=np.float64)
    p = _phase(freq) % 1.0
    dt = np.clip(freq / SR, 1e-6, 0.49)
    v = np.where(p < duty, 1.0, -1.0)
    v = v + _polyblep(p, dt) - _polyblep((p - duty) % 1.0, dt)
    return v


def noise(n, rng):
    return rng.uniform(-1.0, 1.0, n)


def midi(note):
    return 440.0 * 2.0 ** ((note - 69) / 12.0)


# ---------------------------------------------------------------------------------------------
# Envelopes and filters
# ---------------------------------------------------------------------------------------------
def env_exp(n, tau, attack=0.002):
    t = np.arange(n) / SR
    e = np.exp(-t / tau)
    if attack > 0:
        a = np.clip(t / attack, 0.0, 1.0)
        e = e * a
    return e


def env_adsr(n, a, d, s, r):
    """Attack / decay / sustain level / release, all in seconds except the level."""
    t = np.arange(n) / SR
    total = n / SR
    e = np.ones(n)
    e = np.where(t < a, t / max(a, 1e-6), e)
    e = np.where((t >= a) & (t < a + d), 1.0 - (1.0 - s) * (t - a) / max(d, 1e-6), e)
    e = np.where(t >= a + d, s, e)
    rel = np.clip((total - t) / max(r, 1e-6), 0.0, 1.0)
    return e * rel


def fade(x, fade_in=0.002, fade_out=0.006):
    n = len(x)
    fi = int(fade_in * SR)
    fo = int(fade_out * SR)
    y = x.copy()
    if fi > 0:
        y[:fi] *= np.linspace(0.0, 1.0, fi)
    if fo > 0:
        y[-fo:] *= np.linspace(1.0, 0.0, fo)
    return y


def lowpass(x, cutoff, circular=True):
    """One-pole low-pass, computed by FFT convolution.

    `circular=True` wraps around the end (used for looping music so the loop stays seamless);
    `circular=False` is the ordinary causal filter for one-shot sounds.
    """
    a = np.exp(-TAU * cutoff / SR)
    k = int(min(len(x), max(8, 9.0 / max(1.0 - a, 1e-6))))
    h = (1.0 - a) * a ** np.arange(k)
    if circular:
        hx = np.zeros(len(x))
        hx[:k] = h
        return np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(hx), len(x))
    size = 1
    while size < len(x) + k:
        size *= 2
    y = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(h, size), size)
    return y[:len(x)]


def highpass(x, cutoff, circular=True):
    return x - lowpass(x, cutoff, circular)


def bandpass(x, low, high, circular=True):
    return lowpass(highpass(x, low, circular), high, circular)


def soft_clip(x, drive=1.0):
    return np.tanh(x * drive) / np.tanh(drive)


def echo(x, delay_s, feedback, mix, damp=4500.0, taps=6):
    """Circular feedback delay (the tail wraps around, so loops stay seamless)."""
    d = int(delay_s * SR)
    acc = np.zeros_like(x)
    cur = x
    for _ in range(taps):
        cur = np.roll(cur, d)
        cur = lowpass(cur, damp) * feedback
        acc = acc + cur
    return x + acc * mix


def reverb(x, mix=0.25, decay=0.55):
    """Small circular comb reverb (four combs with prime-ish delays)."""
    acc = np.zeros_like(x)
    for ms, g in ((29.7, 0.8), (37.1, 0.75), (41.1, 0.7), (43.7, 0.65)):
        d = int(ms * SR / 1000.0)
        cur = x
        for k in range(1, 9):
            cur = np.roll(cur, d)
            acc = acc + cur * (decay ** k) * g * 0.25
    return x + lowpass(acc, 5000.0) * mix


def normalise(x, peak):
    m = np.max(np.abs(x))
    if m < 1e-9:
        return x
    return x * (peak / m)


# ---------------------------------------------------------------------------------------------
# Instruments (each returns a numpy array)
# ---------------------------------------------------------------------------------------------
def pluck(freq, dur, bright=1.0, tau=0.12):
    n = int(dur * SR)
    f = np.full(n, freq)
    body = 0.6 * triangle(f) + 0.35 * sine(f * 2.0) + 0.18 * pulse(f, 0.3) * bright
    return body * env_exp(n, tau, 0.002)


def bell(freq, dur, tau=0.18):
    """FM-flavoured glass bell: inharmonic partials with individual decay times."""
    n = int(dur * SR)
    out = np.zeros(n)
    for ratio, amp, decay in ((1.0, 1.0, 1.0), (2.0, 0.55, 0.7), (2.76, 0.32, 0.5), (4.07, 0.2, 0.35), (5.4, 0.1, 0.25)):
        f = np.full(n, freq * ratio)
        out += amp * sine(f) * env_exp(n, tau * decay, 0.001)
    return out


def kick(dur=0.28):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = 44.0 + 96.0 * np.exp(-t / 0.035)
    body = np.sin(TAU * np.cumsum(f) / SR) * np.exp(-t / 0.12)
    click = np.sin(TAU * 1800.0 * t) * np.exp(-t / 0.004) * 0.25
    return body + click


def snare(dur=0.2, rng=None):
    rng = rng or np.random.default_rng(3)
    n = int(dur * SR)
    t = np.arange(n) / SR
    nz = highpass(noise(n, rng), 1500.0, False) * np.exp(-t / 0.055)
    tone = np.sin(TAU * 190.0 * t) * np.exp(-t / 0.05) * 0.45
    return nz * 0.8 + tone


def hat(dur=0.05, rng=None, open_=False):
    rng = rng or np.random.default_rng(5)
    n = int(dur * SR)
    t = np.arange(n) / SR
    return highpass(noise(n, rng), 6000.0, False) * np.exp(-t / (0.06 if open_ else 0.012))


def add_wrapped(buf, start, sig, gain=1.0):
    """Adds `sig` into `buf` starting at sample `start`, wrapping around the end."""
    n = len(buf)
    start = int(start) % n
    m = len(sig)
    first = min(m, n - start)
    buf[start:start + first] += sig[:first] * gain
    rest = m - first
    while rest > 0:
        take = min(rest, n)
        buf[:take] += sig[m - rest:m - rest + take] * gain
        rest -= take


def min_wrapped(buf, start, sig):
    """buf = minimum(buf, sig) over sig's span starting at `start` (wrapping around the end)."""
    n = len(buf)
    start = int(start) % n
    m = len(sig)
    first = min(m, n - start)
    buf[start:start + first] = np.minimum(buf[start:start + first], sig[:first])
    if m > first:
        rest = m - first
        buf[:rest] = np.minimum(buf[:rest], sig[first:])


# ---------------------------------------------------------------------------------------------
# Sound effects
# ---------------------------------------------------------------------------------------------
def sfx_jump(rng):
    dur = 0.17
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = 330.0 * (760.0 / 330.0) ** (t / dur)
    tone = 0.62 * triangle(f) + 0.34 * pulse(f, 0.25) + 0.2 * sine(f * 2.0)
    puff = highpass(noise(n, rng), 2500.0, False) * np.exp(-t / 0.012) * 0.25
    return (tone * env_exp(n, 0.075, 0.003) + puff)


def sfx_land(rng):
    dur = 0.18
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = 55.0 + 105.0 * np.exp(-t / 0.03)
    thump = np.sin(TAU * np.cumsum(f) / SR) * np.exp(-t / 0.055)
    dust = lowpass(noise(n, rng), 1100.0, False) * np.exp(-t / 0.028) * 0.7
    return thump + dust


def sfx_wall(rng):
    dur = 0.24
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = 250.0 + 110.0 * np.exp(-t / 0.05) + 14.0 * np.sin(TAU * 26.0 * t)
    boing = 0.75 * np.sin(TAU * np.cumsum(f) / SR) + 0.25 * np.sin(TAU * np.cumsum(f * 2.0) / SR)
    tick = highpass(noise(n, rng), 1800.0, False) * np.exp(-t / 0.006) * 0.35
    return boing * env_exp(n, 0.085, 0.002) + tick


def sfx_combo_step(rng):
    return bell(523.25, 0.42, 0.16)


def _arp(notes, spacing, tail, timbre, total):
    n = int(total * SR)
    out = np.zeros(n)
    for i, note in enumerate(notes):
        sig = timbre(midi(note), tail)
        add_wrapped(out, int(i * spacing * SR), sig)
    return out


def sfx_combo_end_1(rng):
    return _arp([72, 76, 79], 0.06, 0.32, lambda f, d: pluck(f, d, 1.0, 0.11), 0.6)


def sfx_combo_end_2(rng):
    out = _arp([72, 76, 79, 84], 0.055, 0.45, lambda f, d: pluck(f, d, 1.2, 0.14), 0.85)
    n = len(out)
    add_wrapped(out, int(0.165 * SR), bell(midi(96), 0.6, 0.2)[:n], 0.35)
    return out


def sfx_combo_end_3(rng):
    n = int(1.5 * SR)
    out = _arp([72, 76, 79, 84, 88, 91], 0.05, 0.5, lambda f, d: pluck(f, d, 1.4, 0.16), 1.5)
    chord = np.zeros(n)
    for note in (84, 88, 91, 96):
        f = np.full(n, midi(note))
        chord += 0.5 * triangle(f) * env_exp(n, 0.55, 0.01)
    add_wrapped(out, int(0.3 * SR), chord[:n - int(0.3 * SR)], 0.5)
    sparkle = highpass(noise(n, rng), 5000.0, False) * env_exp(n, 0.25, 0.0) * 0.12
    add_wrapped(out, int(0.3 * SR), sparkle[:n - int(0.3 * SR)])
    return out


def sfx_speed_up(rng):
    dur = 0.75
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = 150.0 * (620.0 / 150.0) ** (t / dur)
    trem = 0.72 + 0.28 * np.sin(TAU * 15.0 * t)
    body = 0.55 * saw(f) + 0.35 * pulse(f * 0.5, 0.4) + 0.4 * sine(f * 0.5)
    swell = np.clip(t / 0.5, 0.0, 1.0) ** 1.6 * np.clip((dur - t) / 0.12, 0.0, 1.0)
    whoosh = bandpass(noise(n, rng), 300.0, 2600.0, False) * swell * 0.16
    return lowpass(body * trem, 3200.0, False) * swell + whoosh


def sfx_ui_click(rng):
    n = int(0.05 * SR)
    t = np.arange(n) / SR
    tone = np.sin(TAU * 1250.0 * t) * np.exp(-t / 0.009)
    tick = highpass(noise(n, rng), 3000.0, False) * np.exp(-t / 0.002) * 0.3
    return tone + tick


def sfx_ui_back(rng):
    n = int(0.08 * SR)
    t = np.arange(n) / SR
    f = 800.0 - 260.0 * (t / 0.08)
    return np.sin(TAU * np.cumsum(f) / SR) * np.exp(-t / 0.02)


def sfx_game_over(rng):
    notes = [64, 60, 57, 52]
    n = int(1.6 * SR)
    out = np.zeros(n)
    starts = [0.0, 0.26, 0.52, 0.8]
    lengths = [0.3, 0.3, 0.3, 0.8]
    for note, start, length in zip(notes, starts, lengths):
        m = int(length * SR)
        t = np.arange(m) / SR
        f = midi(note) * (1.0 - 0.03 * (t / length))
        sig = 0.5 * triangle(f) + 0.3 * pulse(f, 0.35) + 0.25 * sine(f * 0.5)
        sig = lowpass(sig, 2400.0, False) * env_exp(m, 0.28 if length > 0.4 else 0.16, 0.004)
        add_wrapped(out, int(start * SR), sig)
    rumble = lowpass(noise(n, rng), 250.0, False) * env_exp(n, 0.5, 0.05) * 0.35
    return out + rumble


def sfx_record(rng):
    n = int(1.7 * SR)
    out = np.zeros(n)
    for i, note in enumerate((72, 76, 79)):
        add_wrapped(out, int(i * 0.1 * SR), pluck(midi(note), 0.4, 1.3, 0.14))
    # sustained top chord with a gentle vibrato
    m = n - int(0.3 * SR)
    t = np.arange(m) / SR
    chord = np.zeros(m)
    for note in (84, 88, 91):
        f = midi(note) * (1.0 + 0.004 * np.sin(TAU * 5.5 * t))
        chord += 0.4 * triangle(f) + 0.18 * sine(f * 2.0)
    chord *= env_adsr(m, 0.01, 0.2, 0.6, 0.9)
    add_wrapped(out, int(0.3 * SR), chord, 0.7)
    for i, note in enumerate((96, 100, 103, 108)):
        add_wrapped(out, int((0.45 + 0.09 * i) * SR), bell(midi(note), 0.6, 0.18), 0.25)
    return out


def sfx_danger(rng):
    n = int(0.24 * SR)
    t = np.arange(n) / SR
    f = np.where(t < 0.11, 466.0, 349.0)
    tone = pulse(f, 0.5) * 0.6 + sine(f) * 0.4
    gate = env_exp(n, 0.09, 0.003) * np.clip((0.24 - t) / 0.02, 0.0, 1.0)
    return lowpass(tone, 2200.0, False) * gate


def sfx_unlock(rng):
    n = int(1.0 * SR)
    out = np.zeros(n)
    for i, note in enumerate((76, 80, 83, 88)):
        add_wrapped(out, int(i * 0.09 * SR), bell(midi(note), 0.7, 0.22), 0.8)
    add_wrapped(out, int(0.36 * SR), highpass(noise(int(0.5 * SR), rng), 6000.0, False) * env_exp(int(0.5 * SR), 0.18, 0.0) * 0.1)
    return out


SFX = {
    "jump": (sfx_jump, 0.8),
    "land": (sfx_land, 0.85),
    "wall": (sfx_wall, 0.8),
    "combo_step": (sfx_combo_step, 0.7),
    "combo_end_1": (sfx_combo_end_1, 0.75),
    "combo_end_2": (sfx_combo_end_2, 0.78),
    "combo_end_3": (sfx_combo_end_3, 0.82),
    "speed_up": (sfx_speed_up, 0.75),
    "ui_click": (sfx_ui_click, 0.6),
    "ui_back": (sfx_ui_back, 0.6),
    "game_over": (sfx_game_over, 0.8),
    "record": (sfx_record, 0.82),
    "danger": (sfx_danger, 0.6),
    "unlock": (sfx_unlock, 0.75),
}


# ---------------------------------------------------------------------------------------------
# Music
# ---------------------------------------------------------------------------------------------
def _bar_samples(bpm):
    return int(round(4 * 60.0 / bpm * SR))


def music_game():
    """'Skyline Sprint': 16 bars at 138 BPM in A minor, built up in four 4-bar sections."""
    rng = np.random.default_rng(1001)
    bpm = 138.0
    bar = _bar_samples(bpm)
    beat = bar // 4
    step = bar // 16          # sixteenth note
    bars = 16
    n = bar * bars
    # chords per bar: Am F C G (x4); root notes in MIDI
    prog = [(57, [57, 60, 64]), (53, [53, 57, 60]), (48, [48, 52, 55]), (55, [55, 59, 62])] * 4

    drums = np.zeros(n)
    bass = np.zeros(n)
    arp = np.zeros(n)
    pad = np.zeros(n)
    lead = np.zeros(n)
    kick_l = kick()
    snare_l = snare(rng=rng)
    hat_c = hat(rng=rng)
    hat_o = hat(0.12, rng, True)

    duck = np.ones(n)
    duck_shape = 1.0 - 0.75 * np.exp(-np.arange(beat) / (0.11 * SR))

    for b in range(bars):
        root, tones = prog[b]
        base = b * bar
        section = b // 4          # 0 intro, 1 groove, 2 lead, 3 full
        # --- pad (all sections)
        m = bar + int(0.3 * SR)
        t = np.arange(m) / SR
        chord = np.zeros(m)
        for k, note in enumerate([tones[0] + 12, tones[1] + 12, tones[2] + 12, tones[0] + 24]):
            f = midi(note)
            chord += (saw(np.full(m, f * 0.997)) + saw(np.full(m, f * 1.003))) * 0.5
        chord = lowpass(chord, 1500.0, False) * env_adsr(m, 0.18, 0.4, 0.8, 0.35) * (0.11 if section == 0 else 0.075)
        add_wrapped(pad, base, chord)

        # --- hats (all sections; open hat on the offbeat from the groove on)
        for i in range(8):
            accent = 1.0 if i % 2 == 0 else 0.55
            add_wrapped(drums, base + i * (bar // 8), hat_c, (0.22 if section == 0 else 0.16) * accent)
        if section >= 1:
            for i in (1, 3, 5, 7):
                add_wrapped(drums, base + i * (bar // 8), hat_o, 0.11)

        # --- kick + snare + bass (from the groove on)
        if section >= 1:
            kick_beats = [0, 1, 2, 3] if section >= 3 else [0, 2]
            for kb in kick_beats:
                add_wrapped(drums, base + kb * beat, kick_l, 0.95)
                min_wrapped(duck, base + kb * beat, duck_shape)
            for sb in (1, 3):
                add_wrapped(drums, base + sb * beat, snare_l, 0.5)
            # driving eighth-note bass with an octave hop on the last eighth
            pattern = [0, 0, 12, 0, 0, 12, 0, 7]
            for i, off in enumerate(pattern):
                note = root - 12 + off
                m = bar // 8
                f = np.full(m, midi(note))
                sig = (0.6 * saw(f) + 0.4 * pulse(f, 0.45)) * env_exp(m, 0.12, 0.004)
                add_wrapped(bass, base + i * (bar // 8), lowpass(sig, 900.0, False), 0.6)

        # --- arpeggio: sixteenths through the chord, two octaves (all sections, brighter later)
        order = [0, 1, 2, 1, 0, 2, 1, 2, 0, 1, 2, 1, 2, 1, 0, 1]
        for i in range(16):
            note = tones[order[i] % 3] + 12 + (12 if i % 4 == 3 else 0)
            m = int(step * 2.2)
            sig = pluck(midi(note), m / SR, 1.0 + 0.4 * section, 0.07)
            gain = 0.27 if section == 0 else 0.2
            add_wrapped(arp, base + i * step, sig, gain * (1.0 if i % 4 == 0 else 0.8))

    # --- lead melody in sections 2 and 3 (bars 9-16): an eight-note motif, varied per chord
    motif = [(0, 3), (2, 1), (4, 2), (2, 2), (5, 3), (4, 1), (2, 2), (0, 2)]   # (scale step, length in sixteenths)
    scale = [69, 72, 74, 76, 79, 81, 84]     # A minor pentatonic-ish (A C D E G A C)
    for b in range(8, 16):
        base = b * bar
        pos = 0
        shift = [0, 0, 2, 1][b % 4] if b < 12 else [2, 1, 3, 4][b % 4]
        for step_idx, ln in motif:
            idx = (step_idx + shift) % len(scale)
            f0 = midi(scale[idx])
            m = int(ln * step * 0.95)
            t = np.arange(m) / SR
            f = f0 * (1.0 + 0.006 * np.sin(TAU * 5.0 * t) * np.clip(t / 0.12, 0.0, 1.0))
            sig = 0.55 * pulse(f, 0.28) + 0.3 * triangle(f) + 0.15 * sine(f * 2.0)
            sig = lowpass(sig, 3800.0, False) * env_adsr(m, 0.006, 0.05, 0.6, 0.05)
            add_wrapped(lead, base + pos * step, sig, 0.17)
            pos += ln

    # --- a snare roll into the loop point (last bar)
    for i in range(8):
        add_wrapped(drums, (bars - 1) * bar + bar // 2 + i * (bar // 16), snare_l, 0.18 + 0.05 * i)

    mix = drums * 0.9 + bass * duck * 1.0 + arp + pad * duck * 0.9 + lead
    mix = echo(mix, 60.0 / bpm * 0.75, 0.42, 0.34)
    mix = reverb(mix, 0.16)
    mix = lowpass(mix, 9500.0)
    mix = soft_clip(mix, 1.4)
    return normalise(mix - np.mean(mix), 0.62)


def music_menu():
    """'Lantern Stairs': 12 bars at 84 BPM in D major, calm and open."""
    rng = np.random.default_rng(2002)
    bpm = 84.0
    bar = _bar_samples(bpm)
    beat = bar // 4
    eighth = bar // 8
    bars = 12
    n = bar * bars
    # Dmaj7 - Bm7 - Gmaj7 - Asus4, three times through
    prog = [
        (50, [62, 66, 69, 73]),
        (47, [59, 62, 66, 69]),
        (43, [55, 59, 62, 66]),
        (45, [57, 62, 64, 69]),
    ] * 3

    pad = np.zeros(n)
    sub = np.zeros(n)
    arp = np.zeros(n)
    melody = np.zeros(n)
    shaker = np.zeros(n)
    hat_s = hat(0.06, rng)

    for b in range(bars):
        root, tones = prog[b]
        base = b * bar
        cycle = b // 4
        # soft pad
        m = bar + int(0.9 * SR)
        chord = np.zeros(m)
        for note in tones:
            f = midi(note)
            chord += (triangle(np.full(m, f * 0.998)) + triangle(np.full(m, f * 1.002))) * 0.5
            chord += 0.25 * sine(np.full(m, f * 0.5))
        chord = lowpass(chord, 1300.0, False) * env_adsr(m, 0.9, 0.5, 0.85, 1.0) * 0.16
        add_wrapped(pad, base, chord)
        # sub bass note on the first beat, repeated softly on beat 3
        for bt, g in ((0, 1.0), (2, 0.6)):
            m = int(beat * 1.9)
            f = np.full(m, midi(root - 12))
            sig = (sine(f) + 0.25 * sine(f * 2.0)) * env_exp(m, 0.9, 0.01)
            add_wrapped(sub, base + bt * beat, sig, 0.5 * g)
        # very light shaker from the second cycle
        if cycle >= 1:
            for i in range(8):
                add_wrapped(shaker, base + i * eighth, hat_s, 0.07 if i % 2 == 0 else 0.04)
        # plucked arpeggio from the second cycle
        if cycle >= 1:
            order = [0, 1, 2, 3, 2, 1, 2, 3]
            for i in range(8):
                note = tones[order[i]] + (12 if i in (3, 7) else 0)
                sig = pluck(midi(note), 0.9, 0.6, 0.35)
                add_wrapped(arp, base + i * eighth, sig, 0.13)

    # bell melody in the last cycle: two-bar phrase, played over both halves
    scale = [74, 76, 78, 81, 83, 85, 86]       # D E F# A B C# D
    phrase = [(0, 0.0, 1.0), (2, 1.0, 0.5), (3, 1.5, 0.5), (4, 2.0, 1.5), (3, 3.5, 0.5),
              (2, 4.0, 1.0), (1, 5.0, 0.5), (2, 5.5, 0.5), (0, 6.0, 2.0)]
    for half in (0, 1):
        base = (8 + half * 2) * bar
        for idx, at, ln in phrase:
            note = scale[(idx + (2 if half else 0)) % len(scale)]
            add_wrapped(melody, base + int(at * beat), bell(midi(note), 1.4, 0.4), 0.2)
    mix = pad + sub + arp + melody + shaker
    mix = echo(mix, 60.0 / bpm * 0.75, 0.5, 0.45, damp=3500.0)
    mix = reverb(mix, 0.32, 0.62)
    mix = lowpass(mix, 8500.0)
    mix = soft_clip(mix, 1.1)
    return normalise(mix - np.mean(mix), 0.6)


MUSIC = {
    "music_game": music_game,
    "music_menu": music_menu,
}


# ---------------------------------------------------------------------------------------------
# WAV output
# ---------------------------------------------------------------------------------------------
def to_int16(x):
    return np.clip(np.round(x * 32767.0), -32768, 32767).astype("<i2")


def wav_bytes(samples, loop=False):
    pcm = to_int16(samples).tobytes()
    fmt = struct.pack("<HHIIHH", 1, 1, SR, SR * 2, 2, 16)
    chunks = b"fmt " + struct.pack("<I", len(fmt)) + fmt
    if loop:
        n = len(samples)
        smpl = struct.pack(
            "<IIIIIIIII", 0, 0, int(1e9 / SR), 60, 0, 0, 0, 1, 0
        ) + struct.pack("<IIIIII", 0, 0, 0, n - 1, 0, 0)
        chunks += b"smpl" + struct.pack("<I", len(smpl)) + smpl
    chunks += b"data" + struct.pack("<I", len(pcm)) + pcm
    return b"RIFF" + struct.pack("<I", 4 + len(chunks)) + b"WAVE" + chunks


def report_line(name, x, loop):
    peak = float(np.max(np.abs(x)))
    rms = float(np.sqrt(np.mean(x * x)))
    dc = float(np.mean(x))
    extra = ""
    if loop:
        step_rms = float(np.sqrt(np.mean(np.diff(x) ** 2)))
        jump = abs(float(x[0]) - float(x[-1]))
        extra = "  loop seam jump %.4f (%.1fx the typical sample step)" % (jump, jump / max(step_rms, 1e-9))
    return "%-13s %6.2fs  peak %.3f (%.1f dBFS)  rms %.3f  dc %+.4f%s" % (
        name, len(x) / SR, peak, 20 * np.log10(max(peak, 1e-9)), rms, dc, extra)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=OUT_DIR, help="output folder (default: assets/audio)")
    ap.add_argument("--report", action="store_true", help="print level statistics")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)

    lines = []
    for name, (fn, peak) in SFX.items():
        rng = np.random.default_rng(sum(ord(c) * (i + 1) for i, c in enumerate(name)))
        x = fn(rng)
        x = fade(x - np.mean(x), 0.002, 0.008)
        x = normalise(soft_clip(x, 1.1), peak)
        with open(os.path.join(args.out, name + ".wav"), "wb") as f:
            f.write(wav_bytes(x))
        lines.append(report_line(name, x, False))
    for name, fn in MUSIC.items():
        x = fn()
        with open(os.path.join(args.out, name + ".wav"), "wb") as f:
            f.write(wav_bytes(x, loop=True))
        lines.append(report_line(name, x, True))
    print("wrote %d files to %s" % (len(SFX) + len(MUSIC), os.path.abspath(args.out)))
    if args.report:
        print("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
