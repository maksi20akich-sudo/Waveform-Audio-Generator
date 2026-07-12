# wave.rb
require 'optparse'
require 'fileutils'

class Envelope
  attr_reader :attack, :decay, :sustain, :release
  def initialize(a, d, s, r)
    @attack, @decay, @sustain, @release = a, d, s, r
  end
end

class WaveGenerator
  attr_accessor :freq, :amp, :duration, :sample_rate, :wave_type, :stereo, :envelope, :sweep_start, :sweep_end

  def initialize(opts = {})
    @freq = opts[:freq] || 440
    @amp = opts[:amp] || 0.8
    @duration = opts[:duration] || 2.0
    @sample_rate = opts[:sample_rate] || 44100
    @wave_type = opts[:wave_type] || 'sine'
    @stereo = opts[:stereo] || false
    @envelope = opts[:envelope]
    @sweep_start = opts[:sweep_start]
    @sweep_end = opts[:sweep_end]
    @samples = []
  end

  def value_at(t)
    freq = @freq
    if @sweep_start && @sweep_end
      freq = @sweep_start + (@sweep_end - @sweep_start) * (t / @duration)
    end
    phase = 2 * Math::PI * freq * t
    val = case @wave_type
          when 'sine' then Math.sin(phase)
          when 'square' then Math.sin(phase) >= 0 ? 1 : -1
          when 'sawtooth' then 2 * (phase / (2 * Math::PI) - (phase / (2 * Math::PI) + 0.5).floor)
          when 'triangle' then 2 * (2 * (phase / (2 * Math::PI) - (phase / (2 * Math::PI) + 0.5).floor).abs) - 1
          when 'noise' then rand(-1.0..1.0)
          else 0
          end
    val *= envelope_value(t) if @envelope
    val
  end

  def envelope_value(t)
    e = @envelope
    if t < e.attack
      return t / (e.attack > 0 ? e.attack : 1)
    end
    t -= e.attack
    if t < e.decay
      return 1 - (1 - e.sustain) * (t / (e.decay > 0 ? e.decay : 1))
    end
    t -= e.decay
    sustain_dur = @duration - e.attack - e.decay - e.release
    if sustain_dur > 0 && t < sustain_dur
      return e.sustain
    end
    t -= sustain_dur
    if t < e.release
      return e.sustain * (1 - t / (e.release > 0 ? e.release : 1))
    end
    0
  end

  def generate
    num_samples = (@duration * @sample_rate).to_i
    channels = @stereo ? 2 : 1
    @samples = Array.new(channels) { [] }
    num_samples.times do |i|
      t = i / @sample_rate.to_f
      val = value_at(t)
      sample = (@amp * val * 32767).round
      channels.times { |ch| @samples[ch] << sample }
    end
  end

  def save_wav(filename)
    File.open(filename, 'wb') do |f|
      channels = @samples.size
      num_samples = @samples[0].size
      data_size = num_samples * 2 * channels
      byte_rate = @sample_rate * 2 * channels
      f.write('RIFF')
      f.write([36 + data_size].pack('V'))
      f.write('WAVE')
      f.write('fmt ')
      f.write([16, 1, channels, @sample_rate, byte_rate, 2 * channels, 16].pack('VvvVVvv'))
      f.write('data')
      f.write([data_size].pack('V'))
      num_samples.times do |i|
        channels.times { |ch| f.write([@samples[ch][i]].pack('v')) }
      end
    end
  end

  def play(filename)
    os = RUBY_PLATFORM
    cmd = nil
    if os =~ /mswin|mingw|windows/
      cmd = "start #{filename}"
    elsif os =~ /darwin/
      cmd = "afplay #{filename}"
    else
      players = ['ffplay', 'aplay', 'mpg123']
      found = players.find { |p| system("which #{p} > /dev/null 2>&1") }
      cmd = "#{found} #{filename}" if found
    end
    system(cmd) if cmd
  end
end

def interactive
  puts "=== Waveform Audio Generator ==="
  types = ['sine', 'square', 'sawtooth', 'triangle', 'noise']
  print "Type (#{types.join('/')}) [sine]: "
  wtype = gets.chomp.strip
  wtype = 'sine' if wtype.empty? || !types.include?(wtype)
  print "Frequency (Hz) [440]: "
  freq = gets.to_f; freq = 440 if freq <= 0
  print "Amplitude (0.0-1.0) [0.8]: "
  amp = gets.to_f; amp = 0.8 if amp < 0 || amp > 1
  print "Duration (s) [2.0]: "
  dur = gets.to_f; dur = 2.0 if dur <= 0
  print "Sample rate [44100]: "
  rate = gets.to_i; rate = 44100 if rate <= 0
  print "Stereo? (y/n) [n]: "
  stereo = gets.chomp.downcase == 'y'
  print "ADSR? (Attack Decay Sustain Release) [none]: "
  adsr_str = gets.chomp.strip
  env = nil
  if adsr_str != '' && adsr_str != 'none'
    parts = adsr_str.split.map(&:to_f)
    env = Envelope.new(*parts) if parts.size == 4
  end
  print "Output file [output.wav]: "
  fname = gets.chomp.strip
  fname = 'output.wav' if fname.empty?
  fname += '.wav' unless fname.end_with?('.wav')
  gen = WaveGenerator.new(freq: freq, amp: amp, duration: dur, sample_rate: rate,
                          wave_type: wtype, stereo: stereo, envelope: env)
  gen.generate
  gen.save_wav(fname)
  puts "Saved to #{fname}"
  print "Play? (y/n) [y]: "
  play = gets.chomp.downcase
  gen.play(fname) unless play == 'n'
end

def cli
  options = {}
  OptionParser.new do |opts|
    opts.on('-f FREQ', '--freq FREQ', Float) { |v| options[:freq] = v }
    opts.on('-t TYPE', '--type TYPE') { |v| options[:type] = v }
    opts.on('-a AMP', '--amp AMP', Float) { |v| options[:amp] = v }
    opts.on('-d DUR', '--dur DUR', Float) { |v| options[:dur] = v }
    opts.on('-r RATE', '--rate RATE', Integer) { |v| options[:rate] = v }
    opts.on('-o OUTPUT', '--output OUTPUT') { |v| options[:output] = v }
    opts.on('--stereo', 'Stereo') { options[:stereo] = true }
    opts.on('--adsr ADSR', 'Attack Decay Sustain Release') { |v| options[:adsr] = v }
    opts.on('--sweep SWEEP', 'Start End') { |v| options[:sweep] = v }
    opts.on('--no-play', 'Skip playback') { options[:no_play] = true }
  end.parse!
  freq = options[:freq] || 440
  wtype = options[:type] || 'sine'
  amp = options[:amp] || 0.8
  dur = options[:dur] || 2.0
  rate = options[:rate] || 44100
  stereo = options[:stereo] || false
  output = options[:output] || 'output.wav'
  env = nil
  if options[:adsr]
    parts = options[:adsr].split.map(&:to_f)
    env = Envelope.new(*parts) if parts.size == 4
  end
  sweep_start = sweep_end = nil
  if options[:sweep]
    parts = options[:sweep].split.map(&:to_f)
    sweep_start, sweep_end = parts if parts.size == 2
  end
  gen = WaveGenerator.new(freq: freq, amp: amp, duration: dur, sample_rate: rate,
                          wave_type: wtype, stereo: stereo, envelope: env,
                          sweep_start: sweep_start, sweep_end: sweep_end)
  gen.generate
  gen.save_wav(output)
  puts "Saved to #{output}"
  gen.play(output) unless options[:no_play]
end

if ARGV.empty?
  interactive
else
  cli
end
