package com.wlyaaaaa.codexlocalremote.mobile;

import android.content.SharedPreferences;
import android.net.http.SslError;
import android.os.Bundle;
import android.webkit.ConsoleMessage;
import android.webkit.RenderProcessGoneDetail;
import android.webkit.SslErrorHandler;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebView;

import androidx.activity.OnBackPressedCallback;

import com.getcapacitor.Bridge;
import com.getcapacitor.BridgeActivity;
import com.getcapacitor.BridgeWebChromeClient;
import com.getcapacitor.BridgeWebViewClient;

import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

public class MainActivity extends BridgeActivity {

    private static final String SHELL_PREFERENCES = "codex_local_remote_mobile_shell";
    private static final String SHELL_VERSION_KEY = "bundled_web_version";
    private static final String ANDROID_SHELL_USER_AGENT = "CodexLocalRemoteAndroidShell";
    private boolean showingConnectionError = false;
    private File runtimeLogFile;
    private NativeSpeechBridge nativeSpeechBridge;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        Bridge currentBridge = getBridge();
        if (currentBridge != null) {
            runtimeLogFile = new File(
                getExternalFilesDir(null) == null ? getFilesDir() : getExternalFilesDir(null),
                "mobile-runtime.log"
            );
            if (runtimeLogFile.length() > 1024 * 1024) {
                runtimeLogFile.delete();
            }
            appendRuntimeLog("APP", "Mobile shell started; versionCode=" + BuildConfig.VERSION_CODE);
            WebView webView = currentBridge.getWebView();
            nativeSpeechBridge = new NativeSpeechBridge(this, webView);
            webView.addJavascriptInterface(nativeSpeechBridge, "CodexNativeSpeech");
            String userAgent = webView.getSettings().getUserAgentString();
            if (!userAgent.contains(ANDROID_SHELL_USER_AGENT)) {
                webView.getSettings().setUserAgentString(userAgent + " " + ANDROID_SHELL_USER_AGENT);
            }
            // Remote pages do not load Capacitor's JavaScript runtime. Prevent BridgeActivity
            // from sending lifecycle events into those pages after a background/foreground cycle.
            currentBridge.getApp().setStatusChangeListener(null);
            currentBridge.setWebViewClient(new ConnectionAwareWebViewClient(currentBridge));
            currentBridge.getWebView().setWebChromeClient(new DiagnosticWebChromeClient(currentBridge));
            registerBackNavigation(currentBridge);
            loadCurrentBundledShell(currentBridge);
        }
    }

    @Override
    public void onDestroy() {
        if (nativeSpeechBridge != null) {
            nativeSpeechBridge.destroy();
            nativeSpeechBridge = null;
        }
        super.onDestroy();
    }

    @Override
    public void onRequestPermissionsResult(
        int requestCode,
        String[] permissions,
        int[] grantResults
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (nativeSpeechBridge != null) {
            nativeSpeechBridge.onRequestPermissionsResult(requestCode, grantResults);
        }
    }

    private void registerBackNavigation(Bridge currentBridge) {
        getOnBackPressedDispatcher().addCallback(this, new OnBackPressedCallback(true) {
            @Override
            public void handleOnBackPressed() {
                WebView webView = currentBridge.getWebView();
                if (webView == null) {
                    finish();
                    return;
                }

                webView.evaluateJavascript(
                    "(function(){var state=window.history&&window.history.state;" +
                    "return state&&Number.isInteger(state.idx)&&state.idx>0?'1':'0';})()",
                    value -> {
                        if ("\"1\"".equals(value) || "1".equals(value)) {
                            webView.goBack();
                            return;
                        }
                        setEnabled(false);
                        getOnBackPressedDispatcher().onBackPressed();
                        setEnabled(true);
                    }
                );
            }
        });
    }

    private String safeUrl(String value) {
        if (value == null) return "";
        try {
            android.net.Uri uri = android.net.Uri.parse(value);
            return uri.buildUpon().clearQuery().fragment(null).build().toString();
        } catch (Exception ignored) {
            return "[invalid-url]";
        }
    }

    private String compactDiagnostic(String value) {
        if (value == null) return "";
        String compact = value.replaceAll("[\\r\\n]+", " ").trim();
        return compact.length() > 2000 ? compact.substring(0, 2000) : compact;
    }

    private synchronized void appendRuntimeLog(String kind, String detail) {
        if (runtimeLogFile == null) return;
        String timestamp = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US).format(new Date());
        try (FileWriter writer = new FileWriter(runtimeLogFile, true)) {
            writer.write(timestamp + " [" + kind + "] " + compactDiagnostic(detail) + System.lineSeparator());
        } catch (IOException ignored) {
            // Runtime diagnostics must never interrupt the remote page.
        }
    }

    private void installRemotePageCompatibility(WebView view) {
        // Capacitor's Cordova lifecycle bridge remains alive after the bundled shell
        // navigates to the remote site. The remote site does not load Capacitor's
        // JavaScript bridge, so make lifecycle callbacks harmless there.
        view.evaluateJavascript(
            "(function(){var c=window.Capacitor||(window.Capacitor={});" +
            "if(typeof c.triggerEvent!=='function'){c.triggerEvent=function(){return null;};}" +
            "document.documentElement.dataset.androidWebview='true';})();",
            null
        );
    }

    private String getVersionedLocalShellUrl(Bridge currentBridge) {
        String localUrl = currentBridge.getLocalUrl();
        if (localUrl.endsWith("/")) {
            localUrl = localUrl.substring(0, localUrl.length() - 1);
        }
        return localUrl + "/?appBuild=" + BuildConfig.VERSION_CODE;
    }

    private void loadCurrentBundledShell(Bridge currentBridge) {
        WebView webView = currentBridge.getWebView();
        SharedPreferences preferences = getSharedPreferences(SHELL_PREFERENCES, MODE_PRIVATE);
        int previousVersion = preferences.getInt(SHELL_VERSION_KEY, -1);

        webView.stopLoading();
        if (previousVersion != BuildConfig.VERSION_CODE) {
            webView.clearCache(true);
            webView.clearHistory();
            preferences.edit().putInt(SHELL_VERSION_KEY, BuildConfig.VERSION_CODE).apply();
        }
        webView.loadUrl(getVersionedLocalShellUrl(currentBridge));
    }

    private boolean isLocalAppUrl(String url, Bridge currentBridge) {
        if (url == null || currentBridge == null || currentBridge.getLocalUrl() == null) {
            return false;
        }

        String localUrl = currentBridge.getLocalUrl();
        if (localUrl.endsWith("/")) {
            localUrl = localUrl.substring(0, localUrl.length() - 1);
        }

        return url.equals(localUrl)
            || url.startsWith(localUrl + "/")
            || url.startsWith(localUrl + "#")
            || url.startsWith(localUrl + "?");
    }

    private void showConnectionError(WebView view, Bridge currentBridge, String errorKind, int statusCode) {
        if (showingConnectionError || currentBridge == null || currentBridge.getLocalUrl() == null) {
            return;
        }

        showingConnectionError = true;
        String localUrl = getVersionedLocalShellUrl(currentBridge);
        String fragment = "#configure?error=" + android.net.Uri.encode(errorKind);
        if (statusCode > 0) {
            fragment += "&status=" + statusCode;
        }

        String errorUrl = localUrl + fragment;
        view.post(() -> view.loadUrl(errorUrl));
    }

    private final class ConnectionAwareWebViewClient extends BridgeWebViewClient {

        private final Bridge currentBridge;

        private ConnectionAwareWebViewClient(Bridge currentBridge) {
            super(currentBridge);
            this.currentBridge = currentBridge;
        }

        @Override
        public void onPageStarted(WebView view, String url, android.graphics.Bitmap favicon) {
            appendRuntimeLog("PAGE_START", safeUrl(url));
            if (!isLocalAppUrl(url, currentBridge)) {
                showingConnectionError = false;
            }
            super.onPageStarted(view, url, favicon);
        }

        @Override
        public void onPageFinished(WebView view, String url) {
            appendRuntimeLog("PAGE_FINISH", safeUrl(url));
            if (!isLocalAppUrl(url, currentBridge)) {
                installRemotePageCompatibility(view);
            }
            super.onPageFinished(view, url);
        }

        @Override
        public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
            super.onReceivedError(view, request, error);
            if (!request.isForMainFrame() || isLocalAppUrl(request.getUrl().toString(), currentBridge)) {
                return;
            }

            String description = error.getDescription() == null
                ? ""
                : error.getDescription().toString().toUpperCase(java.util.Locale.ROOT);
            String errorKind = description.contains("CLEARTEXT") ? "cleartext" : "network";
            appendRuntimeLog("WEB_ERROR", errorKind + " " + safeUrl(request.getUrl().toString()) + " " + description);
            showConnectionError(view, currentBridge, errorKind, 0);
        }

        @SuppressWarnings("deprecation")
        @Override
        public void onReceivedError(WebView view, int errorCode, String description, String failingUrl) {
            super.onReceivedError(view, errorCode, description, failingUrl);
            if (isLocalAppUrl(failingUrl, currentBridge)) {
                return;
            }

            String safeDescription = description == null
                ? ""
                : description.toUpperCase(java.util.Locale.ROOT);
            String errorKind = safeDescription.contains("CLEARTEXT") ? "cleartext" : "network";
            appendRuntimeLog("WEB_ERROR_LEGACY", errorKind + " " + safeUrl(failingUrl) + " " + safeDescription);
            showConnectionError(view, currentBridge, errorKind, 0);
        }

        @Override
        public void onReceivedSslError(WebView view, SslErrorHandler handler, SslError error) {
            handler.cancel();
            String failingUrl = error == null ? null : error.getUrl();
            if (!isLocalAppUrl(failingUrl, currentBridge)) {
                appendRuntimeLog("SSL_ERROR", safeUrl(failingUrl));
                showConnectionError(view, currentBridge, "ssl", 0);
            }
        }

        @Override
        public void onReceivedHttpError(
            WebView view,
            WebResourceRequest request,
            WebResourceResponse errorResponse
        ) {
            super.onReceivedHttpError(view, request, errorResponse);
            if (!request.isForMainFrame() || isLocalAppUrl(request.getUrl().toString(), currentBridge)) {
                return;
            }

            appendRuntimeLog(
                "HTTP_ERROR",
                errorResponse.getStatusCode() + " " + safeUrl(request.getUrl().toString())
            );
            showConnectionError(view, currentBridge, "http", errorResponse.getStatusCode());
        }

        @Override
        public boolean onRenderProcessGone(WebView view, RenderProcessGoneDetail detail) {
            appendRuntimeLog(
                "RENDER_PROCESS_GONE",
                "didCrash=" + detail.didCrash() + ", priority=" + detail.rendererPriorityAtExit()
            );
            return super.onRenderProcessGone(view, detail);
        }
    }

    private final class DiagnosticWebChromeClient extends BridgeWebChromeClient {

        private DiagnosticWebChromeClient(Bridge bridge) {
            super(bridge);
        }

        @Override
        public boolean onConsoleMessage(ConsoleMessage message) {
            String detail =
                message.messageLevel() + " " +
                safeUrl(message.sourceId()) + ":" +
                message.lineNumber() + " " +
                message.message();
            appendRuntimeLog("CONSOLE", detail);
            return super.onConsoleMessage(message);
        }
    }
}
