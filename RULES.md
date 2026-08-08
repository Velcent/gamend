# Rules

## Design & Accessibility

- Contrast floors are WCAG AA: 4.5:1 for text, 3:1 for large text and UI components (focus rings, borders, icons that carry meaning).
- Every status and primary token pair (`--color-X` with `--color-X-content`, and on `base-100`) must pass AA in both themes; `apps/gamend_web/test/gamend_web/a11y_contrast_test.exs` asserts the exact pairs and fails on drift.
- Muted readable text (labels, subtitles, timestamps, counts) uses `text-base-content/70` or stronger. Decorative/disabled looks never go below `/50`.
- Minimum font size is 12px (`text-xs`). No `text-[10px]`/`text-[11px]` outside a genuinely space-constrained badge, and never below 11px.
- Interactive targets are at least 44px on coarse pointers (enforced in `assets/css/app.css`).
- Radii come from the daisyUI tokens only: 4px fields, 8px boxes. No ad-hoc `rounded-*` values.
- Every infinite/ambient animation and smooth scroll sits behind `prefers-reduced-motion`.
- Icon-only buttons and links carry an accessible name (`aria-label` or `sr-only` text).
