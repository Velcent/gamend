// A `<video controls>` that has never been played does not show the poster the
// designer picked — every browser paints its own "not started" chrome over it,
// and all of it is dark:
//
//   Chrome  a near-black gradient across the bottom quarter for the control bar
//   Safari  dims the ENTIRE frame and stamps a play button in the middle
//
// Measured on the hero: the poster is luma 185, the strip Chrome puts over it
// is 68, and the bottom sixth is 39. So the thumbnail a first-time visitor sees
// is much darker and duller than the video it is advertising. No choice of
// poster frame can fix that — the chrome is painted on top of whichever frame
// you pick, and on the hero the poster was already brighter than every frame in
// the video.
//
// So `controls` is not rendered until the viewer asks to play. The markup ships
// an overlay <button> — a real one, so it takes focus and is announced — and
// this turns controls on, starts playback and retires the button on the first
// activation. From then on the native controls behave exactly as before.
//
// A delegated listener rather than per-element wiring: presentation pages are
// rendered by a plain controller with no LiveView on them, so there is no hook
// lifecycle to attach to, and the pages are also served from a cached body that
// can be swapped in without a reload.
const ROOT = "[data-video-cta]"
const BUTTON = "[data-video-cta-play]"

function start(button) {
  const root = button.closest(ROOT)
  const video = root?.querySelector("video")
  if (!video) return

  video.controls = true
  button.remove()

  // Autoplay policies can reject this (it is a user gesture, so normally they
  // do not). Either way the controls are now up, so the viewer can press play
  // themselves — hence no rethrow, just no unhandled rejection.
  const started = video.play()
  if (started && typeof started.catch === "function") started.catch(() => {})
}

export function startVideoClickToPlay() {
  document.addEventListener("click", (event) => {
    const button = event.target instanceof Element && event.target.closest(BUTTON)
    if (button) start(button)
  })
}
