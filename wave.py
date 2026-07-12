# wave.py
import argparse
import math
import struct
import wave
import os
import subprocess
import platform
import random
from typing import Optional, List, Tuple

class Envelope:
    def __init__(self, attack=0.0, decay=0.0, sustain=1.0, release=0.0):
        self.attack = attack
        self.decay = decay
        self.sustain = sustain
        self.release = release

class WaveGenerator:
    def __init__(self, freq=440, amp=0.8, duration=2.0, sample_rate=44100,
                 wave_type='sine', stereo=False, envelope: Optional[Envelope]=None,
                 sweep_start=None, sweep_end=None):
        self.freq = freq
        self.amp = amp
        self.duration = duration
        self.sample_rate = sample_rate
        self.wave_type = wave_type
        self.stereo = stereo
        self.envelope = envelope
        self.sweep_start = sweep_start
        self.sweep_end = sweep_end
        self.samples = []  # list of channels, each channel is list of samples

    def _value_at(self, t):
        # Frequency sweep
        freq = self.freq
        if self.sweep_start is not None and self.sweep_end is not None:
            freq = self.sweep_start + (self.sweep_end - self.sweep_start) * (t / self.duration)
        phase = 2 * math.pi * freq * t
        if self.wave_type == 'sine':
            val = math.sin(phase)
        elif self.wave_type == 'square':
            val = 1 if math.sin(phase) >= 0 else -1
        elif self.wave_type == 'sawtooth':
            val = 2 * (phase / (2 * math.pi) - math.floor(phase / (2 * math.pi) + 0.5))
        elif self.wave_type == 'triangle':
            val = 2 * abs(2 * (phase / (2 * math.pi) - math.floor(phase / (2 * math.pi) + 0.5))) - 1
        elif self.wave_type == 'noise':
            val = random.uniform(-1, 1)
        else:
            val = 0
        # Envelope
        if self.envelope:
            env = self._envelope_value(t)
            val *= env
        return val

    def _envelope_value(self, t):
        e = self.envelope
        if t < e.attack:
            return t / e.attack if e.attack > 0 else 1.0
        t -= e.attack
        if t < e.decay:
            return 1.0 - (1.0 - e.sustain) * (t / e.decay) if e.decay > 0 else e.sustain
        t -= e.decay
        sustain_duration = self.duration - e.attack - e.decay - e.release
        if sustain_duration > 0 and t < sustain_duration:
            return e.sustain
        t -= sustain_duration
        if t < e.release:
            return e.sustain * (1.0 - t / e.release) if e.release > 0 else 0
        return 0

    def generate(self):
        num_samples = int(self.duration * self.sample_rate)
        channels = 2 if self.stereo else 1
        self.samples = [[] for _ in range(channels)]
        for i in range(num_samples):
            t = i / self.sample_rate
            val = self._value_at(t)
            sample = int(self.amp * val * 32767)
            for ch in range(channels):
                self.samples[ch].append(sample)

    def save_wav(self, filename):
        with wave.open(filename, 'w') as wf:
            wf.setnchannels(len(self.samples))
            wf.setsampwidth(2)
            wf.setframerate(self.sample_rate)
            data = b''
            for i in range(len(self.samples[0])):
                for ch in range(len(self.samples)):
                    data += struct.pack('<h', self.samples[ch][i])
            wf.writeframes(data)

    def play(self, filename):
        system = platform.system()
        try:
            if system == 'Windows':
                os.startfile(filename)
            elif system == 'Darwin':
                subprocess.run(['afplay', filename], check=True)
            else:
                for player in ['ffplay', 'aplay', 'mpg123']:
                    try:
                        subprocess.run([player, filename], check=True)
                        return
                    except FileNotFoundError:
                        continue
                print('No suitable audio player found.')
        except Exception as e:
            print(f'Playback error: {e}')

def interactive():
    print('=== Waveform Audio Generator ===')
    types = ['sine', 'square', 'sawtooth', 'triangle', 'noise']
    wtype = input(f'Type ({"/".join(types)}) [sine]: ') or 'sine'
    freq = float(input('Frequency (Hz) [440]: ') or '440')
    amp = float(input('Amplitude (0.0-1.0) [0.8]: ') or '0.8')
    dur = float(input('Duration (s) [2.0]: ') or '2.0')
    rate = int(input('Sample rate [44100]: ') or '44100')
    stereo = input('Stereo? (y/n) [n]: ').lower() == 'y'
    adsr = input('ADSR? (Attack Decay Sustain Release) [none]: ')
    env = None
    if adsr and adsr != 'none':
        parts = list(map(float, adsr.split()))
        if len(parts) == 4:
            env = Envelope(*parts)
    fname = input('Output file [output.wav]: ') or 'output.wav'
    if not fname.endswith('.wav'): fname += '.wav'
    gen = WaveGenerator(freq, amp, dur, rate, wtype, stereo, env)
    gen.generate()
    gen.save_wav(fname)
    print(f'Saved to {fname}')
    if input('Play? (y/n) [y]: ').lower() != 'n':
        gen.play(fname)

def cli():
    parser = argparse.ArgumentParser()
    parser.add_argument('-f', '--freq', type=float, default=440)
    parser.add_argument('-t', '--type', default='sine', choices=['sine','square','sawtooth','triangle','noise'])
    parser.add_argument('-a', '--amp', type=float, default=0.8)
    parser.add_argument('-d', '--dur', type=float, default=2.0)
    parser.add_argument('-r', '--rate', type=int, default=44100)
    parser.add_argument('-o', '--output', default='output.wav')
    parser.add_argument('--stereo', action='store_true')
    parser.add_argument('--adsr', help='Attack Decay Sustain Release')
    parser.add_argument('--sweep', help='Start End')
    parser.add_argument('--no-play', action='store_true')
    args = parser.parse_args()
    env = None
    if args.adsr:
        parts = list(map(float, args.adsr.split()))
        if len(parts) == 4:
            env = Envelope(*parts)
    sweep = None
    if args.sweep:
        parts = list(map(float, args.sweep.split()))
        if len(parts) == 2:
            sweep = parts
    gen = WaveGenerator(args.freq, args.amp, args.dur, args.rate, args.type,
                        args.stereo, env, sweep[0] if sweep else None, sweep[1] if sweep else None)
    gen.generate()
    gen.save_wav(args.output)
    print(f'Saved to {args.output}')
    if not args.no_play:
        gen.play(args.output)

if __name__ == '__main__':
    import sys
    if len(sys.argv) > 1:
        cli()
    else:
        interactive()
