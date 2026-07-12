// Wave.java
import java.io.*;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.*;

class Envelope {
    double attack, decay, sustain, release;
    Envelope(double a, double d, double s, double r) { attack=a; decay=d; sustain=s; release=r; }
}

public class Wave {
    private double freq = 440, amp = 0.8, duration = 2.0;
    private int sampleRate = 44100;
    private String waveType = "sine";
    private boolean stereo = false;
    private Envelope envelope = null;
    private Double sweepStart = null, sweepEnd = null;
    private List<short[]> samples = new ArrayList<>();
    private Random rand = new Random();

    private double valueAt(double t) {
        double f = freq;
        if (sweepStart != null && sweepEnd != null)
            f = sweepStart + (sweepEnd - sweepStart) * (t / duration);
        double phase = 2 * Math.PI * f * t;
        double val = 0;
        switch (waveType) {
            case "sine": val = Math.sin(phase); break;
            case "square": val = Math.sin(phase) >= 0 ? 1 : -1; break;
            case "sawtooth": val = 2*(phase/(2*Math.PI)-Math.floor(phase/(2*Math.PI)+0.5)); break;
            case "triangle": val = 2*Math.abs(2*(phase/(2*Math.PI)-Math.floor(phase/(2*Math.PI)+0.5)))-1; break;
            case "noise": val = rand.nextDouble()*2-1; break;
        }
        if (envelope != null) val *= envelopeValue(t);
        return val;
    }

    private double envelopeValue(double t) {
        Envelope e = envelope;
        if (t < e.attack) return t / (e.attack > 0 ? e.attack : 1);
        t -= e.attack;
        if (t < e.decay) return 1 - (1 - e.sustain) * (t / (e.decay > 0 ? e.decay : 1));
        t -= e.decay;
        double sustainDur = duration - e.attack - e.decay - e.release;
        if (sustainDur > 0 && t < sustainDur) return e.sustain;
        t -= sustainDur;
        if (t < e.release) return e.sustain * (1 - t / (e.release > 0 ? e.release : 1));
        return 0;
    }

    public void generate() {
        int numSamples = (int)(duration * sampleRate);
        int channels = stereo ? 2 : 1;
        samples.clear();
        for (int ch = 0; ch < channels; ch++) samples.add(new short[numSamples]);
        for (int i = 0; i < numSamples; i++) {
            double t = (double)i / sampleRate;
            double val = valueAt(t);
            short s = (short)(amp * val * 32767);
            for (int ch = 0; ch < channels; ch++) samples.get(ch)[i] = s;
        }
    }

    public void saveWAV(String filename) throws IOException {
        try (FileOutputStream fos = new FileOutputStream(filename);
             DataOutputStream dos = new DataOutputStream(fos)) {
            int channels = samples.size();
            int numSamples = samples.get(0).length;
            int dataSize = numSamples * 2 * channels;
            int byteRate = sampleRate * 2 * channels;
            dos.writeBytes("RIFF");
            dos.writeInt(ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(36+dataSize).array());
            dos.writeBytes("WAVE");
            dos.writeBytes("fmt ");
            dos.writeInt(16);
            dos.writeShort(1);
            dos.writeShort(channels);
            dos.writeInt(sampleRate);
            dos.writeInt(byteRate);
            dos.writeShort(2*channels);
            dos.writeShort(16);
            dos.writeBytes("data");
            dos.writeInt(dataSize);
            for (int i = 0; i < numSamples; i++) {
                for (int ch = 0; ch < channels; ch++) dos.writeShort(samples.get(ch)[i]);
            }
        }
    }

    public void play(String filename) {
        String os = System.getProperty("os.name").toLowerCase();
        try {
            if (os.contains("win")) Runtime.getRuntime().exec(new String[]{"cmd","/c","start",filename});
            else if (os.contains("mac")) Runtime.getRuntime().exec(new String[]{"afplay",filename});
            else {
                String[] players = {"ffplay","aplay","mpg123"};
                for (String p : players) {
                    try { Runtime.getRuntime().exec(new String[]{p,filename}); return; } catch (Exception e) {}
                }
            }
        } catch (Exception e) { System.out.println("Playback error: "+e.getMessage()); }
    }

    public static void main(String[] args) throws Exception {
        if (args.length > 0) {
            Map<String,String> params = new HashMap<>();
            for (int i=0; i<args.length; i++) {
                if (args[i].startsWith("-")) {
                    String key = args[i].replaceFirst("^-+","");
                    if (i+1 < args.length && !args[i+1].startsWith("-"))
                        params.put(key, args[++i]);
                    else params.put(key, "true");
                }
            }
            Wave gen = new Wave();
            if (params.containsKey("f")) gen.freq = Double.parseDouble(params.get("f"));
            if (params.containsKey("t")) gen.waveType = params.get("t");
            if (params.containsKey("a")) gen.amp = Double.parseDouble(params.get("a"));
            if (params.containsKey("d")) gen.duration = Double.parseDouble(params.get("d"));
            if (params.containsKey("r")) gen.sampleRate = Integer.parseInt(params.get("r"));
            if (params.containsKey("stereo")) gen.stereo = true;
            if (params.containsKey("adsr")) {
                String[] parts = params.get("adsr").split(" ");
                if (parts.length==4) gen.envelope = new Envelope(Double.parseDouble(parts[0]), Double.parseDouble(parts[1]),
                                                                 Double.parseDouble(parts[2]), Double.parseDouble(parts[3]));
            }
            if (params.containsKey("sweep")) {
                String[] parts = params.get("sweep").split(" ");
                if (parts.length==2) { gen.sweepStart = Double.parseDouble(parts[0]); gen.sweepEnd = Double.parseDouble(parts[1]); }
            }
            String output = params.getOrDefault("o", "output.wav");
            gen.generate();
            gen.saveWAV(output);
            System.out.println("Saved to "+output);
            if (!params.containsKey("no-play")) gen.play(output);
        } else {
            BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
            System.out.println("=== Waveform Audio Generator ===");
            System.out.print("Type (sine/square/sawtooth/triangle/noise) [sine]: ");
            String wtype = br.readLine(); if (wtype.isEmpty()) wtype="sine";
            System.out.print("Frequency (Hz) [440]: ");
            double freq = Double.parseDouble(br.readLine().isEmpty()?"440":br.readLine());
            System.out.print("Amplitude (0.0-1.0) [0.8]: ");
            double amp = Double.parseDouble(br.readLine().isEmpty()?"0.8":br.readLine());
            System.out.print("Duration (s) [2.0]: ");
            double dur = Double.parseDouble(br.readLine().isEmpty()?"2.0":br.readLine());
            System.out.print("Sample rate [44100]: ");
            int rate = Integer.parseInt(br.readLine().isEmpty()?"44100":br.readLine());
            System.out.print("Stereo? (y/n) [n]: ");
            boolean stereo = br.readLine().equalsIgnoreCase("y");
            System.out.print("ADSR? (Attack Decay Sustain Release) [none]: ");
            String adsrStr = br.readLine();
            Envelope env = null;
            if (!adsrStr.isEmpty() && !adsrStr.equals("none")) {
                String[] parts = adsrStr.split(" ");
                if (parts.length==4) env = new Envelope(Double.parseDouble(parts[0]), Double.parseDouble(parts[1]),
                                                        Double.parseDouble(parts[2]), Double.parseDouble(parts[3]));
            }
            System.out.print("Output file [output.wav]: ");
            String fname = br.readLine(); if (fname.isEmpty()) fname="output.wav";
            if (!fname.endsWith(".wav")) fname+=".wav";
            Wave gen = new Wave();
            gen.freq = freq; gen.amp = amp; gen.duration = dur; gen.sampleRate = rate;
            gen.waveType = wtype; gen.stereo = stereo; gen.envelope = env;
            gen.generate();
            gen.saveWAV(fname);
            System.out.println("Saved to "+fname);
            System.out.print("Play? (y/n) [y]: ");
            if (!br.readLine().equalsIgnoreCase("n")) gen.play(fname);
        }
    }
}
