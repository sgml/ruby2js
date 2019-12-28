gem 'minitest'
require 'minitest/autorun'

describe "ES2017 support" do
  
  def to_js( string)
    _(Ruby2JS.convert(string, eslevel: 2017, filters: []).to_s)
  end
  
  def to_js_fn(string)
    _(Ruby2JS.convert(string, eslevel: 2017,
      filters: [Ruby2JS::Filter::Functions]).to_s)
  end
  
  describe :String do
    it "should convert str.ljust" do
      to_js_fn( 'str.ljust(n)' ).must_equal 'str.padEnd(n)'
    end

    it "should convert str.rjust" do
      to_js_fn( 'str.rjust(n)' ).must_equal 'str.padStart(n)'
    end
  end
  
  describe :Hash do
    it "should convert hash.each_pair" do
      to_js_fn( 'h.each_pair {|k,v| x+=v}' ).
        must_equal 'for (let [k, v] of Object.entries(h)) {x += v}'
    end

    it "should convert hash.entries()" do
      to_js_fn( 'h.entries()' ).must_equal 'Object.entries(h)'
    end

    it "should convert hash.values()" do
      to_js_fn( 'h.values()' ).must_equal 'Object.values(h)'
    end
  end

  describe :async do
    it "should handle named functions" do
      to_js( 'async def f(x); end' ).must_equal 'async function f(x) {}'
    end

    it "should handle named methods" do
      to_js( 'class F; async def m(x); end; end' ).
        must_include 'class F {async m(x) {}}'
    end

    it "should handle class methods" do
      to_js( 'class F; async def self.m(x); end; end' ).
        must_equal 'class F {static async m(x) {}}'
    end

    it "should handle instance methods" do
      to_js( 'async def o.m(x); end' ).
        must_include 'o.m = async function(x) {}'
    end

    it "should handle instance methods" do
      to_js( 'async def o.m(x); end' ).
        must_include 'o.m = async function(x) {}'
    end

    it "should handle lambda functions" do
      to_js( 'async lambda {|x| x}' ).
        must_equal 'async x => x'
    end

    it "should handle procs" do
      to_js( 'async proc {|x| x}' ).
        must_equal 'async x => x'
    end

    it "should handle arrow functions" do
      to_js( 'async -> (x) {x}' ).
        must_equal 'async x => x'
    end
  end

  describe :await do
    it "should handle simple method calls" do
      to_js( 'await f(x)' ).must_equal 'await f(x)'
    end

    it "should handle nested method calls" do
      to_js( 'await o.f(x)' ).must_equal 'await o.f(x)'
    end

    it "should handle calls with blocks" do
      to_js( 'await f(x) {|y| y}' ).must_equal 'await f(x, y => y)'
    end
  end
end
