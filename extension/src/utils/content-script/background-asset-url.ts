import { backgroundFetch } from "./background-fetch-client"

const OWN_PAGE_PROTOCOLS = new Set([
  "chrome-extension:",
  "moz-extension:",
  "safari-web-extension:",
  // macOS/iOS app settings pages are loaded with WKWebView.loadFileURL.
  "file:",
])

const resolvedAssetBlobCache = new Map<string, Blob>()
const pendingAssetBlobCache = new Map<string, Promise<Blob | null>>()

const HTTP_URL_RE = /^https?:\/\//i

function isRemoteHttpUrl(value: string) {
  return HTTP_URL_RE.test(value)
}

function getCurrentPageUrl() {
  return typeof window === "undefined" ? "https://example.com/" : window.location.href
}

export function shouldProxyAssetUrl(resourceUrl: string, pageUrl = getCurrentPageUrl()) {
  if (!isRemoteHttpUrl(resourceUrl)) {
    return false
  }

  try {
    const protocol = new URL(pageUrl).protocol
    return isThirdPartyPage(protocol)
  }
  catch {
    return true
  }
}

function isThirdPartyPage(protocol: string) {
  return !OWN_PAGE_PROTOCOLS.has(protocol)
}

export async function resolveContentScriptAssetBlob(resourceUrl: string, pageUrl = getCurrentPageUrl()) {
  if (!shouldProxyAssetUrl(resourceUrl, pageUrl)) {
    return null
  }

  const cachedAssetBlob = resolvedAssetBlobCache.get(resourceUrl)
  if (cachedAssetBlob) {
    return cachedAssetBlob
  }

  const pendingAssetBlob = pendingAssetBlobCache.get(resourceUrl)
  if (pendingAssetBlob) {
    return pendingAssetBlob
  }

  const assetBlobPromise = (async () => {
    try {
      const response = await backgroundFetch(resourceUrl, undefined, {
        credentials: "omit",
        responseType: "base64",
      })
      if (!response.ok) {
        return null
      }

      const assetBlob = await response.blob()
      if (assetBlob.size === 0) {
        return null
      }

      resolvedAssetBlobCache.set(resourceUrl, assetBlob)
      return assetBlob
    }
    catch {
      return null
    }
    finally {
      pendingAssetBlobCache.delete(resourceUrl)
    }
  })()

  pendingAssetBlobCache.set(resourceUrl, assetBlobPromise)
  return assetBlobPromise
}

export function clearResolvedContentScriptAssetBlobs() {
  resolvedAssetBlobCache.clear()
  pendingAssetBlobCache.clear()
}
