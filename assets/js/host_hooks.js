// Host-side extras loaded by the web app through the `gamend-extra-hooks`
// meta tag (see :extra_hook_modules in config/host_config.exs). Ported from
// the gamend_polyglot host.

// Click a section illustration to see it full-size. The dialog is built once,
// on first use, rather than one per image: a page can carry a dozen and each
// would otherwise duplicate its src in the DOM.
//
// `<dialog>.showModal()` is doing the work — focus trap, Esc to close and the
// backdrop all come from the element, so there is no key handling here.
let lightboxDialog = null

function ensureLightboxDialog() {
  if (lightboxDialog) return lightboxDialog

  // Inline styles rather than Tailwind classes: this markup exists only in
  // this file, so the CSS build never sees the class names and purges them —
  // the dialog would open completely unstyled.
  const dialog = document.createElement("dialog")
  Object.assign(dialog.style, {
    position: "fixed",
    inset: "0",
    width: "100%",
    height: "100%",
    maxWidth: "100%",
    maxHeight: "100%",
    margin: "0",
    padding: "0",
    border: "0",
    overflow: "hidden",
    background: "rgba(0, 0, 0, 0.85)",
  })

  const image = document.createElement("img")
  Object.assign(image.style, {
    position: "absolute",
    top: "50%",
    left: "50%",
    transform: "translate(-50%, -50%)",
    maxWidth: "92vw",
    maxHeight: "92vh",
    objectFit: "contain",
    borderRadius: "0.5rem",
    cursor: "zoom-out",
  })
  dialog.appendChild(image)

  // Anywhere at all closes it, the picture included: at this size there is
  // nothing else to aim at, and hunting for a corner is worse than a tap.
  dialog.addEventListener("click", () => dialog.close())
  // Free the bytes when it is put away; a page of screenshots keeps them all
  // decoded otherwise.
  dialog.addEventListener("close", () => image.removeAttribute("src"))

  document.body.appendChild(dialog)
  lightboxDialog = dialog
  return dialog
}

function startImageLightbox() {
  document.querySelectorAll("img[data-lightbox]").forEach((image) => {
    if (image.dataset.lightboxBound === "true") return

    image.dataset.lightboxBound = "true"
    image.style.cursor = "zoom-in"
    image.addEventListener("click", () => {
      const dialog = ensureLightboxDialog()
      const full = dialog.querySelector("img")
      full.src = image.currentSrc || image.src
      full.alt = image.alt || ""
      dialog.showModal()
    })
  })
}

if (typeof document !== "undefined") {
  // This module is imported dynamically, so DOMContentLoaded has usually
  // already fired by the time it runs — listening for it alone silently does
  // nothing.
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", startImageLightbox, { once: true })
  } else {
    startImageLightbox()
  }

  // LiveView navigation replaces the DOM; rebind whatever is new. The
  // per-image bound flag makes this idempotent.
  window.addEventListener("phx:page-loading-stop", startImageLightbox)
}

// No LiveView hooks yet — the loader merges this into its hook map.
export const hooks = {}
