import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:webfeed_plus/webfeed_plus.dart';

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
  final TextEditingController _controller = TextEditingController();
  List<RssItem>? _items;
  bool _loading = false;
  String? _error;

  // A small helper to remove simple HTML tags from descriptions.
  String _stripHtml(String? input) {
    if (input == null) return '';
    return input.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }

  Future<void> _loadFeed([String? url]) async {
    final feedUrl = (url ?? _controller.text).trim();
    if (feedUrl.isEmpty) {
      setState(() => _error = 'Please enter an RSS feed URL.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _items = null;
    });

    try {
      final uri = Uri.parse(feedUrl);
      final resp = await http.get(uri);
      if (resp.statusCode != 200) {
        setState(() => _error = 'Failed to load feed (${resp.statusCode}).');
        return;
      }

      final feed = RssFeed.parse(resp.body);
      setState(() {
        _items = feed.items ?? [];
        if (_items!.isEmpty) _error = 'Feed loaded but no items found.';
      });
    } catch (e) {
      setState(() => _error = 'Error loading feed: ${e.toString()}');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
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
    if (_items == null) {
      return const Center(
        child: Text('Enter an RSS feed URL above and press Load.'),
      );
    }
    return ListView.separated(
      itemCount: _items!.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = _items![index];
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart News'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        hintText: 'https://example.com/feed.xml',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _loadFeed(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _loading ? null : _loadFeed,
                    child: const Text('Load'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _loading
                        ? null
                        : () {
                            const sample =
                                'https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml';
                            _controller.text = sample;
                            _loadFeed(sample);
                          },
                    child: const Text('Sample'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }
}
