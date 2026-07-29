// Cloudflare Turnstile widget, rendered explicitly rather than by the script's
// own DOM scan.
//
// The scan runs once at script load, which is the wrong moment for a LiveView:
// the form may arrive on a later patch, and a live navigation between
// /users/register and /users/log_in re-inserts the container without reloading
// the script. Rendering from `mounted()` ties the widget to the element's
// lifecycle instead, and `destroyed()` frees the widget id so a remount does
// not leak one per visit.
//
// The container itself carries `phx-update="ignore"` (see CoreComponents.captcha)
// because everything inside it — iframe, hidden input — is written by
// Cloudflare, and a patch that reconciled it away would take the token with it.

const SCRIPT_SRC =
  "https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit"

let scriptPromise = null

// One <script> per page, shared by however many widgets mount. Resolves on the
// existing tag when a previous mount already inserted it.
function loadScript() {
  if (scriptPromise) return scriptPromise

  scriptPromise = new Promise((resolve, reject) => {
    if (window.turnstile) return resolve()

    let script = document.querySelector(`script[src="${SCRIPT_SRC}"]`)
    if (!script) {
      script = document.createElement("script")
      script.src = SCRIPT_SRC
      script.async = true
      script.defer = true
      document.head.appendChild(script)
    }

    script.addEventListener("load", () => resolve())
    script.addEventListener("error", () =>
      reject(new Error("turnstile script failed to load"))
    )
  })

  return scriptPromise
}

export const Captcha = {
  mounted() {
    this.widgetId = null

    loadScript()
      .then(() => this.render())
      .catch((err) => {
        // Script blocked (extension, offline, firewalled). Say so where a
        // developer will see it; the server still rejects the empty token, so
        // this degrades to "cannot submit", never to "submitted unverified".
        console.error("[captcha]", err)
      })

    // A rejected token is spent — the next attempt needs a fresh one, so the
    // server asks for a reset rather than the form silently reusing a dead one.
    this.handleEvent("captcha:reset", () => this.reset())
  },

  render() {
    if (!window.turnstile || this.widgetId !== null) return

    this.widgetId = window.turnstile.render(this.el, {
      sitekey: this.el.dataset.sitekey,
      theme: this.el.dataset.theme || "auto",
      // The widget writes its token into a hidden input named
      // cf-turnstile-response, which rides along in the form's phx-submit
      // params at the top level (it is not namespaced under the form's `as`).
      response_field: true,
    })
  },

  reset() {
    if (window.turnstile && this.widgetId !== null) {
      window.turnstile.reset(this.widgetId)
    }
  },

  destroyed() {
    if (window.turnstile && this.widgetId !== null) {
      window.turnstile.remove(this.widgetId)
      this.widgetId = null
    }
  },
}
