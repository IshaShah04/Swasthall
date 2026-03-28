import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'theme_colors.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

// ─────────────────────────────────────────────────────────────────────────────
//  Fuzzy / phonetic search helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Returns true if [query] matches [target] using three strategies:
///   1. Every character of the query appears in order in the target (subsequence)
///   2. Any word in target starts with any word in query
///   3. Levenshtein distance ≤ threshold (catches misspellings)
bool _fuzzyMatch(String target, String query) {
  if (query.isEmpty) return true;
  final t = target.toLowerCase().trim();
  final q = query.toLowerCase().trim();

  // Direct contains — fastest path
  if (t.contains(q)) return true;

  // Each query word matches at least one target word prefix
  final qWords = q.split(RegExp(r'\s+'));
  final tWords = t.split(RegExp(r'\s+'));
  bool allWordsMatch = qWords.every((qw) =>
      tWords.any((tw) => tw.startsWith(qw) || _levenshtein(qw, tw) <= _threshold(qw)));
  if (allWordsMatch) return true;

  // Subsequence match — "crdio" → "cardiology"
  if (_isSubsequence(q.replaceAll(' ', ''), t.replaceAll(' ', ''))) return true;

  return false;
}

/// Threshold scales with word length so short words need exact match.
int _threshold(String word) {
  if (word.length <= 3) return 0;
  if (word.length <= 5) return 1;
  if (word.length <= 8) return 2;
  return 3;
}

/// Classic Levenshtein edit distance (capped early for performance).
int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  // Cap: if lengths differ by more than max threshold, skip heavy computation
  if ((a.length - b.length).abs() > 4) return 99;

  final dp = List.generate(
    a.length + 1,
    (i) => List.generate(b.length + 1, (j) => 0),
  );
  for (int i = 0; i <= a.length; i++) {
    dp[i][0] = i;
  }
  for (int j = 0; j <= b.length; j++) {
    dp[0][j] = j;
  }

  for (int i = 1; i <= a.length; i++) {
    for (int j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      dp[i][j] = [
        dp[i - 1][j] + 1,
        dp[i][j - 1] + 1,
        dp[i - 1][j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
    }
  }
  return dp[a.length][b.length];
}

/// Returns true if [sub] is a subsequence of [str].
bool _isSubsequence(String sub, String str) {
  int si = 0;
  for (int i = 0; i < str.length && si < sub.length; i++) {
    if (str[i] == sub[si]) si++;
  }
  return si == sub.length;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Search Delegate
// ─────────────────────────────────────────────────────────────────────────────

class UniversalSearchDelegate extends SearchDelegate {
  final List<Map<String, dynamic>> data;
  final List<String> history;
  final String scope; // "study_hub" | "lab_test"

  // Speech state shared across rebuilds
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;

  UniversalSearchDelegate({
    required this.data,
    required this.history,
    required this.scope,
  });

  @override
  String get searchFieldLabel =>
      scope == "lab_test" ? "Search Labs & Clinics..." : "Search Medicines...";

  // ── AppBar actions: clear + mic ──────────────────────────────
  @override
  List<Widget>? buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () => query = '',
          ),
        if (!kIsWeb)
          _MicButton(
            speech: _speech,
            isListening: _isListening,
            onResult: (words) {
              query = words;
              _isListening = false;
              showResults(context);
            },
            onListeningChanged: (v) => _isListening = v,
          ),
      ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () {
          _speech.stop();
          close(context, null);
        },
      );

  @override
  Widget buildResults(BuildContext context) => _buildSearchResults();

  @override
  Widget buildSuggestions(BuildContext context) =>
      query.isEmpty ? _buildHistoryList(context) : _buildSearchResults();

  // ── History list ─────────────────────────────────────────────
  Widget _buildHistoryList(BuildContext context) {
    return ListView.builder(
      itemCount: history.length,
      itemBuilder: (context, index) => ListTile(
        leading: Icon(Icons.history, color: AppColors.textMuted(context)),
        title: Text(history[index],
            style: const TextStyle(fontSize: 15)),
        onTap: () {
          query = history[index];
          showResults(context);
        },
      ),
    );
  }

  // ── Fuzzy results list ───────────────────────────────────────
  Widget _buildSearchResults() {
    final q = query.trim();

    final suggestions = data.where((item) {
      final name =
          (item['full_name'] ?? item['name'] ?? '').toString();
      final secondary =
          (item['address'] ?? item['category'] ?? item['speciality'] ?? '')
              .toString();
      return _fuzzyMatch(name, q) || _fuzzyMatch(secondary, q);
    }).toList();

    if (suggestions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded,
                size: 64, color: const Color(0xFFCBD5E1)),
            const SizedBox(height: 16),
            Text(
              'No results for "$q"',
              style: TextStyle(
                  fontSize: 15, color: const Color(0xFF64748B)),
            ),
            const SizedBox(height: 8),
            Text(
              'Try different spelling or use the mic 🎤',
              style: TextStyle(
                  fontSize: 12, color: const Color(0xFF94A3B8)),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: suggestions.length,
      itemBuilder: (context, index) {
        final item = suggestions[index];
        final displayName =
            item['full_name'] ?? item['name'] ?? 'Unknown';
        final subtitle =
            item['address'] ?? item['category'] ?? item['speciality'] ?? '';

        return ListTile(
          leading: CircleAvatar(
            backgroundColor:
                const Color(0xFF6366F1).withValues(alpha: 0.1),
            child: Icon(
              scope == "lab_test"
                  ? Icons.local_hospital_rounded
                  : Icons.medication_rounded,
              color: const Color(0xFF6366F1),
              size: 20,
            ),
          ),
          title: _HighlightText(text: displayName, query: q),
          subtitle: subtitle.isNotEmpty
              ? Text(subtitle,
                  style: TextStyle(
                      fontSize: 12, color: const Color(0xFF475569)))
              : null,
          onTap: () => close(context, displayName),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Mic button widget (stateful, lives inside the delegate's actions)
// ─────────────────────────────────────────────────────────────────────────────
class _MicButton extends StatefulWidget {
  final stt.SpeechToText speech;
  final bool isListening;
  final void Function(String words) onResult;
  final void Function(bool) onListeningChanged;

  const _MicButton({
    required this.speech,
    required this.isListening,
    required this.onResult,
    required this.onListeningChanged,
  });

  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton>
    with SingleTickerProviderStateMixin {
  bool _listening = false;
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    widget.speech.stop();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_listening) {
      await widget.speech.stop();
      _pulse.stop();
      _pulse.reset();
      setState(() => _listening = false);
      widget.onListeningChanged(false);
      return;
    }

    final available = await widget.speech.initialize(
      onError: (_) {
        _pulse.stop();
        _pulse.reset();
        if (mounted) setState(() => _listening = false);
        widget.onListeningChanged(false);
      },
    );
    if (!available) return;

    setState(() => _listening = true);
    _pulse.repeat(reverse: true);
    widget.onListeningChanged(true);

    widget.speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          _pulse.stop();
          _pulse.reset();
          if (mounted) setState(() => _listening = false);
          widget.onListeningChanged(false);
          if (result.recognizedWords.isNotEmpty) {
            widget.onResult(result.recognizedWords);
          }
        }
      },
      listenFor: const Duration(seconds: 15),
      pauseFor: const Duration(seconds: 4),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final scale = _listening ? 1.0 + _pulse.value * 0.2 : 1.0;
        return Transform.scale(
          scale: scale,
          child: IconButton(
            tooltip: _listening ? 'Tap to stop' : 'Search by voice',
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _listening
                    ? Colors.redAccent
                    : const Color(0xFF6366F1),
              ),
              child: Icon(
                _listening ? Icons.mic : Icons.mic_none,
                color: Colors.white,
                size: 18,
              ),
            ),
            onPressed: _toggle,
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Highlight matching characters in result names
// ─────────────────────────────────────────────────────────────────────────────
class _HighlightText extends StatelessWidget {
  final String text;
  final String query;

  const _HighlightText({required this.text, required this.query});

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return Text(text, style: const TextStyle(fontWeight: FontWeight.w500));
    }

    final lower = text.toLowerCase();
    final lowerQ = query.toLowerCase();
    final idx = lower.indexOf(lowerQ);

    if (idx < 0) {
      // No direct match — still show text (fuzzy matched via other field)
      return Text(text, style: const TextStyle(fontWeight: FontWeight.w500));
    }

    return RichText(
      text: TextSpan(
        style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 15,
            fontWeight: FontWeight.w500),
        children: [
          if (idx > 0) TextSpan(text: text.substring(0, idx)),
          TextSpan(
            text: text.substring(idx, idx + lowerQ.length),
            style: const TextStyle(
              color: Color(0xFF6366F1),
              fontWeight: FontWeight.bold,
              backgroundColor: Color(0xFFEEF2FF),
            ),
          ),
          if (idx + lowerQ.length < text.length)
            TextSpan(text: text.substring(idx + lowerQ.length)),
        ],
      ),
    );
  }
}