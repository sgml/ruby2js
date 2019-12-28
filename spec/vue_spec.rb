gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/vue'

describe Ruby2JS::Filter::Vue do

  def to_js(string)
    _(Ruby2JS.convert(string, filters: [Ruby2JS::Filter::Vue],
      scope: self).to_s)
  end

  def to_js_fn(string)
    _(Ruby2JS.convert(
      string, 
      filters: [Ruby2JS::Filter::Functions, Ruby2JS::Filter::Vue], 
      scope: self
    ).to_s)
  end

  describe :createApp do
    it "should create apps" do
      to_js( 'class FooBar<Vue; end' ).
        must_include 'var FooBar = new Vue('
    end
  end

  describe :createClass do
    it "should create classes" do
      to_js( 'class FooBar<Vue; def render; end; end' ).
        must_include 'var FooBar = Vue.component("foo-bar",'
      to_js( 'class FooBar<Vue; template "<span></span>"; end' ).
        must_include 'var FooBar = Vue.component("foo-bar",'
      to_js( 'class FooBar<Vue; template "<span></span>"; end' ).
        must_include 'var FooBar = Vue.component("foo-bar",'
    end

    it "should convert initialize methods to data" do
      to_js( 'class Foo<Vue; def initialize(); @a=1; end; end' ).
        must_include '{data: function() {return {a: 1}}'
    end

    it "should insert an initialize method if none is present" do
      to_js( 'class Foo<Vue; def render; _h1 @title; end; end' ).
        must_include '{data: function() {return {title: undefined}}'
    end

    it "should convert merge uninitialized values - simple" do
      to_js( 'class Foo<Vue; def initialize; @var = ""; end; ' +
        'def render; _h1 @title; end; end' ).
        must_include ', {data: function() {return {var: "", title: undefined}}'
    end

    it "should convert merge uninitialized values - complex" do
      to_js( 'class Foo<Vue; def initialize; value = "x"; @var = value; end; ' +
        'def render; _h1 @title; end; end' ).
        must_include ', {data: function() {' +
          'var $_ = {title: undefined}; var value = "x"; $_.var = value; ' +
          'return $_}'
    end

    it "should initialize, accumulate, and return state if complex" do
      to_js( 'class Foo<Vue; def initialize; @a=1; b=2; @b = b; end; end' ).
        must_include 'data: function() {var $_ = {}; $_.a = 1; ' +
          'var b = 2; $_.b = b; return $_}'
    end

    it "should initialize, accumulate, and return state if ivars are read" do
      to_js( 'class Foo<Vue; def initialize; @a=1; @b = @a; end; end' ).
        must_include '{data: function() {var $_ = {}; $_.a = 1; ' +
          '$_.b = $_.a; return $_}}'
    end

    it "should initialize, accumulate, and return state if multi-assignment" do
      to_js( 'class Foo<Vue; def initialize; @a=@b=1; end; end' ).
        must_include '{data: function() {var $_ = {b: undefined}; ' +
          '$_.a = $_.b = 1; return $_}}'
    end

    it "should initialize, accumulate, and return state if op-assignment" do
      to_js( 'class Foo<Vue; def initialize; @a||=1; end; end' ).
        must_include '{data: function() {var $_ = {a: undefined}; ' +
          '$_.a = $_.a || 1; return $_}}'
    end

    it "should collapse instance variable assignments into a return" do
      to_js( 'class Foo<Vue; def initialize; @a=1; @b=2; end; end' ).
        must_include 'data: function() {return {a: 1, b: 2}}'
    end

    it "should handle lifecycle methods" do
      to_js( 'class Foo<Vue; def updated; console.log "."; end; end' ).
        must_include '{updated: function() {return console.log(".")}'
    end

    it "should handle other methods" do
      to_js( 'class Foo<Vue; def clicked(); @counter+=1; end; end' ).
        must_include ', methods: {clicked: function() {this.$data.counter++}}'
    end

    it "should handle calls to methods" do
      to_js( 'class Foo<Vue; def a(); b(); end; def b(); end; end' ).
        must_include 'this.b()'
    end

    it "should give precedence to locally defined methods" do
      to_js_fn( 'class Foo<Vue; def a(); self.merge(); end; ' +
        'def merge(); end; end' ).
        must_include 'this.merge()'
    end

    it "should handle methods as hash values" do
      to_js( 'class Foo<Vue; def render; _a onClick: b; end; def b(); end; end' ).
        must_include '{click: this.b}'
    end

    it "should NOT handle local variables" do
      to_js( 'class Foo<Vue; def a(); b; end; def b(); end; end' ).
        wont_include 'this.b()'
    end
  end

  describe "Wunderbar/JSX processing" do
    # https://github.com/vuejs/babel-plugin-transform-vue-jsx#difference-from-react-jsx
    it "should create components" do
      to_js( 'class Foo<Vue; def render; _A; end; end' ).
        must_include '$h(A)'
    end

    it "should create components with properties" do
      to_js( 'class Foo<Vue; def render; _A title: "foo"; end; end' ).
        must_include '$h(A, {props: {title: "foo"}})'
    end

    it "should create elements with event listeners" do
      to_js( 'class Foo<Vue; def render; _A onAlert: self.alert; end; end' ).
        must_include '$h(A, {on: {alert: this.alert}})'
    end

    it "should create elements for HTML tags" do
      to_js( 'class Foo<Vue; def render; _a; end; end' ).
        must_include '$h("a")'
    end

    it "should create elements with attributes and text" do
      to_js( 'class Foo<Vue; def render; _a "name", href: "link"; end; end' ).
        must_include '$h("a", {attrs: {href: "link"}}, "name")'
    end

    it "should map underscores to dashes in attributes names" do
      to_js( 'class Foo<Vue; def render; _span data_name: "value"; end; end' ).
        must_include '$h("span", {attrs: {"data-name": "value"}})'
    end

    it "should create elements with DOM Propoerties" do
      to_js( 'class Foo<Vue; def render; _a domPropsTextContent: "name"; end; end' ).
        must_include '$h("a", {domProps: {textContent: "name"}})'
    end

    it "should create elements with event listeners" do
      to_js( 'class Foo<Vue; def render; _a onClick: self.click; end; end' ).
        must_include '$h("a", {on: {click: this.click}})'
    end

    it "should create elements with native event listeners" do
      to_js( 'class Foo<Vue; def render; _a nativeOnClick: self.click; end; end' ).
        must_include '$h("a", {nativeOn: {click: this.click}})'
    end

    it "should create elements with class hash expressions" do
      to_js( 'class Foo<Vue; def render; _a class: {foo: true}; end; end' ).
        must_include '$h("a", {class: {foo: true}})'
    end

    it "should create elements with class array expressions" do
      to_js( 'class Foo<Vue; def render; _a class: ["foo", "bar"]; end; end' ).
        must_include '$h("a", {class: ["foo", "bar"]})'
    end

    it "should create elements with style expressions" do
      to_js( 'class Foo<Vue; def render; _a style: {color: "red"}; end; end' ).
        must_include '$h("a", {style: {color: "red"}})'
    end

    it "should create elements with a key value" do
      to_js( 'class Foo<Vue; def render; _a key: "key"; end; end' ).
        must_include '$h("a", {key: "key"})'
    end

    it "should create elements with a ref value" do
      to_js( 'class Foo<Vue; def render; _a ref: "ref"; end; end' ).
        must_include '$h("a", {ref: "ref"})'
    end

    it "should create elements with a refInFor value" do
      to_js( 'class Foo<Vue; def render; _a refInFor: true; end; end' ).
        must_include '$h("a", {refInFor: true})'
    end

    it "should create elements with a slot value" do
      to_js( 'class Foo<Vue; def render; _a slot: "slot"; end; end' ).
        must_include '$h("a", {slot: "slot"})'
    end

    it "should create simple nested elements" do
      to_js( 'class Foo<Vue; def render; _a {_b}; end; end' ).
        must_include '{render: function($h) {return $h("a", [$h("b")])}'
    end

    it "should handle options with blocks" do
      to_js( 'class Foo<Vue; def render; _a options do _b; end; end; end' ).
        must_include '{render: function($h) ' +
          '{return $h("a", options, [$h("b")])}'
    end

    it "should create complex nested elements - leading" do
      result = to_js('class Foo<Vue; def render; _a {_x; _b if true}; end; end')

      result.must_include 'return $h("a", function() {'
      result.must_include 'var $_ = [$h("x")];'
      result.must_include 'if (true) $_.push($h("b"))'
      result.must_include 'return $_'
    end

    it "should create complex nested elements - trailing" do
      result = to_js('class Foo<Vue; def render; _a {c="c"; _b c}; end; end')

      result.must_include 'return $h("a", function() {'
      result.must_include 'var c = "c"'
      result.must_include 'return [$h("b", c)]'
    end

    it "should collapse consecutive pushes" do
      result = to_js('class Foo<Vue; def render; if true; _a; _b; end; end; end')

      result.must_include '{$_.push($h("a"), $h("b"))}'
    end

    it "should create simple elements nested within complex elements" do
      to_js( 'class Foo<Vue; def render; _a {_b} if true; end; end' ).
        must_include 'if (true) {$_.push($h("a", [$h("b")]))}'
    end

    it "should treat explicit calls to Vue.createElement as simple" do
      to_js( 'class Foo<Vue; def render; _a {Vue.createElement("b")}; ' +
        'end; end' ).
        must_include '$h("a", [$h("b")])'
    end

    it "should push results of explicit calls to Vue.createElement" do
      result = to_js('class Foo<Vue; def render; _a {c="c"; ' +
        'Vue.createElement("b", c)}; end; end')

      result.must_include '$h("a", function() {'
      result.must_include 'return [$h("b", c)]'
      result.must_include '}())'
    end

    it "should handle call with blocks to Vue.createElement" do
      result = to_js( 'class Foo<Vue; def render; ' +
        'Vue.createElement("a") {_b}; end; end' )
      result.must_include '$h("a", function() {'
      result.must_include 'var $_ = [];'
      result.must_include '$_.push($h("b"));'
      result.must_include 'return $_'
      result.must_include '}())'
    end

    it "should iterate" do
      result = to_js('class Foo<Vue; def render; _ul list ' +
        'do |i| _li i; end; end; end')

      result.must_include '$h("ul", '
      result.must_include 'list.map(function(i) {'
      result.must_include '{return $h("li", i)}'
    end

    it "should iterate with markaby style classes/ids" do
      result = to_js('class Foo<Vue; def render; _ul.todos list ' +
        'do |i| _li i; end; end; end')

      result.must_include '$h("ul", {class: ["todos"]}, '
      result.must_include 'list.map(function(i) {'
      result.must_include '{return $h("li", i)})'
    end

    it "should handle text nodes" do
      to_js( 'class Foo<Vue; def render; _a {_ @text}; end; end' ).
        must_include '[this._v(this.$data.text)]'
    end

    it "should apply text nodes" do
      to_js( 'class Foo<Vue; def render; _a {text="hi"; _ text}; end; end' ).
        must_include '{var text = "hi"; return [self._v(text)]}'
    end

    it "should handle arbitrary nodes" do
      to_js( 'class Foo<Vue; def render; _a {_[@text]}; end; end' ).
        must_include 'return $h("a", [this.$data.text])'
    end

    it "should handle lists of arbitrary nodes" do
      to_js( 'class Foo<Vue; def render; _a {_[@text, @text]}; end; end' ).
        must_include '$h("a", [this.$data.text, this.$data.text])'
    end

    it "should apply arbitrary nodes" do
      to_js( 'class Foo<Vue; def render; _a {text="hi"; _[text]}; end; end' ).
        must_include '{var text = "hi"; return [text]}'
    end

    it "should apply list of arbitrary nodes" do
      to_js( 'class Foo<Vue; def render; _a {text="hi"; _[text, text]}; end; end' ).
        must_include '{var text = "hi"; return [text, text]}'
    end
  end

  describe "render method" do
    it "should wrap multiple elements with a span" do
      to_js( 'class Foo<Vue; def render; _h1 "a"; _p "b"; end; end' ).
        must_include 'return $h("span", [$h("h1", "a"), $h("p", "b")])'
    end

    it "should not wrap tail only element with a span" do
      to_js( 'class Foo<Vue; def render; x = "a"; _p x; end; end' ).
        must_include 'function($h) {var x = "a"; return $h("p", x)}}'
    end

    it "should not be fooled by nesting" do
      result = to_js( 'class Foo<Vue; def render; _p "a" if @a; _p "b"; end; end' )
      result.must_include '$h("span", function() {var $_ = [];'
      result.must_include 'if (self.$data.a) {$_.push($h("p", "a"))}'
      result.must_include 'return $_.concat([$h("p", "b")])'
    end

    it "should wrap anything that is not a method or block call with a span" do
      result = to_js( 'class Foo<Vue; def render; if @a; _p "a"; else;_p "b"; end; end; end' )
      result.must_include '$h("span", function() {var $_ = [];'
      result.must_include 'if (self.$data.a) {$_.push($h("p", "a"))}'
      result.must_include 'else {$_.push($h("p", "b"))};'
      result.must_include 'return $_}'
    end

    it "should insert a span if render method is empty" do
      result = to_js( 'class Foo<Vue; def render; end; end' )
      result.must_include '{return $h("span", [])}'
    end
  end

  describe "class attributes" do
    it "should handle class attributes" do
      to_js( 'class Foo<Vue; def render; _a class: "b"; end; end' ).
        must_include '$h("a", {class: ["b"]})'
    end

    it "should handle className attributes" do
      to_js( 'class Foo<Vue; def render; _a className: "b"; end; end' ).
        must_include '$h("a", {class: ["b"]})'
    end

    it "should handle class attributes with spaces" do
      to_js( 'class Foo<Vue; def render; _a class: "b c"; end; end' ).
        must_include '$h("a", {class: ["b", "c"]})'
    end

    it "should handle markaby syntax" do
      to_js( 'class Foo<Vue; def render; _a.b.c href: "d"; end; end' ).
        must_include '$h("a", {class: ["b", "c"], attrs: {href: "d"}})'
    end

    it "should handle mixed strings" do
      to_js( 'class Foo<Vue; def render; _a.b class: "c"; end; end' ).
        must_include '$h("a", {class: ["b", "c"]})'
    end

    it "should handle mixed strings and a value" do
      to_js( 'class Foo<Vue; def render; _a.b class: c; end; end' ).
        must_include '$h("a", {class: ["b", c]})'
    end

    it "should create elements with markup and a class hash expression" do
      to_js( 'class Foo<Vue; def render; _a.bar class: {foo: true}; end; end' ).
        must_include '$h("a", {class: {foo: true, bar: true}})'
    end

    it "should create elements with markup and a class array expression" do
      to_js( 'class Foo<Vue; def render; _a.bar class: ["foo"]; end; end' ).
        must_include '$h("a", {class: ["foo", "bar"]})'
    end

    it "should handle mixed strings and a conditional value" do
      to_js( 'class Foo<Vue; def render; _a.b class: ("c" if d); end; end' ).
        must_include '$h("a", {class: ["b", (d ? "c" : null)]})'
    end

    it "should handle only a value" do
      to_js( 'class Foo<Vue; def render; _a class: c; end; end' ).
        must_include '$h("a", {class: [c]})'
    end

    it "should handle an array value" do
      to_js( 'class Foo<Vue; def render; _a class: [*c]; end; end' ).
        must_include '$h("a", {class: c})'
    end

    it "should handle an array value mixed with markup" do
      to_js( 'class Foo<Vue; def render; _a.b class: [*c]; end; end' ).
        must_include '$h("a", {class: c.concat(["b"])})'
    end
  end

  describe "other attributes" do
    it "should handle markaby syntax ids" do
      to_js( 'class Foo<Vue; def render; _a.b! href: "c"; end; end' ).
        must_include '$h("a", {attrs: {id: "b", href: "c"}})'
    end

    it "should map style string attributes to hashes" do
      to_js( 'class Foo<Vue; def render; _a ' +
        'style: "color: blue; margin-top: 0"; end; end' ).
        must_include '{style: {color: "blue", marginTop: 0}}'
    end
  end

  describe "map gvars/ivars/cvars to refs/state/prop" do
    it "should map instance variables to state" do
      to_js( 'class Foo<Vue; def method(); @x; end; end' ).
        must_include 'this.$data.x'
    end

    it "should map setting instance variables to setting properties" do
      to_js( 'class Foo<Vue; def method(); @x=1; end; end' ).
        must_include 'this.$data.x = 1'
    end

    it "should map setting ivar op_asgn to setting properties" do
      to_js( 'class Foo<Vue; def method(); @x+=1; end; end' ).
        must_include 'this.$data.x++'
    end

    it "should handle parallel instance variables assignment" do
      to_js( 'class Foo<Vue; def method(); @x=@y=1; end; end' ).
        must_include 'this.$data.x = this.$data.y = 1'
    end

    it "should enumerate properties" do
      to_js( 'class Foo<Vue; def render; _span @@x + @@y; end; end' ).
        must_include '{props: ["x", "y"]'
    end

    it "should map class variables to properties" do
      to_js( 'class Foo<Vue; def method(); @@x; end; end' ).
        must_include 'this.$props.x'
    end

    it "should not support assigning to class variables" do
      _(proc {
        to_js( 'class Foo<Vue; def method(); @@x=1; end; end' )
      }).must_raise NotImplementedError
    end
  end

  describe "method calls" do
    it "should handle ivars" do
      to_js( 'class Foo<Vue; def method(); @x.(); end; end' ).
        must_include 'this.$data.x()'
    end

    it "should handle cvars" do
      to_js( 'class Foo<Vue; def method(); @@x.(); end; end' ).
        must_include 'this.$props.x()'
    end
  end

  describe "computed values" do
    it "should handle getters" do
      js = to_js( 'class Foo<Vue; def value; @x; end; def method(); value; end; end' )
      js.must_include ', computed: {value: function() {'
      js.must_include 'this.value'
    end

    it "should NOT handle methods" do
      js = to_js( 'class Foo<Vue; def value(); end; def method(); value; end; end' )
      js.wont_include 'this.value'
    end

    it "should handle setters" do
      js = to_js( 'class Foo<Vue; def value=(x); @x=x; end; def method(); value=1; end; end' )
      js.must_include ', computed: {value: {set: function(x) {'
      js.must_include 'this.value = 1'
    end

    it "should handle setters with op_asgn" do
      js = to_js( 'class Foo<Vue; def value=(x); @x=x; end; def method(); value+=1; end; end' )
      js.must_include 'this.value++'
    end

    it "should combine getters and setters" do
      js = to_js( 'class Foo<Vue; def value; @x; end; def value=(x); @x=x; end; end' )
      js.must_include ', computed: {value: {get: function() {return '
      js.must_include ', set: function(x) {this.$data.x = x}'
    end
  end

  describe 'Vue calls' do
    it 'should create elements outside of render methods' do
      to_js( 'Vue.createElement("span", "text")' ).
        must_include 'this.$createElement("span", "text")'
    end

    it 'should map Vue.render with block to Vue instance' do
      to_js( 'Vue.render "#sidebar" do _Element end' ).
        must_include 'new Vue({el: "#sidebar", render: ' +
          'function($h) {return $h(Element)}})'
    end

    it 'should substitute scope instance variables / props' do
      @data = 5
      to_js( "Vue.render('#sidebar') {_Element(data: @data)}" ).
        must_include '$h(Element, {props: {data: 5}})'
    end

    it 'should map vm method calls to this.$' do
      to_js( 'class Foo<Vue; def method(); Vue.emit("event"); end; end' ).
        must_include 'this.$emit("event")'
    end

    it 'should leave bare Vue.nextTick calls alone' do
      to_js( 'Vue.nextTick { nil }' ).
        must_match 'Vue.nextTick(function() {null})'
    end

    it 'should map Vue.util.defineReactive cvar to class' do
      to_js( 'class Foo; Vue.util.defineReactive @@i, 1; end' ).
        must_include 'Vue.util.defineReactive(Foo, "_i", 1)'
    end

    it 'should map Vue.util.defineReactive ivar to self' do
      to_js( 'class Foo; def method(); Vue.util.defineReactive @i, 1; end; end' ).
        must_include 'Vue.util.defineReactive(this, "_i", 1)'
    end

    it 'should map Vue.util.defineReactive attribute' do
      to_js( 'class Foo; def method(); Vue.util.defineReactive a.b, 1; end; end' ).
        must_include 'Vue.util.defineReactive(a, "b", 1)'
    end
  end

  describe "controlled components" do
    it "should automatically create onInput value functions: input ivar" do
      js = to_js( 'class Foo<Vue; def render; _input value: @x; end; end' )
      js.must_include ', on: {input: function(event) {'
      js.must_include '{self.$data.x = event.target.value}'
      js.must_include ', domProps: {value: this.$data.x,'

      js.must_include '{attrs: {disabled: true},'
      js.must_match(/domProps: \{.*?, disabled: false\}/)
    end

    it "should automatically create onInput value functions: input computed" do
      js = to_js( 'class Foo<Vue; def render; _input value: x; end; ' +
        ' def x=(value); end; end' )
      js.must_include ', on: {input: function(event) {'
      js.must_include '{self.x = event.target.value}'
      js.must_include ', domProps: {value: this.x,'

      js.must_include '{attrs: {disabled: true},'
      js.must_match(/domProps: \{.*?, disabled: false\}/)
    end

    it "should automatically create onInput value functions: input self" do
      js = to_js( 'class Foo<Vue; def render; _input value: self.x; end; end' )
      js.must_include ', on: {input: function(event) {'
      js.must_include '{self.x = event.target.value}'
      js.must_include ', domProps: {value: this.x,'

      js.must_include '{attrs: {disabled: true},'
      js.must_match(/domProps: \{.*?, disabled: false\}/)
    end

    it "should automatically create onInput value functions: input array" do
      js = to_js( 'class Foo<Vue; def render; _input value: @a[x]; end; end' )
      js.must_include ', on: {input: function(event) {'
      js.must_include '{self.$data.a[x] = event.target.value}'
      js.must_include ', domProps: {value: this.$data.a[x],'

      js.must_include '{attrs: {disabled: true},'
      js.must_match(/domProps: \{.*?, disabled: false\}/)
    end

    it "shouldn't automatically create onInput value functions: cvar" do
      js = to_js( 'class Foo<Vue; def render; _input value: @@x; end; end' )
      js.must_include '{attrs: {value: this.$props.x}'

      js.wont_include ', on: {input: function(event) {'
      js.wont_include ' = event.target.value'
      js.wont_include ', domProps: {value: '
      js.wont_include 'disabled'
    end

    it "should automatically create onInput value functions: textarea" do
      js = to_js( 'class Foo<Vue; def render; _textarea value: @x; end; end' )
      js.must_include ', on: {input: function(event) {'
      js.must_include '{self.$data.x = event.target.value}'
      js.must_include ', domProps: {value: this.$data.x,'
      js.must_include ', this.$data.x)'

      js.must_include '{attrs: {disabled: true},'
      js.must_match(/domProps: \{.*?, disabled: false\}/)
    end

    it "shouldn't replace disabled attributes in input elements" do
      js = to_js( 'class Foo<Vue; def render; _input value: @x, disabled: @disabled; end; end' )
      js.wont_include 'disabled: true'
      js.wont_include 'disabled: false'
    end

    it "should automatically create onClick checked functions - ivar" do
      js = to_js( 'class Foo<Vue; def render; _input checked: @x; end; end' )
      js.must_include ', on: {click: function() {'
      js.must_include 'self.$data.x = !self.$data.x}'
      js.must_include ', domProps: {checked: this.$data.x,'

      js.must_include '{attrs: {disabled: true},'
      js.must_match(/domProps: \{.*?, disabled: false\}/)
    end

    it "should automatically create onClick checked functions - cvar based" do
      js = to_js( 'class Foo<Vue; def render; _input checked: @@x.y; end; end' )
      js.must_include ', on: {click: function() {'
      js.must_include 'self.$props.x.y = !self.$props.x.y}'
      js.must_include ', domProps: {checked: this.$props.x.y,'

      js.must_include '{attrs: {disabled: true},'
      js.must_match(/domProps: \{.*?, disabled: false\}/)
    end

    it "should chose checked over value" do
      to_js( 'class Foo<Vue; def render; _input value: "foo", ' +
        'checked: @@x.y; end; end' ).must_include ', on: {click: function() {'
    end

    it "shouldn't replace disabled attributes in checkboxes" do
      js = to_js( 'class Foo<Vue; def render; _input checked: @x, disabled: @disabled; end; end' )
      js.wont_include 'disabled: true'
      js.wont_include 'disabled: false'
    end

    it "should retain onClick functions" do
      js = to_js( 'class Foo<Vue; def render; _input checked: @x, onClick: self.click; end; end' )
      js.must_include ', on: {click: this.click}'
      js.wont_include ', on: {input: function('
    end
  end

  describe "options and mixins" do
    it "should capture and access options" do
      js = to_js( 'class Foo<Vue; options a: b; def render; _p $options.a; end; end' )
      js.must_include '{a: b, render:'
      js.must_include '$h("p", this.$options.a)'
    end

    it "should capture and access el(for apps)" do
      js = to_js( 'class Foo<Vue; el ".element"; end' )
      js.must_include 'el: ".element"'
    end

    it "should enable a mixin to be defined" do
      to_js( 'class Foo<Vue::Mixin; def mounted(); @foo=1; end; end' ).
        must_equal 'var Foo = {mounted: function() {this.$data.foo = 1}}'
    end

    it "should enable a mixin to be included" do
      to_js( 'class Bar<Vue; mixin Foo; end' ).
        must_equal 'var Bar = new Vue({mixins: [Foo]})'
    end
  end

  describe "static methods and properties" do
    it "should handle static properties" do
      to_js( 'class Foo<Vue; def self.one; 1; end; end' ).
        must_include 'get: function() {return 1}'
    end

    it "should handle computed static properties" do
      js = to_js( 'class Foo<Vue; def self.one; return 1; end; end' )
      js.must_include 'Object.defineProperty(Foo, "one", {'
      js.must_include 'get: function() {return 1}'
    end

    it "should handle computed static properties with getters and setters" do
      js = to_js( 'class Foo<Vue; def self.one; Foo._one; end;' +
        'def self.one=(x); Foo._one = x; end; end' )
      js.must_include 'Object.defineProperty(Foo, "one", {'
      js.must_include 'get: function() {return Foo._one}, set'
      js.must_include 'set: function(x) {Foo._one = x}}'
    end

    it "should handle static setters" do
      js = to_js( 'class Foo<Vue; def self.one=(x); Foo._one = x; end; end' )
      js.must_include 'Object.defineProperty(Foo, "one", {'
      js.must_include 'set: function(x) {Foo._one = x}}'
    end

    it "should handle static methods" do
      to_js( 'class Foo<Vue; def self.one(); return 1; end; end' ).
        must_include 'Foo.one = function() {return 1}'
    end

    it "should handle reactive properties" do
      to_js( 'class Foo<Vue; Foo.one=1; end' ).
        must_include 'Vue.util.defineReactive(Foo, "one", 1)'
    end
  end

  describe 'comments' do
    it "should handle class comments" do
      to_js( "#cc\nclass Foo<Vue; end" ).
        must_include "//cc\nvar"
    end

    it "should handle constructor comments" do
      to_js( "class Foo<Vue; \n#ctorc\ndef initialize; end; end" ).
        must_include "//ctorc\n  data: function("
    end

    it "should handle lifecycle method comments" do
      to_js( "class Foo<Vue; \n#lfc\ndef mounted(); end; end" ).
        must_include "//lfc\n  mounted: function("
    end

    it "should handle instance method comments" do
      to_js( "class Foo<Vue;\n#imc\ndef method(); end; def render; end; end" ).
        must_include "//imc\n    method: function("
    end

    it "should handle class method comments" do
      to_js( "class Foo<Vue; \n#cmc\ndef self.method(); end; end" ).
        must_include "//cmc\nFoo.method = function("
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include vue" do
      _(Ruby2JS::Filter::DEFAULTS).must_include Ruby2JS::Filter::Vue
    end
  end
end
