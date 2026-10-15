import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

const _appName = 'FlowTV';
const _androidPip = MethodChannel('flowtv/pip');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      // Keep the first launch inside a typical 1366×768 laptop screen.
      size: Size(1050, 680),
      minimumSize: Size(760, 520),
      center: true,
      title: 'FlowTV',
      backgroundColor: Colors.black,
      titleBarStyle: TitleBarStyle.normal,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  final appState = await FlowState.create();
  runApp(FlowTVApp(state: appState));
}

class TvChannel {
  const TvChannel({
    required this.name,
    required this.url,
    this.logo = '',
    this.group = 'Other',
    this.tvgId = '',
    this.tvgName = '',
  });

  final String name;
  final String url;
  final String logo;
  final String group;
  final String tvgId;
  final String tvgName;

  String get id => url;

  Map<String, dynamic> toJson() => {
        'name': name,
        'url': url,
        'logo': logo,
        'group': group,
        'tvgId': tvgId,
        'tvgName': tvgName,
      };

  factory TvChannel.fromJson(Map<String, dynamic> json) => TvChannel(
        name: (json['name'] ?? 'Unnamed channel').toString(),
        url: (json['url'] ?? '').toString(),
        logo: (json['logo'] ?? '').toString(),
        group: (json['group'] ?? 'Other').toString(),
        tvgId: (json['tvgId'] ?? '').toString(),
        tvgName: (json['tvgName'] ?? '').toString(),
      );
}

class FlowState extends ChangeNotifier {
  FlowState._(this.prefs);
  final SharedPreferences prefs;
  List<TvChannel> channels = [];
  final Set<String> favorites = {};
  final List<String> recentIds = [];
  String lastPlaylistUrl = '';
  int selectedTab = 0;
  int themeIndex = 0; // neon, light, purple
  int accentIndex = 0;
  bool glass = true;
  bool animations = true;
  bool dataSaver = false;
  bool autoReconnect = true;
  bool showDataEstimate = true;
  String quality = 'auto'; // auto / saver / balanced / best / manual
  String bufferMode = 'balanced'; // low / balanced / stable
  bool proxyEnabled = false;
  String proxyUrl = 'http://127.0.0.1:10809';
  String lastError = '';
  bool loadingPlaylist = false;
  String loadingLabel = '';

  static const accentOptions = <Color>[
    Color(0xFF35C7FF),
    Color(0xFF9B5CFF),
    Color(0xFFFF4FA1),
    Color(0xFF39D98A),
    Color(0xFFFFB84D),
    Color(0xFFFC5D6D),
  ];

  Color get accent => accentOptions[accentIndex.clamp(0, accentOptions.length - 1).toInt()];
  bool get lightMode => themeIndex == 1;
  bool get purpleMode => themeIndex == 2;

  static Future<FlowState> create() async {
    final prefs = await SharedPreferences.getInstance();
    final state = FlowState._(prefs);
    await state._load();
    return state;
  }

  Future<void> _load() async {
    themeIndex = prefs.getInt('themeIndex') ?? 0;
    accentIndex = prefs.getInt('accentIndex') ?? 0;
    glass = prefs.getBool('glass') ?? true;
    animations = prefs.getBool('animations') ?? true;
    dataSaver = prefs.getBool('dataSaver') ?? false;
    autoReconnect = prefs.getBool('autoReconnect') ?? true;
    showDataEstimate = prefs.getBool('showDataEstimate') ?? true;
    quality = prefs.getString('quality') ?? 'auto';
    bufferMode = prefs.getString('bufferMode') ?? 'balanced';
    proxyEnabled = prefs.getBool('proxyEnabled') ?? false;
    proxyUrl = prefs.getString('proxyUrl') ?? 'http://127.0.0.1:10809';
    lastPlaylistUrl = prefs.getString('lastPlaylistUrl') ?? '';
    favorites.addAll(prefs.getStringList('favorites') ?? const []);
    recentIds.addAll(prefs.getStringList('recentIds') ?? const []);
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}flowtv_channels.json');
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString()) as List<dynamic>;
        channels = decoded
            .whereType<Map<String, dynamic>>()
            .map(TvChannel.fromJson)
            .where((channel) => channel.url.isNotEmpty)
            .toList();
      }
    } catch (_) {
      channels = [];
    }
  }

  Future<void> _saveChannels() async {
    try {
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      final file = File('${dir.path}${Platform.pathSeparator}flowtv_channels.json');
      await file.writeAsString(jsonEncode(channels.map((c) => c.toJson()).toList()));
    } catch (e) {
      lastError = 'Could not save the channel library: $e';
    }
  }

  Future<void> _set(String key, Object value) async {
    switch (value) {
      case bool v:
        await prefs.setBool(key, v);
        return;
      case int v:
        await prefs.setInt(key, v);
        return;
      case String v:
        await prefs.setString(key, v);
        return;
      case List<String> v:
        await prefs.setStringList(key, v);
        return;
    }
  }

  Future<void> setTheme(int value) async {
    themeIndex = value;
    await _set('themeIndex', value);
    notifyListeners();
  }

  Future<void> setAccent(int value) async {
    accentIndex = value;
    await _set('accentIndex', value);
    notifyListeners();
  }

  Future<void> setGlass(bool value) async {
    glass = value;
    await _set('glass', value);
    notifyListeners();
  }

  Future<void> setAnimations(bool value) async {
    animations = value;
    await _set('animations', value);
    notifyListeners();
  }

  Future<void> setDataSaver(bool value) async {
    dataSaver = value;
    if (value && quality == 'auto') quality = 'saver';
    await _set('dataSaver', value);
    await _set('quality', quality);
    notifyListeners();
  }

  Future<void> setQuality(String value) async {
    quality = value;
    await _set('quality', value);
    notifyListeners();
  }

  Future<void> setBufferMode(String value) async {
    bufferMode = value;
    await _set('bufferMode', value);
    notifyListeners();
  }

  Future<void> setProxyEnabled(bool value) async {
    proxyEnabled = value;
    await _set('proxyEnabled', value);
    notifyListeners();
  }

  Future<void> setProxyUrl(String value) async {
    proxyUrl = value.trim();
    await _set('proxyUrl', proxyUrl);
    notifyListeners();
  }

  Future<void> setToggle(String key, bool value) async {
    switch (key) {
      case 'autoReconnect':
        autoReconnect = value;
        break;
      case 'showDataEstimate':
        showDataEstimate = value;
        break;
    }
    await _set(key, value);
    notifyListeners();
  }

  void goTab(int tab) {
    selectedTab = tab;
    notifyListeners();
  }

  void addRecent(TvChannel channel) {
    recentIds.remove(channel.id);
    recentIds.insert(0, channel.id);
    if (recentIds.length > 30) recentIds.removeLast();
    unawaited(_set('recentIds', recentIds));
    notifyListeners();
  }

  Future<void> toggleFavorite(TvChannel channel) async {
    if (!favorites.add(channel.id)) favorites.remove(channel.id);
    await _set('favorites', favorites.toList());
    notifyListeners();
  }

  TvChannel? byId(String id) {
    for (final channel in channels) {
      if (channel.id == id) return channel;
    }
    return null;
  }

  List<TvChannel> get favoritesList => channels.where((c) => favorites.contains(c.id)).toList();
  List<TvChannel> get recentList => recentIds.map(byId).whereType<TvChannel>().toList();

  Future<int> loadPlaylistUrl(String rawUrl, {bool replace = false}) async {
    final url = rawUrl.trim();
    final uri = Uri.tryParse(url);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme) || uri.host.isEmpty) {
      throw const FormatException('Enter a valid http:// or https:// playlist URL.');
    }
    loadingPlaylist = true;
    loadingLabel = url;
    lastError = '';
    notifyListeners();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 18);
    try {
      if (proxyEnabled) {
        final proxy = Uri.tryParse(proxyUrl.trim());
        if (proxy == null || proxy.host.isEmpty || !{'http', 'https'}.contains(proxy.scheme)) {
          throw const FormatException('Proxy must be an HTTP/HTTPS proxy URL, e.g. http://127.0.0.1:10809');
        }
        client.findProxy = (_) => 'PROXY ${proxy.host}:${proxy.port == 0 ? 80 : proxy.port}';
      }
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 25));
      request.headers.set(HttpHeaders.userAgentHeader, 'FlowTV/1.0 (+playlist importer)');
      final response = await request.close().timeout(const Duration(seconds: 35));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Playlist server returned HTTP ${response.statusCode}.');
      }
      final body = await utf8.decoder.bind(response).join().timeout(const Duration(seconds: 75));
      if (body.length > 70 * 1024 * 1024) throw const FormatException('Playlist is too large (70 MB limit). Use a category playlist instead of a full index.');
      final parsed = await compute(parseM3u, body);
      if (parsed.isEmpty) throw const FormatException('No usable channel URLs were found in this playlist.');
      if (replace) {
        channels = parsed;
      } else {
        final seen = channels.map((c) => c.url).toSet();
        channels.addAll(parsed.where((c) => seen.add(c.url)));
      }
      lastPlaylistUrl = url;
      await _set('lastPlaylistUrl', url);
      await _saveChannels();
      lastError = '';
      notifyListeners();
      return parsed.length;
    } catch (e) {
      lastError = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      rethrow;
    } finally {
      client.close(force: true);
      loadingPlaylist = false;
      loadingLabel = '';
      notifyListeners();
    }
  }

  Future<int> importPlaylistFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['m3u', 'm3u8', 'txt'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return 0;
    final picked = result.files.single;
    final bytes = picked.bytes ?? (picked.path != null ? await File(picked.path!).readAsBytes() : null);
    if (bytes == null) throw const FormatException('Could not read the selected file.');
    final parsed = await compute(parseM3u, utf8.decode(bytes, allowMalformed: true));
    if (parsed.isEmpty) throw const FormatException('No usable channel URLs were found in the file.');
    final seen = channels.map((c) => c.url).toSet();
    channels.addAll(parsed.where((c) => seen.add(c.url)));
    await _saveChannels();
    notifyListeners();
    return parsed.length;
  }

  Future<void> clearLibrary() async {
    channels.clear();
    favorites.clear();
    recentIds.clear();
    await prefs.remove('favorites');
    await prefs.remove('recentIds');
    await _saveChannels();
    notifyListeners();
  }
}

List<TvChannel> parseM3u(String text) {
  final channels = <TvChannel>[];
  final lines = const LineSplitter().convert(text.replaceAll('\uFEFF', ''));
  String name = '';
  String logo = '';
  String group = 'Other';
  String tvgId = '';
  String tvgName = '';
  final seen = <String>{};
  final attrsRegex = RegExp(r'''([\w-]+)="([^"]*)"''');
  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#EXTINF')) {
      final comma = line.indexOf(',');
      final attrPart = comma > 0 ? line.substring(0, comma) : line;
      final display = comma > 0 ? line.substring(comma + 1).trim() : '';
      final attrs = <String, String>{};
      for (final match in attrsRegex.allMatches(attrPart)) {
        attrs[match.group(1)!.toLowerCase()] = match.group(2)!;
      }
      name = display.isNotEmpty ? display : (attrs['tvg-name'] ?? attrs['tvg-id'] ?? 'Unnamed channel');
      logo = attrs['tvg-logo'] ?? '';
      group = attrs['group-title']?.trim().isNotEmpty == true ? attrs['group-title']!.trim() : 'Other';
      tvgId = attrs['tvg-id'] ?? '';
      tvgName = attrs['tvg-name'] ?? '';
      continue;
    }
    if (line.startsWith('#EXTGRP:')) {
      group = line.substring(8).trim();
      continue;
    }
    if (line.startsWith('#')) continue;
    final uri = Uri.tryParse(line);
    if (uri == null || !{'http', 'https', 'rtsp', 'rtmp', 'udp', 'mms'}.contains(uri.scheme)) continue;
    if (!seen.add(line)) {
      continue;
    }
    channels.add(TvChannel(
      name: name.isNotEmpty ? name : uri.host,
      url: line,
      logo: logo,
      group: group.isEmpty ? 'Other' : group,
      tvgId: tvgId,
      tvgName: tvgName,
    ));
    name = '';
    logo = '';
    group = 'Other';
    tvgId = '';
    tvgName = '';
  }
  return channels;
}

class FlowTVApp extends StatelessWidget {
  const FlowTVApp({super.key, required this.state});
  final FlowState state;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: state,
        builder: (context, _) {
          final base = state.accent;
          final brightness = state.lightMode ? Brightness.light : Brightness.dark;
          final scheme = ColorScheme.fromSeed(seedColor: base, brightness: brightness).copyWith(
            primary: base,
            secondary: state.purpleMode ? const Color(0xFFB17BFF) : const Color(0xFF8D71FF),
            surface: state.lightMode ? const Color(0xFFF5F6FC) : const Color(0xFF10162A),
          );
          return MaterialApp(
            title: _appName,
            debugShowCheckedModeBanner: false,
            themeMode: state.lightMode ? ThemeMode.light : ThemeMode.dark,
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: scheme,
              brightness: Brightness.light,
              scaffoldBackgroundColor: const Color(0xFFF5F6FC),
              appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, surfaceTintColor: Colors.transparent),
              snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: scheme.inverseSurface),
              filledButtonTheme: FilledButtonThemeData(
                style: ButtonStyle(
                  animationDuration: Duration(milliseconds: state.animations ? 180 : 0),
                  mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                  overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
                    if (states.contains(WidgetState.pressed)) return base.withValues(alpha: .22);
                    if (states.contains(WidgetState.hovered)) return base.withValues(alpha: .12);
                    return null;
                  }),
                ),
              ),
              textButtonTheme: TextButtonThemeData(
                style: ButtonStyle(
                  animationDuration: Duration(milliseconds: state.animations ? 180 : 0),
                  mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                  overlayColor: WidgetStateProperty.resolveWith<Color?>((states) =>
                    states.contains(WidgetState.hovered) ? base.withValues(alpha: .12) : null),
                ),
              ),
              iconButtonTheme: IconButtonThemeData(
                style: ButtonStyle(
                  animationDuration: Duration(milliseconds: state.animations ? 180 : 0),
                  mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                  overlayColor: WidgetStateProperty.resolveWith<Color?>((states) =>
                    states.contains(WidgetState.hovered) ? base.withValues(alpha: .16) : null),
                ),
              ),
              navigationBarTheme: NavigationBarThemeData(
                backgroundColor: const Color(0xFFF9FAFF),
                indicatorColor: base.withValues(alpha: .17),
                labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
              ),
              cardTheme: CardThemeData(color: Colors.white.withValues(alpha: .78), elevation: 0),
            ),
            darkTheme: ThemeData(
              useMaterial3: true,
              colorScheme: scheme,
              brightness: Brightness.dark,
              scaffoldBackgroundColor: const Color(0xFF070B18),
              appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, surfaceTintColor: Colors.transparent),
              snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: scheme.surfaceContainerHighest),
              filledButtonTheme: FilledButtonThemeData(
                style: ButtonStyle(
                  animationDuration: Duration(milliseconds: state.animations ? 180 : 0),
                  mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                  overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
                    if (states.contains(WidgetState.pressed)) return base.withValues(alpha: .22);
                    if (states.contains(WidgetState.hovered)) return base.withValues(alpha: .12);
                    return null;
                  }),
                ),
              ),
              textButtonTheme: TextButtonThemeData(
                style: ButtonStyle(
                  animationDuration: Duration(milliseconds: state.animations ? 180 : 0),
                  mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                  overlayColor: WidgetStateProperty.resolveWith<Color?>((states) =>
                    states.contains(WidgetState.hovered) ? base.withValues(alpha: .12) : null),
                ),
              ),
              iconButtonTheme: IconButtonThemeData(
                style: ButtonStyle(
                  animationDuration: Duration(milliseconds: state.animations ? 180 : 0),
                  mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
                  overlayColor: WidgetStateProperty.resolveWith<Color?>((states) =>
                    states.contains(WidgetState.hovered) ? base.withValues(alpha: .16) : null),
                ),
              ),
              navigationBarTheme: NavigationBarThemeData(
                backgroundColor: const Color(0xEE080D1D),
                indicatorColor: base.withValues(alpha: .20),
                labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
              ),
              cardTheme: CardThemeData(color: const Color(0xAA111A31), elevation: 0),
            ),
            home: MainShell(state: state),
          );
        },
      );
}

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.state});
  final FlowState state;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final isLight = state.lightMode;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isLight
              ? [const Color(0xFFF4F6FF), const Color(0xFFE9EEFF), const Color(0xFFF8F7FF)]
              : state.purpleMode
                  ? [const Color(0xFF100A25), const Color(0xFF090F23), const Color(0xFF110D2D)]
                  : [const Color(0xFF080D1D), const Color(0xFF0A1530), const Color(0xFF100C28)],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: LayoutBuilder(builder: (context, constraints) {
            final pages = <Widget>[
              HomePage(state: state, onBrowse: () => setState(() => state.goTab(1))),
              BrowsePage(state: state),
              FavoritesPage(state: state),
              SettingsPage(state: state),
            ];
            if (constraints.maxWidth >= 900) {
              return Row(children: [
                Container(
                  width: 230,
                  margin: const EdgeInsets.fromLTRB(12, 12, 5, 16),
                  child: GlassCard(radius: 24, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16), child: Column(children: [
                    const Padding(padding: EdgeInsets.fromLTRB(7, 3, 7, 15), child: FlowLogo(size: 34, withWord: true)),
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    Expanded(child: NavigationRail(
                      backgroundColor: Colors.transparent,
                      extended: true,
                      minWidth: 72,
                      minExtendedWidth: 204,
                      selectedIndex: state.selectedTab,
                      onDestinationSelected: (i) => setState(() => state.goTab(i)),
                      destinations: const [
                        NavigationRailDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: Text('Home')),
                        NavigationRailDestination(icon: Icon(Icons.grid_view_rounded), selectedIcon: Icon(Icons.grid_view_rounded), label: Text('Browse')),
                        NavigationRailDestination(icon: Icon(Icons.favorite_border_rounded), selectedIcon: Icon(Icons.favorite_rounded), label: Text('Favorites')),
                        NavigationRailDestination(icon: Icon(Icons.tune_rounded), selectedIcon: Icon(Icons.tune_rounded), label: Text('Settings')),
                      ],
                    )),
                    const Divider(height: 1),
                    Padding(padding: const EdgeInsets.all(8), child: Text('STREAM SMARTER  •  1.0', textAlign: TextAlign.center, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: .5, color: state.accent))),
                  ])),
                ),
                Expanded(child: IndexedStack(index: state.selectedTab, children: pages)),
              ]);
            }
            return IndexedStack(index: state.selectedTab, children: pages);
          }),
        ),
        bottomNavigationBar: MediaQuery.sizeOf(context).width < 900
            ? NavigationBar(
                selectedIndex: state.selectedTab,
                onDestinationSelected: (i) => setState(() => state.goTab(i)),
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
                  NavigationDestination(icon: Icon(Icons.grid_view_rounded), selectedIcon: Icon(Icons.grid_view_rounded), label: 'Browse'),
                  NavigationDestination(icon: Icon(Icons.favorite_border_rounded), selectedIcon: Icon(Icons.favorite_rounded), label: 'Favorites'),
                  NavigationDestination(icon: Icon(Icons.tune_rounded), selectedIcon: Icon(Icons.tune_rounded), label: 'Settings'),
                ],
              )
            : null,
      ),
    );
  }
}

class AppHeader extends StatelessWidget {
  const AppHeader({super.key, required this.title, this.subtitle, this.leading, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget>? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 16, 16),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 10)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -.5)),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(subtitle!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .62))),
                ],
              ]),
            ),
            ...(trailing ?? const []),
          ],
        ),
      );
}

class FlowLogo extends StatelessWidget {
  const FlowLogo({super.key, this.size = 40, this.withWord = false});
  final double size;
  final bool withWord;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(size * .25),
          child: Image.asset('assets/icon/flowtv_icon.png', width: size, height: size, fit: BoxFit.cover),
        ),
        if (withWord) ...[
          const SizedBox(width: 9),
          Text('FlowTV', style: TextStyle(fontWeight: FontWeight.w900, fontSize: size * .50, letterSpacing: -.5)),
        ],
      ]);
}

class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.radius = 22, this.onTap, this.borderColor});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final state = context.findAncestorWidgetOfExactType<MainShell>()?.state;
    final light = Theme.of(context).brightness == Brightness.light;
    final surface = light ? Colors.white.withValues(alpha: .66) : const Color(0xFF101A32).withValues(alpha: state?.glass == true ? .67 : .95);
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: state?.glass == true ? 16 : 0, sigmaY: state?.glass == true ? 16 : 0),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: borderColor ?? (light ? Colors.white.withValues(alpha: .86) : Colors.white.withValues(alpha: .09))),
            boxShadow: light ? [BoxShadow(color: Colors.black.withValues(alpha: .04), blurRadius: 24, offset: const Offset(0, 8))] : [],
          ),
          child: child,
        ),
      ),
    );
    if (onTap == null) return card;
    return Material(color: Colors.transparent, child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(radius), child: card));
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.actionLabel, this.onAction});
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 12),
        child: Row(children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700))),
        ]),
      );
}

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.state, required this.onBrowse});
  final FlowState state;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    final recent = state.recentList.take(6).toList();
    final favorites = state.favoritesList.take(8).toList();
    final channels = state.channels.reversed.take(12).toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        AppHeader(
          title: 'Your world. Your channels.',
          subtitle: '${state.channels.length} channels in your library',
          leading: const FlowLogo(size: 42),
          trailing: [
            IconButton(tooltip: 'Browse channels', onPressed: onBrowse, icon: const Icon(Icons.search_rounded)),
            IconButton(tooltip: 'Add playlist', onPressed: () => showPlaylistDialog(context, state), icon: const Icon(Icons.add_link_rounded)),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: GlassCard(
            radius: 28,
            padding: const EdgeInsets.all(21),
            child: Stack(children: [
              Positioned(right: -30, top: -45, child: Container(width: 160, height: 160, decoration: BoxDecoration(shape: BoxShape.circle, color: state.accent.withValues(alpha: .16)))),
              Positioned(right: 38, top: 7, child: Icon(Icons.play_circle_filled_rounded, size: 96, color: state.accent.withValues(alpha: .18))),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: state.accent.withValues(alpha: .15), borderRadius: BorderRadius.circular(30)), child: Text('STREAM SMARTER', style: TextStyle(color: state.accent, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2))),
                const SizedBox(height: 15),
                Text('TV, your way.', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, height: 1.05)),
                const SizedBox(height: 8),
                ConstrainedBox(constraints: const BoxConstraints(maxWidth: 255), child: Text('Keep watching when your connection gets rough. Pick your own quality, buffer and data profile.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .7)))),
                const SizedBox(height: 18),
                FilledButton.icon(onPressed: state.channels.isEmpty ? () => showPlaylistDialog(context, state) : onBrowse, icon: Icon(state.channels.isEmpty ? Icons.add_rounded : Icons.live_tv_rounded), label: Text(state.channels.isEmpty ? 'Add your first playlist' : 'Explore channels')),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(children: [
            Expanded(child: _MiniStat(icon: Icons.live_tv_rounded, label: 'Channels', value: '${state.channels.length}', accent: state.accent)),
            const SizedBox(width: 10),
            Expanded(child: _MiniStat(icon: Icons.favorite_rounded, label: 'Favorites', value: '${state.favorites.length}', accent: const Color(0xFFFF5B9C))),
            const SizedBox(width: 10),
            Expanded(child: _MiniStat(icon: Icons.history_rounded, label: 'Recent', value: '${state.recentList.length}', accent: const Color(0xFF9F86FF))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: SectionHeader('Jump right in', actionLabel: 'All channels', onAction: onBrowse),
        ),
        SizedBox(
          height: 104,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            scrollDirection: Axis.horizontal,
            children: [
              _CategoryCard(label: 'Live TV', icon: Icons.live_tv_rounded, colors: const [Color(0xFF0F7AF5), Color(0xFF6C54F5)], onTap: onBrowse),
              _CategoryCard(label: 'Sports', icon: Icons.sports_cricket_rounded, colors: const [Color(0xFF12B886), Color(0xFF007F87)], onTap: () => state.loadPlaylistUrl('https://iptv-org.github.io/iptv/categories/sports.m3u').then((n) => _snack(context, 'Added $n sports entries')).catchError((e) => _snack(context, 'Could not load playlist: $e'))),
              _CategoryCard(label: 'Movies', icon: Icons.movie_creation_outlined, colors: const [Color(0xFFAE42E8), Color(0xFF5738E6)], onTap: () => state.loadPlaylistUrl('https://iptv-org.github.io/iptv/categories/movies.m3u').then((n) => _snack(context, 'Added $n movie entries')).catchError((e) => _snack(context, 'Could not load playlist: $e'))),
              _CategoryCard(label: 'Sri Lanka', icon: Icons.public_rounded, colors: const [Color(0xFFFF8D39), Color(0xFFDC4567)], onTap: () => state.loadPlaylistUrl('https://iptv-org.github.io/iptv/countries/lk.m3u').then((n) => _snack(context, 'Added $n Sri Lankan entries')).catchError((e) => _snack(context, 'Could not load playlist: $e'))),
            ],
          ),
        ),
        if (recent.isNotEmpty) ...[
          Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: SectionHeader('Pick up where you left off', actionLabel: 'See all', onAction: onBrowse)),
          SizedBox(height: 135, child: ListView.separated(padding: const EdgeInsets.symmetric(horizontal: 18), scrollDirection: Axis.horizontal, itemCount: recent.length, separatorBuilder: (_, __) => const SizedBox(width: 12), itemBuilder: (context, i) => ChannelPoster(channel: recent[i], state: state, compact: true))),
        ],
        if (favorites.isNotEmpty) ...[
          Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: SectionHeader('Your favorites', actionLabel: 'View all', onAction: () => state.goTab(2))),
          SizedBox(height: 135, child: ListView.separated(padding: const EdgeInsets.symmetric(horizontal: 18), scrollDirection: Axis.horizontal, itemCount: favorites.length, separatorBuilder: (_, __) => const SizedBox(width: 12), itemBuilder: (context, i) => ChannelPoster(channel: favorites[i], state: state, compact: true))),
        ],
        Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: SectionHeader('Fresh from your library', actionLabel: 'Browse', onAction: onBrowse)),
        if (channels.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: EmptyCard(title: 'Your channel list is waiting', message: 'Import a playlist URL or an M3U/M3U8 file. FlowTV keeps your library on this device.', icon: Icons.playlist_add_rounded, buttonLabel: 'Import playlist', onPressed: () => showPlaylistDialog(context, state)))
        else
          ...channels.take(8).map((channel) => Padding(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4), child: ChannelRow(channel: channel, state: state))),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.icon, required this.label, required this.value, required this.accent});
  final IconData icon;
  final String label;
  final String value;
  final Color accent;
  @override
  Widget build(BuildContext context) => GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        radius: 18,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: accent, size: 19),
          const SizedBox(height: 9),
          Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .6))),
        ]),
      );
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.label, required this.icon, required this.colors, required this.onTap});
  final String label;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 11),
        child: _HoverScale(
          child: SizedBox(
            width: 124,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onTap,
              child: Ink(
                decoration: BoxDecoration(gradient: LinearGradient(colors: colors), borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: colors.first.withValues(alpha: .18), blurRadius: 16, offset: const Offset(0, 7))]),
                child: Padding(padding: const EdgeInsets.all(13), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Icon(icon, color: Colors.white, size: 27), Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))])),
              ),
            ),
          ),
        ),
      ),
      );
}

class _HoverScale extends StatefulWidget {
  const _HoverScale({required this.child});
  final Widget child;

  @override
  State<_HoverScale> createState() => _HoverScaleState();
}

class _HoverScaleState extends State<_HoverScale> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedScale(
          scale: _hovered ? 1.035 : 1,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          child: widget.child,
        ),
      );
}

class BrowsePage extends StatefulWidget {
  const BrowsePage({super.key, required this.state});
  final FlowState state;
  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  final _search = TextEditingController();
  String _category = 'All';
  String _sort = 'Playlist order';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final groups = state.channels.map((e) => e.group.trim()).where((g) => g.isNotEmpty).toSet().toList()..sort();
    final cats = ['All', ...groups.take(80)];
    final query = _search.text.toLowerCase().trim();
    final channelSource = _sort == 'Recently added' ? state.channels.reversed.toList() : state.channels;
    var visible = channelSource.where((channel) {
      final matchesCategory = _category == 'All' || channel.group == _category;
      final matchesSearch = query.isEmpty || channel.name.toLowerCase().contains(query) || channel.group.toLowerCase().contains(query) || channel.tvgId.toLowerCase().contains(query);
      return matchesCategory && matchesSearch;
    }).toList();
    if (_sort == 'A–Z') visible.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (_sort == 'Favorites first') visible.sort((a, b) => (state.favorites.contains(b.id) ? 1 : 0).compareTo(state.favorites.contains(a.id) ? 1 : 0));

    return Column(children: [
      AppHeader(title: 'Browse channels', subtitle: 'Find something worth watching', trailing: [IconButton(tooltip: 'Import playlist', onPressed: () => showPlaylistDialog(context, state), icon: const Icon(Icons.add_link_rounded))]),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Search channels, teams, movies…',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _search.text.isEmpty ? null : IconButton(onPressed: () { _search.clear(); setState(() {}); }, icon: const Icon(Icons.close_rounded)),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surface.withValues(alpha: .68),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
          ),
        ),
      ),
      const SizedBox(height: 13),
      SizedBox(height: 39, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 18), children: [
        for (final category in cats)
          Padding(padding: const EdgeInsets.only(right: 7), child: ChoiceChip(label: Text(category), selected: _category == category, onSelected: (_) => setState(() => _category = category))),
        ActionChip(avatar: const Icon(Icons.sports_cricket_rounded, size: 16), label: const Text('Add Sports'), onPressed: () => _addBuiltin(context, 'https://iptv-org.github.io/iptv/categories/sports.m3u')),
        ActionChip(avatar: const Icon(Icons.movie_outlined, size: 16), label: const Text('Add Movies'), onPressed: () => _addBuiltin(context, 'https://iptv-org.github.io/iptv/categories/movies.m3u')),
        ActionChip(avatar: const Icon(Icons.flag_outlined, size: 16), label: const Text('Add Sri Lanka'), onPressed: () => _addBuiltin(context, 'https://iptv-org.github.io/iptv/countries/lk.m3u')),
      ])),
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 11, 18, 7),
        child: Row(children: [Expanded(child: Text('${visible.length} channels', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .65)))), DropdownButton<String>(value: _sort, underline: const SizedBox.shrink(), items: const [DropdownMenuItem(value: 'Playlist order', child: Text('Playlist order')), DropdownMenuItem(value: 'Recently added', child: Text('Recently added')), DropdownMenuItem(value: 'A–Z', child: Text('A–Z')), DropdownMenuItem(value: 'Favorites first', child: Text('Favorites first'))], onChanged: (v) => setState(() => _sort = v ?? 'Playlist order'))]),
      ),
      if (state.loadingPlaylist) LinearProgressIndicator(valueColor: AlwaysStoppedAnimation(state.accent)),
      Expanded(
        child: visible.isEmpty
            ? EmptyCard(title: query.isNotEmpty ? 'No matches found' : 'No channels yet', message: query.isNotEmpty ? 'Try a shorter search or switch category.' : 'Load a public M3U playlist or import your own channel list.', icon: query.isNotEmpty ? Icons.search_off_rounded : Icons.playlist_add_rounded, buttonLabel: query.isNotEmpty ? 'Clear search' : 'Add playlist', onPressed: query.isNotEmpty ? () { _search.clear(); setState(() { _category = 'All'; }); } : () => showPlaylistDialog(context, state))
            : ListView.builder(padding: const EdgeInsets.fromLTRB(18, 0, 18, 28), itemCount: visible.length, itemBuilder: (context, i) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: ChannelRow(channel: visible[i], state: state))),
      ),
    ]);
  }

  Future<void> _addBuiltin(BuildContext context, String url) async {
    try {
      final count = await widget.state.loadPlaylistUrl(url);
      if (context.mounted) _snack(context, 'Loaded $count entries. Duplicate stream links were skipped.');
    } catch (e) {
      if (context.mounted) _snack(context, 'Could not load: $e');
    }
  }
}

class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key, required this.state});
  final FlowState state;
  @override
  Widget build(BuildContext context) {
    final items = state.favoritesList;
    return Column(children: [
      AppHeader(title: 'Favorites', subtitle: '${items.length} saved channels', trailing: [IconButton(tooltip: 'Add playlist', onPressed: () => showPlaylistDialog(context, state), icon: const Icon(Icons.add_link_rounded))]),
      Expanded(child: items.isEmpty
          ? EmptyCard(title: 'Your favorites live here', message: 'Tap the heart beside any channel to keep it close.', icon: Icons.favorite_border_rounded, buttonLabel: 'Browse channels', onPressed: () => state.goTab(1))
          : ListView.builder(padding: const EdgeInsets.fromLTRB(18, 0, 18, 28), itemCount: items.length, itemBuilder: (context, i) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: ChannelRow(channel: items[i], state: state)))),
    ]);
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.state});
  final FlowState state;

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.only(bottom: 35), children: [
        const AppHeader(title: 'Settings', subtitle: 'Tune FlowTV to your connection'),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: _SettingsSection(title: 'Appearance', icon: Icons.palette_outlined, children: [
          const _SettingCaption('Dashboard theme'),
          Wrap(spacing: 9, runSpacing: 9, children: [
            _ThemeChoice(title: 'Dark Neon', icon: Icons.dark_mode_rounded, selected: state.themeIndex == 0, onTap: () => state.setTheme(0), accent: state.accent),
            _ThemeChoice(title: 'Light', icon: Icons.light_mode_rounded, selected: state.themeIndex == 1, onTap: () => state.setTheme(1), accent: state.accent),
            _ThemeChoice(title: 'Purple Glass', icon: Icons.blur_on_rounded, selected: state.themeIndex == 2, onTap: () => state.setTheme(2), accent: state.accent),
          ]),
          const SizedBox(height: 16),
          const _SettingCaption('Accent color'),
          Row(
            children: List.generate(
              FlowState.accentOptions.length,
              (index) => Expanded(
                child: Center(
                  child: InkWell(
                    onTap: () => state.setAccent(index),
                    borderRadius: BorderRadius.circular(30),
                    child: AnimatedContainer(
                      duration: Duration(milliseconds: state.animations ? 180 : 0),
                      width: state.accentIndex == index ? 34 : 27,
                      height: state.accentIndex == index ? 34 : 27,
                      decoration: BoxDecoration(
                        color: FlowState.accentOptions[index],
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: state.accentIndex == index
                              ? Theme.of(context).colorScheme.onSurface
                              : Colors.transparent,
                          width: 2,
                        ),
                        boxShadow: state.accentIndex == index
                            ? [
                                BoxShadow(
                                  color: FlowState.accentOptions[index]
                                      .withValues(alpha: .38),
                                  blurRadius: 14,
                                ),
                              ]
                            : [],
                      ),
                      child: state.accentIndex == index
                          ? const Icon(
                              Icons.check_rounded,
                              size: 17,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _SwitchSetting(title: 'Blur glass panels', subtitle: 'Translucent cards and soft background blur', value: state.glass, onChanged: state.setGlass),
          _SwitchSetting(title: 'UI animations', subtitle: 'Animated transitions and selection feedback', value: state.animations, onChanged: state.setAnimations),
        ])),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: _SettingsSection(title: 'Playback & data', icon: Icons.speed_rounded, children: [
          _SelectSetting(title: 'Default playback profile', subtitle: 'Used whenever a channel is opened', value: state.quality, options: const {'auto': 'Smart Auto', 'saver': 'Extreme Data Saver', 'balanced': 'Balanced', 'best': 'Best Quality', 'manual': 'Manual / remember choice'}, onChanged: state.setQuality),
          _SelectSetting(title: 'Buffer strategy', subtitle: 'Higher buffering can add live delay', value: state.bufferMode, options: const {'low': 'Low latency', 'balanced': 'Balanced', 'stable': 'Maximum stability'}, onChanged: state.setBufferMode),
          _SwitchSetting(title: 'Data Saver', subtitle: 'Prefer the lowest HLS rendition when available', value: state.dataSaver, onChanged: state.setDataSaver),
          _SwitchSetting(title: 'Auto reconnect', subtitle: 'Retry a stalled stream and lower HLS bitrate after repeated buffering', value: state.autoReconnect, onChanged: (v) => state.setToggle('autoReconnect', v)),
          _SwitchSetting(title: 'Show estimated data usage', subtitle: 'Displays an estimate based on playback bitrate, not exact carrier billing', value: state.showDataEstimate, onChanged: (v) => state.setToggle('showDataEstimate', v)),
          const Padding(padding: EdgeInsets.only(top: 8), child: _NoticeLine(text: 'FlowTV cannot create a lower-bitrate source if a broadcaster only provides one quality. Local downscaling changes the display output, not the bytes already received.')),
        ])),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: _SettingsSection(title: 'Network & V2Ray proxy', icon: Icons.hub_outlined, children: [
          _SwitchSetting(title: 'Use proxy for playlist imports and playback', subtitle: 'Uses an HTTP proxy endpoint configured on this device', value: state.proxyEnabled, onChanged: state.setProxyEnabled),
          TextFormField(
            key: ValueKey('proxy-${state.proxyUrl}'),
            initialValue: state.proxyUrl,
            onFieldSubmitted: state.setProxyUrl,
            decoration: InputDecoration(labelText: 'HTTP proxy URL', hintText: 'http://127.0.0.1:10809', helperText: 'Use the local HTTP proxy port from your V2Ray client. A SOCKS-only port is not the same.', prefixIcon: const Icon(Icons.lan_outlined), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16))),
          ),
          const SizedBox(height: 7),
          Row(children: [Icon(Icons.info_outline_rounded, color: Theme.of(context).colorScheme.primary, size: 18), const SizedBox(width: 8), Expanded(child: Text('Proxy support depends on the stream protocol and V2Ray client. The proxy cannot bypass a channel provider’s access restrictions.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .65))))]),
        ])),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: _SettingsSection(title: 'Library & app', icon: Icons.settings_suggest_outlined, children: [
          _PlainSetting(icon: Icons.playlist_add_rounded, title: 'Import a playlist URL', subtitle: state.lastPlaylistUrl.isEmpty ? 'M3U / M3U8 over HTTP(S)' : state.lastPlaylistUrl, onTap: () => showPlaylistDialog(context, state)),
          _PlainSetting(icon: Icons.folder_open_rounded, title: 'Import an M3U file', subtitle: 'Choose a file from this device', onTap: () async { try { final n = await state.importPlaylistFile(); if (context.mounted && n > 0) _snack(context, 'Imported $n channels.'); } catch (e) { if (context.mounted) _snack(context, 'Import failed: $e'); } }),
          _PlainSetting(icon: Icons.delete_sweep_outlined, title: 'Clear channel library', subtitle: 'Removes imported channels, favorites and history from this device', onTap: () async { final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('Clear library?'), content: const Text('This removes all imported channel links, favorites and recent history from this device. It does not cancel any external subscription.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear library'))])); if (ok == true) { await state.clearLibrary(); if (context.mounted) _snack(context, 'Channel library cleared.'); } }),
          const Divider(height: 20),
          Row(children: [const FlowLogo(size: 42), const SizedBox(width: 12), const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('FlowTV', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)), Text('Version 1.0.1 • Android & Windows', style: TextStyle(fontSize: 12))])), Icon(Icons.verified_user_outlined, color: Theme.of(context).colorScheme.primary)]),
          const SizedBox(height: 8),
          const _NoticeLine(text: 'FlowTV is a player, not a broadcaster. Add streams you are authorized to access. Playlist links may be offline or region-restricted.'),
        ])),
      ]);
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.icon, required this.children});
  final String title;
  final IconData icon;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 14), child: GlassCard(radius: 24, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Container(width: 40, height: 40, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: .14), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: Theme.of(context).colorScheme.primary)), const SizedBox(width: 11), Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)))]),
        const SizedBox(height: 12),
        ...children,
      ])));
}

class _SettingCaption extends StatelessWidget {
  const _SettingCaption(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 10, top: 3), child: Text(text, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)));
}

class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({required this.title, required this.icon, required this.selected, required this.onTap, required this.accent});
  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;
  @override
  Widget build(BuildContext context) => ChoiceChip(avatar: Icon(icon, size: 17), label: Text(title), selected: selected, onSelected: (_) => onTap(), side: BorderSide(color: selected ? accent : Theme.of(context).dividerColor), selectedColor: accent.withValues(alpha: .16));
}

class _SwitchSetting extends StatelessWidget {
  const _SwitchSetting({required this.title, required this.subtitle, required this.value, required this.onChanged});
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.35)),
        value: value,
        onChanged: onChanged,
      );
}

class _SelectSetting extends StatelessWidget {
  const _SelectSetting({required this.title, required this.subtitle, required this.value, required this.options, required this.onChanged});
  final String title;
  final String subtitle;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 7), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 2),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .62))),
        const SizedBox(height: 7),
        DropdownButtonFormField<String>(
          value: options.containsKey(value) ? value : options.keys.first,
          decoration: InputDecoration(isDense: true, filled: true, fillColor: Theme.of(context).colorScheme.surface.withValues(alpha: .48), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)),
          items: options.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
        ),
        const SizedBox(height: 8),
      ]));
}

class _PlainSetting extends StatelessWidget {
  const _PlainSetting({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(contentPadding: EdgeInsets.zero, leading: Icon(icon, color: Theme.of(context).colorScheme.primary), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)), subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall), trailing: const Icon(Icons.chevron_right_rounded), onTap: onTap);
}

class _NoticeLine extends StatelessWidget {
  const _NoticeLine({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: .08), borderRadius: BorderRadius.circular(14)), child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4)));
}

class EmptyCard extends StatelessWidget {
  const EmptyCard({super.key, required this.title, required this.message, required this.icon, required this.buttonLabel, required this.onPressed});
  final String title;
  final String message;
  final IconData icon;
  final String buttonLabel;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Center(child: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(24), child: GlassCard(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 76, height: 76, decoration: BoxDecoration(shape: BoxShape.circle, color: Theme.of(context).colorScheme.primary.withValues(alpha: .12)), child: Icon(icon, size: 37, color: Theme.of(context).colorScheme.primary)),
        const SizedBox(height: 16),
        Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .65))),
        const SizedBox(height: 18),
        FilledButton.icon(onPressed: onPressed, icon: const Icon(Icons.arrow_forward_rounded), label: Text(buttonLabel)),
      ])))));
}

class ChannelRow extends StatelessWidget {
  const ChannelRow({super.key, required this.channel, required this.state});
  final TvChannel channel;
  final FlowState state;

  @override
  Widget build(BuildContext context) {
    final isFavorite = state.favorites.contains(channel.id);
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      radius: 18,
      onTap: () => openChannel(context, state, channel),
      child: Row(children: [
        ChannelLogo(channel: channel, size: 50, accent: state.accent),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(channel.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)), const SizedBox(height: 4), Text(channel.group, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .60))), const SizedBox(height: 4), Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.play_circle_outline_rounded, size: 14, color: state.accent), const SizedBox(width: 4), Text('Open stream', style: TextStyle(fontSize: 10, color: state.accent, fontWeight: FontWeight.w700))])])),
        IconButton(tooltip: isFavorite ? 'Remove favorite' : 'Add favorite', onPressed: () => state.toggleFavorite(channel), icon: Icon(isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: isFavorite ? const Color(0xFFFF5B9C) : Theme.of(context).colorScheme.onSurface.withValues(alpha: .6))),
        const Icon(Icons.chevron_right_rounded, size: 20),
      ]),
    );
  }
}

class ChannelPoster extends StatelessWidget {
  const ChannelPoster({super.key, required this.channel, required this.state, this.compact = false});
  final TvChannel channel;
  final FlowState state;
  final bool compact;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: compact ? 148 : 168,
        child: GlassCard(
          padding: const EdgeInsets.all(11),
          radius: 19,
          onTap: () => openChannel(context, state, channel),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Center(child: ChannelLogo(channel: channel, size: compact ? 52 : 64, accent: state.accent))),
            const SizedBox(height: 8),
            Text(channel.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
            const SizedBox(height: 2),
            Text(channel.group, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .58))),
          ]),
        ),
      );
}

class ChannelLogo extends StatelessWidget {
  const ChannelLogo({super.key, required this.channel, required this.size, required this.accent});
  final TvChannel channel;
  final double size;
  final Color accent;
  @override
  Widget build(BuildContext context) {
    final logoUri = Uri.tryParse(channel.logo);
    final valid = logoUri != null && {'http', 'https'}.contains(logoUri.scheme) && logoUri.host.isNotEmpty;
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(color: accent.withValues(alpha: .09), borderRadius: BorderRadius.circular(size * .24), border: Border.all(color: accent.withValues(alpha: .16))),
      child: valid
          ? ClipRRect(borderRadius: BorderRadius.circular(size * .16), child: Image.network(channel.logo, fit: BoxFit.contain, errorBuilder: (_, __, ___) => _fallback(), loadingBuilder: (context, child, progress) => progress == null ? child : _fallback()))
          : _fallback(),
    );
  }

  Widget _fallback() => Center(child: Text(channel.name.trim().isEmpty ? 'TV' : channel.name.trim().characters.first.toUpperCase(), style: TextStyle(fontWeight: FontWeight.w900, fontSize: size * .36, color: accent)));
}

Future<void> openChannel(BuildContext context, FlowState state, TvChannel channel) async {
  state.addRecent(channel);
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlayerPage(state: state, channel: channel), fullscreenDialog: true));
}

Future<void> showPlaylistDialog(BuildContext context, FlowState state) async {
  final field = TextEditingController(text: state.lastPlaylistUrl);
  final formKey = GlobalKey<FormState>();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Add a playlist'),
      content: SizedBox(width: 460, child: Form(key: formKey, child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Import an M3U/M3U8 playlist from a URL, or choose a local file. Use sources you are allowed to access.', style: Theme.of(dialogContext).textTheme.bodyMedium),
        const SizedBox(height: 16),
        TextFormField(controller: field, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Playlist URL', hintText: 'https://example.com/channels.m3u', prefixIcon: Icon(Icons.link_rounded)), validator: (value) { final u = Uri.tryParse(value?.trim() ?? ''); return u != null && {'http', 'https'}.contains(u.scheme) && u.host.isNotEmpty ? null : 'Enter a valid HTTP(S) URL'; }),
        const SizedBox(height: 12),
        Align(alignment: Alignment.centerLeft, child: Wrap(spacing: 7, runSpacing: 7, children: [
          ActionChip(label: const Text('Movies playlist'), onPressed: () => field.text = 'https://iptv-org.github.io/iptv/categories/movies.m3u'),
          ActionChip(label: const Text('Sports playlist'), onPressed: () => field.text = 'https://iptv-org.github.io/iptv/categories/sports.m3u'),
          ActionChip(label: const Text('Sri Lanka playlist'), onPressed: () => field.text = 'https://iptv-org.github.io/iptv/countries/lk.m3u'),
        ])),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
        TextButton.icon(onPressed: () async { Navigator.pop(dialogContext); try { final count = await state.importPlaylistFile(); if (context.mounted && count > 0) _snack(context, 'Imported $count entries.'); } catch (e) { if (context.mounted) _snack(context, 'Import failed: $e'); } }, icon: const Icon(Icons.folder_open_rounded), label: const Text('Choose file')),
        FilledButton(onPressed: () async {
          if (formKey.currentState?.validate() != true) return;
          final playlistUrl = field.text;
          Navigator.pop(dialogContext);
          try { final count = await state.loadPlaylistUrl(playlistUrl); if (context.mounted) _snack(context, 'Playlist parsed: $count entries.'); }
          catch (e) { if (context.mounted) _snack(context, 'Could not import playlist: $e'); }
        }, child: const Text('Import URL')),
      ],
    ),
  );
  field.dispose();
}

void _snack(BuildContext context, String message) => _showFlowSnack(context, message);

void _showFlowSnack(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  final lower = message.toLowerCase();
  final isError = RegExp(r'could not|failed|failure|error|invalid|exception|unable|not imported|not load').hasMatch(lower);
  final isWarning = !isError && RegExp(r'no data|offline|not available|empty|buffer|timeout').hasMatch(lower);
  final isSuccess = !isError && !isWarning && RegExp(r'imported|added|parsed|cleared|saved|restored|connected|loaded|complete').hasMatch(lower);
  final accent = isError
      ? const Color(0xFFFF5577)
      : isWarning
          ? const Color(0xFFFFC166)
          : isSuccess
              ? const Color(0xFF43E0B2)
              : Theme.of(context).colorScheme.primary;
  final icon = isError
      ? Icons.error_outline_rounded
      : isWarning
          ? Icons.warning_amber_rounded
          : isSuccess
              ? Icons.check_circle_outline_rounded
              : Icons.info_outline_rounded;

  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      elevation: 0,
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 18),
      duration: Duration(seconds: isError || isWarning ? 5 : 3),
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFF111A32), Color(0xFF17142C)],
          ),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: accent.withValues(alpha: .62), width: 1),
          boxShadow: [BoxShadow(color: accent.withValues(alpha: .13), blurRadius: 22, offset: const Offset(0, 7))],
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accent, size: 21),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFF4F7FF), fontSize: 13, height: 1.3, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.state, required this.channel});
  final FlowState state;
  final TvChannel channel;
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final Player player;
  late final VideoController videoController;
  StreamSubscription<bool>? _bufferingSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<String>? _errorSubscription;
  Timer? _hideTimer;
  Timer? _bufferTimer;
  Timer? _stableTimer;
  bool _controlsVisible = true;
  bool _connecting = true;
  bool _rotationLocked = false;
  bool _autoLowered = false;
  bool _showStats = false;
  bool _pip = false;
  bool _desktopMiniPlayer = false;
  Size? _previousWindowSize;
  Offset? _previousWindowPosition;
  bool _previouslyMaximized = false;
  String _error = '';
  String _quality = '';
  int _retries = 0;
  int? _maxHeight;
  DateTime _startedAt = DateTime.now();
  Duration _elapsed = Duration.zero;
  Timer? _elapsedTicker;
  String _displayScale = 'none';
  BoxFit _videoFit = BoxFit.contain;

  @override
  void initState() {
    super.initState();
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
    _quality = widget.state.dataSaver ? 'saver' : widget.state.quality;
    player = Player(configuration: PlayerConfiguration(
      title: widget.channel.name,
      bufferSize: widget.state.bufferMode == 'stable' ? 64 * 1024 * 1024 : 32 * 1024 * 1024,
      logLevel: MPVLogLevel.error,
      protocolWhitelist: const ['udp', 'rtp', 'tcp', 'tls', 'data', 'file', 'http', 'https', 'crypto', 'rtsp', 'rtmp', 'mms'],
    ));
    videoController = VideoController(player);
    _startPlayback();
    _bufferingSubscription = player.stream.buffering.listen(_onBuffering);
    _playingSubscription = player.stream.playing.listen((playing) {
      if (playing && mounted && _connecting) {
        setState(() => _connecting = false);
      }
    });
    _errorSubscription = player.stream.error.listen((error) {
      if (!mounted || error.trim().isEmpty) return;
      setState(() {
        _error = error;
        _connecting = false;
      });
    });
    _elapsedTicker = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && player.state.playing) setState(() => _elapsed = DateTime.now().difference(_startedAt));
    });
    _scheduleHide();
  }

  Future<void> _setMpvProperty(String key, String value) async {
    try {
      final platform = player.platform;
      if (platform is NativePlayer) await platform.setProperty(key, value);
    } catch (_) {
      // Not every backend supports every mpv property. Playback remains usable.
    }
  }

  String get _hlsPreference {
    switch (_quality) {
      case 'saver': return 'min';
      case 'best': return 'max';
      case '360': return '500000';
      case '480': return '900000';
      case '576': return '1500000';
      case '720': return '2200000';
      case '1080': return '4000000';
      case 'auto': return _autoLowered ? 'min' : 'max';
      default: return 'max';
    }
  }

  Future<void> _startPlayback() async {
    if (mounted && (!_connecting || _error.isNotEmpty)) {
      setState(() {
        _connecting = true;
        _error = '';
      });
    }
    try {
      final s = widget.state;
      if (s.proxyEnabled) {
        final p = Uri.tryParse(s.proxyUrl.trim());
        if (p != null && p.host.isNotEmpty && {'http', 'https'}.contains(p.scheme)) {
          await _setMpvProperty('http-proxy', 'http://${p.host}:${p.port == 0 ? 80 : p.port}');
        }
      } else {
        await _setMpvProperty('http-proxy', '');
      }
      await _setMpvProperty('cache', 'yes');
      await _setMpvProperty('demuxer-readahead-secs', s.bufferMode == 'low' ? '2' : s.bufferMode == 'stable' ? '15' : '7');
      await _setMpvProperty('demuxer-max-bytes', s.bufferMode == 'stable' ? '67108864' : '33554432');
      await _setMpvProperty('hls-bitrate', _hlsPreference);
      await player.open(Media(widget.channel.url));
      if (mounted) {
        setState(() {
          _error = '';
          if (player.state.playing) _connecting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _connecting = false;
        });
      }
    }
  }

  void _onBuffering(bool buffering) {
    _bufferTimer?.cancel();
    if (!buffering) {
      _stableTimer?.cancel();
      _stableTimer = Timer(const Duration(seconds: 90), () {
        if (!mounted || player.state.buffering) return;
        _retries = 0;
        if (_autoLowered && _quality == 'auto') {
          _autoLowered = false;
          unawaited(_startPlayback());
        } else {
          setState(() {});
        }
      });
      if (mounted) setState(() {});
      return;
    }
    _bufferTimer = Timer(const Duration(seconds: 14), () async {
      if (!mounted || !player.state.buffering || !widget.state.autoReconnect || _retries >= 3) return;
      _retries++;
      if ((_quality == 'auto' || _quality == 'saver') && !_autoLowered) {
        _autoLowered = true;
        await _setMpvProperty('hls-bitrate', 'min');
      }
      await Future<void>.delayed(Duration(seconds: _retries));
      if (!mounted) return;
      await _startPlayback();
    });
    if (mounted) setState(() {});
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    // Windows needs a little more time for mouse-based controls than touch UI.
    final delay = defaultTargetPlatform == TargetPlatform.windows
        ? const Duration(seconds: 10)
        : const Duration(seconds: 3);
    _hideTimer = Timer(delay, () {
      if (mounted && player.state.playing) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      // On desktop, tapping/clicking the video should reveal or keep controls
      // visible and restart the ten-second timer instead of hiding instantly.
      if (!_controlsVisible) setState(() => _controlsVisible = true);
      _scheduleHide();
      return;
    }
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide(); else _hideTimer?.cancel();
  }

  Future<void> _toggleRotationLock() async {
    setState(() => _rotationLocked = !_rotationLocked);
    if (_rotationLocked) {
      final orientation = MediaQuery.of(context).orientation;
      await SystemChrome.setPreferredOrientations(orientation == Orientation.landscape
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : [DeviceOrientation.portraitUp]);
    } else {
      await SystemChrome.setPreferredOrientations(const []);
    }
  }

  Future<void> _restoreDesktopWindow() async {
    try {
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setMinimumSize(const Size(760, 520));
      if (_previouslyMaximized) {
        await windowManager.maximize();
      } else {
        final previousSize = _previousWindowSize;
        final previousPosition = _previousWindowPosition;
        if (previousSize != null) await windowManager.setSize(previousSize);
        if (previousPosition != null) await windowManager.setPosition(previousPosition);
      }
      if (mounted) setState(() => _desktopMiniPlayer = false);
    } catch (e) {
      if (mounted) _showSnack('Could not restore the player window: $e');
    }
  }

  Future<void> _minimize() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final ok = await _androidPip.invokeMethod<bool>('enterPip') ?? false;
        if (mounted) setState(() => _pip = ok);
        if (!ok && mounted) _showSnack('Picture-in-Picture is not available on this device.');
      } on PlatformException catch (e) {
        if (mounted) _showSnack('Could not enter PiP: ${e.message ?? 'unsupported'}');
      } on MissingPluginException {
        if (mounted) _showSnack('PiP native bridge is not installed in this build.');
      }
    } else if (defaultTargetPlatform == TargetPlatform.windows) {
      try {
        if (_desktopMiniPlayer) {
          // Restore the same window size/position, including maximized state.
          await _restoreDesktopWindow();
        } else {
          _previouslyMaximized = await windowManager.isMaximized();
          _previousWindowSize = await windowManager.getSize();
          _previousWindowPosition = await windowManager.getPosition();
          // A maximized window may ignore the new mini-player dimensions until restored.
          if (_previouslyMaximized) await windowManager.unmaximize();
          await windowManager.setAlwaysOnTop(true);
          await windowManager.setMinimumSize(const Size(360, 230));
          await windowManager.setSize(const Size(480, 300));
          await windowManager.center();
          if (mounted) {
            setState(() {
              _desktopMiniPlayer = true;
              _controlsVisible = true;
            });
            _scheduleHide();
          }
        }
      } catch (e) {
        if (mounted) _showSnack('Could not toggle the Windows mini-player: $e');
      }
    } else {
      _showSnack('Mini-player is not supported on this platform.');
    }
  }

  void _showSnack(String text) => _showFlowSnack(context, text);

  Future<void> _pickQuality() async {
    final tracks = player.state.tracks.video.where((t) => t.id != 'auto' && t.id != 'no').toList();
    final heights = tracks.map((t) => t.h).whereType<int>().toList();
    _maxHeight = heights.isNotEmpty ? heights.reduce((a, b) => a > b ? a : b) : player.state.height;
    final selection = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      showDragHandle: true,
      builder: (context) => SafeArea(child: SingleChildScrollView(child: Padding(padding: const EdgeInsets.fromLTRB(20, 6, 20, 20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Stream quality', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(_maxHeight == null ? 'Source resolution is not known yet.' : 'Highest reported source: ${_maxHeight}p. Higher-than-source options stay disabled.', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        for (final item in const [('auto', 'Smart Auto', 'Automatically prefer a safer rendition after buffering'), ('saver', 'Data Saver', 'Prefer the lowest available HLS bitrate'), ('360', '360p target', 'Select source rendition around this bitrate'), ('480', '480p target', 'Select source rendition around this bitrate'), ('576', '576p target', 'Select source rendition around this bitrate'), ('720', '720p target', 'Unavailable when source tops out below 720p'), ('1080', '1080p target', 'Unavailable when source tops out below 1080p'), ('best', 'Highest available', 'Prefer the highest advertised rendition')])
          _QualityChoice(item: item, enabled: _qualityEnabled(item.$1), selected: _quality == item.$1, onTap: () => Navigator.pop(context, item.$1)),
      ])))),
    );
    if (selection == null) return;
    if (!_qualityEnabled(selection)) {
      _showSnack('The stream does not report that resolution. FlowTV will not upscale and label it as higher quality.');
      return;
    }
    _quality = selection;
    _autoLowered = false;
    await widget.state.setQuality(selection);
    await _setMpvProperty('hls-bitrate', _hlsPreference);
    await _startPlayback();
    if (mounted) { setState(() {}); _scheduleHide(); }
  }

  bool _qualityEnabled(String selected) {
    if (_maxHeight == null) return true;
    if (selected == '1080') return _maxHeight! >= 1080;
    if (selected == '720') return _maxHeight! >= 720;
    if (selected == '576') return _maxHeight! >= 576;
    if (selected == '480') return _maxHeight! >= 480;
    if (selected == '360') return _maxHeight! >= 360;
    return true;
  }

  Future<void> _pickDownscale() async {
    final scale = await showModalBottomSheet<String>(context: context, showDragHandle: true, builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const ListTile(title: Text('Display downscale'), subtitle: Text('Changes local output only; it does not reduce the bytes already downloaded.')),
      for (final item in const [('none', 'Original output'), ('720', 'Downscale display to 720p'), ('480', 'Downscale display to 480p'), ('360', 'Downscale display to 360p')]) ListTile(title: Text(item.$2), trailing: _displayScale == item.$1 ? const Icon(Icons.check_rounded) : null, onTap: () => Navigator.pop(context, item.$1)),
    ])));
    if (scale == null) return;
    _displayScale = scale;
    if (scale == 'none') {
      await _setMpvProperty('vf', '');
    } else {
      final height = int.parse(scale);
      final width = height * 16 ~/ 9;
      await _setMpvProperty('vf', 'scale=$width:$height');
    }
    if (mounted) {
      setState(() {});
      _showSnack('Display output set to ${scale == 'none' ? 'original' : '${scale}p'}. Network data usage is unchanged.');
    }
  }

  Future<void> _pickBufferMode() async {
    final value = await showModalBottomSheet<String>(context: context, showDragHandle: true, builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const ListTile(title: Text('Buffer strategy'), subtitle: Text('More cache may reduce brief stalls but can increase live delay.')),
      for (final item in const [('low', 'Low latency', 'Smaller buffer and less live delay'), ('balanced', 'Balanced', 'Moderate buffer for everyday use'), ('stable', 'Maximum stability', 'Larger buffer for rough connections')])
        ListTile(title: Text(item.$2), subtitle: Text(item.$3), trailing: widget.state.bufferMode == item.$1 ? const Icon(Icons.check_rounded) : null, onTap: () => Navigator.pop(context, item.$1)),
    ])));
    if (value == null) return;
    await widget.state.setBufferMode(value);
    await _setMpvProperty('demuxer-readahead-secs', value == 'low' ? '2' : value == 'stable' ? '15' : '7');
    await _setMpvProperty('demuxer-max-bytes', value == 'stable' ? '67108864' : '33554432');
    if (mounted) setState(() {});
  }

  Future<void> _pickAspectRatio() async {
    final selected = await showModalBottomSheet<BoxFit>(context: context, showDragHandle: true, builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const ListTile(title: Text('Aspect ratio / fit'), subtitle: Text('Contain preserves the whole frame; Cover may crop edges; Fill may stretch the picture.')),
      for (final item in const [(BoxFit.contain, 'Contain • original proportions'), (BoxFit.cover, 'Cover • fill screen, crop if needed'), (BoxFit.fill, 'Fill • stretch to screen'), (BoxFit.fitWidth, 'Fit width'), (BoxFit.fitHeight, 'Fit height')])
        ListTile(title: Text(item.$2), trailing: _videoFit == item.$1 ? const Icon(Icons.check_rounded) : null, onTap: () => Navigator.pop(context, item.$1)),
    ])));
    if (selected != null && mounted) setState(() => _videoFit = selected);
  }

  Future<void> _pickAudio() async {
    final tracks = player.state.tracks.audio;
    final selected = await showModalBottomSheet<AudioTrack>(context: context, showDragHandle: true, builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const ListTile(title: Text('Audio track')),
      ...tracks.map((track) => ListTile(
        title: Text(track.id == 'no' ? 'Off' : track.title ?? track.language ?? 'Audio ${track.id}'),
        subtitle: track.codec == null ? null : Text(track.codec!),
        trailing: player.state.track.audio.id == track.id ? const Icon(Icons.check_rounded) : null,
        onTap: () => Navigator.pop(context, track),
      )),
    ])));
    if (selected != null) await player.setAudioTrack(selected);
  }

  Future<void> _pickSubtitle() async {
    final tracks = player.state.tracks.subtitle;
    final chosen = await showModalBottomSheet<SubtitleTrack>(context: context, showDragHandle: true, builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const ListTile(title: Text('Subtitles')),
      ...tracks.map((track) => ListTile(title: Text(track.id == 'no' ? 'Off' : track.title ?? track.language ?? 'Subtitle ${track.id}'), trailing: player.state.track.subtitle.id == track.id ? const Icon(Icons.check_rounded) : null, onTap: () => Navigator.pop(context, track))),
    ])));
    if (chosen != null) await player.setSubtitleTrack(chosen);
  }

  Future<void> _showMore() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .84,
          ),
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Player controls'),
                  subtitle: Text('Quick settings for this stream'),
                ),
                ListTile(leading: const Icon(Icons.refresh_rounded), title: const Text('Reconnect stream'), subtitle: const Text('Reload this channel now'), onTap: () => Navigator.pop(sheetContext, 'reconnect')),
                ListTile(leading: const Icon(Icons.speed_rounded), title: const Text('Buffer strategy'), subtitle: Text(widget.state.bufferMode.toUpperCase()), onTap: () => Navigator.pop(sheetContext, 'buffer')),
                ListTile(leading: const Icon(Icons.high_quality_rounded), title: const Text('Stream quality'), subtitle: Text(_quality.toUpperCase()), onTap: () => Navigator.pop(sheetContext, 'quality')),
                ListTile(leading: const Icon(Icons.aspect_ratio_rounded), title: const Text('Display downscale'), subtitle: Text(_displayScale == 'none' ? 'Original output' : '${_displayScale}p local output'), onTap: () => Navigator.pop(sheetContext, 'scale')),
                ListTile(leading: const Icon(Icons.closed_caption_rounded), title: const Text('Subtitles'), onTap: () => Navigator.pop(sheetContext, 'subs')),
                ListTile(leading: const Icon(Icons.audiotrack_rounded), title: const Text('Audio track'), onTap: () => Navigator.pop(sheetContext, 'audio')),
                ListTile(leading: const Icon(Icons.aspect_ratio_rounded), title: const Text('Aspect ratio / fit'), subtitle: Text(_videoFit.name), onTap: () => Navigator.pop(sheetContext, 'aspect')),
                SwitchListTile(secondary: const Icon(Icons.lock_clock_outlined), title: const Text('Rotation lock'), value: _rotationLocked, onChanged: (_) => Navigator.pop(sheetContext, 'rotation')),
                SwitchListTile(secondary: const Icon(Icons.bolt_rounded), title: const Text('Data Saver'), value: widget.state.dataSaver, onChanged: (_) => Navigator.pop(sheetContext, 'saver')),
                SwitchListTile(secondary: const Icon(Icons.analytics_outlined), title: const Text('Playback stats'), value: _showStats, onChanged: (_) => Navigator.pop(sheetContext, 'stats')),
              ],
            ),
          ),
        ),
      ),
    );
    switch (selected) {
      case 'quality': await _pickQuality(); break;
      case 'scale': await _pickDownscale(); break;
      case 'subs': await _pickSubtitle(); break;
      case 'audio': await _pickAudio(); break;
      case 'aspect': await _pickAspectRatio(); break;
      case 'buffer': await _pickBufferMode(); break;
      case 'reconnect': _retries = 0; _error = ''; _autoLowered = true; await _startPlayback(); break;
      case 'rotation': await _toggleRotationLock(); break;
      case 'saver':
        await widget.state.setDataSaver(!widget.state.dataSaver);
        _quality = widget.state.dataSaver ? 'saver' : 'auto';
        await _setMpvProperty('hls-bitrate', _hlsPreference);
        await _startPlayback();
        break;
      case 'stats': setState(() => _showStats = !_showStats); break;
    }
    _scheduleHide();
  }

  @override
  void dispose() {
    if (_desktopMiniPlayer) unawaited(_restoreDesktopWindow());
    _hideTimer?.cancel();
    _bufferTimer?.cancel();
    _stableTimer?.cancel();
    _elapsedTicker?.cancel();
    _bufferingSubscription?.cancel();
    _playingSubscription?.cancel();
    _errorSubscription?.cancel();
    unawaited(player.dispose());
    unawaited(SystemChrome.setPreferredOrientations(const []));
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        onPopInvokedWithResult: (didPop, result) { if (didPop) { SystemChrome.setPreferredOrientations(const []); SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge); } },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleControls,
            onDoubleTap: () async => player.playOrPause(),
            child: Stack(fit: StackFit.expand, children: [
              const ColoredBox(color: Colors.black),
              Center(child: Video(controller: videoController, fit: _videoFit, controls: NoVideoControls, pauseUponEnteringBackgroundMode: false, resumeUponEnteringForegroundMode: false, wakelock: true)),
              StreamBuilder<bool>(
                stream: player.stream.buffering,
                initialData: player.state.buffering,
                builder: (context, snapshot) {
                  final buffering = snapshot.data == true;
                  if (!_connecting && !buffering) return const SizedBox.shrink();
                  final title = _connecting ? 'CONNECTING TO CHANNEL' : 'BUFFERING STREAM';
                  final subtitle = _connecting ? 'Preparing your stream…' : 'Waiting for a steadier connection…';
                  return IgnorePointer(
                    child: Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xE8111A32),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: widget.state.accent.withValues(alpha: .38)),
                          boxShadow: [BoxShadow(color: widget.state.accent.withValues(alpha: .12), blurRadius: 28)],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(width: 23, height: 23, child: CircularProgressIndicator(strokeWidth: 2.4, color: widget.state.accent)),
                            const SizedBox(width: 13),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: .7)),
                                const SizedBox(height: 4),
                                Text(subtitle, style: const TextStyle(color: Color(0xFFB9C7E5), fontSize: 11)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              if (_controlsVisible) ...[
                const _GradientOverlay(alignment: Alignment.topCenter),
                const _GradientOverlay(alignment: Alignment.bottomCenter),
                SafeArea(child: Column(children: [
                  Padding(padding: const EdgeInsets.fromLTRB(8, 6, 8, 10), child: Row(children: [
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded, color: Colors.white)),
                    if (!_desktopMiniPlayer) ...[
                      ChannelLogo(channel: widget.channel, size: 38, accent: widget.state.accent),
                      const SizedBox(width: 10),
                    ],
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(widget.channel.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)), if (!_desktopMiniPlayer) Text('${widget.channel.group}  •  LIVE', style: const TextStyle(color: Color(0xFFC5D2F0), fontSize: 11))])),
                    IconButton(tooltip: defaultTargetPlatform == TargetPlatform.windows ? (_desktopMiniPlayer ? 'Restore player window' : 'Enter always-on-top mini-player') : 'Minimize / Picture-in-Picture', onPressed: _minimize, icon: Icon(_desktopMiniPlayer ? Icons.picture_in_picture_rounded : Icons.picture_in_picture_alt_rounded, color: Colors.white)),
                    if (!_desktopMiniPlayer) ...[
                      IconButton(tooltip: 'Rotation lock', onPressed: _toggleRotationLock, icon: Icon(_rotationLocked ? Icons.screen_lock_rotation_rounded : Icons.screen_rotation_rounded, color: Colors.white)),
                      IconButton(tooltip: stateFavTooltip(), onPressed: () => widget.state.toggleFavorite(widget.channel), icon: Icon(widget.state.favorites.contains(widget.channel.id) ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: widget.state.favorites.contains(widget.channel.id) ? const Color(0xFFFF5B9C) : Colors.white)),
                    ],
                    IconButton(tooltip: 'More player settings', onPressed: _showMore, icon: const Icon(Icons.tune_rounded, color: Colors.white)),
                  ])),
                  const Spacer(),
                  if (_error.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8), child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.black.withValues(alpha: .75), borderRadius: BorderRadius.circular(14)), child: Row(children: [const Icon(Icons.warning_amber_rounded, color: Colors.orange), const SizedBox(width: 9), Expanded(child: Text(_error, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12))), IconButton(onPressed: () => _startPlayback(), icon: const Icon(Icons.refresh_rounded, color: Colors.white))]))),
                  if (_retries >= 3) Padding(padding: const EdgeInsets.fromLTRB(18, 0, 18, 8), child: FilledButton.icon(onPressed: () { _retries = 0; _autoLowered = true; _startPlayback(); }, icon: const Icon(Icons.refresh_rounded), label: const Text('Reconnect stream'))),
                  if (_showStats) Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: _PlaybackStats(player: player, elapsed: _elapsed, quality: _quality, proxy: widget.state.proxyEnabled, bufferMode: widget.state.bufferMode)),
                  Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 14), child: Column(children: [
                    Row(children: [
                      IconButton(iconSize: 34, onPressed: () => player.playOrPause(), icon: StreamBuilder<bool>(stream: player.stream.playing, initialData: player.state.playing, builder: (context, snap) => Icon(snap.data == true ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white))),
                      const SizedBox(width: 3),
                      IconButton(onPressed: () => player.setVolume(player.state.volume == 0 ? 100 : 0), icon: Icon(player.state.volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: Colors.white)),
                      Expanded(child: Text(_displayResolution(), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700))),
                      _ControlPill(icon: Icons.high_quality_rounded, label: _quality == 'auto' ? 'AUTO' : _quality.toUpperCase(), onTap: _pickQuality),
                      const SizedBox(width: 6),
                      IconButton(onPressed: () => SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky), icon: const Icon(Icons.fullscreen_rounded, color: Colors.white)),
                    ]),
                    if (widget.state.showDataEstimate) Align(alignment: Alignment.centerLeft, child: Text(_estimatedData(), style: const TextStyle(color: Color(0xFFB8C8E8), fontSize: 10))),
                    const SizedBox(height: 9),
                    Row(children: [
                      Expanded(child: Text(_formatDuration(_elapsed), style: const TextStyle(color: Colors.white70, fontSize: 10))),
                      Text((_pip || _desktopMiniPlayer) ? 'MINI-PLAYER ACTIVE' : widget.state.bufferMode.toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 10)),
                      const SizedBox(width: 9),
                      Text(_rotationLocked ? 'ROTATION LOCKED' : 'LIVE', style: const TextStyle(color: Colors.white70, fontSize: 10)),
                    ]),
                  ])),
                ])),
              ],
            ]),
          ),
        ),
      );

  String stateFavTooltip() => widget.state.favorites.contains(widget.channel.id) ? 'Remove from favorites' : 'Add to favorites';

  String _displayResolution() {
    final h = player.state.height;
    if (h == null) return 'SOURCE QUALITY';
    return '${h}p source${_displayScale == 'none' ? '' : ' • ${_displayScale}p output'}';
  }

  String _estimatedData() {
    final seconds = _elapsed.inSeconds;
    int mbps;
    switch (_quality) {
      case 'saver': case '360': mbps = 450; break;
      case '480': mbps = 800; break;
      case '576': mbps = 1200; break;
      case '720': mbps = 2200; break;
      case '1080': case 'best': mbps = 4000; break;
      default: mbps = 1500;
    }
    final mb = seconds * mbps / 8 / 1000;
    return 'Estimated data: ${mb < 1000 ? '${mb.toStringAsFixed(0)} MB' : '${(mb / 1000).toStringAsFixed(2)} GB'} • rough estimate';
  }
}

class _GradientOverlay extends StatelessWidget {
  const _GradientOverlay({required this.alignment});
  final Alignment alignment;
  @override
  Widget build(BuildContext context) => IgnorePointer(child: Align(alignment: alignment, child: Container(height: alignment == Alignment.topCenter ? 165 : 240, decoration: BoxDecoration(gradient: LinearGradient(begin: alignment == Alignment.topCenter ? Alignment.topCenter : Alignment.bottomCenter, end: alignment == Alignment.topCenter ? Alignment.bottomCenter : Alignment.topCenter, colors: [Colors.black.withValues(alpha: .78), Colors.black.withValues(alpha: 0)])))));
}

class _ControlPill extends StatelessWidget {
  const _ControlPill({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12), child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .15), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withValues(alpha: .18))), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: Colors.white, size: 16), const SizedBox(width: 5), Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900))])));
}

class _QualityChoice extends StatelessWidget {
  const _QualityChoice({required this.item, required this.enabled, required this.selected, required this.onTap});
  final (String, String, String) item;
  final bool enabled;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Opacity(opacity: enabled ? 1 : .35, child: ListTile(
        enabled: enabled,
        contentPadding: EdgeInsets.zero,
        title: Text(item.$2, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(item.$3, style: Theme.of(context).textTheme.bodySmall),
        trailing: selected ? Icon(Icons.check_circle_rounded, color: Theme.of(context).colorScheme.primary) : enabled ? const Icon(Icons.radio_button_unchecked_rounded) : const Icon(Icons.lock_outline_rounded),
        onTap: enabled ? onTap : null,
      ));
}

class _PlaybackStats extends StatelessWidget {
  const _PlaybackStats({required this.player, required this.elapsed, required this.quality, required this.proxy, required this.bufferMode});
  final Player player;
  final Duration elapsed;
  final String quality;
  final bool proxy;
  final String bufferMode;
  @override
  Widget build(BuildContext context) => Container(width: double.infinity, margin: const EdgeInsets.only(bottom: 7), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.black.withValues(alpha: .70), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withValues(alpha: .15))), child: Wrap(spacing: 17, runSpacing: 7, children: [
        _StatLabel(label: 'SOURCE', value: '${player.state.width ?? '?'} × ${player.state.height ?? '?'}'),
        _StatLabel(label: 'PROFILE', value: quality.toUpperCase()),
        _StatLabel(label: 'BUFFER', value: '${player.state.buffer.inSeconds}s'),
        _StatLabel(label: 'PROXY', value: proxy ? 'ON' : 'OFF'),
        _StatLabel(label: 'CACHE', value: bufferMode.toUpperCase()),
        _StatLabel(label: 'WATCH TIME', value: _formatDuration(elapsed)),
      ]));
}

class _StatLabel extends StatelessWidget {
  const _StatLabel({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [Text(label, style: const TextStyle(color: Color(0xFF91A7CE), fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: .7)), const SizedBox(height: 3), Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800))]);
}

String _formatDuration(Duration duration) {
  final h = duration.inHours;
  final m = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}
