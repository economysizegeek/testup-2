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

        testsuite = discover_testcases(testsuite_path)
        coverage = Coverage.new(testsuite_path)
        missing_tests = coverage.missing_tests(testsuite)

        testsuites[testsuite_name] = {
            :testcases => testsuite,
            :coverage => coverage.percent(missing_tests),
            :missing_coverage => missing_tests
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
        testcases[testcase] = testcase.test_methods
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

    # @param [String] testcase_file
    # @return [Object|Nil] The TestUp::TestCase object.
    def load_testcase(testcase_file)
      testcase_name = File.basename(testcase_file, '.*')

      # If the test has been loaded before try to undefine it so that test methods
      # that has been renamed or removed doesn't linger. This will only work if
      # the testcase file is named idential to the testcase class.
      #In the case of specs - it should match in the main describe block
      remove_old_tests(testcase_name.intern)
      remove_old_spec_tests(testcase_name)
      # Cache the current list of testcase classes.
      existing_test_classes = all_test_classes
      puts "Exsiting Test Classes = ", existing_test_classes.collect { |ek| ek.to_s }.join(",")
      # Attempt to load the testcase so it can be inspected for testcases and
      # test methods. Any errors is wrapped up in a custom error type so it can
      # be caught further up and displayed in the UI.
      testcase = nil
      begin
        load testcase_file
        new_classes = all_test_classes - existing_test_classes
        new_classes.each do |new_class|
          if new_class.to_s === testcase_name.to_s
            if !new_class.ancestors.include?(TestUp::TestCaseExtendable)
              new_class.extend(TestUp::TestCaseExtendable)
            end
            puts "Found the testcase", new_class
            testcase = new_class
            break
          end
        end
      rescue ScriptError, StandardError => error
        warn "#{error.class} Loading #{testcase_name}"
        warn format_load_backtrace(error)
        raise TestCaseLoadError.new(error)
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

        klasses << klass if klass.ancestors.include?(MiniTest::Test) || klass.ancestors.include?(MiniTest::Spec)
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
        MiniTest::Runnable.runnables.each { |klass|
          if klass.to_s == testcase.to_s
            puts "Going to remove #{klass.to_s}"
          end
        }
        MiniTest::Runnable.runnables.delete_if { |klass|
          klass.to_s == testcase.to_s
        }
        GC.start
      end
      nil
    end

    def remove_old_spec_tests(testcase)
      MiniTest::Runnable.runnables.each { |klass|
        if klass.to_s == testcase.to_s || klass.to_s.match("#{testcase.to_s}::")
          puts "Going to remove #{klass.to_s}/#{testcase.to_s}"
        end
      }
      MiniTest::Runnable.runnables.delete_if { |klass|
        klass.to_s == testcase.to_s || klass.to_s.match("#{testcase.to_s}::")
      }
      GC.start

      nil
    end

  end # class
end # module
