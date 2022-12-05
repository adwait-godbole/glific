defmodule Glific.Clients.Dev do
  @moduledoc """
  Tweak GCS Bucket name based on group that the contact is in (if any)
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Contacts.Contact,
    Groups.ContactGroup,
    Groups.Group,
    Repo,
    Templates.SessionTemplate
  }

  @sample_set [
    %{id: 1, name: "A"},
    %{id: 2, name: "B"},
    %{id: 3, name: "C"},
    %{id: 4, name: "D"},
    %{id: 5, name: "E"},
    %{id: 6, name: "F"},
    %{id: 7, name: "G"},
    %{id: 8, name: "H"},
    %{id: 9, name: "I"},
    %{id: 10, name: "J"},
    %{id: 11, name: "K"},
    %{id: 12, name: "L"},
    %{id: 13, name: "M"},
    %{id: 14, name: "N"},
    %{id: 15, name: "O"},
    %{id: 16, name: "P"},
    %{id: 17, name: "Q"},
    %{id: 18, name: "R"},
    %{id: 19, name: "S"},
    %{id: 20, name: "T"},
    %{id: 21, name: "U"},
    %{id: 22, name: "V"},
    %{id: 23, name: "W"}
  ]

  @doc """
  In the case of TAP we retrieve the first group the contact is in and store
  and set the remote name to be a sub-directory under that group (if one exists)
  """
  @spec gcs_file_name(map()) :: String.t()
  def gcs_file_name(media) do
    group_name =
      Contact
      |> where([c], c.id == ^media["contact_id"])
      |> join(:inner, [c], cg in ContactGroup, on: c.id == cg.contact_id)
      |> join(:inner, [_c, cg], g in Group, on: cg.group_id == g.id)
      |> select([_c, _cg, g], g.label)
      |> order_by([_c, _cg, g], g.label)
      |> first()
      |> Repo.one()

    if is_nil(group_name),
      do: media["remote_name"],
      else: group_name <> "/" <> media["remote_name"]
  end

  @doc """
  get template form EEx without variables
  """
  @spec template(String.t(), String.t()) :: binary
  def template(shortcode, params_staring \\ "") do
    [template | _tail] =
      SessionTemplate
      |> where([st], st.shortcode == ^shortcode)
      |> Repo.all()

    %{
      uuid: template.uuid,
      name: "Template",
      expression: nil,
      variables: parse_template_vars(template, params_staring)
    }
    |> Jason.encode!()
  end

  defp parse_template_vars(template, params_staring) do
    params = String.split(params_staring || "", "|", trim: true)

    if length(params) == template.number_parameters do
      params
    else
      params_with_missing =
        params ++ Enum.map(1..template.number_parameters, fn _i -> "{{ missing var  }}" end)

      Enum.take(params_with_missing, template.number_parameters)
    end
  end

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook("get_data", _fields) do
    data = Enum.take_random(@sample_set, Enum.random(1..5))

    %{data: data, count: length(data)}
  end

  def webhook(_, fields), do: fields
end
