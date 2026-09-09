import 'dart:convert';
import 'dart:io';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

bool publicResearchUrl(Uri uri) {
  if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) return false;
  final host = uri.host.toLowerCase().replaceAll(RegExp(r'^\[|\]$'), '');
  if (host == 'localhost' || host.endsWith('.localhost') || host.endsWith('.local')) return false;
  final address = InternetAddress.tryParse(host);
  return address == null || publicResearchAddress(address);
}

bool publicResearchAddress(InternetAddress address) {
  if (address.isLoopback || address.isLinkLocal || address.isMulticast) return false;
  final bytes = address.rawAddress;
  if (bytes.length == 16) {
    if (bytes.every((b) => b == 0) || (bytes[0] & 0xfe) == 0xfc) return false;
    // IPv4-mapped IPv6 must pass the same IPv4 checks.
    if (bytes.take(10).every((b) => b == 0) && bytes[10] == 255 && bytes[11] == 255) {
      return publicResearchAddress(InternetAddress(bytes.skip(12).join('.')));
    }
    return true;
  }
  final a = bytes[0], b = bytes[1];
  return !(a == 0 || a == 10 || a == 127 || a >= 224 ||
      (a == 169 && b == 254) || (a == 172 && b >= 16 && b <= 31) ||
      (a == 192 && b == 168) || (a == 100 && b >= 64 && b <= 127));
}

String _clean(String text) => text.replaceAll(RegExp(r'[ \t\r\n]+'), ' ').trim();

List<Map<String, dynamic>> parseResearchResults(String source, int limit) {
  final document = html.parse(source);
  final results = <Map<String, dynamic>>[];
  final seen = <String>{};
  for (final card in document.querySelectorAll('.result')) {
    final anchor = card.querySelector('a.result__a');
    if (anchor == null) continue;
    final href = Uri.tryParse(anchor.attributes['href'] ?? '');
    final url = Uri.tryParse(href?.queryParameters['uddg'] ?? href?.toString() ?? '');
    if (url == null || !publicResearchUrl(url) || !seen.add(url.toString())) continue;
    results.add({'title': _clean(anchor.text), 'url': url.toString(), 'domain': url.host,
      'snippet': _clean(card.querySelector('.result__snippet')?.text ?? '')});
    if (results.length == limit) break;
  }
  return results;
}

Map<String, dynamic> extractResearchPage(String source, Uri url, int offset, int maxChars) {
  final document = html.parse(source);
  final title = _clean(document.querySelector('title')?.text ?? '');
  final description = document.querySelector('meta[name="description"]')?.attributes['content'];
  final published = document.querySelector('meta[property="article:published_time"]')?.attributes['content'];
  final author = document.querySelector('meta[name="author"]')?.attributes['content'];
  for (final node in document.querySelectorAll('script,style,noscript,nav,footer,header,aside,form')) { node.remove(); }
  final root = document.querySelector('article') ?? document.querySelector('main') ?? document.body;
  // Add paragraph boundaries without duplicating nested text.
  for (final node in root?.querySelectorAll('p,h1,h2,h3,h4,li,blockquote,br,tr') ?? []) { node.appendText('\n'); }
  final text = (root?.text ?? '').split('\n').map(_clean).where((line) => line.isNotEmpty).join('\n');
  final start = offset.clamp(0, text.length);
  final end = (start + maxChars).clamp(0, text.length);
  final links = <Map<String, String>>[];
  final seen = <String>{};
  for (final anchor in root?.querySelectorAll('a[href]') ?? []) {
    final target = url.resolve(anchor.attributes['href']!);
    if (!publicResearchUrl(target) || !seen.add(target.toString())) continue;
    links.add({'title': _clean(anchor.text), 'url': target.toString()});
    if (links.length >= 20) break;
  }
  return {'success': true, 'url': url.toString(), 'title': title, 'domain': url.host,
    if (author != null) 'author': author, if (published != null) 'publishedAt': published,
    if (description != null) 'description': description,
    'retrievedAt': DateTime.now().toUtc().toIso8601String(),
    'text': text.substring(start, end), 'offset': start, 'totalChars': text.length,
    'nextOffset': end < text.length ? end : null, 'links': links};
}

/// One per AI run: shared transport, bounded parallel reads and response cache.
class ResearchService {
  ResearchService({required this.client, this.resolveAddresses = InternetAddress.lookup});
  final http.Client client;
  final Future<List<InternetAddress>> Function(String host) resolveAddresses;
  final _cache = <String, Map<String, dynamic>>{};

  Future<(Uri, String, String)> _read(Uri initial) async {
    var uri = initial;
    for (var redirects = 0; redirects <= 5; redirects++) {
      if (!publicResearchUrl(uri)) throw const FormatException('Only public HTTPS pages can be read.');
      final addresses = await resolveAddresses(uri.host).timeout(const Duration(seconds: 8));
      if (addresses.isEmpty || addresses.any((address) => !publicResearchAddress(address))) {
        throw const FormatException('This address does not resolve to a public web server.');
      }
      final request = http.Request('GET', uri)..followRedirects = false;
      request.headers['User-Agent'] = 'XandoraStudio/1.0 research assistant';
      final response = await client.send(request).timeout(const Duration(seconds: 20));
      if (response.statusCode >= 300 && response.statusCode < 400) {
        final location = response.headers['location'];
        await response.stream.listen((_) {}).cancel();
        if (location == null) throw const FormatException('Redirect has no destination.');
        uri = uri.resolve(location);
        continue;
      }
      if (response.statusCode != 200) {
        await response.stream.listen((_) {}).cancel();
        throw HttpException('Research server returned HTTP ${response.statusCode}');
      }
      final type = response.headers['content-type'] ?? '';
      if (!type.contains('text/') && !type.contains('json')) {
        await response.stream.listen((_) {}).cancel();
        throw const FormatException('This source is not readable HTML or text.');
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(const Duration(seconds: 15))) {
        bytes.addAll(chunk);
        if (bytes.length > 2000000) throw const FormatException('Page exceeds the 2 MB research limit.');
      }
      return (uri, utf8.decode(bytes, allowMalformed: true), type);
    }
    throw const FormatException('Too many redirects.');
  }

  Future<Map<String, dynamic>> run(Map<String, dynamic> args) async {
    final action = args['action'];
    final inputs = action == 'search'
        ? (args['queries'] as List? ?? [args['query']])
        : (args['urls'] as List? ?? [args['url']]);
    if (!['search', 'fetch'].contains(action) || inputs.isEmpty || inputs.length > 8 || inputs.any((v) => v is! String || v.trim().isEmpty)) {
      return {'success': false, 'error': 'Use search with 1–8 queries or fetch with 1–8 URLs.'};
    }
    final values = inputs.cast<String>().toSet().toList();
    final results = <Map<String, dynamic>>[];
    // At most three public requests concurrently; retain each source's errors.
    for (var i = 0; i < values.length; i += 3) {
      results.addAll(await Future.wait(values.skip(i).take(3).map((value) async {
        final key = jsonEncode({...args, 'input': value});
        if (_cache.containsKey(key)) return {..._cache[key]!, 'cached': true};
        try {
          final uri = action == 'search' ? Uri.https('html.duckduckgo.com', '/html/', {'q': value}) : Uri.parse(value);
          final (resolved, source, type) = await _read(uri);
          late Map<String, dynamic> result;
          if (action == 'search') {
            final cards = parseResearchResults(source, ((args['maxResults'] as num?)?.toInt() ?? 5).clamp(1, 10));
            result = {'success': cards.isNotEmpty, 'query': value, 'results': cards,
              if (cards.isEmpty) 'error': 'No readable search results. The provider may have blocked this request; try a focused query or fetch a known source URL.'};
          } else {
            final offset = ((args['offset'] as num?)?.toInt() ?? 0).clamp(0, 2000000);
            final count = ((args['maxChars'] as num?)?.toInt() ?? (values.length > 1 ? 4000 : 12000)).clamp(500, 24000);
            result = type.contains('html') ? extractResearchPage(source, resolved, offset, count)
                : {'success': true, 'url': resolved.toString(), 'text': source.substring(offset.clamp(0, source.length), (offset + count).clamp(0, source.length)),
                  'totalChars': source.length, 'nextOffset': offset + count < source.length ? offset + count : null};
          }
          if (result['success'] == true) {
            if (_cache.length >= 32) _cache.remove(_cache.keys.first);
            _cache[key] = result;
          }
          return result;
        } catch (error) { return <String, dynamic>{'success': false, 'input': value, 'error': '$error'}; }
      })));
    }
    return results.length == 1 ? results.single : {
      'success': results.any((r) => r['success'] == true),
      'partial': results.any((r) => r['success'] != true), 'results': results,
    };
  }
}
