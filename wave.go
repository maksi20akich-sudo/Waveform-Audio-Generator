// wave.go
package main

import (
	"bufio"
	"flag"
	"fmt"
	"math"
	"os"
	"os/exec"
	"runtime"
	"strconv"
	"strings"
)

type Envelope struct {
	Attack  float64 // seconds
	Decay   float64
	Sustain float64 // amplitude level (0-1)
	Release float64
}

type WaveGen struct {
	Freq       float64
	Amp        float64
	Duration   float64
	SampleRate int
	WaveType   string
	Stereo     bool
	Envelope   *Envelope
	SweepStart float64
	SweepEnd   float64
	samples    [][]int16 // [channel][sample]
}

func NewWaveGen() *WaveGen {
	return &WaveGen{SampleRate: 44100, Amp: 0.8, Duration: 2.0, WaveType: "sine"}
}

func (w *WaveGen) generate() {
	numSamples := int(w.Duration * float64(w.SampleRate))
	channels := 1
	if w.Stereo {
		channels = 2
	}
	w.samples = make([][]int16, channels)
	for ch := 0; ch < channels; ch++ {
		w.samples[ch] = make([]int16, numSamples)
	}
	for i := 0; i < numSamples; i++ {
		t := float64(i) / float64(w.SampleRate)
		// Frequency sweep
		freq := w.Freq
		if w.SweepEnd > 0 {
			freq = w.SweepStart + (w.SweepEnd-w.SweepStart)*(t/w.Duration)
		}
		phase := 2 * math.Pi * freq * t
		var val float64
		switch w.WaveType {
		case "sine":
			val = math.Sin(phase)
		case "square":
			val = 1.0
			if math.Sin(phase) < 0 {
				val = -1.0
			}
		case "sawtooth":
			val = 2*(phase/(2*math.Pi)-math.Floor(phase/(2*math.Pi)+0.5))
		case "triangle":
			val = 2*math.Abs(2*(phase/(2*math.Pi)-math.Floor(phase/(2*math.Pi)+0.5))) - 1
		case "noise":
			val = 2*rand.Float64() - 1
		default:
			val = 0
		}
		// ADSR envelope
		if w.Envelope != nil {
			env := w.computeEnvelope(t)
			val *= env
		}
		sampleVal := int16(w.Amp * val * 32767)
		for ch := 0; ch < channels; ch++ {
			w.samples[ch][i] = sampleVal
		}
	}
}

func (w *WaveGen) computeEnvelope(t float64) float64 {
	e := w.Envelope
	dur := w.Duration
	if t < e.Attack {
		return t / e.Attack
	}
	t -= e.Attack
	if t < e.Decay {
		return 1.0 - (1.0-e.Sustain)*(t/e.Decay)
	}
	t -= e.Decay
	if t < dur-e.Release-e.Attack-e.Decay {
		return e.Sustain
	}
	t -= (dur - e.Release - e.Attack - e.Decay)
	if t < e.Release {
		return e.Sustain * (1.0 - t/e.Release)
	}
	return 0
}

func (w *WaveGen) saveWAV(filename string) error {
	file, err := os.Create(filename)
	if err != nil {
		return err
	}
	defer file.Close()
	channels := len(w.samples)
	numSamples := len(w.samples[0])
	dataSize := numSamples * 2 * channels
	byteRate := w.SampleRate * 2 * channels
	blockAlign := 2 * channels
	// RIFF header
	file.WriteString("RIFF")
	writeU32(file, uint32(36+dataSize))
	file.WriteString("WAVE")
	// fmt chunk
	file.WriteString("fmt ")
	writeU32(file, 16)
	writeU16(file, 1) // PCM
	writeU16(file, uint16(channels))
	writeU32(file, uint32(w.SampleRate))
	writeU32(file, uint32(byteRate))
	writeU16(file, uint16(blockAlign))
	writeU16(file, 16) // bits per sample
	// data chunk
	file.WriteString("data")
	writeU32(file, uint32(dataSize))
	// samples interleaved
	for i := 0; i < numSamples; i++ {
		for ch := 0; ch < channels; ch++ {
			writeI16(file, w.samples[ch][i])
		}
	}
	return nil
}

func writeU32(f *os.File, v uint32) {
	b := []byte{byte(v), byte(v >> 8), byte(v >> 16), byte(v >> 24)}
	f.Write(b)
}
func writeU16(f *os.File, v uint16) {
	b := []byte{byte(v), byte(v >> 8)}
	f.Write(b)
}
func writeI16(f *os.File, v int16) {
	u := uint16(v)
	f.Write([]byte{byte(u), byte(u >> 8)})
}

func (w *WaveGen) play(filename string) {
	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "windows":
		cmd = exec.Command("cmd", "/c", "start", filename)
	case "darwin":
		cmd = exec.Command("afplay", filename)
	default:
		players := []string{"ffplay", "aplay", "mpg123"}
		for _, p := range players {
			if _, err := exec.LookPath(p); err == nil {
				cmd = exec.Command(p, filename)
				break
			}
		}
	}
	if cmd != nil {
		cmd.Run()
	}
}

func interactive() {
	reader := bufio.NewReader(os.Stdin)
	fmt.Println("=== Waveform Audio Generator ===")
	types := []string{"sine", "square", "sawtooth", "triangle", "noise"}
	fmt.Printf("Type (%s) [sine]: ", strings.Join(types, "/"))
	wtype, _ := reader.ReadString('\n')
	wtype = strings.TrimSpace(wtype)
	if wtype == "" || !contains(types, wtype) {
		wtype = "sine"
	}
	fmt.Print("Frequency (Hz) [440]: ")
	freq := getFloat(reader, 440)
	fmt.Print("Amplitude (0.0-1.0) [0.8]: ")
	amp := getFloat(reader, 0.8)
	fmt.Print("Duration (s) [2.0]: ")
	dur := getFloat(reader, 2.0)
	fmt.Print("Sample rate [44100]: ")
	rate := getInt(reader, 44100)
	fmt.Print("Stereo? (y/n) [n]: ")
	stereo, _ := reader.ReadString('\n')
	stereo = strings.TrimSpace(stereo)
	fmt.Print("ADSR? (Attack Decay Sustain Release) [none]: ")
	adsrStr, _ := reader.ReadString('\n')
	adsrStr = strings.TrimSpace(adsrStr)
	var env *Envelope
	if adsrStr != "" && adsrStr != "none" {
		parts := strings.Fields(adsrStr)
		if len(parts) == 4 {
			a, _ := strconv.ParseFloat(parts[0], 64)
			d, _ := strconv.ParseFloat(parts[1], 64)
			s, _ := strconv.ParseFloat(parts[2], 64)
			r, _ := strconv.ParseFloat(parts[3], 64)
			env = &Envelope{Attack: a, Decay: d, Sustain: s, Release: r}
		}
	}
	fmt.Print("Output file [output.wav]: ")
	fname, _ := reader.ReadString('\n')
	fname = strings.TrimSpace(fname)
	if fname == "" {
		fname = "output.wav"
	}
	if !strings.HasSuffix(fname, ".wav") {
		fname += ".wav"
	}
	gen := &WaveGen{
		Freq:       freq,
		Amp:        amp,
		Duration:   dur,
		SampleRate: rate,
		WaveType:   wtype,
		Stereo:     stereo == "y",
		Envelope:   env,
	}
	gen.generate()
	if err := gen.saveWAV(fname); err != nil {
		fmt.Println("Error saving:", err)
		return
	}
	fmt.Printf("Saved to %s\n", fname)
	fmt.Print("Play? (y/n) [y]: ")
	play, _ := reader.ReadString('\n')
	if strings.ToLower(strings.TrimSpace(play)) != "n" {
		gen.play(fname)
	}
}

func getFloat(r *bufio.Reader, def float64) float64 {
	s, _ := r.ReadString('\n')
	s = strings.TrimSpace(s)
	if s == "" {
		return def
	}
	v, err := strconv.ParseFloat(s, 64)
	if err != nil {
		return def
	}
	return v
}
func getInt(r *bufio.Reader, def int) int {
	s, _ := r.ReadString('\n')
	s = strings.TrimSpace(s)
	if s == "" {
		return def
	}
	v, err := strconv.Atoi(s)
	if err != nil {
		return def
	}
	return v
}
func contains(s []string, e string) bool {
	for _, a := range s {
		if a == e {
			return true
		}
	}
	return false
}

func cli() {
	gen := &WaveGen{SampleRate: 44100, Amp: 0.8, Duration: 2.0, WaveType: "sine"}
	flag.Float64Var(&gen.Freq, "f", 440, "Frequency")
	flag.StringVar(&gen.WaveType, "t", "sine", "Type")
	flag.Float64Var(&gen.Amp, "a", 0.8, "Amplitude")
	flag.Float64Var(&gen.Duration, "d", 2.0, "Duration")
	flag.IntVar(&gen.SampleRate, "r", 44100, "Sample rate")
	output := flag.String("o", "output.wav", "Output file")
	stereo := flag.Bool("stereo", false, "Stereo")
	adsrStr := flag.String("adsr", "", "ADSR envelope: attack decay sustain release")
	sweepStr := flag.String("sweep", "", "Sweep: start_freq end_freq")
	noPlay := flag.Bool("no-play", false, "Skip playback")
	flag.Parse()

	if *sweepStr != "" {
		parts := strings.Fields(*sweepStr)
		if len(parts) == 2 {
			gen.SweepStart, _ = strconv.ParseFloat(parts[0], 64)
			gen.SweepEnd, _ = strconv.ParseFloat(parts[1], 64)
		}
	}
	if *adsrStr != "" {
		parts := strings.Fields(*adsrStr)
		if len(parts) == 4 {
			a, _ := strconv.ParseFloat(parts[0], 64)
			d, _ := strconv.ParseFloat(parts[1], 64)
			s, _ := strconv.ParseFloat(parts[2], 64)
			r, _ := strconv.ParseFloat(parts[3], 64)
			gen.Envelope = &Envelope{Attack: a, Decay: d, Sustain: s, Release: r}
		}
	}
	gen.Stereo = *stereo
	gen.generate()
	if err := gen.saveWAV(*output); err != nil {
		fmt.Println("Error saving:", err)
		return
	}
	fmt.Printf("Saved to %s\n", *output)
	if !*noPlay {
		gen.play(*output)
	}
}

func main() {
	if len(os.Args) > 1 {
		cli()
	} else {
		interactive()
	}
}
