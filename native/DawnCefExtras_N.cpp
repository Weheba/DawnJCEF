// Dawn additions to the JCEF native library. They back org.cef.browser.DawnCefExtras, a class
// that ships with the Dawn launcher rather than the upstream jcef-api jar, so these symbols add
// API without changing any upstream class or signature. A runtime without them throws
// UnsatisfiedLinkError on first use, which the launcher treats as "capability absent".

#include <jni.h>

#include "include/cef_browser.h"
#include "include/cef_request_context.h"
#include "jni_scoped_helpers.h"
#include "jni_util.h"
#include "request_context_handler.h"

extern "C" {

// Version of this extension surface. Bumped whenever a Dawn native entry point is added.
JNIEXPORT jint JNICALL
Java_org_cef_browser_DawnCefExtras_N_1ExtrasVersion(JNIEnv* env, jclass cls) {
  return 1;
}

// CefRequestContext::CreateContext with a disk-backed cache_path. Upstream JCEF only exposes
// the in-memory variant (see the TODO in CefRequestContext_N.cpp). |jcache_path| must be a
// child of CefSettings.root_cache_path; CEF rejects anything else and falls back to in-memory.
JNIEXPORT jobject JNICALL
Java_org_cef_browser_DawnCefExtras_N_1CreatePersistentContext(
    JNIEnv* env,
    jclass cls,
    jobject jhandler,
    jstring jcache_path,
    jboolean jpersist_session_cookies) {
  CefRefPtr<CefRequestContextHandler> handler = nullptr;
  if (jhandler != nullptr) {
    handler = new RequestContextHandler(env, jhandler);
  }

  CefRequestContextSettings settings;
  CefString(&settings.cache_path) = GetJNIString(env, jcache_path);
  settings.persist_session_cookies = jpersist_session_cookies != JNI_FALSE;
  CefRefPtr<CefRequestContext> context =
      CefRequestContext::CreateContext(settings, handler);
  if (!context.get())
    return nullptr;

  ScopedJNIObjectLocal jContext(
      env, NewJNIObject(env, "org/cef/browser/CefRequestContext_N"));
  if (!jContext)
    return nullptr;

  SetCefForJNIObject(env, jContext, context.get(), "CefRequestContext");
  return jContext.Release();
}

// CefBrowserHost::WasHidden for off-screen browsers. Upstream JCEF's setWindowVisibility is a
// no-op outside macOS windowed browsers, so an OSR page never learns it is hidden: the
// compositor keeps producing frames, timers are not throttled, the renderer keeps foreground
// priority and document.visibilityState stays "visible".
JNIEXPORT void JNICALL
Java_org_cef_browser_DawnCefExtras_N_1WasHidden(JNIEnv* env,
                                               jclass cls,
                                               jobject jbrowser,
                                               jboolean jhidden) {
  CefRefPtr<CefBrowser> browser =
      GetCefFromJNIObject<CefBrowser>(env, jbrowser, "CefBrowser");
  if (!browser.get())
    return;
  CefRefPtr<CefBrowserHost> host = browser->GetHost();
  if (!host.get() || !host->IsWindowRenderingDisabled())
    return;
  host->WasHidden(jhidden != JNI_FALSE);
}

}  // extern "C"
