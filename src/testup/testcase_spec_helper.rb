#This module adds in methods to make it easier to remove references to improve GC
#Because before/after use define_method - they end up creating a closure that can't be GC'd
require "minitest/spec"
module TestUp
  module TestCaseSpecHelper
    def remove_child!(child)
      @children.delete_if { |i| i == child }
    end

    def wipe_children!
      @children = []
    end

    def before _type = nil, &block
      puts "Warning before blocks cause memory leaks in this environment"
      define_method :setup do
        super()
        self.instance_eval(&block)
      end

    end

    def after _type = nil, &block
      puts "Warning after blocks cause memory leaks environment"
      define_method :teardown do
        super()
        self.instance_eval(&block)
      end

    end
  end
end
Minitest::Spec.extend(TestUp::TestCaseSpecHelper)