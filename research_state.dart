import 'model.dart';

String researchAddress(String input) {
  final text = input.trim();
  final uri = Uri.tryParse(text);
  if (uri != null && ['http', 'https'].contains(uri.scheme) && uri.host.isNotEmpty) {
    return uri.toString();
  }
  if (!text.contains(RegExp(r'\s')) && text.contains('.') && !text.contains(':')) {
    return 'https://$text';
  }
  return Uri.https('duckduckgo.com', '/', {'q': text}).toString();
}

/// Project-owned browser state is serialized alongside the author's work.
class ResearchState {
  ResearchState(this.project);
  final Project project;
  Map<String, dynamic> get data {
    final raw = project.layout['researchBrowser'];
    if (raw is Map<String, dynamic>) return raw;
    return project.layout['researchBrowser'] = <String, dynamic>{};
  }

  String get url => data['url'] as String? ?? 'https://duckduckgo.com';
  String get title => data['title'] as String? ?? '';
  List<Map<String, dynamic>> get history =>
      (data['history'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  List<Map<String, dynamic>> get bookmarks =>
      (data['bookmarks'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

  void visit(String url, String title) {
    if (!['http', 'https'].contains(Uri.tryParse(url)?.scheme)) return;
    if (this.url != url) data['scrollY'] = 0;
    data['url'] = url;
    data['title'] = title;
    final entries = history..removeWhere((e) => e['url'] == url);
    entries.insert(0, {'url': url, 'title': title, 'at': DateTime.now().toUtc().toIso8601String()});
    data['history'] = entries.take(100).toList();
  }

  void toggleBookmark() {
    final entries = bookmarks;
    if (entries.any((e) => e['url'] == url)) {
      entries.removeWhere((e) => e['url'] == url);
    } else {
      entries.add({'url': url, 'title': title.isEmpty ? url : title});
    }
    data['bookmarks'] = entries;
  }
}

CreativeObject researchClip({required String text, required String url, required String title}) {
  final label = title.trim().isEmpty ? text.trim().split('\n').first : title.trim();
  return CreativeObject(
    kind: 'research',
    title: label.length > 70 ? '${label.substring(0, 67)}…' : label,
    body: text.trim(),
    meta: {
      'url': url,
      'sources': [if (url.isNotEmpty) url],
      'sourceTitle': title,
      'quote': text.trim(),
      'status': 'Clipped',
      'clippedAt': DateTime.now().toUtc().toIso8601String(),
    },
  );
}

/// Cache selection before focus moves from the native WebView to Flutter.
/// Messages only update a preview; saving requires a gesture in the app.
const researchSelectionBridge = r'''
(() => {
  if (window.top !== window) return;
  let timer;
  const send = () => {
    const text = window.getSelection()?.toString().trim() || '';
    if (text) window.chrome.webview.postMessage({type:'researchSelection', text:text.slice(0, 50000), url:location.href, title:document.title});
  };
  document.addEventListener('selectionchange', () => { clearTimeout(timer); timer = setTimeout(send, 120); });
  document.addEventListener('mouseup', send);
  document.addEventListener('dragstart', send);
  let scrollTimer;
  window.addEventListener('scroll', () => {
    clearTimeout(scrollTimer);
    scrollTimer = setTimeout(() => window.chrome.webview.postMessage({type:'researchScroll', y:window.scrollY}), 300);
  });
})();
''';
