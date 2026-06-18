# Spec: Live Interaction URL for the CHAPI Demos
> **⚠️ The important change:** the CHAPI demos are all static sites today. Making the interaction URL real means adding the **first backend service to the demo stack** — a small exchange service that the demo issuer creates an exchange on per store request, and that a wallet (same-device or cross-device) dereferences to complete the flow. Everything else in this spec follows from that.

Status: **DRAFT** — for discussion on [chapi-demo-issuer#14](https://github.com/credential-handler/chapi-demo-issuer/pull/14).
## Summary
chapi-demo-issuer#14 sends a fake `interact` protocol URL so the CHAPI mediator's cross-device QR section (credential-handler/authn.io#167) renders. But the URL is not live and the demo wallet ignores `protocols` entirely, so:

- scanning the QR code on another device goes nowhere; and
  
- the same-device demo wallet never exercises the interaction URL path.
  

This spec makes the interaction URL functional end to end across three pieces: a new demo exchange service, the demo issuer, and the demo wallet.
## Current State
| Piece | Today |
|---|---|
| `chapi-demo-issuer` | Static site. Sends `protocols: {interact (fake), OID4VC (fake), vcapi (fake)}`; VP embedded directly in the `WebCredential`. |
| `chapi-demo-wallet` | Static site. `wallet-ui-store.html` reads the embedded VP from `event.credential.data`; `protocols` never inspected. No QR scanning, no URL dereferencing. |
| Mediator (authn.io ≥7.3.0) | Shows the cross-device QR section when the request carries an https `interact`/`interaction` URL with `iuv=1`. |
## Goals
1. The QR code shown by the mediator encodes a **live** interaction URL: a wallet on a second device can dereference it and receive the demo VP.
  
2. The same-device demo wallet **prefers** `protocols.interact` when present, fetching the VP via the exchange instead of (or in addition to) the embedded copy, demonstrating the protocol-based path.
  
3. The demo wallet gains an entry point for cross-device use: accept an interaction URL (paste box, or prefilled via the exchanger's redirect page) and complete the exchange.
  
## Non-Goals
- Production-grade exchange infrastructure (auth, persistence, multi-tenant).
  
- DIDAuth / holder binding within the exchange.
  
- Changing the mediator (authn.io) — it already does its part.
  
- The `get()`/verifier flow (issuer `store()` flow first; verifier is a follow-up that reuses the same service).
  
## Design
### 1. New: demo exchange service
A minimal Node service (working name: `chapi-demo-exchanger`) speaking a deliberately demo-shaped protocol — just the two endpoints below, not full VC-API exchanges (see Resolved Decisions). In-memory state only.

Endpoints:

- `POST /exchanges` — called by the demo issuer page when the user clicks store. Body: `{verifiablePresentation}`. Returns `{exchangeId, interactionUrl}` where `interactionUrl = https://<exchanger-host>/exchanges/<exchangeId>?iuv=1`.
  
- `POST /exchanges/:id` — called by a wallet dereferencing the interaction URL. Returns `{verifiablePresentation}` for the wallet to store.
  

Properties:

- Exchange records are in-memory, **single-use**, expire after a short TTL (proposal: 15 minutes — matches a user finishing a QR scan).
  
- `exchangeId` is an unguessable random value (≥128 bits).
  
- CORS: allow the demo wallet origins (the wallet dereferences the URL from the browser).
  
- Deployment: a container in the demo stack alongside the three existing demos; needs a public TLS hostname so phones can reach it.
  

A new self-contained service rather than an existing DB exchanger — see Resolved Decisions.
### 2. Demo issuer changes (`chapi-demo-issuer`)
On store click:

1. `POST /exchanges` to the exchange service with the test VP.
  
2. Put the returned `interactionUrl` in `protocols.interact` (replacing the fake URL from chapi-demo-issuer#14).
  
3. Keep the embedded VP and the fake `OID4VC`/`vcapi` entries as-is, so the demo still works if the exchange service is down (fail soft: fall back to the fake URL or omit `interact`).
  
### 3. Demo wallet, same-device path (`chapi-demo-wallet`)
In `wallet-ui-store.html`:

- If `event.credential.options?.protocols?.interact` is present, dereference it (`POST`, per the exchange service contract) and store the returned VP; show which path was used in the UI (useful for demos).
  
- Fall back to the embedded `event.credential.data` if dereferencing fails.
  
### 4. Demo wallet, cross-device path (`chapi-demo-wallet`)
New page (e.g. `interact.html`), reachable from the wallet home page:

- A text input to paste an interaction URL (also prefilled when arriving via the exchanger's redirect page — see note below).
  
- Validate: https + `iuv=1` (same rule the mediator applies).
  
- Dereference the exchange and store the resulting VP via the existing `storeInWallet()` mock storage.
  
- No in-wallet QR scanner is planned: phones scan the mediator's QR with their built-in camera app, which opens the interaction URL and redirects here (see Open Questions).
  

Note: on a phone, the natural flow is scan with the camera app → opens the interaction URL in the browser. The exchange service serves a tiny HTML page on `GET /exchanges/:id?iuv=1` that links/redirects into the demo wallet's `interact.html` with the URL prefilled, making the QR scan-to-store flow work with zero typing. Complexity is minimal: one extra GET route returning a small static HTML page (~20 lines); no state or logic beyond what the exchanger already has.
## Data Flow (cross-device)
```
issuer page ── POST /exchanges {vp} ──▶ exchanger (stores vp, TTL)
issuer page ── store(WebCredential{protocols.interact: url}) ──▶ mediator
mediator ── renders QR(url) ──▶ user scans with phone
phone ── GET url ──▶ exchanger ── redirect ──▶ demo wallet interact.html
demo wallet ── POST url ──▶ exchanger ── {vp} ──▶ wallet stores vp
```
## Personal Information Impact
Demo/test data only — the VP is the canned fake university degree credential; no real PII is collected, stored, or transmitted. The exchange service holds that fake VP transiently in memory (single-use, short TTL, never logged). No accounts, cookies, or tracking. If the demos are ever changed to accept user-supplied credentials, this section must be revisited.
## Security Considerations
- Interaction URLs are capability URLs: possession grants the VP. Mitigated by demo-only data, unguessable IDs, single-use semantics, and short TTL.
  
- TLS required end to end (the mediator already rejects non-https URLs).
  
- The exchange service accepts arbitrary VPs for storage — bound the payload size and per-IP exchange creation rate to keep the demo service abuse-safe.
  
- No authentication by design (demo); the service must never be extended to hold real credentials without adding it.
  
## Testing
- Local: extend the `chapi-demo-stack` docker compose with the exchanger container; the existing cloudflared tunnels make the interaction URL reachable from a phone.
  
- Manual happy path: issuer store → QR appears → scan on phone → wallet stores VP → both devices confirm.
  
- Failure paths: expired exchange, reused exchange, exchanger down (issuer falls back), invalid URL pasted into `interact.html`.
  
## Resolved Decisions
- **Protocol stays demo-shaped.** The exchanger speaks only the minimal two-endpoint protocol above, not full VC-API exchanges. Matching VC-API exactly would let real wallets complete the exchange but adds spec surface the demo doesn't need.
  
- **Keep the exchanger's** `GET` **redirect page.** It's what makes camera-app scanning work with zero typing, and it costs one static-HTML GET route (~20 lines) — cheaper than teaching the QR to encode a wallet-wrapping URL, which would also stop the QR from encoding the actual interaction URL.
  
- **New minimal service** rather than piggybacking on an existing DB VC-API workflow service (follows from the demo-shaped protocol decision).
  
## Open Questions
1. Repo/home for the exchanger: new `chapi-demo-exchanger` repo vs. a directory in `chapi-demo-stack`? Leaning new repo; confirm with reviewers.
  
2. Does the demo wallet need its own **in-page QR scanner** (using the browser camera API from `interact.html`), or is the phone's built-in camera app enough — i.e. scan with the camera app → URL opens in the browser → exchanger redirect lands in the wallet? Assumed: the camera app path is enough and no in-wallet scanner is built.
