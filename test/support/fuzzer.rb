# frozen_string_literal: true

# Mutates documents for fuzz tests, reproducibly from a seed.
class Fuzzer
  SNIPPETS = [
    "<", ">", "&", "&amp;", "&#0;", "&#x110000;", "&undefined;", "]]>", "<![CDATA[", "<!--", "-->", "<?pi?>",
    "<!DOCTYPE x [<!ENTITY e \"y\">]>", "<!ENTITY e SYSTEM \"file:///etc/passwd\">", "\x00", "\xFF\xFE", "\xEF\xBB\xBF",
    "é", "\u{1F3C3}", "xmlns=\"urn:x\"", "xmlns:ns3=\"\"", "ns9:", "=\"\"", "'", "\"",
    "-0", "+7", "1e400", "-1e400", "NaN", "INF", "99999999999999999999999999", "1.5.5", "2026-02-30T25:61:61Z",
    "<Value>", "</Value>", "<Trackpoint>", "</Trackpoint>", "<Lap StartTime=\"x\">", "</Lap>", "<Extensions>",
    "<trkpt lat=\"91\" lon=\"181\">", "</trkpt>", "<extensions>", "</gpx>", "</TrainingCenterDatabase>"
  ].map(&:b).freeze

  # Values for mutate_values: valid, invalid and edge-case text, already
  # escaped for XML.
  VALUES = [
    "", " ", "\t\n", "0", "-0", "+0", "1", "-1", "+7", "007", "255", "256", "65535", "65536", "4294967296",
    "1.5", "-1.5", ".5", "5.", "1e3", "1E-3", "-1e400", "1e400", "INF", "-INF", "NaN", "12,5", "0x1A", "1_000",
    "90", "90.0000001", "-180", "180", "360", "99999999999999999999999999999999",
    "2026-01-01T08:00:00Z", "2026-01-01T08:00:00", "2026-01-01T08:00:00.123456789+14:00", "2026-01-01T08:00:00-14:01",
    "2024-02-29T00:00:00Z", "2023-02-29T00:00:00Z", "2026-01-01T24:00:00Z", "-0001-01-01T00:00:00Z", "2026",
    "Running", "running", "Biking", "Other", "Active", "Resting", "Manual", "HeartRate", "Present", "Footpod", "Bike",
    "First Aid", "4th Category", "Generic", "true", "false", "1", "yes", "3d", " 3d", "dgps",
    "006-A1234-00", "en", "eng", "A" * 300, "&amp;&lt;&gt;", "&#233;&#x1F3C3;", "\u00e9t\u00e9", "\u{1F3C3}"
  ].map { |value| value.encode(Encoding::UTF_8) }.freeze

  def initialize(seed)
    @random = Random.new(seed)
  end

  # Replaces some text contents and attribute values from the root element
  # on, keeping the markup and the XML declaration.
  def mutate_values(document)
    root = document.index(/<[A-Za-z]/) || 0
    document[0, root] + document[root..].gsub(/(?<=>)[^<]+(?=<)|(?<==")[^"]*(?=")/) do |value|
      next value if value.strip.empty? && @random.rand(4).positive?
      next value if value.start_with?("http") || @random.rand(3).zero?

      VALUES.sample(random: @random)
    end
  end

  def mutate(document)
    bytes = document.b.dup
    (1 + @random.rand(4)).times { bytes = mutate_once(bytes) }
    bytes
  end

  private

  def mutate_once(bytes)
    return SNIPPETS.sample(random: @random).dup if bytes.empty?

    at = @random.rand(bytes.bytesize)
    case @random.rand(6)
    when 0 then bytes.byteslice(0, at)
    when 1 then bytes.byteslice(0, at) + bytes.byteslice((at + 1 + @random.rand(64))..).to_s
    when 2 then bytes.byteslice(0, at) + SNIPPETS.sample(random: @random) + bytes.byteslice(at..).to_s
    when 3 then flip(bytes, at)
    when 4
      length = 1 + @random.rand(200)
      bytes.byteslice(0, at) + bytes.byteslice(at, length).to_s * (2 + @random.rand(3)) + bytes.byteslice(at..).to_s
    else bytes.byteslice(0, at) + @random.bytes(1 + @random.rand(8)) + bytes.byteslice(at..).to_s
    end
  end

  def flip(bytes, at)
    copy = bytes.dup
    copy.setbyte(at, copy.getbyte(at) ^ (1 << @random.rand(8)))
    copy
  end
end
