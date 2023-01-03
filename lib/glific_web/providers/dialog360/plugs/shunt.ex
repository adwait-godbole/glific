defmodule GlificWeb.Providers.Dialog360.Plugs.Shunt do
  @moduledoc """
  A Dialog360 shunt which will redirect all the incoming requests to the dialog360 router based on there event type.
  """

  alias Plug.Conn

  alias Glific.{Appsignal, Partners, Partners.Organization, Repo}

  @doc false
  @spec init(Plug.opts()) :: Plug.opts()
  def init(opts), do: opts

  @doc """
  Build the context with the root user for all dialog360 calls, this
  gives us permission to update contacts etc
  """
  @spec build_context(Conn.t()) :: Organization.t()
  def build_context(conn) do
    organization = Partners.organization(conn.assigns[:organization_id])
    Repo.put_current_user(organization.root_user)
    organization
  end

  @doc false
  @spec call(Plug.Conn.t(), Plug.opts()) :: Plug.Conn.t()
  def call(conn, opts) do

    IO.inspect(conn)
    IO.inspect(opts)

  end


  @doc false
  @spec change_path_info(Plug.Conn.t(), list()) :: Plug.Conn.t()
  def change_path_info(conn, new_path) do
    ## setting up appsignal namespace so that we can ignore this
    Appsignal.set_namespace("dialog360_webhooks")
    put_in(conn.path_info, new_path)
  end
end
