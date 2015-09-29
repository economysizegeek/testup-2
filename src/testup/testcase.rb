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

  # Methods used by the test discoverer.
  module TestCaseExtendable

    def test_methods
      if respond_to?(:children)

        tests = []
        children.each do |child|
          tests.concat(child.test_methods)
        end
      else
        tests = public_instance_methods(true).grep(/^test_/i).sort

      end
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
