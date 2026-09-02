defmodule GamendWeb.Api.V1.PaymentWebhookController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gamend.Payments

  tags(["Payments"])

  operation(:stripe,
    operation_id: "payments_stripe_webhook",
    summary: "Receive Stripe webhook events",
    request_body: {"Stripe event", "application/json", %OpenApiSpex.Schema{type: :object}},
    responses: [
      ok: {"Accepted", "application/json", %OpenApiSpex.Schema{type: :object}},
      bad_request: {"Invalid webhook", "application/json", %OpenApiSpex.Schema{type: :object}}
    ]
  )

  def stripe(conn, _params) do
    raw_body = conn.private[:raw_body] || ""
    signature = conn |> get_req_header("stripe-signature") |> List.first()

    case Payments.handle_stripe_webhook(raw_body, signature) do
      {:ok, status} ->
        json(conn, %{ok: true, status: status})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: normalize_error(reason)})
    end
  end

  operation(:google,
    operation_id: "payments_google_webhook",
    summary: "Receive Google Play RTDN Pub/Sub push events",
    request_body: {"Google RTDN event", "application/json", %OpenApiSpex.Schema{type: :object}},
    responses: [
      ok: {"Accepted", "application/json", %OpenApiSpex.Schema{type: :object}},
      bad_request: {"Invalid webhook", "application/json", %OpenApiSpex.Schema{type: :object}}
    ]
  )

  def google(conn, params) do
    raw_body = conn.private[:raw_body] || ""

    # Pub/Sub push subscriptions cannot send a custom `Authorization` header —
    # they send a Google-signed OIDC token instead — so a deployment configured
    # per our own docs had every real notification rejected, and voided
    # purchases and subscription revocations silently never landed. Pub/Sub
    # *can* carry a query string on the push endpoint URL, which is the
    # documented way to give it a shared secret, so accept the token there too:
    #
    #     https://your.host/api/v1/payments/webhooks/google?token=<GAMEND_PAYMENTS_GOOGLE_PLAY_RTDN_TOKEN>
    #
    # Verifying the OIDC token would be stronger and is the better long-term
    # answer; this makes the configured secret actually usable in the meantime.
    authorization =
      case get_req_header(conn, "authorization") do
        [header | _] -> header
        [] -> query_token(params)
      end

    case Payments.handle_google_webhook(raw_body, authorization) do
      {:ok, status} ->
        json(conn, %{ok: true, status: status})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: normalize_error(reason)})
    end
  end

  operation(:apple,
    operation_id: "payments_apple_webhook",
    summary: "Receive App Store Server Notification v2 events",
    request_body: {"Apple notification", "application/json", %OpenApiSpex.Schema{type: :object}},
    responses: [
      ok: {"Accepted", "application/json", %OpenApiSpex.Schema{type: :object}},
      bad_request: {"Invalid webhook", "application/json", %OpenApiSpex.Schema{type: :object}}
    ]
  )

  def apple(conn, _params) do
    raw_body = conn.private[:raw_body] || ""

    case Payments.handle_apple_webhook(raw_body) do
      {:ok, status} ->
        json(conn, %{ok: true, status: status})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: normalize_error(reason)})
    end
  end

  defp query_token(%{"token" => token}) when is_binary(token) and token != "",
    do: "Bearer " <> token

  defp query_token(_params), do: nil

  defp normalize_error(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp normalize_error(reason), do: inspect(reason)
end
