import 'package:flutter/material.dart';

/// Deprecated placeholder kept only so older local imports do not break analysis.
/// The active eSewa flow now uses browser / Custom Tabs via EsewaCheckoutCoordinator.
class EsewaWebResult {
  final bool isSuccess;
  final bool isCancelled;
  final bool isFailed;
  final String base64Data;

  const EsewaWebResult({
    this.isSuccess = false,
    this.isCancelled = false,
    this.isFailed = false,
    this.base64Data = '',
  });
}

class EsewaWebViewPage extends StatelessWidget {
  final Object initiateResult;

  const EsewaWebViewPage({super.key, required this.initiateResult});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('eSewa')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'This legacy WebView screen is no longer used. '
            'Use the browser / Custom Tabs eSewa flow instead.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
