defmodule GamendWeb.Schemas.Session do
  @moduledoc """
  A signed-in session: what email login, device login and refresh answer
  under `data`.
  """
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "Session",
    description: "Tokens for a signed-in user",
    type: :object,
    properties: %{
      access_token: %Schema{type: :string, description: "JWT access token (15 min)"},
      refresh_token: %Schema{type: :string, description: "JWT refresh token (30 days)"},
      expires_in: %Schema{type: :integer, description: "Seconds until the access token expires"},
      user_id: %Schema{type: :string, format: :uuid},
      username: %Schema{type: :string, description: "Unique handle"},
      display_name: %Schema{type: :string, description: "Chosen name"}
    },
    required: [:access_token, :refresh_token, :expires_in, :user_id, :username, :display_name],
    example: %{
      access_token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
      refresh_token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
      expires_in: 900,
      user_id: "0198c0de-0002-7000-8000-000000000002",
      username: "coolplayer-1234",
      display_name: "CoolPlayer"
    }
  })
end

defmodule GamendWeb.Schemas.SessionResponse do
  @moduledoc "A session under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.Session
end

defmodule GamendWeb.Schemas.OAuthResult do
  @moduledoc """
  What a provider token exchange answers. Two outcomes share it, because the
  wire does: without a bearer token the user signs in and the token fields are
  set; with one, the provider is linked to that account and `linked` and
  `provider` are set instead.
  """
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "OAuthResult",
    description:
      "Tokens when signing in; `linked` and `provider` when linking to the bearer's account",
    type: :object,
    properties: %{
      access_token: %Schema{type: :string, description: "Sign-in only"},
      refresh_token: %Schema{type: :string, description: "Sign-in only"},
      expires_in: %Schema{type: :integer, description: "Sign-in only: seconds until expiry"},
      user_id: %Schema{type: :string, format: :uuid, description: "Sign-in only"},
      linked: %Schema{type: :boolean, description: "Link only: always true"},
      provider: %Schema{type: :string, description: "Link only: the account field linked"}
    }
  })
end

defmodule GamendWeb.Schemas.OAuthResultResponse do
  @moduledoc "An OAuth exchange result under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.OAuthResult
end

defmodule GamendWeb.Schemas.OAuthAuthorization do
  @moduledoc "Where to send the player to sign in, and the session to poll for the result."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "OAuthAuthorization",
    description: "A started OAuth sign-in",
    type: :object,
    properties: %{
      authorization_url: %Schema{type: :string, description: "Open this for the player"},
      session_id: %Schema{
        type: :string,
        description: "Poll `GET /auth/session/{session_id}` with it"
      }
    },
    required: [:authorization_url, :session_id],
    example: %{
      authorization_url: "https://discord.com/oauth2/authorize?...",
      session_id: "abc123..."
    }
  })
end

defmodule GamendWeb.Schemas.AuthProvidersResponse do
  @moduledoc "The OAuth providers a player may sign in with, under `data`."
  alias OpenApiSpex.Schema

  use GamendWeb.Schemas.Envelope,
    data: %Schema{
      type: :array,
      items: %Schema{type: :string, enum: ["discord", "google", "apple", "facebook", "steam"]}
    },
    description: "Enabled sign-in providers under `data`"
end

defmodule GamendWeb.Schemas.OAuthAuthorizationResponse do
  @moduledoc "A started OAuth sign-in under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.OAuthAuthorization
end

defmodule GamendWeb.Schemas.OAuthSessionStatusResponse do
  @moduledoc "An OAuth session's state under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.OAuthSessionStatus
end
