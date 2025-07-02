defmodule Guardian.Plug.EnsureNotAuthenticatedTest do
  @moduledoc false

  import Plug.Test
  import Plug.Conn
  use ExUnit.Case, async: true

  alias Guardian.Plug.EnsureNotAuthenticated

  @resource %{id: "bobby"}

  defmodule Handler do
    @moduledoc false

    import Plug.Conn
    @behaviour Guardian.Plug.ErrorHandler

    @impl Guardian.Plug.ErrorHandler
    def auth_error(conn, {type, reason}, _opts) do
      body = inspect({type, reason})

      conn
      |> send_resp(401, body)
    end
  end

  defmodule Impl do
    @moduledoc false

    use Guardian,
      otp_app: :guardian,
      token_module: Guardian.Support.TokenModule

    def subject_for_token(%{id: id}, _claims), do: {:ok, id}
    def subject_for_token(%{"id" => id}, _claims), do: {:ok, id}

    def resource_from_claims(%{"sub" => id}), do: {:ok, %{id: id}}
  end

  setup do
    handler = __MODULE__.Handler
    {:ok, token, claims} = __MODULE__.Impl.encode_and_sign(@resource)
    {:ok, %{claims: claims, conn: conn(:get, "/"), token: token, handler: handler}}
  end

  describe "with a verified token" do
    setup ctx do
      conn =
        ctx.conn
        |> Guardian.Plug.put_current_token(ctx.token, [])
        |> Guardian.Plug.put_current_claims(ctx.claims, [])

      {:ok, %{conn: conn}}
    end

    test "it returns an error", ctx do
      conn = EnsureNotAuthenticated.call(ctx.conn, error_handler: ctx.handler)
      assert {401, _, "{:already_authenticated, :already_authenticated}"} = sent_resp(conn)
      assert conn.halted
    end

    test "does not halt conn when option is set to false", ctx do
      conn = EnsureNotAuthenticated.call(ctx.conn, error_handler: ctx.handler, halt: false)
      assert {401, _, "{:already_authenticated, :already_authenticated}"} = sent_resp(conn)
      refute conn.halted
    end
  end

  describe "with no verified token" do
    test "it allows the request to continue", ctx do
      conn = EnsureNotAuthenticated.call(ctx.conn, error_handler: ctx.handler)
      refute conn.halted
      refute conn.status == 401
    end
  end
end
