class BreakpointTracker
  
  class Handler
    def initialize(meth, ip, line, prc)
      @method = meth
      @ip = ip
      @line = line
      @handler = prc
    end
    
    def install
      enc = InstructionSequence::Encoder.new
      @orig = enc.replace_instruction @method.bytecodes, @ip, [:yield_debugger]
      @method.compile
    end
    
    def restore_into(ctx)
      enc = InstructionSequence::Encoder.new
      enc.replace_instruction @method.bytecodes, @ip, @orig
      @method.compile
      # Reset instruction pointer back to where yield_debugger was
      ctx.ip = ctx.ip - (InstructionSet[:yield_debugger].arg_count + 1)
    end
    
    def call(ctx)
      @handler.call(ctx)
    end
  end
  
  def initialize
    @handlers = Hash.new { |h,k| h[k] = {} }
    @debug_channel = Channel.new
    @control_channel = Channel.new
  end
  
  attr_accessor :debug_channel
  attr_accessor :control_channel
  
  def add_thread(thr)
    thr.set_debugging @debug_channel, @control_channel
  end
  
  def on(method, opts, &prc)
    cm = method.compiled_method
    if line = opts[:line]
      tip = cm.first_ip_on_line(line)
    elsif op = opts[:ip]
      tip = op
    else
      raise ArgumentError, "Unknown selector: #{opts.inspect}"
    end
    
    handler = Handler.new(cm, tip, line, prc)
    @handlers[cm][tip] = handler
    handler.install
    return handler
  end
  
  def find_handler(ctx)
    cm = ctx.method
    ip = ctx.ip - 1
    @handlers[cm][ip]
  end
  
  def process
    ctx = @debug_channel.receive
    pnt = find_handler(ctx)
    unless pnt
      raise "Unable to find handler for #{ctx.inspect}"
    end
    pnt.call(ctx)
    pnt.restore_into(ctx)
  end
  
  def wake_target
    @control_channel.send nil
  end
  
end
