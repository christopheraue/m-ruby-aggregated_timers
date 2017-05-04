class IOEventLoop
  class Concurrency
    class Future
      def initialize(concurrency)
        @concurrency = concurrency
      end
  
      def result(opts = {})
        @concurrency.waiting = true
  
        if seconds = opts[:within]
          timeout_result = opts.fetch(:timeout_result, TimeoutError.new("waiting timed out after #{seconds} second(s)"))
          @concurrency.schedule_in seconds, timeout_result
        end

        # yields back to the loop from the concurrency calling this method
        result = Fiber.yield

        (CancelledError === result) ? raise(result) : result
      end

      def resume_with(result)
        @concurrency.resume_with result
      end

      def cancel(reason = "waiting cancelled")
        @concurrency.resume_with CancelledError.new(reason)
        :cancelled
      end

      def cancel_schedule
        @concurrency.cancel_schedule
      end

      def waiting?
        @concurrency.waiting
      end

      def await_readable(io, *args)
        @concurrency.loop.attach_reader(io) { @concurrency.loop.detach_reader(io); @concurrency.resume_with :readable }
        result *args
      end

      def cancel_awaiting_readable(io)
        @concurrency.loop.detach_reader io
        @concurrency.resume_with :cancelled
      end

      def await_writable(io, *args)
        @concurrency.loop.attach_writer(io) { @concurrency.loop.detach_writer(io); @concurrency.resume_with :writable }
        result *args
      end

      def cancel_awaiting_writable(io)
        @concurrency.loop.detach_writer io
        @concurrency.resume_with :cancelled
      end
    end
  end
end