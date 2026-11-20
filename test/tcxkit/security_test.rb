# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"

class SecurityTest < Minitest::Test
  def test_refuses_a_dtd_internal_subset
    xml = %(<?xml version="1.0"?>\n<!DOCTYPE TrainingCenterDatabase [<!ENTITY e "x">]>\n) +
          Documents.tcx("<Notes>&e;</Notes>", declaration: false)

    assert_raises(TcxKit::UnsafeContentError) { Documents.read(xml) }
  end

  def test_refuses_entity_expansion
    entities = (1..9).map { |n| %(<!ENTITY e#{n} "#{"&e#{n - 1};" * 10}">) }.join
    xml = %(<!DOCTYPE t [<!ENTITY e0 "lol">#{entities}]>) + Documents.tcx("<Notes>&e9;</Notes>", declaration: false)

    assert_raises(TcxKit::UnsafeContentError) { Documents.read(xml) }
  end

  def test_never_reads_external_entities_or_dtds
    Dir.mktmpdir do |dir|
      secret = File.join(dir, "secret.txt")
      File.write(secret, "SECRET")
      dtd = File.join(dir, "evil.dtd")
      File.write(dtd, %(<!ENTITY e SYSTEM "file://#{secret}">))
      xml = %(<!DOCTYPE TrainingCenterDatabase SYSTEM "file://#{dtd}">) +
            Documents.tcx("<Notes>&e;</Notes>", declaration: false)
      texts = []

      assert_raises(TcxKit::Error) do
        TcxKit::XML::Parser.new(StringIO.new(xml), limits: TcxKit::Limits::DEFAULT, source_label: "t")
                           .each_event { |type, element| texts << element.text if type == :end }
      end
      refute texts.any? { |text| text.to_s.include?("SECRET") }
    end
  end

  def test_an_undeclared_entity_is_invalid
    assert_raises(TcxKit::Error) { Documents.read(Documents.tcx("<Notes>&nbsp;</Notes>")) }
  end

  def test_errors_do_not_contain_document_text
    error = assert_raises(TcxKit::Error) { Documents.read(Documents.tcx("<Notes>private note & more</Notes>")) }

    refute_includes error.message, "private note"
  end
end
