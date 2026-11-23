# frozen_string_literal: true

# Times reading a synthetic 24-hour activity: a trackpoint every second, with
# position, altitude, distance, heart rate and the Activity Extension's speed,
# running cadence and power. The values are made up.
#
#   bundle exec ruby -Ilib bench/read_24h.rb [path]
#
# The file is written to path (default: tmp/24h.tcx) unless it exists.
# Prints the best of three CPU times for streaming the messages and for
# building the Activity view.
require "fileutils"
require "tcxkit"

path = ARGV[0] || File.expand_path("../tmp/24h.tcx", __dir__)
unless File.exist?(path)
  FileUtils.mkdir_p(File.dirname(path))
  start = Time.utc(2026, 1, 1)
  File.open(path, "w") do |file|
    file << %(<?xml version="1.0" encoding="UTF-8"?>\n<TrainingCenterDatabase xmlns="#{TcxKit::NAMESPACE}" ) +
            %(xmlns:ns3="#{TcxKit::ACTIVITY_EXTENSION_NAMESPACE}"><Activities><Activity Sport="Running">) +
            %(<Id>2026-01-01T00:00:00Z</Id><Lap StartTime="2026-01-01T00:00:00Z"><TotalTimeSeconds>86400</TotalTimeSeconds>) +
            %(<DistanceMeters>216000</DistanceMeters><Calories>1</Calories><Intensity>Active</Intensity><TriggerMethod>Manual</TriggerMethod><Track>\n)
    86_400.times do |i|
      file << "<Trackpoint><Time>#{(start + i).strftime('%FT%TZ')}</Time><Position><LatitudeDegrees>#{10 + (i * 1e-6)}</LatitudeDegrees>" \
              "<LongitudeDegrees>#{20 + (i * 1e-6)}</LongitudeDegrees></Position><AltitudeMeters>12.5</AltitudeMeters>" \
              "<DistanceMeters>#{i * 2.5}</DistanceMeters><HeartRateBpm><Value>140</Value></HeartRateBpm><Extensions><ns3:TPX>" \
              "<ns3:Speed>2.5</ns3:Speed><ns3:RunCadence>85</ns3:RunCadence><ns3:Watts>250</ns3:Watts></ns3:TPX></Extensions></Trackpoint>\n"
    end
    file << "</Track></Lap></Activity></Activities></TrainingCenterDatabase>\n"
  end
end

cpu = -> { Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID) }
best = lambda do |label, &block|
  times = Array.new(3) do
    GC.start
    started = cpu.call
    block.call
    cpu.call - started
  end
  puts format("%-10s %6.2f s CPU", label, times.min)
end

puts format("%s: %.1f MB, Ruby %s, Nokogiri %s (libxml2 %s)", path, File.size(path) / 1e6, RUBY_VERSION,
            Nokogiri::VERSION, Nokogiri::VERSION_INFO.dig("libxml", "loaded"))
best.call("messages") { TcxKit::Reader.new(path).each_message { |*| nil } }
best.call("activity") { TcxKit::Activity.read(path) }
