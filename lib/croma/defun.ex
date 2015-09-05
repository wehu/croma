defmodule Croma.Defun do
  @moduledoc """
  Module that provides `Croma.Defun.defun/2` macro.
  """

  @doc """
  Defines a function together with its typespec.
  This provides a lighter-weight syntax for functions with type specifications and functions with multiple clauses.

  ## Example
  The following examples assume that `Croma.Defun` is imported
  (you can import it by using `Croma`).

      defun f(a: integer, b: String.t) :: String.t do
        "\#{a} \#{b}"
      end

  The code above is expanded to the following function definition.

      @spec f(integer, String.t) :: String.t
      def f(a, b) do
        "\#{a} \#{b}"
      end

  Function with multiple clauses and/or pattern matching on parameters can be defined
  in the same way as `case do ... end`:

      defun dumbmap(as: [a], f: (a -> b)) :: [b] when a: term, b: term do
        ([]     , _) -> []
        ([h | t], f) -> [f.(h) | dumbmap(t, f)]
      end

  is converted to

      @spec dumbmap([a], (a -> b)) :: [b] when a: term, b: term
      def dumbmap(as, f)
      def dumbmap([], _) do
        []
      end
      def dumbmap([h | t], f) do
        [f.(h) | dumbmap(t, f)]
      end

  ## Known limitations
  - Pattern matching against function parameters should use `(param1, param2) when guards -> block` style.
  In other words, pattern matching in the form of `defun f({:ok, _})` is not supported.
  - Overloaded typespecs are not supported.
  """
  defmacro defun({:::, _, [fun, ret_type]}, [do: block]) do
    defun_impl(:def, fun, ret_type, [], block, __CALLER__)
  end
  defmacro defun({:when, _, [{:::, _, [fun, ret_type]}, type_params]}, [do: block]) do
    defun_impl(:def, fun, ret_type, type_params, block, __CALLER__)
  end

  @doc """
  Defines a private function together with its typespec.
  See `defun/2` for usage of this macro.
  """
  defmacro defunp({:::, _, [fun, ret_type]}, [do: block]) do
    defun_impl(:defp, fun, ret_type, [], block, __CALLER__)
  end
  defmacro defunp({:when, _, [{:::, _, [fun, ret_type]}, type_params]}, [do: block]) do
    defun_impl(:defp, fun, ret_type, type_params, block, __CALLER__)
  end

  @doc """
  Defines a unit-testable private function together with its typespec.
  See `defun/2` for usage of this macro.
  See also `Croma.Defpt.defpt/2`.
  """
  defmacro defunpt({:::, _, [fun, ret_type]}, [do: block]) do
    defun_impl(:defpt, fun, ret_type, [], block, __CALLER__)
  end
  defmacro defunpt({:when, _, [{:::, _, [fun, ret_type]}, type_params]}, [do: block]) do
    defun_impl(:defpt, fun, ret_type, type_params, block, __CALLER__)
  end

  defmodule Arg do
    defstruct [:name, :type, :default, :guard?]

    def new({name, type_expr1}) do
      {type_expr2, default} = extract_default(type_expr1)
      {type_expr3, guard? } = extract_guard(type_expr2)
      %Arg{name: name, type: type_expr3, default: default, guard?: guard?}
    end

    defp extract_default({:\\, _, [inner_expr, default]}), do: {inner_expr, default}
    defp extract_default(type_expr                      ), do: {type_expr , nil    }

    defp extract_guard({{:., _, [Access, :get]}, _, [{:g, _, _}, inner_expr]}), do: {inner_expr, true }
    defp extract_guard(type_expr                                             ), do: {type_expr , false}

    def guard_expr(%Arg{guard?: false}, _), do: nil
    def guard_expr(%Arg{guard?: true, name: name, type: type}, caller) do
      Croma.Guard.make(type, Macro.var(name, Croma), caller)
    end
  end

  defp defun_impl(def_or_defp, {fname, env, args0}, ret_type, type_params, block, caller) do
    args = case args0 do
      fcontext when is_atom(fcontext) -> []                  # function definition without parameter list
      _ -> (List.first(args0) || []) |> Enum.map(&Arg.new/1) # 1 argument: name-type keyword list
    end
    spec = typespec(fname, env, args, ret_type, type_params)
    bodyless = bodyless_function(def_or_defp, fname, env, args)
    fundef = function_definition(def_or_defp, fname, env, args, block, caller)
    {:__block__, [], [spec, bodyless, fundef]}
  end

  defp typespec(fname, env, args, ret_type, type_params) do
    arg_types = Enum.map(args, &(&1.type))
    func_with_return_type = {:::, [], [{fname, [], arg_types}, ret_type]}
    spec_expr = case type_params do
      [] -> func_with_return_type
      _  -> {:when, [], [func_with_return_type, type_params]}
    end
    {:@, env, [
        {:spec, [], [spec_expr]}
      ]}
  end

  defp bodyless_function(def_or_defp, fname, env, args) do
    arg_exprs = Enum.map(args, fn
      %Arg{name: name, default: nil    } -> {name, [], Elixir}
      %Arg{name: name, default: default} -> {:\\, [], [{name, [], Elixir}, default]}
    end)
    {def_or_defp, env, [{fname, env, arg_exprs}]}
  end

  defp function_definition(def_or_defp, fname, env, args, block, caller) do
    defs = case block do
      {:__block__, _, multiple_defs} -> multiple_defs
      single_def                     -> List.wrap(single_def)
    end
    if Enum.all?(defs, &pattern_match_expr?/1) do
      if Enum.any?(args, &(&1.guard?)), do: raise "guard generation cannot be used with clause syntax"
      clause_defs = Enum.map(defs, &to_clause_definition(def_or_defp, fname, &1))
      {:__block__, env, clause_defs}
    else
      # Ugly workaround for variable context issues with nested macro invocations: Overwrite context of every variables
      arg_names = Enum.map(args, &Macro.var(&1.name, Croma))
      block_with_modified_context = Macro.prewalk(block, fn
        {name, meta, context} when is_atom(context) -> {name, meta, Croma}
        t -> t
      end)
      guard_exprs = Enum.map(args, &Arg.guard_expr(&1, caller)) |> Enum.reject(&is_nil/1)
      if Enum.empty?(guard_exprs) do
        {def_or_defp, env, [{fname, env, arg_names}, [do: block_with_modified_context]]}
      else
        combined_guard_expr = Enum.reduce(guard_exprs, fn(expr, acc) -> {:and, env, [acc, expr]} end)
        {def_or_defp, env, [{:when, env, [{fname, env, arg_names}, combined_guard_expr]}, [do: block_with_modified_context]]}
      end
    end
  end

  defp pattern_match_expr?({:->, _, _}), do: true
  defp pattern_match_expr?(_          ), do: false

  defp to_clause_definition(def_or_defp, fname, {:->, env, [args, block]}) do
    case args do
      [{:when, _, when_args}] ->
        fargs = Enum.take(when_args, length(when_args) - 1)
        guards = List.last(when_args)
        when_expr = {:when, [], [{fname, [], fargs}, guards]}
        {def_or_defp, env, [when_expr, [do: block]]}
      _ ->
        {def_or_defp, env, [{fname, env, args}, [do: block]]}
    end
  end
end
