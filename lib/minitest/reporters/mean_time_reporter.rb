require 'minitest/reporters'
require 'yaml'

module Minitest
  module Reporters

    # This reporter creates a report providing the average (mean), minimum and
    # maximum times for a test to run. Running this for all your tests will
    # allow you to:
    #
    # 1) Identify the slowest running tests over time as potential candidates
    #    for improvements or refactoring.
    # 2) Identify (and fix) regressions in test run speed caused by changes to
    #    your tests or algorithms in your code.
    # 3) Provide an abundance of statistics to enjoy.
    #
    # This is achieved by creating a (configurable) 'previous runs' statistics
    # file which is parsed at the end of each run to provide a new
    # (configurable) report. These statistics can be reset at any time by using
    # a simple rake task:
    #
    #     rake reset_statistics
    #
    class MeanTimeReporter < Minitest::Reporters::DefaultReporter

      # Reset the statistics file for this reporter. Called via a rake task:
      #
      #     rake reset_statistics
      #
      # @return [Boolean]
      def self.reset_statistics!
        new.reset_statistics!
      end

      # @param options [Hash]
      # @option previous_runs_filename [String] Contains the times for each test
      #   by description. Defaults to '/tmp/minitest_reporters_previous_run'.
      # @option report_filename [String] Contains the parsed results for the
      #   last test run. Defaults to '/tmp/minitest_reporters_report'.
      # @return [Minitest::Reporters::MeanTimeReporter]
      def initialize(options = {})
        super

        @all_suite_times = []
      end

      # Copies the suite times from the
      # {Minitest::Reporters::DefaultReporter#after_suite} method, making them
      # available to this class.
      #
      # @return [Hash<String => Float>]
      def after_suite(suite)
        super

        @all_suite_times = @suite_times
      end

      # Runs the {Minitest::Reporters::DefaultReporter#report} method and then
      # enhances it by storing the results to the 'previous_runs_filename' and
      # outputs the parsed results to both the 'report_filename' and the
      # terminal.
      #
      def report
        super

        create_or_update_previous_runs!

        create_new_report!

        write_to_screen!
      end

      # Resets the 'previous runs' file, essentially removing all previous
      # statistics gathered.
      #
      # @return [void]
      def reset_statistics!
        File.open(previous_runs_filename, 'w+') { |f| f.write('') }
      end

      protected

      attr_accessor :all_suite_times

      private

      # @return [Hash<String => Float>]
      def current_run
        Hash[all_suite_times]
      end

      # @return [Hash] Sets default values for the filenames used by this class,
      #   and the number of tests to output to output to the screen after each
      #   run.
      def defaults
        {
          count:                  15,
          previous_runs_filename: '/tmp/minitest_reporters_previous_run',
          report_filename:        '/tmp/minitest_reporters_report',
        }
      end

      # Added to the top of the report file and to the screen output.
      #
      # @return [String]
      def report_title
        "\n\e[4mMinitest Reporters: Mean Time Report\e[24m (Samples: #{samples})\n"
      end

      # The report itself. Displays statistics about all runs, ideal for use
      # with the Unix 'head' command. Listed in slowest average descending
      # order.
      #
      # @return [String]
      def report_body
        previous_run.each_with_object([]) do |(description, timings), obj|
          size = Array(timings).size
          sum  = Array(timings).inject { |total, x| total + x }
          avg  = (sum / size).round(9).to_s.ljust(12)
          min  = Array(timings).min.to_s.ljust(12)
          max  = Array(timings).max.to_s.ljust(12)

          obj << "#{avg_label} #{avg} " \
                 "#{min_label} #{min} " \
                 "#{max_label} #{max} " \
                 "#{des_label} #{description}\n"
        end.sort.reverse.join
      end

      # @return [Hash]
      def options
        defaults.merge!(@options)
      end

      # @return [Fixnum] The number of tests to output to output to the screen
      #   after each run.
      def count
        options[:count]
      end

      # @return [Hash<String => Array<Float>]
      def previous_run
        @previous_run ||= YAML.load_file(previous_runs_filename)
      end

      # @return [String] The path to the file which contains all the durations
      #   for each test run. The previous runs file is in YAML format, using the
      #   test name for the key and an array containing the time taken to run
      #   this test for values.
      def previous_runs_filename
        options[:previous_runs_filename]
      end

      # Returns a boolean indicating whether a previous runs file exists.
      #
      # @return [Boolean]
      def previously_ran?
        File.exist?(previous_runs_filename)
      end

      # @return [String] The path to the file which contains the parsed test
      #   results. The results file contains a line for each test with the
      #   average time of the test, the minimum time the test took to run,
      #   the maximum time the test took to run and a description of the test
      #   (which is the test name as emitted by Minitest).
      def report_filename
        options[:report_filename]
      end

      # A barbaric way to find out how many runs are in the previous runs file;
      # this method takes the first test listed, and counts its samples
      # trusting (naively) all runs to be the same number of samples. This will
      # produce incorrect averages when new tests are added, so it is advised
      # to restart the statistics by removing the 'previous runs' file. A rake
      # task is provided to make this more convenient.
      #
      #    rake reset_statistics
      #
      # @return [Fixnum]
      def samples
        return 1 unless previous_run.first[1].is_a?(Array)

        previous_run.first[1].size
      end

      # Creates a new 'previous runs' file, or updates the existing one with
      # the latest timings.
      #
      # @return [void]
      def create_or_update_previous_runs!
        if previously_ran?
          current_run.each do |description, elapsed|
          new_times = if previous_run["#{description}"]
                        Array(previous_run["#{description}"]) << elapsed

                      else
                        Array(elapsed)

                      end

            previous_run.store("#{description}", new_times)
          end

          File.write(previous_runs_filename, previous_run.to_yaml)

        else

          File.write(previous_runs_filename, current_run.to_yaml)

        end
      end

      # Creates a new report file in the 'report_filename'. This file contains
      # a line for each test of the following example format:
      #
      # Avg: 0.0555555 Min: 0.0498765 Max: 0.0612345 Description: The test name
      #
      # Note however the timings are to 9 decimal places, and padded to 12
      # characters and each label is coloured, Avg (yellow), Min (green),
      # Max (red) and Description (blue). It looks pretty!
      #
      # @return [void]
      def create_new_report!
        File.write(report_filename, report_title + report_body)
      end

      # Writes a number of tests (configured via the 'count' option) to the
      # screen after creating the report. See '#create_new_report!' for example
      # output information.
      #
      # @return [void]
      def write_to_screen!
        puts report_title
        puts report_body.lines.take(count)
      end

      # @return [String] A yellow 'Avg:' label.
      def avg_label
        "\e[33mAvg:\e[39m"
      end

      # @return [String] A blue 'Description:' label.
      def des_label
        "\e[34mDescription:\e[39m"
      end

      # @return [String] A red 'Max:' label.
      def max_label
        "\e[31mMax:\e[39m"
      end

      # @return [String] A green 'Min:' label.
      def min_label
        "\e[32mMin:\e[39m"
      end

    end
  end
end
