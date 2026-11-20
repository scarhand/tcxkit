# frozen_string_literal: true

require_relative "test_helper"

class SmokeTest < Minitest::Test
  def test_version
    assert_match(/\A\d+\.\d+\.\d+\z/, TcxKit::VERSION)
  end

  def test_errors_carry_their_position
    error = TcxKit::InvalidFileError.new("Unexpected end tag", source: "run.tcx", line: 3, column: 7)

    assert_equal "Unexpected end tag (run.tcx, line 3, column 7)", error.message
    assert_equal 3, error.line
    assert_kind_of TcxKit::Error, error
  end

  def test_limit_errors_name_the_limit
    error = TcxKit::LimitExceededError.new("Too deep", limit: :max_depth, line: 65)

    assert_equal :max_depth, error.limit
    assert_equal "Too deep (line 65)", error.message
  end
end
