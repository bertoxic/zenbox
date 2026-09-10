import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';
import 'editor.dart' show askText;
import 'model.dart';
import 'theme.dart';
import 'notification_service.dart';
import 'research_state.dart';

Future<void>? _browserEnvironment;

Future<void> _initializeBrowserEnvironment(String userDataPath) async {
  try {
    await WebviewController.initializeEnvironment(userDataPath: userDataPath);
  } on PlatformException catch (error) {
    // Another browser view may have initialized the process-wide environment
    // before this view was created. That environment is safe to reuse.
    if (error.code != 'environment_already_initialized') rethrow;
  }
}

class ResearchBrowserView extends StatefulWidget {
  const ResearchBrowserView({
    super.key,
    required this.store,
    required this.onOpenNote,
  });

  final StudioStore store;
  final void Function(CreativeObject) onOpenNote;

  @override
  State<ResearchBrowserView> createState() => _ResearchBrowserViewState();
}

class _ResearchBrowserViewState extends State<ResearchBrowserView> {
  final _controller = WebviewController();
  final _urlController = TextEditingController(text: 'https://duckduckgo.com');
  bool _isInitialized = false;
  bool _isLoading = false;
  String? _initError;
  String _pageTitle = '';
  bool _showNotes = true;
  late ResearchState _state;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  String _selection = '';
  String _selectionUrl = '';
  String _selectionTitle = '';
  String _noteQuery = '';
  bool _restoring = true;
  final List<Map<String, String>> _tabs = [];
  int _activeTab = 0;

  final List<Map<String, String>> bookmarks = [
    {'name': 'DuckDuckGo', 'url': 'https://duckduckgo.com'},
    {'name': 'Wikipedia', 'url': 'https://en.wikipedia.org'},
    {'name': 'Scholar', 'url': 'https://scholar.google.com'},
    {'name': 'Archive.org', 'url': 'https://archive.org'},
    {'name': 'OpenStax', 'url': 'https://openstax.org'},
  ];

  @override
  void initState() {
    super.initState();
    _state = ResearchState(widget.store.project);
    final savedTabs = (_state.data['tabs'] as List? ?? [])
        .whereType<Map>()
        .map(
          (tab) => {
            'url': tab['url']?.toString() ?? '',
            'title': tab['title']?.toString() ?? '',
          },
        )
        .where((tab) => tab['url']!.isNotEmpty)
        .toList();
    _tabs.addAll(
      savedTabs.isEmpty
          ? [
              {'url': _state.url, 'title': _state.title},
            ]
          : savedTabs,
    );
    _activeTab = ((_state.data['activeTab'] as num?)?.toInt() ?? 0).clamp(
      0,
      _tabs.length - 1,
    );
    _urlController.text = _tabs[_activeTab]['url']!;
    _pageTitle = _tabs[_activeTab]['title']!;
    _showNotes = _state.data['showNotes'] != false;
    _initBrowser();
  }

  void _saveTabs() {
    _state.data['tabs'] = _tabs
        .map((tab) => Map<String, String>.from(tab))
        .toList();
    _state.data['activeTab'] = _activeTab;
    widget.store.changed();
  }

  void _newTab([String? url]) {
    final destination = url ?? 'https://duckduckgo.com';
    setState(() {
      _tabs.add({'url': destination, 'title': ''});
      _activeTab = _tabs.length - 1;
      _urlController.text = destination;
      _pageTitle = '';
    });
    _saveTabs();
    _navigate(destination);
  }

  void _selectTab(int index) {
    if (index == _activeTab || index < 0 || index >= _tabs.length) return;
    setState(() {
      _activeTab = index;
      _urlController.text = _tabs[index]['url']!;
      _pageTitle = _tabs[index]['title']!;
      _selection = '';
    });
    _saveTabs();
    if (_isInitialized) _controller.loadUrl(_urlController.text);
  }

  void _closeTab(int index) {
    if (_tabs.length == 1) {
      setState(() {
        _tabs[0] = {'url': 'https://duckduckgo.com', 'title': ''};
        _urlController.text = _tabs[0]['url']!;
        _pageTitle = '';
      });
      _navigate(_urlController.text);
      return;
    }
    setState(() {
      _tabs.removeAt(index);
      if (_activeTab >= _tabs.length) _activeTab = _tabs.length - 1;
      _urlController.text = _tabs[_activeTab]['url']!;
      _pageTitle = _tabs[_activeTab]['title']!;
    });
    _saveTabs();
    if (_isInitialized) _controller.loadUrl(_urlController.text);
  }

  Future<void> _initBrowser() async {
    try {
      _browserEnvironment ??=
          _initializeBrowserEnvironment(
            '${widget.store.directory.path}/browser-profile',
          ).catchError((Object error) {
            _browserEnvironment = null;
            throw error;
          });
      await _browserEnvironment;
      if (!mounted) return;
      await _controller.initialize();
      if (!mounted) return;
      final restoreUrl = _urlController.text;
      final restoreScroll = (_state.data['scrollY'] as num?)?.toDouble() ?? 0;
      _subscriptions.add(
        _controller.url.listen((url) {
          if (mounted && url.isNotEmpty) {
            _urlController.text = url;
            _tabs[_activeTab]['url'] = url;
            _selection = '';
            _state.visit(url, '');
            _saveTabs();
            widget.store.changed();
          }
        }),
      );
      _subscriptions.add(
        _controller.title.listen((title) {
          if (mounted) {
            setState(() => _pageTitle = title);
            _tabs[_activeTab]['title'] = title;
            _state.visit(_urlController.text, title);
            _saveTabs();
            widget.store.changed();
          }
        }),
      );
      _subscriptions.add(
        _controller.loadingState.listen((state) {
          if (mounted) {
            setState(() => _isLoading = state == LoadingState.loading);
            if (state == LoadingState.navigationCompleted && _restoring) {
              _restoring = false;
              if (_urlController.text == restoreUrl) {
                unawaited(
                  _controller
                      .executeScript('window.scrollTo(0, $restoreScroll)')
                      .catchError((_) => null),
                );
              }
            }
          }
        }),
      );
      _subscriptions.add(
        _controller.webMessage.listen((message) {
          if (!mounted || message is! Map) return;
          if (message['type'] == 'researchSelection' &&
              message['text'] is String) {
            final text = message['text'] as String;
            setState(() {
              _selection = text.substring(0, text.length.clamp(0, 50000));
              _selectionUrl = _urlController.text;
              _selectionTitle = _pageTitle;
            });
          } else if (message['type'] == 'researchScroll' &&
              message['y'] is num &&
              !_restoring) {
            _state.data['scrollY'] = (message['y'] as num).clamp(0, 10000000);
            widget.store.changed();
          }
        }, onError: (Object _) {}),
      );
      await _controller.addScriptToExecuteOnDocumentCreated(
        researchSelectionBridge,
      );

      await _controller.loadUrl(restoreUrl);

      if (mounted) {
        setState(() => _isInitialized = true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _initError = e.toString());
      }
    }
  }

  void _navigate([String? specificUrl]) {
    var text = (specificUrl ?? _urlController.text).trim();
    if (text.isEmpty) return;
    text = researchAddress(text);
    _urlController.text = text;
    _tabs[_activeTab]['url'] = text;
    _tabs[_activeTab]['title'] = '';
    _saveTabs();
    if (_isInitialized) {
      _controller.loadUrl(text);
    }
  }

  Future<void> _clipPage() async {
    final url = _urlController.text.trim();
    final title = _pageTitle.isNotEmpty ? _pageTitle : url;
    final note = await askText(
      context,
      'Clip page to research notes',
      initial:
          '${_selection.isEmpty ? '' : '$_selection\n\n'}Source: $title\nURL: $url\n\nKey takeaways:\n',
      hint: 'Your notes or key takeaways...',
      multiline: true,
    );
    if (note == null) return;
    final o = CreativeObject(
      kind: 'research',
      title: title.length > 55 ? '${title.substring(0, 52)}…' : title,
      body: note,
      meta: {
        'url': url,
        'sources': [url],
        'status': 'Clipped',
        'clippedAt': DateTime.now().toIso8601String(),
      },
    );
    widget.store.add(o);
    if (mounted) {
      TopNotification.show(
        context,
        'Saved "${o.title}" to project research',
        icon: Icons.bookmark_added_outlined,
      );
    }
  }

  void _createNoteFromDrop(Object data) {
    if (data is String) {
      final text = data.trim();
      if (text.isEmpty) return;
      final firstLine = text.split('\n').first.trim();
      final title = firstLine.length > 40
          ? '${firstLine.substring(0, 37)}…'
          : (firstLine.isEmpty ? 'Research Snippet' : firstLine);
      final note = researchClip(
        text: text,
        url: _selectionUrl.isEmpty ? _urlController.text : _selectionUrl,
        title: title,
      );
      widget.store.add(note);
      if (mounted) {
        TopNotification.show(
          context,
          'Created research note from snippet: "$title"',
          icon: Icons.note_add_outlined,
          duration: const Duration(seconds: 2),
        );
      }
    } else if (data is CreativeObject) {
      if (data.kind == 'research') return;
      if (widget.store.project.objects.any(
        (o) => o.id == data.id && o.kind == 'research',
      ))
        return;
      final note = CreativeObject(
        kind: 'research',
        title: 'Note: ${data.title}',
        body: data.body.isNotEmpty
            ? data.body
            : 'Asset reference: ${data.title}',
        meta: {
          'source': 'Object ${data.id}',
          'linkedId': data.id,
          'status': 'Referenced',
          'clippedAt': DateTime.now().toIso8601String(),
        },
        links: [data.id],
      );
      widget.store.add(note);
      if (mounted) {
        TopNotification.show(
          context,
          'Created research note for "${data.title}"',
          icon: Icons.note_add_outlined,
          duration: const Duration(seconds: 2),
        );
      }
    }
  }

  void _openExternally() {
    final url = researchAddress(_urlController.text);
    Process.run('rundll32.exe', ['url.dll,FileProtocolHandler', url]);
  }

  void _saveSelection() {
    if (_selection.trim().isEmpty) return;
    widget.store.add(
      researchClip(
        text: _selection,
        url: _selectionUrl,
        title: _selectionTitle,
      ),
    );
    setState(() {
      _selection = '';
      _showNotes = true;
    });
    TopNotification.show(
      context,
      'Selection saved with its source',
      icon: Icons.bookmark_added_outlined,
    );
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _controller.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final researchNotes = widget.store.project
        .of('research')
        .where(
          (note) => '${note.title} ${note.body} ${note.meta['sources']}'
              .toLowerCase()
              .contains(_noteQuery.toLowerCase()),
        )
        .toList();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
          decoration: BoxDecoration(
            color: paper,
            border: Border(bottom: BorderSide(color: line)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: _isInitialized ? _controller.goBack : null,
                    icon: const Icon(Icons.arrow_back, size: 18),
                  ),
                  IconButton(
                    tooltip: 'Forward',
                    onPressed: _isInitialized ? _controller.goForward : null,
                    icon: const Icon(Icons.arrow_forward, size: 18),
                  ),
                  IconButton(
                    tooltip: 'Reload',
                    onPressed: _isInitialized ? _controller.reload : null,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 18),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: cream,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: line),
                      ),
                      child: TextField(
                        controller: _urlController,
                        style: const TextStyle(fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'Search or enter website address…',
                          prefixIcon: Icon(
                            Icons.search,
                            size: 16,
                            color: muted,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                        onSubmitted: (_) => _navigate(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _clipPage,
                    icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                    label: const Text(
                      'Clip to Project',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Bookmark this page',
                    onPressed: () {
                      setState(() => _state.toggleBookmark());
                      widget.store.changed();
                    },
                    icon: Icon(
                      _state.bookmarks.any((b) => b['url'] == _state.url)
                          ? Icons.star
                          : Icons.star_border,
                      size: 18,
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Saved pages and browsing history',
                    icon: const Icon(Icons.history, size: 18),
                    onSelected: _navigate,
                    itemBuilder: (_) => [
                      for (final entry in [
                        ..._state.bookmarks,
                        ..._state.history,
                      ])
                        PopupMenuItem(
                          value: entry['url'] as String,
                          child: Text(
                            '${entry['title'] == '' ? entry['url'] : entry['title']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                  IconButton(
                    tooltip: 'Open in system browser',
                    onPressed: _openExternally,
                    icon: const Icon(Icons.open_in_new, size: 18),
                  ),
                  IconButton(
                    tooltip: _showNotes
                        ? 'Hide research notes'
                        : 'Show research notes',
                    onPressed: () {
                      setState(() => _showNotes = !_showNotes);
                      _state.data['showNotes'] = _showNotes;
                      widget.store.changed();
                    },
                    icon: Icon(
                      _showNotes
                          ? Icons.vertical_split
                          : Icons.vertical_split_outlined,
                      color: _showNotes ? sage : muted,
                      size: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 34,
                child: Row(
                  children: [
                    Expanded(
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _tabs.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 5),
                        itemBuilder: (context, index) {
                          final tab = _tabs[index];
                          final active = index == _activeTab;
                          return InkWell(
                            onTap: () => _selectTab(index),
                            borderRadius: BorderRadius.circular(7),
                            child: Container(
                              constraints: const BoxConstraints(
                                minWidth: 120,
                                maxWidth: 210,
                              ),
                              padding: const EdgeInsets.only(
                                left: 10,
                                right: 3,
                              ),
                              decoration: BoxDecoration(
                                color: active
                                    ? paleSage.withValues(alpha: .62)
                                    : cream,
                                border: Border.all(color: active ? sage : line),
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    active
                                        ? Icons.public
                                        : Icons.public_outlined,
                                    size: 13,
                                    color: active ? sage : muted,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      (tab['title']?.trim().isNotEmpty ?? false)
                                          ? tab['title']!
                                          : 'New tab',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: active
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Close tab',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 25,
                                      minHeight: 25,
                                    ),
                                    icon: const Icon(Icons.close, size: 14),
                                    onPressed: () => _closeTab(index),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: 'New tab',
                      onPressed: _newTab,
                      icon: const Icon(Icons.add, size: 18),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    'Quick Links: ',
                    style: TextStyle(fontSize: 10, color: muted),
                  ),
                  const SizedBox(width: 6),
                  Wrap(
                    spacing: 6,
                    children: bookmarks.map((b) {
                      return InkWell(
                        onTap: () => _navigate(b['url']),
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: paleSage.withValues(alpha: .35),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            b['name']!,
                            style: TextStyle(fontSize: 10, color: ink),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_selection.isNotEmpty)
          Material(
            color: paleSage,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Draggable<String>(
                      data: _selection,
                      feedback: Material(
                        child: SizedBox(
                          width: 260,
                          child: Text(
                            _selection,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      child: Text(
                        'Drag to notes: $_selection',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _saveSelection,
                    icon: const Icon(Icons.note_add_outlined, size: 16),
                    label: const Text('Save selection'),
                  ),
                  IconButton(
                    tooltip: 'Dismiss selection',
                    onPressed: () => setState(() => _selection = ''),
                    icon: const Icon(Icons.close, size: 16),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _initError != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.travel_explore, size: 48, color: sage),
                              const SizedBox(height: 16),
                              const Text(
                                'Research Web Browser',
                                style: TextStyle(
                                  fontFamily: 'Georgia',
                                  fontSize: 22,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'WebView initialization: $_initError\nYou can still open links in your default browser.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: muted,
                                  height: 1.6,
                                ),
                              ),
                              const SizedBox(height: 18),
                              FilledButton.icon(
                                onPressed: _openExternally,
                                icon: const Icon(Icons.open_in_new, size: 16),
                                label: const Text('Open DuckDuckGo externally'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : !_isInitialized
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text(
                              'Initializing research browser…',
                              style: TextStyle(fontSize: 12, color: muted),
                            ),
                          ],
                        ),
                      )
                    : Webview(_controller),
              ),
              if (_showNotes)
                Container(
                  width: 310,
                  decoration: BoxDecoration(
                    color: paper,
                    border: Border(left: BorderSide(color: line)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Text(
                              'RESEARCH NOTES',
                              style: TextStyle(
                                fontSize: 10,
                                letterSpacing: 1.5,
                                fontWeight: FontWeight.bold,
                                color: muted,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: 'New note',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 26,
                                minHeight: 26,
                              ),
                              onPressed: _clipPage,
                              icon: const Icon(Icons.add, size: 16),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: 'Search notes and sources',
                            suffixIcon: IconButton(
                              tooltip: 'Paste clipboard into a note',
                              icon: const Icon(Icons.content_paste, size: 16),
                              onPressed: () async {
                                final data = await Clipboard.getData(
                                  Clipboard.kTextPlain,
                                );
                                if (mounted && data?.text != null)
                                  _createNoteFromDrop(data!.text!);
                              },
                            ),
                          ),
                          onChanged: (value) =>
                              setState(() => _noteQuery = value),
                        ),
                      ),
                      Expanded(
                        child: DragTarget<Object>(
                          onWillAcceptWithDetails: (details) {
                            if (details.data is String) return true;
                            if (details.data is CreativeObject) {
                              final obj = details.data as CreativeObject;
                              if (obj.kind == 'research') return false;
                              return true;
                            }
                            return false;
                          },
                          onAcceptWithDetails: (details) =>
                              _createNoteFromDrop(details.data),
                          builder: (context, candidates, rejected) {
                            final isHovering = candidates.isNotEmpty;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              decoration: BoxDecoration(
                                color: isHovering
                                    ? sage.withValues(alpha: 0.08)
                                    : Colors.transparent,
                                border: isHovering
                                    ? Border.all(color: sage, width: 2)
                                    : null,
                              ),
                              child: Stack(
                                children: [
                                  if (researchNotes.isEmpty)
                                    Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(20),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.note_add_outlined,
                                              size: 36,
                                              color: isHovering ? sage : muted,
                                            ),
                                            const SizedBox(height: 10),
                                            Text(
                                              isHovering
                                                  ? 'Drop here to create research note'
                                                  : 'No research notes yet.\nDrop highlighted text or assets here,\nor click "+" to clip web pages.',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: isHovering ? ink : muted,
                                                height: 1.6,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                  else
                                    ListView.builder(
                                      padding: const EdgeInsets.all(12),
                                      itemCount: researchNotes.length,
                                      itemBuilder: (context, index) {
                                        final note = researchNotes[index];
                                        final url =
                                            note.meta['url'] as String? ?? '';
                                        return Draggable<CreativeObject>(
                                          data: note,
                                          feedback: Material(
                                            elevation: 6,
                                            color: paper,
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            child: Container(
                                              padding: const EdgeInsets.all(10),
                                              width: 200,
                                              child: Text(
                                                note.title,
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ),
                                          ),
                                          child: Container(
                                            margin: const EdgeInsets.only(
                                              bottom: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              color: cream,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(color: line),
                                            ),
                                            child: Material(
                                              color: Colors.transparent,
                                              child: InkWell(
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                onTap: () =>
                                                    widget.onOpenNote(note),
                                                child: Padding(
                                                  padding: const EdgeInsets.all(
                                                    12,
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          Expanded(
                                                            child: Text(
                                                              note.title,
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: const TextStyle(
                                                                fontSize: 12,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                            ),
                                                          ),
                                                          Icon(
                                                            Icons
                                                                .drag_indicator,
                                                            size: 12,
                                                            color: muted,
                                                          ),
                                                          IconButton(
                                                            tooltip:
                                                                'Delete research note',
                                                            iconSize: 15,
                                                            padding:
                                                                EdgeInsets.zero,
                                                            constraints:
                                                                const BoxConstraints(
                                                                  minWidth: 24,
                                                                  minHeight: 24,
                                                                ),
                                                            color: const Color(
                                                              0xFFA54141,
                                                            ),
                                                            onPressed: () =>
                                                                widget.store
                                                                    .remove(
                                                                      note,
                                                                    ),
                                                            icon: const Icon(
                                                              Icons
                                                                  .delete_outline,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      if (url.isNotEmpty) ...[
                                                        const SizedBox(
                                                          height: 4,
                                                        ),
                                                        InkWell(
                                                          onTap: () =>
                                                              _navigate(url),
                                                          child: Text(
                                                            url,
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: TextStyle(
                                                              fontSize: 9,
                                                              color: sage,
                                                              decoration:
                                                                  TextDecoration
                                                                      .underline,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                      const SizedBox(height: 6),
                                                      Text(
                                                        note.body,
                                                        maxLines: 3,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: muted,
                                                          height: 1.5,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 6),
                                                      Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .end,
                                                        children: [
                                                          TextButton(
                                                            style: TextButton.styleFrom(
                                                              padding:
                                                                  const EdgeInsets.symmetric(
                                                                    horizontal:
                                                                        6,
                                                                  ),
                                                              minimumSize:
                                                                  const Size(
                                                                    0,
                                                                    20,
                                                                  ),
                                                            ),
                                                            onPressed: () =>
                                                                widget
                                                                    .onOpenNote(
                                                                      note,
                                                                    ),
                                                            child: const Text(
                                                              'Open',
                                                              style: TextStyle(
                                                                fontSize: 10,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  if (isHovering && researchNotes.isNotEmpty)
                                    Positioned(
                                      top: 8,
                                      left: 8,
                                      right: 8,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8,
                                          horizontal: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: gold,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: ink.withValues(alpha: .15),
                                              blurRadius: 6,
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.add_circle_outline,
                                              size: 14,
                                              color: ink,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              'DROP TO CREATE RESEARCH NOTE',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 1.1,
                                                color: ink,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
