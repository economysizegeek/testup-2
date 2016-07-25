#This wrapper class makes it easier to abstract some differences between specs & units
module TestUp
  class TestMethodWrapper
    def initialize(test_case, test_method)
      @test_case = test_case
      @test_method = test_method

    end

    def to_s
      if @test_case.spec?
        "#{@test_case.name.split("::").last} #{@test_method.to_s.gsub(/^test_[0-9]+_/, "")}"
      else
        @test_method.to_s
      end
    end
    def minitest_pattern
      if @test_case.spec?
        "#{@test_case.name}##{@test_method.to_s.strip}"
      else
        @test_method.to_s
      end

    end
  end
end