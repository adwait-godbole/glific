defmodule Glific.Providers.GupshupContacts do
  @moduledoc """
  Contacts API layer between application and Gupshup
  """

  use Publicist

  import GlificWeb.Gettext

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Partners,
    Partners.Organization,
    Providers.Gupshup.ApiClient,
    Repo
  }

  @behaviour Glific.Providers.ContactBehaviour
  @days_shift -14

  @doc """
    Update a contact phone as opted in
  """
  @impl Glific.Providers.ContactBehaviour

  @spec optin_contact(map()) :: {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  def optin_contact(%{organization_id: organization_id} = attrs) do
    ApiClient.optin_contact(organization_id, %{user: attrs.phone})
    |> case do
      {:ok, %Tesla.Env{status: status}} when status in 200..299 ->
        %{
          name: attrs[:name],
          phone: attrs.phone,
          organization_id: organization_id,
          optin_time: Map.get(attrs, :optin_time, DateTime.utc_now()),
          optin_status: true,
          optin_method: Map.get(attrs, :method, "BSP"),
          language_id:
            Map.get(attrs, :language_id, Partners.organization_language_id(organization_id)),
          bsp_status: :hsm
        }
        |> create_or_update_contact()

      _ ->
        {:error, ["gupshup", "couldn't connect"]}
    end
  end

  @doc """
    This method creates a contact if it does not exist. Otherwise, updates it.
  """
  @spec create_or_update_contact(map()) :: {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  def create_or_update_contact(contact_data) do
    case Repo.get_by(Contact, %{phone: contact_data.phone}) do
      nil ->
        Contacts.create_contact(contact_data)

      contact ->
        # in the case of update we need to ensure that we preserve bsp_status
        # and optin_time, method if the contact is already opted in
        contact_data =
          if contact.optin_status,
            do:
              contact_data
              |> Map.put(:bsp_status, contact.bsp_status || contact_data.bsp_status)
              |> Map.put(:optin_method, contact.optin_method || contact_data.optin_method)
              |> Map.put(:optin_time, contact.optin_time || contact_data.optin_time),
            else: contact_data

        Contacts.update_contact(contact, contact_data)
    end
  end

  @doc """
  Fetch opted in contacts data from providers server
  """
  @spec fetch_opted_in_contacts(map()) :: :ok | any()
  def fetch_opted_in_contacts(attrs) do
    organization = Partners.organization(attrs.organization_id)

    case ApiClient.fetch_opted_in_contacts(attrs.organization_id) do
      {:ok, %Tesla.Env{status: status, body: body}} when status in 200..299 ->
        {:ok, response_data} = Jason.decode(body)

        if response_data["status"] == "error" do
          {:error,
           dgettext("errors", "Error updating opted-in contacts: %{message}",
             message: response_data["message"]
           )}
        else
          users = response_data["users"]
          update_contacts(users, organization)
        end

      {:ok, %Tesla.Env{status: status}} when status in 400..499 ->
        {:error, dgettext("errors", "Error updating opted-in contacts: Invalid BSP API key")}

      {:error, %Tesla.Error{reason: reason}} ->
        {:error,
         dgettext("errors", "Error updating opted-in contacts: %{reason}", reason: reason)}
    end

    :ok
  end

  @spec update_contacts(list() | nil, Organization.t() | nil) :: :ok | any()
  defp update_contacts(users, organization) do
    Enum.each(users, fn user ->
      if user["optinStatus"] == "OPT_IN" do
        # handle scenario when contact has not sent a message yet
        last_message_at = last_message_at(user["lastMessageTimeStamp"])

        {:ok, optin_time} = DateTime.from_unix(user["optinTimeStamp"], :millisecond)

        phone = user["countryCode"] <> user["phoneCode"]

        Contacts.upsert(%{
          phone: phone,
          last_message_at: last_message_at,
          optin_time: optin_time |> DateTime.truncate(:second),
          optin_status: true,
          optin_method: user["optinSource"],
          bsp_status: check_bsp_status(last_message_at),
          organization_id: organization.id,
          language_id: organization.default_language_id,
          last_communication_at: last_message_at
        })
      end
    end)
  end

  @spec last_message_at(non_neg_integer()) :: DateTime.t()
  defp last_message_at(0) do
    Timex.shift(DateTime.utc_now(), days: @days_shift)
  end

  defp last_message_at(time) do
    DateTime.from_unix(time, :millisecond)
    |> elem(1)
    |> DateTime.truncate(:second)
  end

  @spec check_bsp_status(DateTime.t()) :: atom()
  defp check_bsp_status(last_message_at) do
    if Timex.diff(DateTime.utc_now(), last_message_at, :hours) < 24 do
      :session_and_hsm
    else
      :hsm
    end
  end
end
