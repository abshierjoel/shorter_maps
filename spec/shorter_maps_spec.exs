defmodule TinyMapsSpec do
  use ESpec
  import TinyMaps

  def eval(quoted_code), do: fn -> Code.eval_quoted(quoted_code) end

  describe "map construction" do
    context "~M" do
      example "with one key" do
        key = "value"
        expect(~M{key} |> to(eq(%{key: "value"})))
      end

      example "with many keys" do
        key_1 = "value_1"
        key_2 = :value_2
        key_3 = 3
        expect(~M{key_1, key_2, key_3} |> to(eq(%{key_1: "value_1", key_2: :value_2, key_3: 3})))
      end

      example "with mixed keys" do
        key_1 = "val_1"
        key_2_alt = :val2
        expect(~M{key_1, key_2: key_2_alt} |> to(eq(%{key_1: "val_1", key_2: :val2})))
      end

      it "raises on invalid varnames" do
        quoted = quote do: ~M{4asdf}
        expect(fn -> Code.eval_quoted(quoted) end |> to(raise_exception()))
      end
    end

    context "~m" do
      example "with one key" do
        a_key = :test_value
        expect(~m{a_key} |> to(eq(%{"a_key" => :test_value})))
      end

      example "with many keys" do
        first_name = "chris"
        last_name = "meyer"

        expect(
          ~m{first_name, last_name}
          |> to(eq(%{"first_name" => "chris", "last_name" => "meyer"}))
        )
      end

      example "with mixed keys" do
        key_1 = "value_1"
        key_2_alt = :val_2

        expect(
          ~m{key_1, "key_2" => key_2_alt}
          |> to(eq(%{"key_1" => "value_1", "key_2" => :val_2}))
        )
      end

      it "raises on invalid varnames" do
        code = quote do: ~m{4asdf}
        expect(eval(code) |> to(raise_exception(SyntaxError)))
      end
    end
  end

  describe "inline pattern matches" do
    example "for ~M" do
      ~M{key_1, key_2} = %{key_1: 1, key_2: 2}
      expect(key_1 |> to(eq(1)))
      expect(key_2 |> to(eq(2)))
    end

    example "for ~m" do
      ~m{key_1, key_2} = %{"key_1" => 1, "key_2" => 2}
      expect(key_1 |> to(eq(1)))
      expect(key_2 |> to(eq(2)))
    end

    example "with mixed_keys" do
      ~M{key_1, key_2: key_2_alt} = %{key_1: :val_1, key_2: "val 2"}
      expect(key_1 |> to(eq(:val_1)))
      expect(key_2_alt |> to(eq("val 2")))
    end

    it "fails to match when there is no match" do
      code = quote do: ~M{key_1} = %{key_2: 1}
      expect(eval(code) |> to(raise_exception(MatchError)))
    end
  end

  describe "function head matches" do
    context "in module" do
      defmodule TestModule do
        def test(~M{key_1, key_2}), do: {:first, key_1, key_2}
        def test(~m{key_1}), do: {:second, key_1}
        def test(_), do: :third
      end

      it "matches in module function heads" do
        expect(TestModule.test(%{key_1: 1, key_2: 2}) |> to(eq({:first, 1, 2})))
        expect(TestModule.test(%{"key_1" => 1}) |> to(eq({:second, 1})))
      end
    end

    context "in anonymous functions" do
      it "matches anonymous function heads" do
        fun = fn
          ~m{foo} -> {:first, foo}
          ~M{foo} -> {:second, foo}
          _ -> :no_match
        end

        assert fun.(%{"foo" => "bar"}) == {:first, "bar"}
        assert fun.(%{foo: "barr"}) == {:second, "barr"}
        assert fun.(%{baz: "bong"}) == :no_match
      end
    end
  end

  describe "struct syntax" do
    defmodule TestStruct do
      defstruct a: nil
    end

    defmodule TestStruct.Child.GrandChild.Struct do
      defstruct a: nil
    end

    example "of construction" do
      a = 5
      expect(~M{%TestStruct a} |> to(eq(%TestStruct{a: 5})))
    end

    example "of alias resolution" do
      alias TestStruct, as: TS
      a = 3
      expect(~M{%TS a} |> to(eq(%TS{a: 3})))
    end

    example "of alias resolution" do
      alias TestStruct.Child.GrandChild.{Struct}
      a = 0
      expect(~M{%Struct a} |> to(eq(%TestStruct.Child.GrandChild.Struct{a: 0})))
    end

    example "of case pattern-match" do
      a = 5

      case %TestStruct{a: 0} do
        ~M{%TestStruct ^a} -> raise("shouldn't have matched")
        ~M{%TestStruct _a} -> :ok
      end
    end

    # TODO: figure out why this test doesn't work.  A manual test in a compiled
    # .ex does raise a KeyError, but not this one:
    # it "raises on invalid keys" do
    #   code = quote do: b = 5; ~m{%TestStruct b}
    #   expect eval(code) |> to(raise_exception(KeyError))
    # end

    it "works for a local module" do
      defmodule InnerTestStruct do
        defstruct a: nil

        def test() do
          a = 5
          ~M{%__MODULE__ a}
        end
      end

      # need to use the :__struct__ version due to compile order?
      expect(InnerTestStruct.test() |> to(eq(%{__struct__: InnerTestStruct, a: 5})))
    end
  end

  describe "update syntax" do
    context "~M" do
      example "with one key" do
        initial = %{a: 1, b: 2, c: 3}
        a = 10
        expect(~M{initial|a} |> to(eq(%{a: 10, b: 2, c: 3})))
      end

      it "allows homogenous keys" do
        initial = %{a: 1, b: 2, c: 3}
        {a, b} = {6, 7}
        expect(~M{initial|a, b} |> to(eq(%{a: 6, b: 7, c: 3})))
      end

      it "allows mixed keys" do
        initial = %{a: 1, b: 2, c: 3}
        {a, d} = {6, 7}
        expect(~M{initial|a, b: d} |> to(eq(%{a: 6, b: 7, c: 3})))
      end

      it "can update a struct" do
        old_struct = %Range{first: 1, last: 2}
        last = 3
        expect(~M{old_struct|last} |> to(eq(%Range{first: 1, last: 3})))
      end

      defmodule TestStructForUpdate do
        defstruct a: 1, b: 2, c: 3
      end

      example "of multiple key update" do
        old_struct = %TestStructForUpdate{a: 10, b: 20, c: 30}
        a = 3
        b = 4
        expect(~M{old_struct|a, b} |> to(eq(%TestStructForUpdate{a: 3, b: 4, c: 30})))
      end
    end

    context "~m" do
      example "with one key" do
        initial = %{"a" => 1, "b" => 2, "c" => 3}
        a = 10
        expect(~m{initial|a} |> to(eq(%{"a" => 10, "b" => 2, "c" => 3})))
      end

      it "allows homogenous keys" do
        initial = %{"a" => 1, "b" => 2, "c" => 3}
        {a, b} = {6, 7}
        expect(~m{initial|a, b} |> to(eq(%{"a" => 6, "b" => 7, "c" => 3})))
      end

      it "allows mixed keys" do
        initial = %{"a" => 1, "b" => 2, "c" => 3}
        {a, d} = {6, 7}
        expect(~m{initial|a, "b" => d} |> to(eq(%{"a" => 6, "b" => 7, "c" => 3})))
      end
    end
  end

  describe "pin syntax" do
    context "~M" do
      example "happy case" do
        matching = 5
        ~M{^matching} = %{matching: 5}
      end

      example "sad case" do
        not_matching = 5

        case %{not_matching: 6} do
          ~M{^not_matching} -> raise("matched when it shouldn't have")
          _ -> :ok
        end
      end
    end

    context "~m" do
      example "happy case" do
        matching = 5
        ~m{^matching} = %{"matching" => 5}
      end

      example "sad case" do
        not_matching = 5

        case %{"not_matching" => 6} do
          ~m{^not_matching} -> raise("matched when it shouldn't have")
          _ -> :ok
        end
      end
    end
  end

  describe "ignore syntax" do
    context "~M" do
      example "happy case" do
        ~M{_ignored, real_val} = %{ignored: 5, real_val: 19}
        expect(real_val |> to(eq(19)))
      end

      example "sad case" do
        case %{real_val: 19} do
          ~M{_not_present, _real_val} -> raise("matched when it shouldn't have")
          _ -> :ok
        end
      end
    end

    context "~m" do
      example "happy case" do
        ~m{_ignored, real_val} = %{"ignored" => 5, "real_val" => 19}
        expect(real_val |> to(eq(19)))
      end

      example "sad case" do
        case %{"real_val" => 19} do
          ~m{_not_present, _real_val} -> raise("matched when it shouldn't have")
          _ -> :ok
        end
      end
    end

    def blah do
      :bleh
    end

    describe "zero-arity" do
      example "Kernel function" do
        expect(~M{node()} |> to(eq(%{node: node()})))
      end

      example "local function" do
        expect(~M{blah()} |> to(eq(%{blah: :bleh})))
      end

      it "calls the function at run-time" do
        mypid = self()
        expect(~M{self()} |> to(eq(%{self: mypid})))
      end
    end

    describe "nested sigils" do
      example "two levels" do
        [a, b, c] = [1, 2, 3]
        expect(~M{a, b: ~M(b, c)} |> to(eq(%{a: 1, b: %{b: 2, c: 3}})))
      end
    end

    describe "literals" do
      example "adding" do
        a = 1
        expect(~M{a, b: a+2} |> to(eq(%{a: 1, b: 3})))
      end

      example "function call" do
        a = []
        expect(~M{a, len: length(a)} |> to(eq(%{a: [], len: 0})))
      end

      example "embedded tinymap" do
        a = 1
        b = 2
        expect(~M{a, b: ~M(b)} |> to(eq(%{a: 1, b: %{b: 2}})))
      end

      example "embedded commas" do
        a = 1
        expect(~M{a, b: <<1, 2, 3>>} |> to(eq(%{a: 1, b: <<1, 2, 3>>})))
      end

      example "function call with arguments" do
        a = :hey
        expect(~M{a, b: div(10, 3)} |> to(eq(%{a: :hey, b: 3})))
      end

      example "pipeline" do
        a = :hey
        expect(~M{a, b: a |> Atom.to_string} |> to(eq(%{a: :hey, b: "hey"})))
      end

      example "string keys" do
        a = "blah"
        b = "bleh"

        expect(
          ~m{a, "b" => ~m(a, b)}
          |> to(eq(%{"a" => "blah", "b" => %{"a" => "blah", "b" => "bleh"}}))
        )
      end

      example "string interpolation" do
        a = "blah"
        b = "bleh"
        expect(~M(a, b: "#{b <> b}, c") |> to(eq(%{a: a, b: "blehbleh, c"})))
      end
    end

    describe "regressions and bugfixes" do
      example "of mixed-mode parse error" do
        a = 5
        expect(~M{key: [1, a, 2]} |> to(eq(%{key: [1, 5, 2]})))
      end

      example "of import shadowing" do
        defmodule Test do
          import TinyMaps

          def test do
            get_struct(:a)
            get_old_map(:a)
            expand_variables(:a, :b)
            expand_variable(:a, :b)
            identify_entries(:a, :b, :c)
            check_entry(:a, :b)
            expand_variable(:a, :b)
            fix_key(:a)
            modifier(:a, :b)
            do_sigil_m(:a, :b)
          end

          def get_struct(a), do: ~M{a}
          def get_old_map(a), do: a
          def expand_variables(a, b), do: {a, b}
          def expand_variable(a, b), do: {a, b}
          def identify_entries(a, b, c), do: {a, b, c}
          def check_entry(a, b), do: {a, b}
          def fix_key(a), do: a
          def modifier(a, b), do: {a, b}
          def do_sigil_m(a, b), do: {a, b}
        end
      end

      example "of varname variations" do
        a? = 1
        expect(~M{a?} |> to(eq(%{a?: 1})))
        a5 = 2
        expect(~M{a5} |> to(eq(%{a5: 2})))
        a! = 3
        expect(~M{a!} |> to(eq(%{a!: 3})))
      end
    end
  end
end
