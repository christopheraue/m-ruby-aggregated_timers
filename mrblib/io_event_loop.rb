Object.__send__(:remove_const, :IOEventLoop) if Object.const_defined? :IOEventLoop

class IOEventLoop
  include CallbacksAttachable

  def initialize(*)
    @wall_clock = WallClock.new

    @run_queue = RunQueue.new self
    @io_watcher = IOWatcher.new self

    @event_loop = Fiber.new do
      while true
        if (waiting_time = @run_queue.waiting_time) == 0
          @run_queue.process_pending
        elsif @io_watcher.watches? or waiting_time
          @io_watcher.process_ready_in waiting_time
        else
          # Having no pending timeouts or IO events would make run this loop
          # forever. But, since we always leave the loop through one of the
          # fibers resumed in the code above, this part of the loop is never
          # reached. When  resuming the loop at a later time it will be because
          # of an added timeout of IO event. So, there will always be something
          # to wait for.
          raise Error, "Infinitely running event loop detected. This " <<
            "should not happen and is considered a bug in this gem."
        end
      end
    end
  end

  attr_reader :wall_clock

  def resume
    @event_loop.transfer
  end


  # Concurrently executed block of code

  def concurrently # &block
    fiber = Fiber.new do |future|
      result = begin
        yield
      rescue Exception => e
        trigger :error, e
        e
      end

      future.evaluate_to result
      resume
    end

    future = Future.new self, @run_queue, fiber
    @run_queue.schedule fiber, 0, future
    future
  end


  # Waiting for a given time

  def wait(seconds)
    @run_queue.schedule Fiber.current, seconds
    resume
  end


  # Waiting for a readable IO

  def await_readable(io, opts = {})
    fiber = Fiber.current
    max_seconds = opts[:within]
    @run_queue.schedule fiber, max_seconds, false if max_seconds
    @io_watcher.watch_reader io, fiber
    resume
  ensure
    @io_watcher.cancel_watching_reader io
    @run_queue.cancel fiber if max_seconds
  end


  # Waiting for a writable IO

  def await_writable(io, opts = {})
    fiber = Fiber.current
    max_seconds = opts[:within]
    @run_queue.schedule fiber, max_seconds, false if max_seconds
    @io_watcher.watch_writer io, fiber
    resume
  ensure
    @io_watcher.cancel_watching_writer io
    @run_queue.cancel fiber if max_seconds
  end


  # Watching events

  def watch_events(*args)
    EventWatcher.new(self, *args)
  end
end