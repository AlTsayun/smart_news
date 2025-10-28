import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:webfeed_plus/webfeed_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart News',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      // Provide a dark theme and force the app to use it by default.
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme:
            ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.dark),
      ),
      themeMode: ThemeMode.dark,
      home: const FeedPage(),
    );
  }
}

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  final TextEditingController _newFeedController = TextEditingController();
  final List<String> _feeds = [];
  List<RssItem> _items = [];
  bool _loading = false;
  String? _error;

  // A small helper to remove simple HTML tags from descriptions.
  String _stripHtml(String? input) {
    if (input == null) return '';
    return input.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }

  DateTime? _parseDate(dynamic input) {
    if (input == null) return null;
    try {
      if (input is DateTime) return input;
      final s = input.toString();
      return DateTime.tryParse(s) ?? DateTime.tryParse(s.replaceAll(',',''));
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSavedFeeds();
  }

  Future<void> _loadSavedFeeds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('feeds') ?? [];
      setState(() {
        _feeds.clear();
        _feeds.addAll(saved);
      });
      if (_feeds.isNotEmpty) {
        _loadAllFeeds();
      }
    } catch (_) {
      // ignore errors reading prefs; app continues without persisted feeds
    }
  }

  Future<void> _saveFeeds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('feeds', _feeds);
    } catch (_) {
      // ignore write errors
    }
  }

  Future<void> _loadAllFeeds() async {
    if (_feeds.isEmpty) {
      setState(() {
        _items = [];
        _error = 'No feeds added. Add a feed on the left.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _items = [];
    });

    final Map<String, RssItem> unique = {};
    final List<String> errors = [];

    // Fetch all feeds in parallel but tolerate individual failures.
    final futures = _feeds.map((url) async {
      try {
        final uri = kIsWeb
            // Use a CORS proxy for web platform
            ? Uri.parse('https://api.allorigins.win/raw?url=${Uri.encodeComponent(url)}')
            : Uri.parse(url);
            
        final resp = await http.get(uri, headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml,application/rss+xml,application/atom+xml;q=0.9',
        });
        
        if (resp.statusCode != 200) {
          errors.add('$url -> HTTP ${resp.statusCode} (${resp.reasonPhrase})');
          return;
        }

        try {
          // Try RSS format first
          final feed = RssFeed.parse(resp.body);
          for (final item in feed.items ?? []) {
            final key = (item.link ?? item.title ?? '').toString().trim();
            if (key.isEmpty) continue;
            unique.putIfAbsent(key, () => item);
          }
          return; // Successfully parsed as RSS
        } catch (rssError) {
          try {
            // Try Atom format if RSS fails
            final atomFeed = AtomFeed.parse(resp.body);
            for (final entry in atomFeed.items ?? []) {
              // Convert Atom entry to RSS-like format for consistency
              final item = RssItem(
                title: entry.title,
                description: entry.summary ?? entry.content,
                link: entry.links?.firstOrNull?.href,
                pubDate: entry.updated ?? entry.published,
                author: entry.authors?.firstOrNull?.name,
              );
              final key = (item.link ?? item.title ?? '').toString().trim();
              if (key.isEmpty) continue;
              unique.putIfAbsent(key, () => item);
            }
            return; // Successfully parsed as Atom
          } catch (atomError) {
            // If both RSS and Atom parsing fail, throw detailed error
            throw Exception('Feed format not recognized: RSS error: $rssError, Atom error: $atomError');
          }
        }
      } catch (e) {
        // Include more context in error messages
        final error = e.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
        errors.add('$url -> ${error.length > 100 ? '${error.substring(0, 100)}...' : error}');
      }
    }).toList();

    await Future.wait(futures);

    final items = unique.values.toList();
    // Try to sort by pubDate descending when available.
    items.sort((a, b) {
      final da = _parseDate(a.pubDate);
      final db = _parseDate(b.pubDate);
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });

    setState(() {
      _items = items;
      if (_items.isEmpty && errors.isEmpty) {
        _error = 'Feeds loaded but no items found.';
      } else if (errors.isNotEmpty) {
        _error = 'Some feeds failed:\n${errors.join('\n')}';
      }
      _loading = false;
    });
  }

  Future<void> _addFeed() async {
    final url = _newFeedController.text.trim();
    if (url.isEmpty) return;
    if (_feeds.contains(url)) {
      // move to top
      setState(() {
        _feeds.remove(url);
        _feeds.insert(0, url);
      });
      _newFeedController.clear();
      await _saveFeeds();
      _loadAllFeeds();
      return;
    }
    setState(() {
      _feeds.insert(0, url);
      _newFeedController.clear();
    });
    await _saveFeeds();
    _loadAllFeeds();
  }

  Future<void> _removeFeed(String url) async {
    setState(() {
      _feeds.remove(url);
    });
    await _saveFeeds();
    _loadAllFeeds();
  }

  @override
  void dispose() {
    _newFeedController.dispose();
    super.dispose();
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: Colors.red)),
      );
    }
    if (_items.isEmpty) {
      return const Center(
        child: Text('Add some RSS feeds on the left and they will appear here.'),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadAllFeeds,
      child: ListView.separated(
        itemCount: _items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
        final item = _items[index];
        final title = item.title ?? '(no title)';
        final date = (item.pubDate ?? '').toString();
        final desc = _stripHtml(item.description ?? item.content?.value ?? '');
        final subtitle =
            (date.isNotEmpty ? '$date\n' : '') +
            (desc.length > 200 ? '${desc.substring(0, 200)}…' : desc);

        return ListTile(
          title: Text(title),
          subtitle: Text(subtitle),
          isThreeLine: true,
          onTap: () => _showItemDialog(item),
        );
      },
    ),
    );
  }

  void _showItemDialog(RssItem item) {
    final title = item.title ?? '(no title)';
    final link = item.link ?? '(no link)';
    final desc = _stripHtml(item.description ?? item.content?.value ?? '');
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.pubDate != null)
                Text(
                  (item.pubDate ?? '').toString(),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              const SizedBox(height: 8),
              Text(desc),
              const SizedBox(height: 12),
              Text('Link: $link', style: const TextStyle(color: Colors.blue)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildSidePanel(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newFeedController,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      hintText: 'https://example.com/feed.xml',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _addFeed(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _addFeed,
                  child: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Expanded(
              child: _feeds.isEmpty
                  ? const Center(child: Text('No feeds yet'))
                  : ListView.separated(
                      itemCount: _feeds.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final url = _feeds[index];
                        return ListTile(
                          title: Text(url, maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => _removeFeed(url),
                          ),
                          onTap: () {
                            // Move tapped feed to top and reload
                            setState(() {
                              _feeds.removeAt(index);
                              _feeds.insert(0, url);
                            });
                            _loadAllFeeds();
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sidePanel = _buildSidePanel(context);
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 700;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Smart News'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        ),
        drawer: wide ? null : Drawer(child: sidePanel),
        body: SafeArea(
          child: Row(
            children: [
              if (wide)
                Container(
                  width: 320,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    border: Border(right: BorderSide(color: Theme.of(context).dividerColor)),
                  ),
                  child: sidePanel,
                ),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      );
    });
  }
}
