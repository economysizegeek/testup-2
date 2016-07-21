#-------------------------------------------------------------------------------
#
# Copyright 2013-2014 Trimble Navigation Ltd.
# License: The MIT License (MIT)
#
#-------------------------------------------------------------------------------


require File.join(__dir__, 'minitest_setup.rb')

if defined?(Sketchup)
  require File.join(__dir__, 'sketchup_test_utilities.rb')
end


module TestUp
  class TestMethodWrapper
    def initialize(test_case, test_method)
      @test_case = test_case
      @test_method = test_method

    end

    def to_s
      if @test_case.spec?
        "#{@test_case.name.split("::").last} - #{@test_method.to_s.gsub(/^test_[0-9]+_/, "")}"
      else
        @test_method.to_s
      end
    end
  end
  # Methods used by the test discoverer.
  module TestCaseExtendable
    def spec?
      self.ancestors.include?(Minitest::Spec)
    end

    def unit?
      self.ancestors.include?(Minitest::Unit)
    end

    def test_methods
      tests = public_instance_methods(true).grep(/^test_/i).collect { |t| TestMethodWrapper.new(self, t) }

      if respond_to?(:children)
        children.each do |child|
          tests.concat(child.test_methods)
        end
      end
    #  puts "Returning #{self.name} is speck? #{self.spec?} ", tests.join(",")
      tests
    end

  end # module TestCaseExtendable


  # Inherit tests from this class to get access to utility methods for SketchUp.
  class TestCase < Minitest::Test

    extend TestCaseExtendable

    if defined?(Sketchup)
      include SketchUpTestUtilities
    end

  end # class

end # module
