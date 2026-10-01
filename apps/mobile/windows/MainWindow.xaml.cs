using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text;
using Windows.Globalization;
using Windows.Media.SpeechRecognition;
using System.Windows;
using Microsoft.Web.WebView2.Core;

namespace CodexLocalRemote.Windows;

public partial class MainWindow : Window
{
    private const string ShellHost = "codex-local-remote.local";
    private const int RemoteNavigationTimeoutMilliseconds = 12_000;
    private static readonly Uri ShellUri = new($"https://{ShellHost}/index.html");
    private string? _lastAuthenticatedUrlPath;
    private string? _pendingConnectionUrl;
    private string? _activeRemoteNavigationUrl;
    private CancellationTokenSource? _remoteNavigationTimeout;
    private bool _connectionErrorShown;
    private SpeechRecognizer? _speechRecognizer;
    private string? _speechRequestId;
    private readonly StringBuilder _speechFinalTranscript = new();
    private bool _speechStopping;

    public MainWindow()
    {
        InitializeComponent();
        Loaded += async (_, _) => await InitializeBrowserAsync();
        Closed += async (_, _) =>
        {
            CancelRemoteNavigationTimeout();
            await DisposeNativeSpeechAsync();
        };
    }

    private async Task InitializeBrowserAsync()
    {
        try
        {
            var webRoot = Path.Combine(AppContext.BaseDirectory, "web");
            if (!Directory.Exists(webRoot))
            {
                throw new DirectoryNotFoundException(
                    $"The client web bundle was not found at '{webRoot}'. Build the mobile shell before starting the Windows client.");
            }

            var clientDataFolder = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "CodexLocalRemote",
                "WindowsClient");
            var userDataFolder = Path.Combine(clientDataFolder, "WebView2");
            _lastAuthenticatedUrlPath = Path.Combine(clientDataFolder, "last-authenticated-url.txt");

            var environment = await CoreWebView2Environment.CreateAsync(userDataFolder: userDataFolder);
            await Browser.EnsureCoreWebView2Async(environment);

            Browser.CoreWebView2.SetVirtualHostNameToFolderMapping(
                ShellHost,
                webRoot,
                CoreWebView2HostResourceAccessKind.DenyCors);
            Browser.CoreWebView2.WebMessageReceived += OnWebMessageReceived;
            Browser.CoreWebView2.NavigationStarting += OnNavigationStarting;
            Browser.CoreWebView2.NavigationCompleted += OnNavigationCompleted;

            var lastAuthenticatedUrl = ReadLastAuthenticatedUrl();
            if (lastAuthenticatedUrl is not null)
            {
                _pendingConnectionUrl = lastAuthenticatedUrl;
                _activeRemoteNavigationUrl = lastAuthenticatedUrl;
                StartRemoteNavigationTimeout();
                Browser.Source = new Uri(lastAuthenticatedUrl);
            }
            else
            {
                Browser.Source = ShellUri;
            }
        }
        catch (Exception exception)
        {
            MessageBox.Show(
                $"Windows 客户端初始化失败。\n\n{exception.Message}",
                "Codex Local Remote",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
    }

    private void OnWebMessageReceived(object? sender, CoreWebView2WebMessageReceivedEventArgs args)
    {
        string message;
        try
        {
            message = args.TryGetWebMessageAsString();
        }
        catch (ArgumentException)
        {
            return;
        }

        if (string.Equals(message, "open-connection-settings", StringComparison.Ordinal))
        {
            CancelRemoteNavigationTimeout();
            _pendingConnectionUrl = null;
            _activeRemoteNavigationUrl = null;
            Browser.Source = new Uri($"{ShellUri}#configure");
            return;
        }

        ClientMessage? clientMessage;
        try
        {
            clientMessage = JsonSerializer.Deserialize<ClientMessage>(message);
        }
        catch (JsonException)
        {
            return;
        }

        if (clientMessage is null) return;

        switch (clientMessage.Type)
        {
            case "connect":
                if (!TryNormalizeRemoteUrl(clientMessage.Url, out var connectionUrl)) return;
                _pendingConnectionUrl = connectionUrl;
                _activeRemoteNavigationUrl = connectionUrl;
                _connectionErrorShown = false;
                ClearLastAuthenticatedUrl();
                StartRemoteNavigationTimeout();
                Browser.Source = new Uri(connectionUrl);
                break;
            case "authenticated":
                if (!TryGetActiveRemoteUrl(out var authenticatedUrl)) return;
                _pendingConnectionUrl = null;
                _activeRemoteNavigationUrl = authenticatedUrl;
                _connectionErrorShown = false;
                CancelRemoteNavigationTimeout();
                SaveLastAuthenticatedUrl(authenticatedUrl);
                break;
            case "authentication-required":
                if (!TryGetActiveRemoteUrl(out _)) return;
                _pendingConnectionUrl = null;
                _activeRemoteNavigationUrl = null;
                CancelRemoteNavigationTimeout();
                ClearLastAuthenticatedUrl();
                break;
            case "speech-start":
                if (string.IsNullOrWhiteSpace(clientMessage.RequestId)) return;
                _ = StartNativeSpeechAsync(clientMessage.RequestId, clientMessage.Locale);
                break;
            case "speech-stop":
                if (string.Equals(clientMessage.RequestId, _speechRequestId, StringComparison.Ordinal))
                {
                    _ = StopNativeSpeechAsync(false);
                }
                break;
            case "speech-abort":
                if (string.Equals(clientMessage.RequestId, _speechRequestId, StringComparison.Ordinal))
                {
                    _ = StopNativeSpeechAsync(true);
                }
                break;
        }
    }

    private void OnNavigationStarting(object? sender, CoreWebView2NavigationStartingEventArgs args)
    {
        if (IsShellUrl(args.Uri))
        {
            CancelRemoteNavigationTimeout();
            _activeRemoteNavigationUrl = null;
            return;
        }

        if (!TryNormalizeRemoteUrl(args.Uri, out var remoteUrl)) return;

        _activeRemoteNavigationUrl = remoteUrl;
        _pendingConnectionUrl ??= remoteUrl;
        _connectionErrorShown = false;
        StartRemoteNavigationTimeout();
    }

    private void OnNavigationCompleted(object? sender, CoreWebView2NavigationCompletedEventArgs args)
    {
        if (IsShellUrl(Browser.Source?.ToString()) &&
            _activeRemoteNavigationUrl is null &&
            _pendingConnectionUrl is null)
        {
            CancelRemoteNavigationTimeout();
            return;
        }

        if (args.IsSuccess && (args.HttpStatusCode == 0 || args.HttpStatusCode < 400))
        {
            CancelRemoteNavigationTimeout();
            return;
        }

        if (!TryGetActiveRemoteUrl(out var attemptedUrl)) return;

        var errorKind = args.HttpStatusCode >= 400 ? "http" : "network";
        var status = args.HttpStatusCode >= 400 ? $"&status={args.HttpStatusCode}" : string.Empty;
        ShowConnectionFailure(errorKind, status, attemptedUrl);
    }

    private async Task StartNativeSpeechAsync(string requestId, string? locale)
    {
        await DisposeNativeSpeechAsync();
        _speechRequestId = requestId;
        _speechFinalTranscript.Clear();
        _speechStopping = false;

        try
        {
            SpeechRecognizer recognizer;
            try
            {
                recognizer = string.IsNullOrWhiteSpace(locale)
                    ? new SpeechRecognizer()
                    : new SpeechRecognizer(new Language(locale));
            }
            catch
            {
                recognizer = new SpeechRecognizer();
            }

            recognizer.HypothesisGenerated += OnSpeechHypothesisGenerated;
            recognizer.ContinuousRecognitionSession.ResultGenerated += OnSpeechResultGenerated;
            recognizer.ContinuousRecognitionSession.Completed += OnSpeechCompleted;

            var compilation = await recognizer.CompileConstraintsAsync();
            if (compilation.Status != SpeechRecognitionResultStatus.Success)
            {
                recognizer.Dispose();
                SendNativeSpeechEvent("error", error: "service-not-allowed");
                ClearNativeSpeechState();
                return;
            }

            _speechRecognizer = recognizer;
            await recognizer.ContinuousRecognitionSession.StartAsync();
            SendNativeSpeechEvent("started");
        }
        catch (System.Runtime.InteropServices.COMException exception)
            when (exception.HResult == unchecked((int)0x80045509))
        {
            SendNativeSpeechEvent("error", error: "speech-policy-not-accepted");
            OpenWindowsPrivacySettings("ms-settings:privacy-speech");
            await DisposeNativeSpeechAsync();
        }
        catch (UnauthorizedAccessException)
        {
            SendNativeSpeechEvent("error", error: "not-allowed");
            OpenWindowsPrivacySettings("ms-settings:privacy-microphone");
            await DisposeNativeSpeechAsync();
        }
        catch (System.Runtime.InteropServices.COMException exception)
            when (exception.HResult == unchecked((int)0x80070005))
        {
            SendNativeSpeechEvent("error", error: "not-allowed");
            OpenWindowsPrivacySettings("ms-settings:privacy-microphone");
            await DisposeNativeSpeechAsync();
        }
        catch
        {
            SendNativeSpeechEvent("error", error: "audio-capture");
            await DisposeNativeSpeechAsync();
        }
    }

    private async Task StopNativeSpeechAsync(bool abort)
    {
        var recognizer = _speechRecognizer;
        if (recognizer is null)
        {
            SendNativeSpeechEvent("ended");
            ClearNativeSpeechState();
            return;
        }

        _speechStopping = true;
        try
        {
            if (abort)
            {
                await recognizer.ContinuousRecognitionSession.CancelAsync();
            }
            else
            {
                await recognizer.ContinuousRecognitionSession.StopAsync();
            }
        }
        catch
        {
            SendNativeSpeechEvent("ended");
            await DisposeNativeSpeechAsync();
        }
    }

    private void OnSpeechHypothesisGenerated(
        SpeechRecognizer sender,
        SpeechRecognitionHypothesisGeneratedEventArgs args)
    {
        var current = JoinSpeechTranscript(_speechFinalTranscript.ToString(), args.Hypothesis.Text);
        SendNativeSpeechEvent("result", transcript: current, isFinal: false);
    }

    private void OnSpeechResultGenerated(
        SpeechContinuousRecognitionSession sender,
        SpeechContinuousRecognitionResultGeneratedEventArgs args)
    {
        var text = args.Result.Text?.Trim();
        if (string.IsNullOrWhiteSpace(text)) return;
        if (_speechFinalTranscript.Length > 0) _speechFinalTranscript.Append(' ');
        _speechFinalTranscript.Append(text);
        SendNativeSpeechEvent("result", transcript: _speechFinalTranscript.ToString(), isFinal: true);
    }

    private void OnSpeechCompleted(
        SpeechContinuousRecognitionSession sender,
        SpeechContinuousRecognitionCompletedEventArgs args)
    {
        if (!_speechStopping && args.Status != SpeechRecognitionResultStatus.Success)
        {
            SendNativeSpeechEvent("error", error: "unknown");
        }
        else
        {
            SendNativeSpeechEvent("ended");
        }
        _ = DisposeNativeSpeechAsync();
    }

    private static void OpenWindowsPrivacySettings(string uri)
    {
        try
        {
            System.Diagnostics.Process.Start(
                new System.Diagnostics.ProcessStartInfo(uri)
                {
                    UseShellExecute = true,
                });
        }
        catch
        {
        }
    }

    private static string JoinSpeechTranscript(string committed, string hypothesis)
    {
        if (string.IsNullOrWhiteSpace(committed)) return hypothesis;
        if (string.IsNullOrWhiteSpace(hypothesis)) return committed;
        return $"{committed} {hypothesis}";
    }

    private void SendNativeSpeechEvent(
        string type,
        string? transcript = null,
        bool? isFinal = null,
        string? error = null)
    {
        var requestId = _speechRequestId;
        if (string.IsNullOrWhiteSpace(requestId) || Browser.CoreWebView2 is null) return;

        var payload = new Dictionary<string, object?>
        {
            ["type"] = type,
            ["requestId"] = requestId,
        };
        if (transcript is not null) payload["transcript"] = transcript;
        if (isFinal.HasValue) payload["final"] = isFinal.Value;
        if (error is not null) payload["error"] = error;

        var json = JsonSerializer.Serialize(payload);
        _ = Dispatcher.InvokeAsync(async () =>
        {
            if (Browser.CoreWebView2 is null) return;
            await Browser.CoreWebView2.ExecuteScriptAsync(
                $"window.dispatchEvent(new CustomEvent('codex-native-speech',{{detail:{json}}}));");
        });
    }

    private async Task DisposeNativeSpeechAsync()
    {
        var recognizer = _speechRecognizer;
        _speechRecognizer = null;
        if (recognizer is not null)
        {
            recognizer.HypothesisGenerated -= OnSpeechHypothesisGenerated;
            recognizer.ContinuousRecognitionSession.ResultGenerated -= OnSpeechResultGenerated;
            recognizer.ContinuousRecognitionSession.Completed -= OnSpeechCompleted;
            recognizer.Dispose();
        }
        await Task.CompletedTask;
        ClearNativeSpeechState();
    }

    private void ClearNativeSpeechState()
    {
        _speechRequestId = null;
        _speechFinalTranscript.Clear();
        _speechStopping = false;
    }

    private bool TryGetCurrentRemoteUrl(out string url)
    {
        url = string.Empty;
        var source = Browser.Source;
        if (source is null ||
            string.Equals(source.Host, ShellHost, StringComparison.OrdinalIgnoreCase) ||
            (source.Scheme != Uri.UriSchemeHttp && source.Scheme != Uri.UriSchemeHttps))
        {
            return false;
        }

        return TryNormalizeRemoteUrl(source.GetLeftPart(UriPartial.Path), out url);
    }

    private bool TryGetActiveRemoteUrl(out string url)
    {
        if (TryGetCurrentRemoteUrl(out url)) return true;
        if (TryNormalizeRemoteUrl(_activeRemoteNavigationUrl, out url)) return true;
        if (TryNormalizeRemoteUrl(_pendingConnectionUrl, out url)) return true;
        return TryNormalizeRemoteUrl(ReadLastAuthenticatedUrl(), out url);
    }

    private static bool IsShellUrl(string? value)
    {
        return Uri.TryCreate(value, UriKind.Absolute, out var uri) &&
            string.Equals(uri.Host, ShellHost, StringComparison.OrdinalIgnoreCase);
    }

    private void StartRemoteNavigationTimeout()
    {
        CancelRemoteNavigationTimeout();
        var timeout = new CancellationTokenSource();
        _remoteNavigationTimeout = timeout;
        _ = WaitForRemoteNavigationAsync(timeout);
    }

    private async Task WaitForRemoteNavigationAsync(CancellationTokenSource timeout)
    {
        try
        {
            await Task.Delay(RemoteNavigationTimeoutMilliseconds, timeout.Token);
            if (timeout.IsCancellationRequested) return;

            await Dispatcher.InvokeAsync(() =>
            {
                if (!ReferenceEquals(_remoteNavigationTimeout, timeout) ||
                    _connectionErrorShown ||
                    !TryGetActiveRemoteUrl(out var attemptedUrl))
                {
                    return;
                }

                ShowConnectionFailure("network", string.Empty, attemptedUrl);
            });
        }
        catch (OperationCanceledException)
        {
        }
        finally
        {
            timeout.Dispose();
        }
    }

    private void CancelRemoteNavigationTimeout()
    {
        _remoteNavigationTimeout?.Cancel();
        _remoteNavigationTimeout = null;
    }

    private void ShowConnectionFailure(string errorKind, string status, string attemptedUrl)
    {
        if (_connectionErrorShown) return;
        _connectionErrorShown = true;
        CancelRemoteNavigationTimeout();
        _pendingConnectionUrl = null;
        _activeRemoteNavigationUrl = null;
        ClearLastAuthenticatedUrl();

        try
        {
            Browser.CoreWebView2?.Stop();
        }
        catch (InvalidOperationException)
        {
        }

        var encodedUrl = Uri.EscapeDataString(attemptedUrl);
        Browser.Source = new Uri($"{ShellUri}#configure?error={errorKind}{status}&url={encodedUrl}");
    }

    private static bool TryNormalizeRemoteUrl(string? value, out string url)
    {
        url = string.Empty;
        if (!Uri.TryCreate(value, UriKind.Absolute, out var parsed) ||
            (parsed.Scheme != Uri.UriSchemeHttp && parsed.Scheme != Uri.UriSchemeHttps) ||
            !string.IsNullOrEmpty(parsed.UserInfo))
        {
            return false;
        }

        var builder = new UriBuilder(parsed)
        {
            Query = string.Empty,
            Fragment = string.Empty,
        };
        if (!builder.Path.EndsWith("/", StringComparison.Ordinal)) builder.Path += "/";
        url = builder.Uri.AbsoluteUri;
        return true;
    }

    private string? ReadLastAuthenticatedUrl()
    {
        if (string.IsNullOrWhiteSpace(_lastAuthenticatedUrlPath) ||
            !File.Exists(_lastAuthenticatedUrlPath))
        {
            return null;
        }

        try
        {
            var value = File.ReadAllText(_lastAuthenticatedUrlPath).Trim();
            return TryNormalizeRemoteUrl(value, out var normalized) ? normalized : null;
        }
        catch (IOException)
        {
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            return null;
        }
    }

    private void SaveLastAuthenticatedUrl(string url)
    {
        if (string.IsNullOrWhiteSpace(_lastAuthenticatedUrlPath)) return;
        Directory.CreateDirectory(Path.GetDirectoryName(_lastAuthenticatedUrlPath)!);
        File.WriteAllText(_lastAuthenticatedUrlPath, url);
    }

    private void ClearLastAuthenticatedUrl()
    {
        if (string.IsNullOrWhiteSpace(_lastAuthenticatedUrlPath)) return;
        try
        {
            File.Delete(_lastAuthenticatedUrlPath);
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }

    private sealed class ClientMessage
    {
        [JsonPropertyName("type")]
        public string? Type { get; init; }

        [JsonPropertyName("url")]
        public string? Url { get; init; }

        [JsonPropertyName("requestId")]
        public string? RequestId { get; init; }

        [JsonPropertyName("locale")]
        public string? Locale { get; init; }
    }
}
