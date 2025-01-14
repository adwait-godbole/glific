defmodule Glific.Flows.FlowRevision do
  @moduledoc """
  The flow revision object which encapsulates the complete flow as emitted by
  by `https://github.com/nyaruka/floweditor`
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__

  alias Glific.{
    Flows.Flow,
    Partners.Organization,
    Repo
  }

  @required_fields [:definition, :flow_id, :organization_id]
  @optional_fields [:revision_number, :status, :version]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          definition: map() | nil,
          revision_number: integer() | nil,
          version: integer() | nil,
          status: String.t() | nil,
          flow_id: non_neg_integer | nil,
          flow: Flow.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime_usec | nil,
          updated_at: :utc_datetime_usec | nil
        }

  schema "flow_revisions" do
    field(:definition, :map)

    # this value is only needed for revisions that are published at any point
    # this basically allows us to map specific data to a specific flow versio
    field(:version, :integer, default: 0)

    field(:revision_number, :integer)

    # the values for status are: draft, published, archived
    # archived is for versions which were published previously
    field(:status, :string, default: "draft")

    belongs_to(:flow, Flow)
    belongs_to(:organization, Organization)

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(FlowRevision.t(), map()) :: Ecto.Changeset.t()
  def changeset(flow_revision, attrs) do
    flow_revision
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_published_flow_revision(flow_revision, attrs)
  end

  @doc """
  Default definition when we create a new flow
  """
  @spec default_definition(Flow.t()) :: map()
  def default_definition(flow) do
    %{
      "name" => flow.name,
      "uuid" => flow.uuid,
      "spec_version" => "13.1.0",
      "language" => "base",
      "type" => "messaging",
      "nodes" => [],
      "_ui" => %{},
      "revision" => 1,
      "expire_after_minutes" => 10_080
    }
  end

  @doc false
  @spec create_flow_revision(map()) :: {:ok, FlowRevision.t()} | {:error, Ecto.Changeset.t()}
  def create_flow_revision(attrs \\ %{}) do
    %FlowRevision{}
    |> FlowRevision.changeset(attrs)
    |> Repo.insert()
  end

  ## check only when we are publishing a flow
  defp validate_published_flow_revision(changeset, flow_revision, %{status: "published"} = _attrs) do
    Repo.fetch_by(FlowRevision, %{flow_id: flow_revision.flow_id, status: "published"})
    |> case do
      {:ok, flow_revision} ->
        add_error(
          changeset,
          :status,
          "Flow is already published with id #{flow_revision.id}, please archive it instead "
        )

      _ ->
        changeset
    end
  end

  defp validate_published_flow_revision(changeset, _, _), do: changeset
end
