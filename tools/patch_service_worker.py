"""Cache Godot WASM by content hash across PWA gameplay releases."""
from __future__ import annotations
import hashlib
from pathlib import Path

WEB = Path(__file__).resolve().parent.parent / "build/web"
WORKER = WEB / "index.service.worker.js"
WASM = WEB / "index.wasm"


def main() -> int:
    text = WORKER.read_text(encoding="utf-8")
    digest = hashlib.sha256(WASM.read_bytes()).hexdigest()[:20]
    marker = "const CACHE_NAME = CACHE_PREFIX + CACHE_VERSION;"
    assert text.count(marker) == 1, "Godot service-worker template changed"
    text = text.replace(marker, marker + "\nconst ENGINE_CACHE_PREFIX = 'kana-run-wasm-';"
                        + f"\nconst ENGINE_CACHE_NAME = ENGINE_CACHE_PREFIX + '{digest}';")
    line = "const FULL_CACHE = CACHED_FILES.concat(CACHEABLE_FILES);"
    assert text.count(line) == 1, "Godot cache definition changed"
    text = text.replace(line, """// WASM belongs to the stable engine cache; PCK belongs to the release cache.
const FULL_CACHE = CACHED_FILES.concat(CACHEABLE_FILES.filter((x) => x !== 'index.wasm'));""")
    old_filter = "keys.filter((key) => key.startsWith(CACHE_PREFIX) && key !== CACHE_NAME)"
    assert text.count(old_filter) == 1, "Godot activate cleanup changed"
    text = text.replace(old_filter, """keys.filter((key) =>
            (key.startsWith(CACHE_PREFIX) && key !== CACHE_NAME)
            || (key.startsWith(ENGINE_CACHE_PREFIX) && key !== ENGINE_CACHE_NAME))""")
    needle = """	(event) => {
		const isNavigate"""
    assert text.count(needle) == 1, "Godot fetch routing changed"
    replacement = """	(event) => {
        const engineUrl = new URL('index.wasm', self.registration.scope).href;
        if (event.request.method === 'GET' && event.request.url === engineUrl) {
            event.respondWith((async () => {
                const cache = await caches.open(ENGINE_CACHE_NAME);
                const existing = await cache.match(event.request);
                if (existing) {
                    return ENSURE_CROSSORIGIN_ISOLATION_HEADERS
                        ? ensureCrossOriginIsolationHeaders(existing) : existing;
                }
                let response = await fetch(event.request);
                if (ENSURE_CROSSORIGIN_ISOLATION_HEADERS) {
                    response = ensureCrossOriginIsolationHeaders(response);
                }
                if (response.ok) await cache.put(event.request, response.clone());
                return response;
            })());
            return;
        }
		const isNavigate"""
    text = text.replace(needle, replacement)
    WORKER.write_text(text, encoding="utf-8")
    print(f"[pwa-cache] Reusable Godot WASM hash: {digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
