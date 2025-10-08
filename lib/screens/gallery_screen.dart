import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';

/// 🎨 Chủ đề pastel Wonder Kids
class AppTheme {
  static const Color pink = Color(0xFFF8E8EE);
  static const Color lavender = Color(0xFFE4D4F0);
  static const Color cream = Color(0xFFFFF9F5);
  static const Color ink = Color(0xFF2E2A32);
  static const Color inkSoft = Color(0xFF6B6670);
  static const Color line = Color(0xFFE7E3EA);
  static const Color primary = Color(0xFF7C6DB0);
  static const Color primarySoft = Color(0xFFA596CC);

  static ThemeData light() {
    final base = ThemeData(useMaterial3: true);
    return base.copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        background: cream,
        surface: Colors.white,
        primary: primary,
      ),
      scaffoldBackgroundColor: cream,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: ink,
        elevation: 0,
      ),
      cardTheme: const CardThemeData(
        color: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: primarySoft, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}

/// 🧩 Model dữ liệu prompt
class PromptItem {
  final String id;
  final String title;
  final String image;
  final String prompt;
  final List<String> tags;
  final String? category;

  PromptItem({
    required this.id,
    required this.title,
    required this.image,
    required this.prompt,
    required this.tags,
    this.category,
  });

  factory PromptItem.fromJson(Map<String, dynamic> j) => PromptItem(
    id: (j['id'] ?? '').toString(),
    title: (j['title'] ?? '').toString(),
    image: (j['image'] ?? '').toString(),
    prompt: (j['prompt'] ?? '').toString(),
    tags: ((j['tags'] ?? []) as List).map((e) => e.toString()).toList(),
    category: j['category']?.toString(),
  );
}

/// 🧩 Quản lý AppOpenAd hiển thị 1 lần/ngày
class AppOpenAdManager {
  static AppOpenAd? _appOpenAd;
  static bool _isShowingAd = false;
  static const adUnitId = 'ca-app-pub-4467146889101185/4787169345';
  static const _lastShownKey = 'last_app_open_ad_date';

  static Future<void> showAdIfAllowed() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now();
    final lastShown = prefs.getString(_lastShownKey);

    if (lastShown != null && lastShown == _formatDate(today)) {
      debugPrint("✅ AppOpenAd đã hiển thị hôm nay, bỏ qua.");
      return;
    }

    await _loadAd();

    if (_appOpenAd != null && !_isShowingAd) {
      _isShowingAd = true;
      _appOpenAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          _isShowingAd = false;
          ad.dispose();
          prefs.setString(_lastShownKey, _formatDate(today));
          _loadAd();
        },
      );
      _appOpenAd!.show();
    } else {
      debugPrint("⚠️ Không có AppOpenAd khả dụng.");
    }
  }

  static Future<void> _loadAd() async {
    await AppOpenAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) => _appOpenAd = ad,
        onAdFailedToLoad: (error) => _appOpenAd = null,
      ),
    );
  }

  static String _formatDate(DateTime date) =>
      "${date.year}-${date.month}-${date.day}";
}

/// 🖼️ Màn hình chính Wonder Kids Gallery
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _q = TextEditingController();
  final ScrollController _scroll = ScrollController();

  List<PromptItem> all = [];
  List<PromptItem> visible = [];
  String? updatedAt;
  bool loading = true;
  bool isLoadingMore = false;
  bool hasMore = true;
  String? error;
  final int batchSize = 30;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  // Ad fields
  NativeAd? _nativeAd;
  bool _isNativeAdLoaded = false;
  int _scrollCounter = 0;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeInOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut));
    _loadTrending();
    _scroll.addListener(_onScroll);
    _initAppOpenAd(); // ✅ hiển thị quảng cáo khi mở app
  }

  Future<void> _initAppOpenAd() async => AppOpenAdManager.showAdIfAllowed();

  @override
  void dispose() {
    _q.dispose();
    _scroll.dispose();
    _fadeCtrl.dispose();
    _nativeAd?.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
      _loadMore();
    }
    _scrollCounter++;
    if (_scrollCounter % 10 == 0) _loadNativeAd(); // ✅ sau mỗi 10 ảnh
  }

  void _loadNativeAd() {
    _nativeAd = NativeAd(
      adUnitId: 'ca-app-pub-4467146889101185/3987741929',
      factoryId: 'listTile',
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (ad) => setState(() => _isNativeAdLoaded = true),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _isNativeAdLoaded = false;
        },
      ),
    )..load();
  }

  Future<void> _loadTrending({bool bustCache = false}) async {
    setState(() {
      loading = true;
      error = null;
      all.clear();
      visible.clear();
      hasMore = true;
      _fadeCtrl.reset();
    });
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('prompts_cache');
    final cachedVersion = prefs.getString('prompts_version');
    final cachedUpdatedAt = prefs.getString('prompts_updatedAt');

    try {
      final ref = FirebaseStorage.instance.ref('prompts/prompts_trending.json');
      final url = await ref.getDownloadURL();
      final uri = Uri.parse('$url?t=${DateTime.now().millisecondsSinceEpoch}');
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final remoteData = jsonDecode(res.body);
        final remoteVersion = remoteData['updatedAt']?.toString();
        if (cached != null && !bustCache && cachedVersion == remoteVersion) {
          _parseData(jsonDecode(cached), cachedUpdatedAt);
        } else {
          _parseData(remoteData, remoteVersion);
          await prefs.setString('prompts_cache', res.body);
          await prefs.setString('prompts_version', remoteVersion ?? '');
          await prefs.setString('prompts_updatedAt', remoteVersion ?? '');
        }
      } else {
        throw Exception('HTTP ${res.statusCode}');
      }
    } catch (e) {
      if (cached != null) {
        _parseData(jsonDecode(cached), cachedUpdatedAt);
      } else {
        error = 'Không thể tải dữ liệu: $e';
      }
    }
    setState(() => loading = false);
    _fadeCtrl.forward();
  }

  void _parseData(Map<String, dynamic> data, String? version) {
    final items = ((data['items'] ?? []) as List)
        .map((e) => PromptItem.fromJson(e))
        .toList();
    items.sort((a, b) => b.id.compareTo(a.id));
    all = items;
    visible = all.take(batchSize).toList();
    hasMore = all.length > batchSize;
    updatedAt = version;
  }

  Future<void> _loadMore() async {
    if (isLoadingMore || !hasMore) return;
    setState(() => isLoadingMore = true);
    await Future.delayed(const Duration(milliseconds: 250));
    final nextCount = visible.length + batchSize;
    if (nextCount < all.length) {
      setState(() => visible = all.take(nextCount).toList());
    } else {
      setState(() {
        visible = all;
        hasMore = false;
      });
    }
    setState(() => isLoadingMore = false);
  }

  void _applyFilters() {
    final q = _q.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() {
        visible = all.take(batchSize).toList();
        hasMore = all.length > batchSize;
      });
      return;
    }
    final results = all
        .where((it) => (it.title + ' ' + it.prompt).toLowerCase().contains(q))
        .toList();
    setState(() {
      visible = results.take(batchSize).toList();
      hasMore = results.length > batchSize;
    });
  }

  Future<void> _onRefresh() async => _loadTrending(bustCache: true);

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.light(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Khám phá ảnh'),
          actions: [
            IconButton(
              tooltip: 'Làm mới',
              onPressed: () => _loadTrending(bustCache: true),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : (error != null)
            ? Center(child: Text(error!))
            : RefreshIndicator(
                onRefresh: _onRefresh,
                color: AppTheme.primary,
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  children: [
                    TextField(
                      controller: _q,
                      onChanged: (_) => _applyFilters(),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded),
                        hintText: 'Tìm theo từ khoá / prompt...',
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (updatedAt != null)
                      FadeTransition(
                        opacity: _fadeAnim,
                        child: SlideTransition(
                          position: _slideAnim,
                          child: Shimmer.fromColors(
                            baseColor: AppTheme.inkSoft.withOpacity(0.4),
                            highlightColor: AppTheme.primarySoft.withOpacity(
                              0.6,
                            ),
                            period: const Duration(seconds: 3),
                            child: Center(
                              child: Text(
                                "🕓 Dữ liệu cập nhật: ${_formatDate(updatedAt!)}",
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.inkSoft,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: visible.isEmpty
                          ? const _EmptyState()
                          : _GalleryGrid(items: visible, rootContext: context),
                    ),
                    if (_isNativeAdLoaded)
                      Container(
                        margin: const EdgeInsets.all(12),
                        height: 100,
                        decoration: BoxDecoration(
                          color: Colors.purple[50],
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: AdWidget(ad: _nativeAd!),
                      ),
                    if (isLoadingMore)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    if (!hasMore && visible.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: Text('🎉 Hết prompt rồi nhé!')),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  String _formatDate(String raw) {
    try {
      final dt = DateTime.parse(raw);
      return "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}";
    } catch (_) {
      return raw;
    }
  }
}

/// 🧩 Lưới ảnh
class _GalleryGrid extends StatelessWidget {
  final List<PromptItem> items;
  final BuildContext rootContext;

  const _GalleryGrid({required this.items, required this.rootContext});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: .9,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) =>
          _GalleryCard(item: items[i], rootContext: rootContext),
    );
  }
}

/// 🖼️ Card ảnh với hiệu ứng + popup chi tiết
class _GalleryCard extends StatefulWidget {
  final PromptItem item;
  final BuildContext rootContext;

  const _GalleryCard({required this.item, required this.rootContext});

  @override
  State<_GalleryCard> createState() => _GalleryCardState();
}

class _GalleryCardState extends State<_GalleryCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;
  bool _hovering = false;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut);
    _scaleAnim = Tween<double>(
      begin: 0.95,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutBack));
    Future.delayed(
      Duration(milliseconds: 100 + (50 * (widget.item.id.hashCode % 5))),
      () => _animCtrl.forward(),
    );
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: () => _showDetail(context),
        onLongPressStart: (_) => setState(() => _hovering = true),
        onLongPressEnd: (_) => setState(() => _hovering = false),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: _hovering ? 0.95 : 1,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 200),
            scale: _hovering ? 1.03 : 1.0,
            child: FadeTransition(
              opacity: _fadeAnim,
              child: ScaleTransition(
                scale: _scaleAnim,
                child: Card(
                  elevation: _hovering ? 8 : 0,
                  shadowColor: _hovering
                      ? AppTheme.primarySoft.withOpacity(0.4)
                      : null,
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      Expanded(
                        child: FutureBuilder<String>(
                          future: _resolveImage(widget.item.image),
                          builder: (context, snap) {
                            if (!snap.hasData) {
                              return Container(
                                color: AppTheme.cream,
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              );
                            }
                            return CachedNetworkImage(
                              imageUrl: snap.data!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                              fadeInDuration: const Duration(milliseconds: 300),
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          widget.item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 🪩 Popup chi tiết ảnh + prompt
  void _showDetail(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Đóng',
      barrierColor: Colors.black45,
      pageBuilder: (_, __, ___) => GestureDetector(
        onVerticalDragUpdate: (details) {
          if (details.primaryDelta != null && details.primaryDelta! > 12) {
            Navigator.of(context).pop();
          }
        },
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxHeight = constraints.maxHeight * 0.8;
                return Dialog(
                  insetPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 24,
                  ),
                  backgroundColor: Colors.white.withOpacity(0.92),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxHeight),
                    child: FutureBuilder<String>(
                      future: _resolveImage(widget.item.image),
                      builder: (context, snap) {
                        return Column(
                          children: [
                            // Ảnh trên cùng
                            Stack(
                              children: [
                                if (snap.hasData)
                                  ClipRRect(
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(24),
                                    ),
                                    child: CachedNetworkImage(
                                      imageUrl: snap.data!,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      height: maxHeight * 0.4,
                                    ),
                                  )
                                else
                                  SizedBox(
                                    height: maxHeight * 0.4,
                                    child: const Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                Positioned(
                                  right: 8,
                                  top: 8,
                                  child: IconButton(
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      color: Colors.white,
                                      size: 28,
                                    ),
                                    onPressed: () => Navigator.pop(context),
                                  ),
                                ),
                              ],
                            ),

                            // Tiêu đề + prompt có cuộn
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.item.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                        color: AppTheme.ink,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Expanded(
                                      child: SingleChildScrollView(
                                        child: SelectableText(
                                          widget.item.prompt,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            color: AppTheme.inkSoft,
                                            height: 1.4,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // Nút cố định dưới cùng
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.95),
                                borderRadius: const BorderRadius.vertical(
                                  bottom: Radius.circular(24),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.inkSoft.withOpacity(0.1),
                                    offset: const Offset(0, -1),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.primary,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    onPressed: () {
                                      Clipboard.setData(
                                        ClipboardData(text: widget.item.prompt),
                                      );
                                      ScaffoldMessenger.of(
                                        widget.rootContext,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            '✅ Đã copy prompt vào clipboard!',
                                          ),
                                          behavior: SnackBarBehavior.floating,
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.copy,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                    label: const Text(
                                      'Copy Prompt',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.primarySoft,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    onPressed: () {
                                      final text =
                                          '${widget.item.title}\n\n${widget.item.prompt}';
                                      Share.share(text);
                                    },
                                    icon: const Icon(
                                      Icons.share,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                    label: const Text(
                                      'Chia sẻ',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
      transitionBuilder: (_, anim, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeInOut),
        child: ScaleTransition(
          scale: Tween<double>(
            begin: 0.95,
            end: 1.0,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
          child: child,
        ),
      ),
      transitionDuration: const Duration(milliseconds: 300),
    );
  }
}

/// 🧱 Trạng thái trống
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(
            Icons.insert_emoticon_outlined,
            size: 40,
            color: AppTheme.inkSoft,
          ),
          SizedBox(height: 12),
          Text(
            'Không tìm thấy prompt nào phù hợp',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 6),
          Text('Hãy thử từ khoá khác nhé.'),
        ],
      ),
    );
  }
}

/// 🔗 Lấy ảnh từ Firebase
Future<String> _resolveImage(String path) async {
  if (path.startsWith('http')) return path;
  final ref = FirebaseStorage.instance.ref(path);
  return ref.getDownloadURL();
}
