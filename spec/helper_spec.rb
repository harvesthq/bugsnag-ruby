# encoding: utf-8

require 'spec_helper'
require 'set'

describe Bugsnag::Helpers do

  describe "trim_if_needed" do

    it "breaks recursion" do
      a = [1, 2, 3]
      b = [2, a]
      a << b
      value = Bugsnag::Helpers.trim_if_needed(a)
      expect(value).to eq([1, 2, 3, [2, "[RECURSION]"]])
    end

    it "does not break equal objects without recursion" do
      data = [1, [1, 2], [1, 2], "a"]
      value = Bugsnag::Helpers.trim_if_needed(data)
      expect(value).to eq data
    end

    it "preserves bool types" do
      value = Bugsnag::Helpers.trim_if_needed([1, 3, true, "NO", "2", false])
      expect(value[2]).to be_a(TrueClass)
      expect(value[5]).to be_a(FalseClass)
    end

    it "preserves Numeric types" do
      value = Bugsnag::Helpers.trim_if_needed([1, 3.445, true, "NO", "2", false])
      expect(value[0]).to be_a(Numeric)
      expect(value[1]).to be_a(Numeric)
    end

    it "preserves String types" do
      value = Bugsnag::Helpers.trim_if_needed([1, 3, true, "NO", "2", false])
      expect(value[3]).to be_a(String)
      expect(value[4]).to be_a(String)
    end

    context "payload length is less than allowed" do

      it "does not change strings" do
        value = SecureRandom.hex(4096)
        expect(Bugsnag::Helpers.trim_if_needed(value)).to eq value
      end

      it "does not change arrays" do
        value = 1000.times.map {|i| "#{i} - #{i + 1}" }
        expect(Bugsnag::Helpers.trim_if_needed(value)).to eq value
      end

      it "does not change hashes" do
        value = Hash[*1000.times.map{|i| ["#{i}", i]}.flatten]
        expect(Bugsnag::Helpers.trim_if_needed(value)).to eq value
      end
    end

    context "payload length is greater than allowed" do

      context "value is a String" do
        it "trims length" do
          value = Bugsnag::Helpers.trim_if_needed(SecureRandom.hex(500_000/2))
          expect(::JSON.dump(value.length).length).to be < Bugsnag::Helpers::MAX_STRING_LENGTH
        end
      end

      context "value is an Array" do
        it "trims nested string contents" do
          value = [[30.times.map {|i| SecureRandom.hex(8192) }]]
          json = ::JSON.dump(Bugsnag::Helpers.trim_if_needed(value))
          expect(json.length).to be < Bugsnag::Helpers::MAX_PAYLOAD_LENGTH
        end

        it "trims string contents" do
          value = 30.times.map {|i| SecureRandom.hex(8192) }
          json = ::JSON.dump(Bugsnag::Helpers.trim_if_needed(value))
          expect(json.length).to be < Bugsnag::Helpers::MAX_PAYLOAD_LENGTH
        end
      end

      context "value is a Set" do
        it "trims string contents" do
          value = Set.new(30.times.map {|i| SecureRandom.hex(8192) })
          json = ::JSON.dump(Bugsnag::Helpers.trim_if_needed(value))
          expect(json.length).to be < Bugsnag::Helpers::MAX_PAYLOAD_LENGTH
        end
      end

      context "value can be converted to a String" do
        it "converts to a string and trims" do
          value = Set.new(30_000.times.map {|i| Bugsnag::Helpers })
          json = ::JSON.dump(Bugsnag::Helpers.trim_if_needed(value))
          expect(json.length).to be < Bugsnag::Helpers::MAX_PAYLOAD_LENGTH
        end
      end

      context "value is a Hash" do

        before(:each) do
          @metadata = {
            :short_string => "this should not be truncated",
            :long_string => 10000.times.map {|i| "should truncate" }.join(""),
            :long_string_ary => 30.times.map {|i| SecureRandom.hex(8192) }
          }

          @trimmed_metadata = Bugsnag::Helpers.trim_if_needed @metadata
        end

        it "does not trim short values" do
          expect(@trimmed_metadata[:short_string]).to eq @metadata[:short_string]
        end

        it "trims long string values" do
          expect(@trimmed_metadata[:long_string].length).to eq(Bugsnag::Helpers::MAX_STRING_LENGTH)
          expect(@trimmed_metadata[:long_string].match(/\[TRUNCATED\]$/)).to_not be_nil
        end

        it "trims nested long string values" do
          @trimmed_metadata[:long_string_ary].each do |str|
            expect(str.match(/\[TRUNCATED\]$/)).to_not be_nil
            expect(str.length).to eq(Bugsnag::Helpers::MAX_STRING_LENGTH)
          end
        end

        it "does not change the argument value" do
          expect(@metadata[:long_string].length).to be > Bugsnag::Helpers::MAX_STRING_LENGTH
          expect(@metadata[:long_string].match(/\[TRUNCATED\]$/)).to be_nil
          expect(@metadata[:short_string].length).to eq(28)
          expect(@metadata[:short_string]).to eq("this should not be truncated")
          expect(@trimmed_metadata[:long_string_ary].length).to eq(30)
        end
      end

      context "and trimmed strings are not enough" do
        it "truncates long arrays" do
          value = 100.times.map {|i| SecureRandom.hex(8192) }
          trimmed_value = Bugsnag::Helpers.trim_if_needed(value)
          expect(trimmed_value.length).to be > 0
          trimmed_value.each do |str|
            expect(str.match(/\[TRUNCATED\]$/)).to_not be_nil
            expect(str.length).to eq(Bugsnag::Helpers::MAX_STRING_LENGTH)
          end

          expect(::JSON.dump(trimmed_value).length).to be < Bugsnag::Helpers::MAX_PAYLOAD_LENGTH
        end

        it "does not remove entire events" do
          value = {
            events: [{
              app: {},
              context: {},
              metaData: {},
              exceptions: (0..2).map do
                {
                  stacktrace: (0..200).map do
                    {
                      inProject: true,
                      lineNumber: 305,
                      code: {
                        302 => "",
                        303 => "      # Executes the SQL statement in the context of this connection.",
                        304 => "      def execute(sql, name = nil)",
                        305 => "        log(sql, name) { @connection.query(sql) }",
                        306 => "      end",
                        307 => "",
                        308 => "      # MysqlAdapter has to free a result after using it, so we use this method to write"
                      },
                      file: ".bundle/gems/activerecord-4.2.5.2/lib/active_record/connection_adapters/abstract_mysql_adapter.rb",
                      method: "query"
                    }
                  end
                }
              end
            }]
          }
          trimmed_value = Bugsnag::Helpers.trim_if_needed(value)
          expect(trimmed_value[:events].size).to eq(1)
        end
      end
    end
  end
end
