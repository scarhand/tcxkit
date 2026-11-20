# frozen_string_literal: true

require "stringio"

# Builders for synthetic test documents. Values are made up.
module Documents
  module_function

  def tcx(body = "<Activities/>", declaration: true)
    xml = +""
    xml << %(<?xml version="1.0" encoding="UTF-8"?>\n) if declaration
    xml << %(<TrainingCenterDatabase xmlns="#{TcxKit::NAMESPACE}">\n#{body}\n</TrainingCenterDatabase>\n)
    xml
  end

  # Events from the XML layer, as [type, name, depth, text] rows.
  def events(xml, limits: TcxKit::Limits::DEFAULT)
    rows = []
    parser = TcxKit::XML::Parser.new(StringIO.new(xml), limits: TcxKit::Limits.coerce(limits), source_label: "test")
    parser.each_event { |type, element| rows << [type, element.name, element.depth, type == :end ? element.text : nil] }
    rows
  end

  def read(xml, **options)
    TcxKit::Reader.new(StringIO.new(xml), **options).each_message { |_message| nil }
  end

  def messages(xml, **options)
    TcxKit::Reader.new(StringIO.new(xml), **options).each_message.to_a
  end

  # The first message with that name.
  def message(xml, name)
    messages(xml).find { |message| message.name == name }
  end

  def fixture(name)
    File.expand_path("../fixtures/#{name}", __dir__)
  end

  # A trackpoint document with the given Trackpoint children.
  def trackpoint(children)
    tcx(%(<Activities><Activity Sport="Running"><Id>2026-01-01T08:00:00Z</Id>
      <Lap StartTime="2026-01-01T08:00:00Z"><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>1</DistanceMeters>
      <Calories>1</Calories><Intensity>Active</Intensity><TriggerMethod>Manual</TriggerMethod>
      <Track><Trackpoint>#{children}</Trackpoint></Track></Lap></Activity></Activities>))
  end
end
