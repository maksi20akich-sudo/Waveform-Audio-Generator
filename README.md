🌊 Waveform Audio Generator (Enhanced)

A powerful **audio waveform generator** that synthesises pure tones (sine, square, sawtooth, triangle, noise) and saves them as WAV files, with optional stereo, ADSR envelope, and system playback.  
Ideal for audio testing, sound design, and learning DSP.

## ✨ Features (Enhanced)
- **5 waveform types** – sine, square, sawtooth, triangle, white noise.
- **Stereo support** – generate left/right channels independently.
- **ADSR envelope** – Attack, Decay, Sustain, Release for realistic sounds.
- **Frequency sweep** – optional linear frequency sweep (start/end frequency).
- **WAV export** – 16‑bit PCM, mono or stereo.
- **Command‑line & interactive** – both modes supported.
- **System playback** – automatically plays the generated file.

## 🗂 Languages & Files
| Language          | File      |
|-------------------|-----------|
| Go                | `wave.go` |
| Python            | `wave.py` |
| JavaScript (Node) | `wave.js` |
| C#                | `Wave.cs` |
| Java              | `Wave.java` |
| Ruby              | `wave.rb` |
| Swift             | `wave.swift` |

## 🚀 How to Run
Each file is standalone – run with the appropriate interpreter/compiler.

| Language | Command (interactive) | Command (CLI) |
|----------|----------------------|---------------|
| Go       | `go run wave.go` | `go run wave.go -f 440 -t sine -o out.wav` |
| Python   | `python wave.py` | `python wave.py -f 440 -t sine -o out.wav` |
| JavaScript | `node wave.js` | `node wave.js --freq 440 --type sine --output out.wav` |
| C#       | `dotnet run` | `dotnet run -- -f 440 -t sine -o out.wav` |
| Java     | `java Wave` | `java Wave -f 440 -t sine -o out.wav` |
| Ruby     | `ruby wave.rb` | `ruby wave.rb -f 440 -t sine -o out.wav` |
| Swift    | `swift wave.swift` | `swift wave.swift -f 440 -t sine -o out.wav` |

## 📊 Example (Interactive)
=== Waveform Audio Generator ===
Type (sine/square/sawtooth/triangle/noise) [sine]: sine
Frequency (Hz) [440]: 440
Amplitude (0.0-1.0) [0.8]: 0.8
Duration (s) [2.0]: 2.0
Sample rate [44100]: 44100
Stereo? (y/n) [n]: n
ADSR? (Attack Decay Sustain Release) [none]: 0.1 0.2 0.7 0.3
Output file [output.wav]: sine_440.wav
Generating... Saved to sine_440.wav
Playing...

text

## 🔧 CLI Options (Common)
| Option | Description |
|--------|-------------|
| `-f, --freq` | Frequency in Hz (default: 440) |
| `-t, --type` | Waveform type |
| `-a, --amp` | Amplitude (0‑1, default: 0.8) |
| `-d, --dur` | Duration in seconds (default: 2.0) |
| `-r, --rate` | Sample rate (default: 44100) |
| `-o, --output` | Output WAV filename |
| `--stereo` | Generate stereo (default: mono) |
| `--adsr` | ADSR envelope: `attack decay sustain release` (floats) |
| `--sweep` | Frequency sweep: `start_freq end_freq` |
| `--no-play` | Skip playback |

## 📁 WAV Format
- **Format**: PCM, 16‑bit, mono or stereo.
- **Envelope**: linear amplitude scaling per sample.

## 🤝 Contributing
Add more effects (chorus, reverb) or real‑time output – PRs welcome!

## 📜 License
MIT – use freely.
