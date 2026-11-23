# frozen_string_literal: true

require_relative "../test_helper"

class TypesTest < Minitest::Test
  T = TcxKit::Types

  # Kernel#Float warns about numbers beyond a Float; a file must not be
  # able to make the reader print anything.
  def test_numbers_beyond_a_float_are_decoded_silently
    verbose = $VERBOSE
    $VERBOSE = true
    assert_silent do
      assert_equal [nil, :not_finite], T.decode(T.double, "1e400").drop(1)
      assert_equal [nil, :not_finite], T.decode(T.double, "-1.8e308").drop(1)
      assert_equal [nil, :not_finite], T.decode(T.decimal, "9" * 400).drop(1)
      assert_equal [0.0, nil], T.decode(T.double, "1e-400").drop(1)
      assert_equal [0.0, nil], T.decode(T.decimal, "0.#{'0' * 400}1").drop(1)
    end
  ensure
    $VERBOSE = verbose
  end

  def test_numbers_at_the_edges_of_a_float
    assert_equal Float::MAX, T.decode(T.double, "1.7976931348623157e308")[1]
    assert_equal 1.0e-310, T.decode(T.double, "1e-310")[1]
    assert_equal(-0.0025, T.decode(T.double, "-2.5E-3")[1])
    assert_equal 0.0, T.decode(T.double, "0e999999999")[1]
  end

  # Ruby before 3.4 rejects these forms in Float(); XSD allows them.
  def test_nothing_after_the_decimal_point
    assert_equal [5.0, 1000.0, -5.0, 0.5], %w[5. 1.e3 -5. .5].map { |text| T.decode(T.double, text)[1] }
    assert_equal [5.0, 5.0], %w[5. +5.].map { |text| T.decode(T.decimal, text)[1] }
  end

  def test_a_huge_exponent_is_not_computed
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert_equal :not_finite, T.decode(T.double, "1e999999999999")[2]
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 0.1
  end
end
