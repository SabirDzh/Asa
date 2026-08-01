# Browser performance and security hardening

## Goal
Reduce avoidable memory/network work in the in-app browser without weakening the existing HTTPS-only navigation policy or breaking task-link behavior.

## Scope
1. Inspect the current WebView and favicon flow and use only APIs available in the existing dependency set.
2. Add bounded in-memory favicon reuse and decode favicons at a small target size.
3. Keep favicon work non-blocking and avoid favicon requests for HTTP or invalid URLs.
4. Configure the WebView for a neutral background and retain JavaScript unrestricted for general web compatibility, while preserving the existing no-bridge/no-injection policy.
5. Keep WebView errors visible using the stable package API; do not guess main-frame versus secondary-resource failures because the installed WebResourceError type does not expose that information.
6. Add regression tests for favicon URL policy/cache behavior and existing HTTPS navigation behavior.
7. Run formatting, `dart analyze`, focused Flutter tests, and code review.

## Constraints
- Embedded browsing remains HTTPS-only; HTTP uses the external browser.
- Do not add third-party favicon services.
- Do not clear WebView cache automatically; that would hurt speed and increase network use.
- Do not add a JavaScript bridge or inject scripts.
- Do not introduce platform-specific imports unless the project already declares the package directly and the API is verified.
