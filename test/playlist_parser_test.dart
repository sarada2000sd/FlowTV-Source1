import 'package:flutter_test/flutter_test.dart';
import 'package:flowtv/main.dart';

void main() {
  group('parseM3u', () {
    test('reads names, logos, ids, and category metadata', () {
      const playlist = '''#EXTM3U
#EXTINF:-1 tvg-id="sony.pix" tvg-name="Sony PIX" tvg-logo="https://example.com/sony.png" group-title="Movies",Sony PIX HD
https://example.com/sony/master.m3u8
''';
      final channels = parseM3u(playlist);
      expect(channels, hasLength(1));
      expect(channels.single.name, 'Sony PIX HD');
      expect(channels.single.group, 'Movies');
      expect(channels.single.logo, 'https://example.com/sony.png');
      expect(channels.single.tvgId, 'sony.pix');
      expect(channels.single.url, 'https://example.com/sony/master.m3u8');
    });

    test('skips duplicate stream URLs and unsupported lines', () {
      const playlist = '''#EXTM3U
#EXTINF:-1 group-title="Sports",Match channel
https://example.com/live.m3u8
#EXTINF:-1 group-title="Other",Duplicate channel
https://example.com/live.m3u8
#EXTINF:-1,Unsupported entry
javascript:alert(1)
''';
      final channels = parseM3u(playlist);
      expect(channels, hasLength(1));
      expect(channels.single.name, 'Match channel');
    });

    test('uses host as fallback title for bare stream links', () {
      final channels = parseM3u('https://tv.example.org/live.m3u8\n');
      expect(channels.single.name, 'tv.example.org');
      expect(channels.single.group, 'Other');
    });
  });
}
