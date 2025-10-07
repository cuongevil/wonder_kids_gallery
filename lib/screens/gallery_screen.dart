import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:firebase_storage/firebase_storage.dart';

// 🔹 File JSON bạn đã upload trong Storage: prompts/prompts_trending.json

class PromptItem {
  final String id;
  final String title;
  final String image;
  final String prompt;
  final List<String> tags;
  final String? category;
  final String? trendDate;

  PromptItem({
    required this.id,
    required this.title,
    required this.image,
    required this.prompt,
    required this.tags,
    this.category,
    this.trendDate,
  });

  factory PromptItem.fromJson(Map<String, dynamic> j) => PromptItem(
    id: (j['id'] ?? '').toString(),
    title: (j['title'] ?? '').toString(),
    image: (j['image'] ?? '').toString(),
    prompt: (j['prompt'] ?? '').toString(),
    tags: ((j['tags'] ?? []) as List).map((e) => e.toString()).toList(),
    category: j['category']?.toString(),
    trendDate: j['trendDate']?.toString(),
  );
}

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  List<PromptItem> all = [];
  List<PromptItem> visible = [];
  bool loading = true;
  String? error;
  String? updatedAt;

  // Filters
  final TextEditingController _q = TextEditingController();
  final Set<String> selectedTags = {};
  String selectedCategory = 'Tất cả';
  List<String> allTags = [];
  List<String> allCategories = ['Tất cả'];

  @override
  void initState() {
    super.initState();
    _loadTrending();
    _q.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  // 🔹 Đọc JSON từ Firebase Storage
  Future<void> _loadTrending({bool bustCache = false}) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      // Lấy URL tạm của file trong Storage
      final ref = FirebaseStorage.instance.ref('prompts/prompts_trending.json');
      final url = await ref.getDownloadURL();
      final uri = bustCache
          ? Uri.parse('$url?t=${DateTime.now().millisecondsSinceEpoch}')
          : Uri.parse(url);

      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final items = ((data['items'] ?? []) as List)
            .map((e) => PromptItem.fromJson(e))
            .toList();
        updatedAt = data['updatedAt']?.toString();
        all = items;
        _buildFacets();
        _applyFilters();
        setState(() => loading = false);
      } else {
        setState(() {
          error = 'Không tải được JSON (${res.statusCode})';
          loading = false;
        });
      }
    } catch (e) {
      setState(() {
        error = 'Lỗi khi tải từ Firebase Storage: $e';
        loading = false;
      });
    }
  }

  void _buildFacets() {
    final tags = <String>{};
    final cats = <String>{};
    for (final it in all) {
      tags.addAll(it.tags);
      if ((it.category ?? '').isNotEmpty) cats.add(it.category!);
    }
    allTags = tags.toList()..sort();
    allCategories = ['Tất cả', ...cats.toList()..sort()];
  }

  void _applyFilters() {
    final q = _q.text.trim().toLowerCase();
    setState(() {
      visible = all.where((it) {
        final hay =
        (it.title + ' ' + it.prompt + ' ' + it.tags.join(' ')).toLowerCase();
        final okQ = q.isEmpty ? true : hay.contains(q);
        final okTag =
        selectedTags.isEmpty ? true : it.tags.any(selectedTags.contains);
        final okCat =
        selectedCategory == 'Tất cả' ? true : it.category == selectedCategory;
        return okQ && okTag && okCat;
      }).toList();
    });
  }

  Future<void> _onRefresh() async => _loadTrending(bustCache: true);

  void _clearFilters() {
    selectedTags.clear();
    selectedCategory = 'Tất cả';
    _q.clear();
    _applyFilters();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wonder Kids Gallery'),
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            onPressed: () => _loadTrending(bustCache: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : (error != null)
          ? Center(child: Text(error!))
          : RefreshIndicator(
        onRefresh: _onRefresh,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (updatedAt != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Cập nhật: $updatedAt',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.grey)),
              ),
            TextField(
              controller: _q,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Tìm theo từ khóa / prompt / tag...',
                filled: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: selectedCategory,
                    items: allCategories
                        .map((c) =>
                        DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => selectedCategory = v);
                      _applyFilters();
                    },
                    decoration: InputDecoration(
                      labelText: 'Danh mục',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.filter_alt_off),
                  label: const Text('Xoá lọc'),
                )
              ],
            ),
            const SizedBox(height: 8),
            if (allTags.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: -8,
                children: allTags.map((t) {
                  final selected = selectedTags.contains(t);
                  return ChoiceChip(
                    label: Text(t),
                    selected: selected,
                    onSelected: (v) {
                      if (v) {
                        selectedTags.add(t);
                      } else {
                        selectedTags.remove(t);
                      }
                      _applyFilters();
                    },
                  );
                }).toList(),
              ),
            const SizedBox(height: 12),
            GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              gridDelegate:
              const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.9,
              ),
              itemCount: visible.length,
              itemBuilder: (context, i) => _GalleryCard(visible[i]),
            )
          ],
        ),
      ),
    );
  }
}

class _GalleryCard extends StatelessWidget {
  final PromptItem item;
  const _GalleryCard(this.item);

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => _showPrompt(context),
        child: Column(
          children: [
            Expanded(
              child: FutureBuilder<String>(
                future: _resolveImage(item.image),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return CachedNetworkImage(
                    imageUrl: snap.data!,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) =>
                    const Center(child: Text('Ảnh lỗi')),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String> _resolveImage(String path) async {
    // Nếu là URL thì dùng trực tiếp, nếu không thì lấy từ Firebase Storage
    if (path.startsWith('http')) return path;
    final ref = FirebaseStorage.instance.ref(path);
    return ref.getDownloadURL();
  }

  void _showPrompt(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              if (item.trendDate != null) ...[
                const SizedBox(height: 4),
                Text('Ngày: ${item.trendDate}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
              const SizedBox(height: 12),
              SelectableText(item.prompt,
                  style: const TextStyle(fontSize: 14, height: 1.4)),
              if (item.tags.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(
                    spacing: 6,
                    children:
                    item.tags.map((t) => Chip(label: Text(t))).toList()),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: item.prompt));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Đã copy prompt')));
                      }
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copy Prompt'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () =>
                        Share.share(item.prompt, subject: 'Prompt sinh ảnh'),
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Share Prompt'),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}
