# Rendering strategy

Hybrid by default: static unless a route genuinely needs request-time data,
auth, or personalization. No blanket `force-dynamic`/`force-static` anywhere
in this app. The per-route reasoning lives as a comment at the top of each
file; this note is the one-page summary the Founder's directive asked for.

Heuristic used everywhere below: *Is this content the same for all visitors
and stable? → static. Does it depend on the current user, auth, or
request-specific data? → dynamic, and keep a static shell around it where
one exists.*

## User Hub (built)

| Route | Strategy | Why |
|---|---|---|
| `/` | Static | Marketing pitch, identical for every anonymous visitor. The signed-in-user redirect lives in `middleware.ts`, not in the page, so the component itself has no cookie dependency. |
| `/login` | Static (client component) | No server data at all; Supabase auth runs in the browser post-hydration. |
| `/register` | Fully dynamic | Single-user gate + form; nothing on it is shared across visitors. |
| `/verify` | Fully dynamic | Which of three states renders depends entirely on this user's own verification/actor rows. |
| `/dashboard` (layout) | Fully dynamic, not Suspense-split | Nav and header content depend on the same auth/profile/actor gate that also decides whether to redirect away — no data-independent shell exists above that gate. |
| `/dashboard/orders` | Hybrid | Static heading shell; RLS-scoped order list streams in via Suspense. |
| `/dashboard/notifications` | Hybrid | Static heading shell; per-user notification list streams in via Suspense. |
| `/dashboard/raise-intent` | Hybrid | Static heading shell; service catalogue + actor lookup stream in via Suspense before the client form mounts. |

## Not yet built

Marketplace, Operator App, Executive Dashboard, Admin Console don't exist in
this app yet. When built:

- **Marketplace** (public-facing, like User Hub): default static/ISR for
  listing/browse pages, hybrid for anything user-specific (cart, orders),
  same pattern as `/dashboard/*` above.
- **Operator App / Executive Dashboard / Admin Console** (internal
  workforce only): default dynamic/hybrid — almost every view is
  personalized or permission-gated. Still extract static UI chrome
  (layout frames, icons, labels) into non-async components and stream
  genuinely live operational data (dispatch queues, live positions) via
  client-side polling/subscriptions after the initial shell loads, rather
  than re-fetching the full page. Prioritize correctness and freshness
  over static performance — these are internal tools, not public pages.
