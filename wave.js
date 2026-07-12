// wave.js
const fs = require('fs');
const readline = require('readline');
const { exec } = require('child_process');

const rl = readline.createInterface({ input: process.stdin, output: process.stdout });

class Envelope {
    constructor(attack, decay, sustain, release) {
        this.attack = attack;
        this.decay = decay;
        this.sustain = sustain;
        this.release = release;
    }
}

class WaveGenerator {
    constructor(opts = {}) {
        this.freq = opts.freq || 440;
        this.amp = opts.amp || 0.8;
        this.duration = opts.duration || 2.0;
        this.sampleRate = opts.sampleRate || 44100;
        this.waveType = opts.waveType || 'sine';
        this.stereo = opts.stereo || false;
        this.envelope = opts.envelope || null;
        this.sweepStart = opts.sweepStart || null;
        this.sweepEnd = opts.sweepEnd || null;
        this.samples = [];
    }

    _valueAt(t) {
        let freq = this.freq;
        if (this.sweepStart !== null && this.sweepEnd !== null) {
            freq = this.sweepStart + (this.sweepEnd - this.sweepStart) * (t / this.duration);
        }
        const phase = 2 * Math.PI * freq * t;
        let val = 0;
        switch (this.waveType) {
            case 'sine': val = Math.sin(phase); break;
            case 'square': val = Math.sin(phase) >= 0 ? 1 : -1; break;
            case 'sawtooth': val = 2 * (phase / (2 * Math.PI) - Math.floor(phase / (2 * Math.PI) + 0.5)); break;
            case 'triangle': val = 2 * Math.abs(2 * (phase / (2 * Math.PI) - Math.floor(phase / (2 * Math.PI) + 0.5))) - 1; break;
            case 'noise': val = Math.random() * 2 - 1; break;
            default: val = 0;
        }
        if (this.envelope) val *= this._envelopeValue(t);
        return val;
    }

    _envelopeValue(t) {
        const e = this.envelope;
        if (t < e.attack) return t / e.attack || 1;
        let t2 = t - e.attack;
        if (t2 < e.decay) return 1 - (1 - e.sustain) * (t2 / e.decay || 0);
        t2 -= e.decay;
        const sustainDur = this.duration - e.attack - e.decay - e.release;
        if (sustainDur > 0 && t2 < sustainDur) return e.sustain;
        t2 -= sustainDur;
        if (t2 < e.release) return e.sustain * (1 - t2 / e.release || 0);
        return 0;
    }

    generate() {
        const numSamples = Math.floor(this.duration * this.sampleRate);
        const channels = this.stereo ? 2 : 1;
        this.samples = Array.from({ length: channels }, () => []);
        for (let i = 0; i < numSamples; i++) {
            const t = i / this.sampleRate;
            const val = this._valueAt(t);
            const sample = Math.round(this.amp * val * 32767);
            for (let ch = 0; ch < channels; ch++) {
                this.samples[ch].push(sample);
            }
        }
    }

    saveWAV(filename) {
        const channels = this.samples.length;
        const numSamples = this.samples[0].length;
        const dataSize = numSamples * 2 * channels;
        const byteRate = this.sampleRate * 2 * channels;
        const buffer = Buffer.alloc(44 + dataSize);
        let offset = 0;
        const writeU32 = v => { buffer.writeUInt32LE(v, offset); offset += 4; };
        const writeU16 = v => { buffer.writeUInt16LE(v, offset); offset += 2; };
        buffer.write('RIFF', 0);
        writeU32(36 + dataSize);
        buffer.write('WAVE', 8);
        buffer.write('fmt ', 12);
        writeU32(16);
        writeU16(1);
        writeU16(channels);
        writeU32(this.sampleRate);
        writeU32(byteRate);
        writeU16(2 * channels);
        writeU16(16);
        buffer.write('data', offset);
        offset += 4;
        writeU32(dataSize);
        for (let i = 0; i < numSamples; i++) {
            for (let ch = 0; ch < channels; ch++) {
                buffer.writeInt16LE(this.samples[ch][i], offset);
                offset += 2;
            }
        }
        fs.writeFileSync(filename, buffer);
    }

    play(filename) {
        const platform = process.platform;
        let cmd;
        if (platform === 'win32') cmd = `start "" "${filename}"`;
        else if (platform === 'darwin') cmd = `afplay "${filename}"`;
        else cmd = `ffplay "${filename}" || aplay "${filename}" || mpg123 "${filename}"`;
        exec(cmd, (err) => { if (err) console.log('Playback error:', err.message); });
    }
}

function ask(q) { return new Promise(r => rl.question(q, r)); }

async function interactive() {
    console.log('=== Waveform Audio Generator ===');
    const types = ['sine', 'square', 'sawtooth', 'triangle', 'noise'];
    let wtype = await ask(`Type (${types.join('/')}) [sine]: `) || 'sine';
    if (!types.includes(wtype)) wtype = 'sine';
    const freq = parseFloat(await ask('Frequency (Hz) [440]: ') || '440') || 440;
    const amp = parseFloat(await ask('Amplitude (0.0-1.0) [0.8]: ') || '0.8') || 0.8;
    const dur = parseFloat(await ask('Duration (s) [2.0]: ') || '2.0') || 2.0;
    const rate = parseInt(await ask('Sample rate [44100]: ') || '44100') || 44100;
    const stereo = (await ask('Stereo? (y/n) [n]: ')).toLowerCase() === 'y';
    const adsrStr = await ask('ADSR? (Attack Decay Sustain Release) [none]: ');
    let env = null;
    if (adsrStr && adsrStr !== 'none') {
        const parts = adsrStr.split(/\s+/).map(Number);
        if (parts.length === 4) env = new Envelope(...parts);
    }
    let fname = await ask('Output file [output.wav]: ') || 'output.wav';
    if (!fname.endsWith('.wav')) fname += '.wav';
    const gen = new WaveGenerator({ freq, amp, duration: dur, sampleRate: rate, waveType: wtype, stereo, envelope: env });
    gen.generate();
    gen.saveWAV(fname);
    console.log(`Saved to ${fname}`);
    if ((await ask('Play? (y/n) [y]: ')).toLowerCase() !== 'n') gen.play(fname);
    rl.close();
}

function cli() {
    const args = require('minimist')(process.argv.slice(2));
    let env = null;
    if (args.adsr) {
        const parts = args.adsr.split(/\s+/).map(Number);
        if (parts.length === 4) env = new Envelope(...parts);
    }
    let sweepStart = null, sweepEnd = null;
    if (args.sweep) {
        const parts = args.sweep.split(/\s+/).map(Number);
        if (parts.length === 2) { sweepStart = parts[0]; sweepEnd = parts[1]; }
    }
    const gen = new WaveGenerator({
        freq: args.f || args.freq || 440,
        amp: args.a || args.amp || 0.8,
        duration: args.d || args.dur || 2.0,
        sampleRate: args.r || args.rate || 44100,
        waveType: args.t || args.type || 'sine',
        stereo: args.stereo || false,
        envelope: env,
        sweepStart, sweepEnd
    });
    gen.generate();
    const output = args.o || args.output || 'output.wav';
    gen.saveWAV(output);
    console.log(`Saved to ${output}`);
    if (!args['no-play']) gen.play(output);
}

if (process.argv.length > 2) cli(); else interactive();
