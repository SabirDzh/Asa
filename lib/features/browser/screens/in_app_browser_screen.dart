import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/task_attachment_service.dart';
import '../../../core/app_strings.dart';

/// Opens an http(s) task link in the app on Android/iOS and externally on
/// platforms without a supported native WebView (desktop and web).
///
/// Returns false when the URL is invalid or no external handler is available.
Future<bool> openTaskLink(
  BuildContext context,
  String value, {
  String? title,
}) async {
  if (!isAllowedTaskLink(value)) return false;
  final uri = Uri.parse(value.trim());

  if (InAppBrowserScreen.supportsEmbeddedWebView && uri.scheme == 'https') {
    if (!context.mounted) return false;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => InAppBrowserScreen(url: uri, title: title),
      ),
    );
    return true;
  }

  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// A lightweight, privacy-conscious browser for links stored in tasks.
///
/// The screen accepts only HTTPS URLs for embedded browsing. HTTP links remain
/// valid task links but use the platform browser, avoiding iOS ATS exceptions.
/// It does not expose a JavaScript bridge, inject scripts, or persist browsing
/// data in the app.
class InAppBrowserScreen extends StatefulWidget {
  final Uri url;
  final String? title;
  final bool forceExternal;

  const InAppBrowserScreen({
    super.key,
    required this.url,
    this.title,
    this.forceExternal = false,
  });

  static bool get supportsEmbeddedWebView =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @visibleForTesting
  static Uri? faviconUriFor(Uri uri) {
    if (uri.scheme != 'https' || uri.host.isEmpty) return null;
    return Uri(
      scheme: 'https',
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: '/favicon.ico',
    );
  }

  @visibleForTesting
  static int get faviconFailureCacheSize => _Favicon.failureCacheSize;

  @visibleForTesting
  static void rememberFaviconFailureForTesting(Uri uri) =>
      _Favicon.rememberFailureForTesting(uri);

  @visibleForTesting
  static void resetFaviconFailureCache() => _Favicon.resetFailureCache();

  @override
  State<InAppBrowserScreen> createState() => _InAppBrowserScreenState();
}

class _InAppBrowserScreenState extends State<InAppBrowserScreen> {
  WebViewController? _controller;
  Uri? _currentUrl;
  int _progress = 0;
  bool _canGoBack = false;
  bool _canGoForward = false;
  String? _error;

  String get _language => Localizations.localeOf(context).languageCode;

  String _tr(String key) => AppStrings.get(key, _language);

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;
    if (!widget.forceExternal &&
        InAppBrowserScreen.supportsEmbeddedWebView &&
        widget.url.scheme == 'https' &&
        isAllowedTaskLink(widget.url.toString())) {
      final controller =
          WebViewController()
            ..setBackgroundColor(Theme.of(context).scaffoldBackgroundColor)
            ..setJavaScriptMode(JavaScriptMode.unrestricted)
            ..setNavigationDelegate(
              NavigationDelegate(
                onProgress: (progress) {
                  if (!mounted) return;
                  setState(() => _progress = progress.clamp(0, 100));
                },
                onPageStarted: (url) {
                  if (!mounted) return;
                  setState(() {
                    _currentUrl = Uri.tryParse(url) ?? _currentUrl;
                    _error = null;
                    _progress = 0;
                  });
                },
                onPageFinished: (_) {
                  if (!mounted) return;
                  setState(() => _progress = 100);
                  unawaited(_updateNavigationState());
                },
                onWebResourceError: (error) {
                  // webview_flutter 4.x does not expose the failing URL or
                  // main-frame flag on WebResourceError. Keep the callback
                  // conservative and avoid guessing whether a resource is
                  // secondary; the platform WebView remains responsible for
                  // the actual loading policy.
                  if (!mounted) return;
                  setState(() => _error = error.description);
                },
                onNavigationRequest: (request) {
                  final uri = Uri.tryParse(request.url);
                  return uri != null &&
                          uri.scheme == 'https' &&
                          isAllowedTaskLink(request.url)
                      ? NavigationDecision.navigate
                      : NavigationDecision.prevent;
                },
              ),
            )
            ..loadRequest(widget.url);
      _controller = controller;
    }
  }

  Future<void> _updateNavigationState() async {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final canGoBack = await controller.canGoBack();
    final canGoForward = await controller.canGoForward();
    if (!mounted) return;
    setState(() {
      _canGoBack = canGoBack;
      _canGoForward = canGoForward;
    });
  }

  Future<void> _goBack() async {
    final controller = _controller;
    if (controller == null || !_canGoBack) return;
    await controller.goBack();
    await _updateNavigationState();
  }

  Future<void> _goForward() async {
    final controller = _controller;
    if (controller == null || !_canGoForward) return;
    await controller.goForward();
    await _updateNavigationState();
  }

  Future<void> _reload() async {
    if (_controller == null) return;
    setState(() {
      _error = null;
      _progress = 0;
    });
    await _controller!.reload();
  }

  Future<void> _openExternally() async {
    final opened = await launchUrl(
      _currentUrl ?? widget.url,
      mode: LaunchMode.externalApplication,
    );
    if (!mounted || opened) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_tr('browser_external_failed'))));
  }

  @override
  Widget build(BuildContext context) {
    final currentUrl = _currentUrl ?? widget.url;
    final domain = currentUrl.host;
    final title =
        widget.title?.trim().isNotEmpty == true ? widget.title!.trim() : domain;
    final controller = _controller;
    final faviconUri = InAppBrowserScreen.faviconUriFor(currentUrl);

    return PopScope<void>(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _canGoBack) unawaited(_goBack());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: _tr('browser_back'),
            onPressed:
                _canGoBack ? _goBack : () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back),
          ),
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
              Semantics(
                label: _tr(
                  'browser_secure_connection',
                ).replaceFirst('{domain}', domain),
                child: Row(
                  children: [
                    _Favicon(uri: faviconUri, domain: domain),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        domain,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: _tr('browser_forward'),
              onPressed: _canGoForward ? _goForward : null,
              icon: const Icon(Icons.arrow_forward),
            ),
            IconButton(
              tooltip: _tr('browser_reload'),
              onPressed: controller == null ? null : _reload,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: _tr('browser_open_external'),
              onPressed: _openExternally,
              icon: const Icon(Icons.open_in_new),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(3),
            child:
                controller != null && _progress < 100
                    ? LinearProgressIndicator(
                      minHeight: 3,
                      value: _progress == 0 ? null : _progress / 100,
                    )
                    : const SizedBox(height: 3),
          ),
        ),
        body:
            controller == null
                ? _buildUnsupportedState()
                : Stack(
                  children: [
                    WebViewWidget(controller: controller),
                    if (_error != null) _buildErrorBanner(),
                  ],
                ),
      ),
    );
  }

  Widget _buildUnsupportedState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.language, size: 48),
            const SizedBox(height: 16),
            Text(_tr('browser_not_supported'), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _openExternally,
              icon: const Icon(Icons.open_in_new),
              label: Text(_tr('browser_open_external')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Align(
      alignment: Alignment.topCenter,
      child: Material(
        elevation: 2,
        color: Theme.of(context).colorScheme.errorContainer,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _tr('browser_load_error'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: _reload,
                  child: Text(_tr('browser_retry')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Favicon extends StatelessWidget {
  static const _maxFailureCacheEntries = 24;
  static final LinkedHashMap<String, bool> _failedUris =
      LinkedHashMap<String, bool>();

  final Uri? uri;
  final String domain;

  const _Favicon({required this.uri, required this.domain});

  static int get failureCacheSize => _failedUris.length;

  static void resetFailureCache() => _failedUris.clear();

  static bool _hasFailed(Uri uri) => _failedUris.containsKey(uri.toString());

  static void rememberFailureForTesting(Uri uri) => _rememberFailure(uri);

  static void _rememberFailure(Uri? uri) {
    if (uri == null) return;
    final key = uri.toString();
    _failedUris.remove(key);
    _failedUris[key] = true;
    while (_failedUris.length > _maxFailureCacheEntries) {
      _failedUris.remove(_failedUris.keys.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (uri == null || _hasFailed(uri!)) return _fallback();

    return Image.network(
      uri.toString(),
      key: const ValueKey('browser-favicon'),
      width: 14,
      height: 14,
      fit: BoxFit.contain,
      cacheWidth: 32,
      cacheHeight: 32,
      semanticLabel: 'Favicon for $domain',
      errorBuilder: (_, _, _) {
        _Favicon._rememberFailure(uri);
        return _fallback();
      },
    );
  }

  Widget _fallback() {
    return const Icon(
      Icons.language,
      key: ValueKey('browser-favicon-fallback'),
      size: 14,
    );
  }
}
