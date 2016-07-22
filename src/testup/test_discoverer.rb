#-------------------------------------------------------------------------------
#
# Copyright 2013-2014 Trimble Navigation Ltd.
# License: The MIT License (MIT)
#
#-------------------------------------------------------------------------------


module TestUp

  class TestDiscoverer

    # Error type used when loading the .RB files containing the test cases.
    class TestCaseLoadError < StandardError
      attr_reader :original_error

      def initialize(error)
        @original_error = error
      end
    end


    attr_reader :errors


    # @param [Array<String>] paths_to_testsuites
    def initialize(paths_to_testsuites)
      @paths_to_testsuites = paths_to_testsuites
      @errors = []
    end

    # @return [Array]
    def discover
      @errors.clear
      testsuites = {}
      for testsuite_path in @paths_to_testsuites
        if !File.directory?(testsuite_path)
          warn "WARNING: Not a valid directory: #{testsuite_path}"
          next
        end

        testsuite_name = File.basename(testsuite_path)
        if testsuites.key?(testsuite_name)
          # TODO: raise custom error and catch later for display in UI.
          raise "Duplicate testsuites: #{testsuite_name} - #{testsuite_path}"
        end
       # puts "Looking at testsuite - #{testsuite_name}"
        testsuite = discover_testcases(testsuite_path)
        coverage = Coverage.new(testsuite_path)
        missing_tests = coverage.missing_tests(testsuite)

        testsuites[testsuite_name] = {
            :testcases => testsuite,
            :coverage => coverage.percent(missing_tests),
            :missing_coverage => {} # DJE - turning this off for now missing_tests
        }
      end
      testsuites
    end

    private

    def discover_testcases(testsuite_path)
      testcases = {}
      testcase_source_files = discover_testcase_source_files(testsuite_path)
      for testcase_file in testcase_source_files
        begin
          testcase = load_testcase(testcase_file)
        rescue TestCaseLoadError => error
          @errors << error
          next
        end
        next if testcase.nil?
        next if testcase.test_methods.empty?
        testcases[testcase.name] = testcase.test_methods
       # puts "Adding to  testcases[#{testcase.name}", testcase.test_methods.join(",")
      end
      testcases
    end

    # @param [String] testcase_filename
    # @return [String]
    def get_testcase_suitename(testcase_filename)
      path = File.expand_path(testcase_filename)
      parts = path.split(File::SEPARATOR)
      testcase_file = File.basename(testcase_filename)
      testcase_name = File.basename(testcase_filename, '.*')
      # The TC_*.rb file might be wrapped in a TC_* folder. The suite name is the
      # parent of either one of these.
      index = parts.index(testcase_name) || parts.index(testcase_file)
      parts[index - 1]
    end

    # @param [Array<String>] testsuite_paths
    # @return [Array<String>] Path to all test case files found.
    def discover_testcase_source_files(testsuite_path)
      testcase_filter = File.join(testsuite_path, 'TC_*.rb')
      Dir.glob(testcase_filter)
    end

    #Used to add to spec
    # @param [Class] The base spec class
    # @return [Class] The base spec class that has been extended

    def extend_with_TestCaseExtendable(testcase)
      unless testcase.singleton_class.ancestors.include?(TestCaseExtendable)
        #   puts "Adding TestCaseExtenable to  #{testcase.name}"
        testcase.extend(TestCaseExtendable)
      end
      if testcase.respond_to?(:children) && testcase.children.length > 0
        testcase.children.collect { |child|
          #   puts "Adding TestCaseExtenable to  #{child.name}"

          extend_with_TestCaseExtendable(child) }
      end
      return(testcase)
    end

    # @param [String] testcase_file
    # @return [Object|Nil] The TestUp::TestCase object.
    def load_testcase(testcase_file)
      testcase_name = File.basename(testcase_file, '.*')
      # If the test has been loaded before try to undefine it so that test methods
      # that has been renamed or removed doesn't linger. This will only work if
      # the testcase file is named idential to the testcase class.


      remove_old_tests(testcase_name.intern)
      remove_old_spec_tests(testcase_name)
      # Cache the current list of testcase classes. This will only work properly
      # for tests prefixed with TC_*

      #puts "Before:", all_test_classes.join(",")
      all_test_classes #Not sure why this has to run twice to work
      existing_test_classes = all_test_classes
      # Attempt to load the testcase so it can be inspected for testcases and
      # test methods. Any errors is wrapped up in a custom error type so it can
      # be caught further up and displayed in the UI.
      begin
        load testcase_file
      rescue ScriptError, StandardError => error
        warn "#{error.class} Loading #{testcase_name}"
        warn format_load_backtrace(error)
        raise TestCaseLoadError.new(error)
      end
      puts "___________________________"
      Puts "Minitest::VERSION"
      puts "---------------------------"
      MiniTest::Runnable.runnables.each { |klass|

        puts "Runnable #{klass}"

      }
      # Ideally there should be one test case per test file and the name of the
      # file and test class should be the same.
      # Because some of our older tests didn't conform to that we must inspect
      # what new classes was loaded.
      new_classes = all_test_classes - existing_test_classes

      new_test_classes = root_classes(new_classes)


      if new_test_classes.first && new_test_classes.first.ancestors.include?(Minitest::Spec)
        testcase = new_test_classes.first
        #   puts "This test case is a spec", testcase
        #DJE - Need to handle supporting a way to get the list of children/methods for it to use to tezt
        extend_with_TestCaseExtendable(testcase)
        #Handle sub children
      #  puts "Methods", testcase.test_methods.join(",")
      else

        if new_test_classes.empty?
          # This happens if another test case loaded a test case with the same name.
          # Our old todo section has sections like that.
          warn "'#{testcase_name}' - No new test cases loaded."
          #warn existing_test_classes.sort{|a,b|a.name<=>b.name}.join("\n")
          return nil
        elsif new_test_classes.size > 1
          # NOTE: More than one test class is currently not supported.
          # TODO(thomthom): Sub-classes will trigger this. Fix this.
          warn "'#{testcase_name}' - " <<
                   "More than one test class loaded: #{new_test_classes.join(', ')}"
          return nil
        end
        testcase = new_test_classes.first

        # If the testcase class didn't inherit from TestUp::TestCase we need to
        # ensure to extend it so the TestUp utility methods is availible.
        unless testcase.singleton_class.ancestors.include?(TestCaseExtendable)
          # TODO(thomthom): Hook this up to deprecation warning.
          #warn "Invalid testcase: #{testcase} (#{testcase.ancestors.inspect})"
          testcase.extend(TestCaseExtendable)
        end

      end

      testcase
    end


    # @param [Array<Class>] klasses
    # @return [Array<Class>]
    def root_classes(klasses)
      klasses.select { |klass| !klass.name.include?('::') }
    end

    # @param [Exception] error
    # @return [String]
    def format_load_backtrace(error)
      file_basename = File.basename(__FILE__)
      index = error.backtrace.index { |line|
        line =~ /testup\/#{file_basename}:\d+:in `load'/i
      }
      filtered_backtrace = error.backtrace[0..index]
      error.message << "\n" << filtered_backtrace.join("\n")
    end

    # @return [Array<Class>]
    def all_test_classes
      klasses = []
      ObjectSpace.each_object(Class) { |klass|
        next if klass.to_s.downcase.match("minitest::")
        next if klasses.collect { |k| k.to_s }.include?(klass.to_s)
        if klass.ancestors.include?(MiniTest::Spec) && !klass.to_s.match("::")
          klasses << klass
        elsif klass.ancestors.include?(MiniTest::Test)
          klasses << klass

        end

      }
      klasses
    end

    # Remove the old testcase class so changes can be made without reloading
    # SketchUp. This is done because MiniTest is made to be run as a traditional
    # Ruby script on a web server where the lifespan of objects isn't persistent
    # as it is in SketchUp.
    #
    # @param [Symbol] testcase
    # @return [Nil]
    def remove_old_tests(testcase)
      if Object.constants.include?(testcase)
        Object.send(:remove_const, testcase)
        # Remove any previously loaded versions from MiniTest. Otherwise MiniTest
        # will keep running them along with the new ones.
        MiniTest::Runnable.runnables.delete_if { |klass|
          klass.to_s == testcase.to_s
        }
        GC.start
      end
      nil
    end

    def remove_old_spec_tests(testcase)
      puts "Thinking about revmoving #{testcase}"
      klasses = []
      MiniTest::Runnable.runnables.each { |klass|
        if klass.to_s == testcase.to_s || klass.to_s.match("#{testcase.to_s}::")
         puts "Going to remove #{klass.to_s}/#{testcase.to_s}"
          klasses << klass
        end
      }
      MiniTest::Runnable.runnables.delete_if { |klass| klasses.include?(klass) }
      klasses.each do |klass|
        if Object.constants.include?(klass)
          Object.send(:remove_const, klass)
          puts "Removing const"
        end

      end

      GC.start

      nil
    end

  end # class
end # module
