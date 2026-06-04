import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class KhaltiCheckoutResult {
  final bool reachedReturnUrl;
  final bool userClosed;
  final Uri? callbackUri;

  const KhaltiCheckoutResult({
    required this.reachedReturnUrl,
    required this.userClosed,
    this.callbackUri,
  });
}

class KhaltiCheckoutPage extends StatefulWidget {
  final String paymentUrl;
  final String returnUrl;
  final String title;

  const KhaltiCheckoutPage({
    super.key,
    required this.paymentUrl,
    required this.returnUrl,
    this.title = 'Khalti Checkout',
  });

  @override
  State<KhaltiCheckoutPage> createState() => _KhaltiCheckoutPageState();
}

class _KhaltiCheckoutPageState extends State<KhaltiCheckoutPage> {
  InAppWebViewController? _controller;
  bool _loading = true;
  bool _handled = false;

  void _finish({
    required bool reachedReturnUrl,
    required bool userClosed,
    Uri? uri,
  }) {
    if (_handled || !mounted) return;
    _handled = true;
    Navigator.of(context).pop(
      KhaltiCheckoutResult(
        reachedReturnUrl: reachedReturnUrl,
        userClosed: userClosed,
        callbackUri: uri,
      ),
    );
  }

  bool _maybeHandleReturnUrl(Uri? uri) {
    if (uri == null) return false;
    if (uri.toString().startsWith(widget.returnUrl)) {
      _finish(reachedReturnUrl: true, userClosed: false, uri: uri);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (!_handled) {
          _finish(reachedReturnUrl: false, userClosed: true);
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: Stack(
          children: [
            InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(widget.paymentUrl)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                useShouldOverrideUrlLoading: true,
                mediaPlaybackRequiresUserGesture: false,
              ),
              onWebViewCreated: (controller) {
                _controller = controller;
              },
              onLoadStart: (controller, url) {
                setState(() => _loading = true);
                _maybeHandleReturnUrl(url);
              },
              onLoadStop: (controller, url) async {
                if (mounted) {
                  setState(() => _loading = false);
                }
                _maybeHandleReturnUrl(url);
              },
              onUpdateVisitedHistory: (controller, url, isReload) {
                _maybeHandleReturnUrl(url);
              },
              shouldOverrideUrlLoading: (controller, action) async {
                final uri = action.request.url;
                if (_maybeHandleReturnUrl(uri)) {
                  return NavigationActionPolicy.CANCEL;
                }
                return NavigationActionPolicy.ALLOW;
              },
            ),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _finish(
                      reachedReturnUrl: false,
                      userClosed: true,
                    ),
                    child: const Text('Close'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      await _controller?.reload();
                    },
                    child: const Text('Refresh'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
