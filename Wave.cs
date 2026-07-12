// Wave.cs
using System;
using System.Collections.Generic;
using System.IO;
using System.Diagnostics;
using System.Runtime.InteropServices;

class Envelope {
    public double Attack, Decay, Sustain, Release;
    public Envelope(double a, double d, double s, double r) { Attack = a; Decay = d; Sustain = s; Release = r; }
}

class WaveGenerator {
    public double Freq { get; set; } = 440;
    public double Amp { get; set; } = 0.8;
    public double Duration { get; set; } = 2.0;
    public int SampleRate { get; set; } = 44100;
    public string WaveType { get; set; } = "sine";
    public bool Stereo { get; set; } = false;
    public Envelope Envelope { get; set; } = null;
    public double? SweepStart { get; set; } = null;
    public double? SweepEnd { get; set; } = null;
    private List<short[]> samples = new List<short[]>();

    private double ValueAt(double t) {
        double freq = Freq;
        if (SweepStart.HasValue && SweepEnd.HasValue)
            freq = SweepStart.Value + (SweepEnd.Value - SweepStart.Value) * (t / Duration);
        double phase = 2 * Math.PI * freq * t;
        double val = 0;
        switch (WaveType) {
            case "sine": val = Math.Sin(phase); break;
            case "square": val = Math.Sin(phase) >= 0 ? 1 : -1; break;
            case "sawtooth": val = 2 * (phase / (2 * Math.PI) - Math.Floor(phase / (2 * Math.PI) + 0.5)); break;
            case "triangle": val = 2 * Math.Abs(2 * (phase / (2 * Math.PI) - Math.Floor(phase / (2 * Math.PI) + 0.5))) - 1; break;
            case "noise": val = new Random().NextDouble() * 2 - 1; break;
            default: val = 0; break;
        }
        if (Envelope != null) val *= EnvelopeValue(t);
        return val;
    }

    private double EnvelopeValue(double t) {
        var e = Envelope;
        if (t < e.Attack) return t / (e.Attack > 0 ? e.Attack : 1);
        t -= e.Attack;
        if (t < e.Decay) return 1 - (1 - e.Sustain) * (t / (e.Decay > 0 ? e.Decay : 1));
        t -= e.Decay;
        double sustainDur = Duration - e.Attack - e.Decay - e.Release;
        if (sustainDur > 0 && t < sustainDur) return e.Sustain;
        t -= sustainDur;
        if (t < e.Release) return e.Sustain * (1 - t / (e.Release > 0 ? e.Release : 1));
        return 0;
    }

    public void Generate() {
        int numSamples = (int)(Duration * SampleRate);
        int channels = Stereo ? 2 : 1;
        samples.Clear();
        for (int ch = 0; ch < channels; ch++) samples.Add(new short[numSamples]);
        for (int i = 0; i < numSamples; i++) {
            double t = (double)i / SampleRate;
            double val = ValueAt(t);
            short sample = (short)(Amp * val * 32767);
            for (int ch = 0; ch < channels; ch++) samples[ch][i] = sample;
        }
    }

    public void SaveWAV(string filename) {
        using var fs = new FileStream(filename, FileMode.Create);
        using var bw = new BinaryWriter(fs);
        int channels = samples.Count;
        int numSamples = samples[0].Length;
        int dataSize = numSamples * 2 * channels;
        int byteRate = SampleRate * 2 * channels;
        bw.Write("RIFF".ToCharArray()); bw.Write(36 + dataSize);
        bw.Write("WAVE".ToCharArray());
        bw.Write("fmt ".ToCharArray()); bw.Write(16);
        bw.Write((short)1); bw.Write((short)channels);
        bw.Write(SampleRate); bw.Write(byteRate);
        bw.Write((short)(2 * channels)); bw.Write((short)16);
        bw.Write("data".ToCharArray()); bw.Write(dataSize);
        for (int i = 0; i < numSamples; i++) {
            for (int ch = 0; ch < channels; ch++) bw.Write(samples[ch][i]);
        }
    }

    public void Play(string filename) {
        try {
            if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
                Process.Start("cmd", $"/c start {filename}");
            else if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
                Process.Start("afplay", filename);
            else {
                string[] players = { "ffplay", "aplay", "mpg123" };
                foreach (var p in players) {
                    try { Process.Start(p, filename); return; } catch { }
                }
            }
        } catch { }
    }
}

class Program {
    static void Main(string[] args) {
        if (args.Length > 0) {
            var dict = new Dictionary<string, string>();
            for (int i = 0; i < args.Length; i++) {
                if (args[i].StartsWith("-")) {
                    string key = args[i].TrimStart('-');
                    if (i + 1 < args.Length && !args[i+1].StartsWith("-"))
                        dict[key] = args[++i];
                    else dict[key] = "true";
                }
            }
            var gen = new WaveGenerator();
            if (dict.ContainsKey("f")) gen.Freq = double.Parse(dict["f"]);
            if (dict.ContainsKey("t")) gen.WaveType = dict["t"];
            if (dict.ContainsKey("a")) gen.Amp = double.Parse(dict["a"]);
            if (dict.ContainsKey("d")) gen.Duration = double.Parse(dict["d"]);
            if (dict.ContainsKey("r")) gen.SampleRate = int.Parse(dict["r"]);
            if (dict.ContainsKey("stereo")) gen.Stereo = true;
            if (dict.ContainsKey("adsr")) {
                var parts = dict["adsr"].Split(' ');
                if (parts.Length == 4)
                    gen.Envelope = new Envelope(double.Parse(parts[0]), double.Parse(parts[1]),
                                                double.Parse(parts[2]), double.Parse(parts[3]));
            }
            if (dict.ContainsKey("sweep")) {
                var parts = dict["sweep"].Split(' ');
                if (parts.Length == 2) { gen.SweepStart = double.Parse(parts[0]); gen.SweepEnd = double.Parse(parts[1]); }
            }
            string output = dict.ContainsKey("o") ? dict["o"] : "output.wav";
            gen.Generate();
            gen.SaveWAV(output);
            Console.WriteLine($"Saved to {output}");
            if (!dict.ContainsKey("no-play")) gen.Play(output);
        } else {
            Console.WriteLine("=== Waveform Audio Generator ===");
            Console.Write("Type (sine/square/sawtooth/triangle/noise) [sine]: ");
            string wtype = Console.ReadLine(); if (string.IsNullOrEmpty(wtype)) wtype = "sine";
            Console.Write("Frequency (Hz) [440]: ");
            double.TryParse(Console.ReadLine(), out double freq); if (freq <= 0) freq = 440;
            Console.Write("Amplitude (0.1-1.0) [0.8]: ");
            double.TryParse(Console.ReadLine(), out double amp); if (amp < 0 || amp > 1) amp = 0.8;
            Console.Write("Duration (s) [2.0]: ");
            double.TryParse(Console.ReadLine(), out double dur); if (dur <= 0) dur = 2.0;
            Console.Write("Sample rate [44100]: ");
            int.TryParse(Console.ReadLine(), out int rate); if (rate <= 0) rate = 44100;
            Console.Write("Stereo? (y/n) [n]: ");
            bool stereo = Console.ReadLine()?.ToLower() == "y";
            Console.Write("ADSR? (Attack Decay Sustain Release) [none]: ");
            string adsrStr = Console.ReadLine();
            Envelope env = null;
            if (!string.IsNullOrEmpty(adsrStr) && adsrStr != "none") {
                var parts = adsrStr.Split(' ');
                if (parts.Length == 4) env = new Envelope(double.Parse(parts[0]), double.Parse(parts[1]),
                                                          double.Parse(parts[2]), double.Parse(parts[3]));
            }
            Console.Write("Output file [output.wav]: ");
            string fname = Console.ReadLine(); if (string.IsNullOrEmpty(fname)) fname = "output.wav";
            if (!fname.EndsWith(".wav")) fname += ".wav";
            var gen = new WaveGenerator { Freq = freq, Amp = amp, Duration = dur, SampleRate = rate,
                                          WaveType = wtype, Stereo = stereo, Envelope = env };
            gen.Generate();
            gen.SaveWAV(fname);
            Console.WriteLine($"Saved to {fname}");
            Console.Write("Play? (y/n) [y]: ");
            if (Console.ReadLine()?.ToLower() != "n") gen.Play(fname);
        }
    }
}
