defmodule Ldap.Ecto.Adapter do
  ####
  # Ecto.Adapter
  ##

  # TYPES

  # @type t :: Ecto.Adapter.t
  @type t :: Ecto.Adapter.Custom

  @type query_meta
    :: %{
      prefix: binary | nil,
      sources: tuple,
      preloads: term,
      select: map
    }

  @type schema_meta
    :: %{
      source: source,
      schema: atom,
      context: term,
      autogenerate_id: {atom, :id | :binary_id}
    }

  @type source
    :: {prefix :: binary | nil, table :: binary}

  @type fields
    :: Keyword.t

  @type filters
    :: Keyword.t

  @type constraints
    :: Keyword.t

  @type returning
    :: [atom]

  @type prepared
    :: term

  @type cached
    :: term

  @type process
    :: (field :: Macro.t, value :: term, context :: term -> term)

  @type on_conflict
    :: {:raise, list(), []} |
       {:nothing, list(), [atom]} |
       {Ecto.Query.t, list(), [atom]}

#  @type autogenerate_id
#    :: {field :: atom, type :: :id | :binary_id, value :: term} | nil

  @typep repo :: Ecto.Repo.t

  @typep options :: Keyword.t


# CALLBACKS

  @behaviour Ecto.Adapter

  alias Ldap.Ecto
  alias Ldap.Ecto.{Adapter, Helper, Converter}

  # Ecto.Adapter.__before_compile__/1
  # @spec __before_compile__(term, env :: Macro.Env.t) :: Macro.t # <- extra term in docs?
  # @spec __before_compile__(env :: Macro.Env.t) :: Macro.t
  defmacro __before_compile__(env) do
#    module = env.module
#    config = Module.get_attribute(module, :config)
  end

  # Ecto.Adapter.autogenerate/1
  @spec autogenerate(field_type :: :id | :binary_id | :embed_id)
    ::  term |
        nil |
        no_return

  def autogenerate(_field_type) do
    nil
  end

  # Ecto.Adapter.child_spec/2
  @spec child_spec(repo, options)
    :: :supervisor.child_spec

  def child_spec(repo, options) do
    Supervisor.Spec.worker(Ldap.Ecto, [repo, options], name: Ldap.Ecto)
  end

  # Ecto.Adapter.ensure_all_started/2
  @spec ensure_all_started(repo, type :: :application.restart_type)
    ::  {:ok, [atom]} |
        {:error, atom}

  def ensure_all_started(_repo, _restart_type) do
#    Ldap.Ecto.start_link
    {:ok, []}
  end

  # Ecto.Adapter.delete/4
  @spec delete(repo, schema_meta, filters, options)
    ::  {:ok, fields} |
        {:invalid, constraints} |
        {:error, :stale} |
        no_return

  def delete(_repo, _schema_meta, _filters, _options) do

  end

  # Ecto.Adapter.dumpers/2
  @spec dumpers(primitive_type :: Ecto.Type.primitive, ecto_type :: Ecto.Type.t)
    :: [(term -> {:ok, term} | :error) | Ecto.Type.t]

  def dumpers(_, nil), do: {:ok, nil}
  def dumpers({:in, _type}, {:in, _}), do: [&Helper.dump_in/1]
  def dumpers(:string, _type), do: [&Helper.dump_string/1]
  def dumpers({:array, :string}, _type), do: [&Helper.dump_array/1]
  def dumpers(:datetime, _type), do: [&Helper.dump_date/1]
  def dumpers(Ecto.DateTime, _type), do: [&Helper.dump_date/1]
  def dumpers(_primitive, type), do: [type]

  # Ecto.Adapter.execute/6
  @spec execute(repo, query_meta, query, params :: list, process | nil, options)
    :: result
    when
      result: {integer, [[term]] | nil} | no_return,
      query:
        {:nocache, prepared} |
        {:cached, (prepared -> :ok), cached} |
        {:cache, (cached -> :ok), prepared}

  def execute(_repo, query_meta, {:nocache, prepared}, params, process, options) do
    {:filter, filter} = Helper.construct_filter(Keyword.get(prepared, :filter), params)
    options_filter = :eldap.and(Converter.options_to_filter(options))
    full_filter = :eldap.and([filter, options_filter])

    search_response =
      prepared
      |> Keyword.put(:filter, options_filter)
      |> Helper.replace_dn_search_with_objectclass_present
      |> Helper.merge_search_options(prepared)
      |> Ldap.Ecto.search

      fields = Helper.ordered_fields(query_meta.sources)
      count = Helper.count_fields(query_meta.select.preprocess, query_meta.sources)

      {:ok, {:eldap_search_result, results, []}} = search_response

      result_set =
        for entry <- results do
          entry
          |> Helper.process_entry
  #        |> Helper.prune_attrs(fields, count)
          |> Helper.generate_models(process, query_meta.select.preprocess)
        end

      {count, result_set}
  end


  # Ecto.Adapter.insert/6
  @spec insert(repo, schema_meta, fields, on_conflict, returning, options)
    ::  {:ok, fields} |
        {:invalid, constraints} |
        no_return

  def insert(_repo, _schema_meta, _fields, _on_conflict, _returning, _options) do

  end

  # Ecto.Adapter.insert_all/7
  @spec insert_all(repo, schema_meta, header :: [atom], [fields], on_conflict, returning, options)
    ::  {integer, [[term]] | nil} |
        no_return

  def insert_all(_repo, _schema_meta, _header, _rows, _on_conflict, _returning, _options) do

  end

  # Ecto.Adapter.loaders/2
  @spec loaders(primitive_type :: Ecto.Type.primitive, ecto_type :: Ecto.Type.t)
    :: [(term -> {:ok, term} | :error) | Ecto.Type.t]

  def loaders(:id, type), do: [type]
  def loaders(:string, _type), do: [&Helper.load_string/1]
  def loaders(:binary, _type), do: [&Helper.load_string/1]
  def loaders(:datetime, _type), do: [&Helper.load_date/1]
  def loaders(Ecto.DateTime, _type), do: [&Helper.load_date/1]
  def loaders({:array, :string}, _type), do: [&Helper.load_array/1]
  def loaders(_primitive, nil), do: [nil]
  def loaders(_primitive, type), do: [type]

  # Ecto.Adapter.prepare/2
  @spec prepare(atom :: :all | :update_all | :delete_all, query :: Ecto.Query.t)
    ::  {:cache, prepared} |
        {:nocache, prepared}

  def prepare(:all, query) do
    query_meta =
      [
        Helper.construct_filter(query),
        Helper.construct_base(query),
        Helper.construct_scope(query),
        Helper.construct_attributes(query),
      ]
  #    |> Enum.map(&(apply(Ldap.Ecto, &1, [query])))
      |> Enum.filter(&(&1))

      {:nocache, query_meta}
  end

  def prepare(:update_all, query), do: raise "Update is currently unsupported"
  def prepare(:delete_all, query), do: raise "Delete is currently unsupported"

  # Ecto.Adapter.update/6
  @spec update(repo, schema_meta, fields, filters, returning, options)
    ::  {:ok, fields} |
        {:invalid, constraints} |
        {:error, :stale} |
        no_return

  def update(_repo, _schema_meta, _fields, _filters, _returning, _options) do

  end

end
