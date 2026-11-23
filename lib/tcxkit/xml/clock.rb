# frozen_string_literal: true

module TcxKit
  module XML
    # Measures reading time for Limits#max_seconds, leaving out the time
    # spent in the caller's block.
    class Clock
      MONOTONIC = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }

      def initialize(max_seconds, now: MONOTONIC)
        @max_seconds = max_seconds
        @now = now
        @started = now.call
        @paused = 0.0
      end

      # Starts measuring from now.
      def restart
        @started = @now.call
        @paused = 0.0
      end

      def exceeded?
        @max_seconds && (@now.call - @started - @paused) > @max_seconds
      end

      # Runs the caller's block without counting its time. Without a time
      # limit there is nothing to measure.
      def outside
        return yield unless @max_seconds

        started = @now.call
        begin
          yield
        ensure
          @paused += @now.call - started
        end
      end
    end
  end
end
