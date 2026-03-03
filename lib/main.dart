import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'firebase_options.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CONSTANTS & GLOBALS
// ─────────────────────────────────────────────────────────────────────────────

const String kAdminEmail = 'farmaccdummy1@gmail.com';

final AudioPlayer globalPlayer = AudioPlayer();
List<Map<String, String>> _currentQueue = [];
int _currentQueueIdx = 0;
bool _playingFromPlaylist = false;
String? _currentPlaylistName;

final ValueNotifier<String> currentMoodNotifier = ValueNotifier('Joyful');
final ValueNotifier<Map<String, String>> currentSongNotifier = ValueNotifier({});
final List<Playlist> globalPlaylists = [];
final ValueNotifier<int> playlistChangeNotifier = ValueNotifier(0);
void notifyPlaylistChanged() => playlistChangeNotifier.value++;

// ─────────────────────────────────────────────────────────────────────────────
// SONG LIST
// ─────────────────────────────────────────────────────────────────────────────

List<Map<String, String>> kSongs = [
  {
    'title': 'Happy', 'artist': 'Aura Collective', 'mood': 'Joyful',
    'path': 'assets/audio/Happy.mp3', 'art': 'assets/images/happy_art.png', 'isAsset': 'true',
  },
  {
    'title': 'Sad', 'artist': 'Aura Collective', 'mood': 'Melancholic',
    'path': 'assets/audio/Sad.mp3', 'art': 'assets/images/sad_art.png', 'isAsset': 'true',
  },
  {
    'title': 'Calm', 'artist': 'Aura Collective', 'mood': 'Calm',
    'path': 'assets/audio/Calm.mp3', 'art': 'assets/images/calm_art.png', 'isAsset': 'true',
  },
  {
    'title': 'Energetic', 'artist': 'Aura Collective', 'mood': 'Energetic',
    'path': 'assets/audio/Energetic.mp3', 'art': 'assets/images/energetic_art.png', 'isAsset': 'true',
  },
  {
    'title': 'Romantic', 'artist': 'Aura Collective', 'mood': 'Romantic',
    'path': 'assets/audio/Love.mp3', 'art': 'assets/images/love_art.png', 'isAsset': 'true',
  },
  {
    'title': 'Rock', 'artist': 'Aura Collective', 'mood': 'Rock',
    'path': 'assets/audio/Rock.mp3', 'art': 'assets/images/rock_art.png', 'isAsset': 'true',
  },
];

// ─────────────────────────────────────────────────────────────────────────────
// PERSISTENCE
// ─────────────────────────────────────────────────────────────────────────────

Future<void> saveSongs() async {
  final prefs = await SharedPreferences.getInstance();
  final remote = kSongs.where((s) => s['isAsset'] != 'true').toList();
  await prefs.setString('remote_songs', jsonEncode(remote));
}

Future<void> loadSongs() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('remote_songs');
  if (raw != null) {
    final List decoded = jsonDecode(raw);
    kSongs.addAll(decoded.map((e) => Map<String, String>.from(e)));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DOWNLOAD
// ─────────────────────────────────────────────────────────────────────────────

final ValueNotifier<Map<String, double>> downloadProgress = ValueNotifier({});
final Map<String, String> downloadedPaths = {};

Future<void> loadDownloadedPaths() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('downloaded_paths');
  if (raw != null) {
    final Map decoded = jsonDecode(raw);
    decoded.forEach((k, v) => downloadedPaths[k as String] = v as String);
  }
}

Future<void> saveDownloadedPaths() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('downloaded_paths', jsonEncode(downloadedPaths));
}

Future<void> downloadSong(Map<String, String> song) async {
  final title = song['title']!;
  final url = song['path']!;
  if (song['isAsset'] == 'true') return;
  try {
    final dir = await getApplicationDocumentsDirectory();
    final filePath = '${dir.path}/${title.replaceAll(' ', '_')}.mp3';
    downloadProgress.value = {...downloadProgress.value, title: 0.0};
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      await File(filePath).writeAsBytes(response.bodyBytes);
      downloadedPaths[title] = filePath;
      await saveDownloadedPaths();
    }
    downloadProgress.value = Map.from(downloadProgress.value)..remove(title);
  } catch (_) {
    downloadProgress.value = Map.from(downloadProgress.value)..remove(title);
  }
}

bool isDownloaded(String title) => downloadedPaths.containsKey(title);

// ─────────────────────────────────────────────────────────────────────────────
// MODELS & HELPERS
// ─────────────────────────────────────────────────────────────────────────────

class Playlist {
  final String id;
  String name;
  final List<Map<String, String>> songs;
  Playlist({required this.id, required this.name, List<Map<String, String>>? songs})
      : songs = songs ?? [];
}

class MoodConfig {
  final List<Color> gradient;
  final Color accent;
  final Color particle;
  final String shape;
  final int count;
  final double speed;
  const MoodConfig({
    required this.gradient, required this.accent,
    required this.particle, required this.shape,
    required this.count,    required this.speed,
  });
}

MoodConfig moodCfg(String m) {
  switch (m) {
    case 'Joyful':      return const MoodConfig(gradient: [Color(0xFFFF6B35), Color(0xFFFF1493)], accent: Color(0xFFFF6B35), particle: Color(0xFFFFD700), shape: 'star',   count: 28, speed: 1.6);
    case 'Melancholic': return const MoodConfig(gradient: [Color(0xFF1A1A2E), Color(0xFF6A0572)], accent: Color(0xFF6A0572), particle: Color(0xFFCE93D8), shape: 'circle', count: 20, speed: 0.55);
    case 'Calm':        return const MoodConfig(gradient: [Color(0xFF0F3460), Color(0xFF16C79A)], accent: Color(0xFF16C79A), particle: Color(0xFF7FFFD4), shape: 'drop',   count: 16, speed: 0.45);
    case 'Energetic':   return const MoodConfig(gradient: [Color(0xFF0052D4), Color(0xFFFFD700)], accent: Color(0xFF0052D4), particle: Color(0xFFFFD700), shape: 'bolt',   count: 30, speed: 2.5);
    case 'Romantic':    return const MoodConfig(gradient: [Color(0xFF8B0000), Color(0xFFFF69B4)], accent: Color(0xFFFF69B4), particle: Color(0xFFFF69B4), shape: 'heart',  count: 22, speed: 0.9);
    case 'Rock':        return const MoodConfig(gradient: [Color(0xFF1C1C1C), Color(0xFF434343)], accent: Color(0xFFFF4500), particle: Color(0xFFFF4500), shape: 'bolt',   count: 26, speed: 2.2);
    default:            return const MoodConfig(gradient: [Color(0xFF1A1A2E), Color(0xFF16213E)], accent: Colors.white,     particle: Colors.white38,    shape: 'circle', count: 10, speed: 0.5);
  }
}

IconData moodIcon(String m) {
  switch (m) {
    case 'Joyful':      return Icons.wb_sunny_rounded;
    case 'Melancholic': return Icons.water_drop_rounded;
    case 'Calm':        return Icons.spa_rounded;
    case 'Energetic':   return Icons.bolt_rounded;
    case 'Romantic':    return Icons.favorite_rounded;
    case 'Rock':        return Icons.music_note_rounded;
    default:            return Icons.music_note_rounded;
  }
}

Color adaptiveText(List<Color> gradient, {bool secondary = false}) {
  // Calculate perceived brightness of the first gradient color
  final c = gradient[0];
  final brightness = (c.r * 299 + c.g * 587 + c.b * 114) / 1000;
  final isDark = brightness < 0.5;
  if (secondary) return isDark ? Colors.white54 : Colors.black45;
  return isDark ? Colors.white : Colors.black87;
}

// ─────────────────────────────────────────────────────────────────────────────
// PARTICLE ENGINE
// ─────────────────────────────────────────────────────────────────────────────

class _P {
  double x, y, vx, vy, size, opacity, phase, rot, rotSpeed;
  _P({required this.x, required this.y, required this.vx, required this.vy,
    required this.size, required this.opacity, required this.phase,
    required this.rot, required this.rotSpeed});
}

class MoodParticles extends StatefulWidget {
  final String moodName;
  final bool active;
  const MoodParticles({super.key, required this.moodName, required this.active});
  @override State<MoodParticles> createState() => _MoodParticlesState();
}

class _MoodParticlesState extends State<MoodParticles> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late List<_P> _ps;
  final _rng = math.Random();
  String _lastMood = '';

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();
    _spawn(widget.moodName);
    _ctrl.addListener(() { if (mounted) setState(() {}); });
  }

  void _spawn(String m) {
    _lastMood = m;
    final cfg = moodCfg(m);
    _ps = List.generate(cfg.count, (_) {
      final angle = _rng.nextDouble() * math.pi * 2;
      final spd   = (0.001 + _rng.nextDouble() * 0.003) * cfg.speed;
      return _P(x: _rng.nextDouble(), y: _rng.nextDouble(),
          vx: math.cos(angle) * spd * 0.3, vy: -spd,
          size: 5 + _rng.nextDouble() * 14, opacity: 0.25 + _rng.nextDouble() * 0.65,
          phase: _rng.nextDouble() * math.pi * 2, rot: _rng.nextDouble() * math.pi * 2,
          rotSpeed: (_rng.nextDouble() - 0.5) * 0.04);
    });
  }

  @override
  void didUpdateWidget(MoodParticles old) {
    super.didUpdateWidget(old);
    if (old.moodName != widget.moodName) _spawn(widget.moodName);
  }

  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();
    final cfg = moodCfg(_lastMood);
    return IgnorePointer(
        child: CustomPaint(
            painter: _PPainter(ps: _ps, color: cfg.particle, shape: cfg.shape, t: _ctrl.value),
            size: Size.infinite));
  }
}

class _PPainter extends CustomPainter {
  final List<_P> ps;
  final Color color;
  final String shape;
  final double t;
  const _PPainter({required this.ps, required this.color, required this.shape, required this.t});

  @override
  void paint(Canvas canvas, Size sz) {
    for (final p in ps) {
      double y = ((p.y + p.vy * t * 120) % 1.0 + 1.0) % 1.0;
      y = 1.0 - y;
      final x  = (p.x + p.vx * t * 120 + math.sin(t * math.pi * 2 + p.phase) * 0.035) % 1.0;
      final pulse = 0.6 + 0.4 * math.sin(t * math.pi * 4 + p.phase);
      final paint = Paint()
        ..color = color.withValues(alpha: (p.opacity * pulse).clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;
      canvas.save();
      canvas.translate(x * sz.width, y * sz.height);
      canvas.rotate(p.rot + p.rotSpeed * t * 120);
      switch (shape) {
        case 'star':  _star(canvas, p.size, paint);  break;
        case 'heart': _heart(canvas, p.size, paint); break;
        case 'bolt':  _bolt(canvas, p.size, paint);  break;
        case 'drop':  _drop(canvas, p.size, paint);  break;
        default:
          canvas.drawCircle(Offset.zero, p.size / 2, paint);
      }
      canvas.restore();
    }
  }

  void _star(Canvas c, double s, Paint p) {
    final path = Path();
    for (int i = 0; i < 5; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / 5;
      final b = a + math.pi / 5;
      if (i == 0) path.moveTo(math.cos(a)*s/2, math.sin(a)*s/2);
      else         path.lineTo(math.cos(a)*s/2, math.sin(a)*s/2);
      path.lineTo(math.cos(b)*s/4, math.sin(b)*s/4);
    }
    path.close(); c.drawPath(path, p);
  }

  void _heart(Canvas c, double s, Paint p) {
    c.drawPath(Path()
      ..moveTo(0, s/4)
      ..cubicTo(-s/2, -s/6, -s/2, -s/2, 0, -s/6)
      ..cubicTo( s/2, -s/2,  s/2, -s/6, 0,  s/4), p);
  }

  void _bolt(Canvas c, double s, Paint p) {
    c.drawPath(Path()
      ..moveTo(s*.1,-s/2) ..lineTo(-s*.1,-s*.05) ..lineTo(s*.15,-s*.05)
      ..lineTo(-s*.1, s/2) ..lineTo(s*.3,-s*.1)  ..lineTo(s*.05,-s*.1)
      ..close(), p);
  }

  void _drop(Canvas c, double s, Paint p) {
    c.drawPath(Path()
      ..moveTo(0,-s/2) ..cubicTo(s/3,-s/4,s/3,s/4,0,s/2)
      ..cubicTo(-s/3,s/4,-s/3,-s/4,0,-s/2) ..close(), p);
  }

  @override bool shouldRepaint(_PPainter o) => o.t != t || o.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// YOUTUBE HELPER
// ─────────────────────────────────────────────────────────────────────────────

bool isYouTubeUrl(String url) {
  return url.contains('youtube.com') || url.contains('youtu.be');
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN
// ─────────────────────────────────────────────────────────────────────────────

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (_) {}

  await loadSongs();
  await loadDownloadedPaths();
  _currentQueue = List.from(kSongs);
  runApp(const AuraHubApp());
}

// ─────────────────────────────────────────────────────────────────────────────
// APP
// ─────────────────────────────────────────────────────────────────────────────

class AuraHubApp extends StatelessWidget {
  const AuraHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AuraHub',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        sliderTheme: SliderThemeData(
          thumbColor: Colors.white,
          activeTrackColor: Colors.white,
          inactiveTrackColor: Colors.white24,
          overlayColor: Colors.white24,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          trackHeight: 3,
        ),
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const _Loader();
          if (!snap.hasData) return const LoginPage();
          final email = (snap.data!.email ?? '').toLowerCase().trim();
          return email == kAdminEmail.toLowerCase() ? const AdminPage() : const AuraHomePage();
        },
      ),
    );
  }
}

class _Loader extends StatelessWidget {
  const _Loader();
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(child: CircularProgressIndicator(color: Colors.white)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LOGIN PAGE
// ─────────────────────────────────────────────────────────────────────────────

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with SingleTickerProviderStateMixin {
  final _eCtrl = TextEditingController();
  final _pCtrl = TextEditingController();
  bool _loading = false, _gLoading = false, _obs = true;
  String? _err;
  late AnimationController _ac;
  late Animation<double> _fa;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _fa = CurvedAnimation(parent: _ac, curve: Curves.easeOut);
    _ac.forward();
  }

  @override
  void dispose() {
    _eCtrl.dispose(); _pCtrl.dispose(); _ac.dispose(); super.dispose();
  }

  Future<void> _login() async {
    setState(() { _loading = true; _err = null; });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _eCtrl.text.trim(), password: _pCtrl.text.trim(),
      );
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _err = _friendly(e.code));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _googleLogin() async {
    setState(() { _gLoading = true; _err = null; });
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) { setState(() => _gLoading = false); return; }
      final googleAuth = await googleUser.authentication;
      final cred = GoogleAuthProvider.credential(accessToken: googleAuth.accessToken, idToken: googleAuth.idToken);
      await FirebaseAuth.instance.signInWithCredential(cred);
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _err = _friendly(e.code));
    } finally {
      if (mounted) setState(() => _gLoading = false);
    }
  }

  String _friendly(String c) {
    switch (c) {
      case 'user-not-found':     return 'No account with this email.';
      case 'wrong-password':     return 'Incorrect password.';
      case 'invalid-email':      return 'Enter a valid email.';
      case 'invalid-credential': return 'Invalid email or password.';
      default:                   return 'Something went wrong.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF0A0A0A), Color(0xFF0A1A2E), Color(0xFF0A0A0A)],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fa,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 48),
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 80, height: 80,
                          decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFF6A0572), Color(0xFFFF1493)])),
                          child: const Center(child: Text('♪', style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900))),
                        ),
                        const SizedBox(height: 16),
                        const Text('AURA HUB', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 6)),
                        const SizedBox(height: 4),
                        const Text('feel the music', style: TextStyle(color: Colors.white38, fontSize: 12, letterSpacing: 3)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 48),
                  const Text('Welcome', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  const Text('Sign in to continue', style: TextStyle(color: Colors.white38, fontSize: 14)),
                  const SizedBox(height: 28),
                  if (_err != null) ...[_ErrorBox(message: _err!), const SizedBox(height: 16)],
                  const _Label('Email'),
                  const SizedBox(height: 6),
                  _Field(ctrl: _eCtrl, hint: 'Enter your email', icon: Icons.email_outlined, type: TextInputType.emailAddress),
                  const SizedBox(height: 16),
                  const _Label('Password'),
                  const SizedBox(height: 6),
                  _Field(
                    ctrl: _pCtrl, hint: 'Enter your password', icon: Icons.lock_outline_rounded, obs: _obs,
                    suffix: IconButton(
                      icon: Icon(_obs ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.white38, size: 20),
                      onPressed: () => setState(() => _obs = !_obs),
                    ),
                  ),
                  const SizedBox(height: 28),
                  _BigBtn(label: 'Sign In', loading: _loading, disabled: _loading || _gLoading, onTap: _login),
                  const SizedBox(height: 16),
                  const Row(children: [
                    Expanded(child: Divider(color: Colors.white12)),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('or', style: TextStyle(color: Colors.white38, fontSize: 13))),
                    Expanded(child: Divider(color: Colors.white12)),
                  ]),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity, height: 54,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white24), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                      onPressed: (_loading || _gLoading) ? null : _googleLogin,
                      child: _gLoading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('G', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                          SizedBox(width: 10),
                          Text('Continue with Google', style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Center(
                    child: GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterPage())),
                      child: RichText(
                        text: const TextSpan(
                          text: "Don't have an account? ",
                          style: TextStyle(color: Colors.white38, fontSize: 14),
                          children: [TextSpan(text: 'Create one', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, decoration: TextDecoration.underline))],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REGISTER PAGE
// ─────────────────────────────────────────────────────────────────────────────

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> with SingleTickerProviderStateMixin {
  final _nCtrl = TextEditingController();
  final _eCtrl = TextEditingController();
  final _pCtrl = TextEditingController();
  final _cCtrl = TextEditingController();
  bool _loading = false, _obs = true, _obsC = true;
  String? _err;
  late AnimationController _ac;
  late Animation<double> _fa;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _fa = CurvedAnimation(parent: _ac, curve: Curves.easeOut);
    _ac.forward();
  }

  @override
  void dispose() {
    _nCtrl.dispose(); _eCtrl.dispose(); _pCtrl.dispose(); _cCtrl.dispose();
    _ac.dispose(); super.dispose();
  }

  Future<void> _register() async {
    if (_pCtrl.text != _cCtrl.text) { setState(() => _err = 'Passwords do not match.'); return; }
    if (_pCtrl.text.length < 6) { setState(() => _err = 'Password must be at least 6 characters.'); return; }
    setState(() { _loading = true; _err = null; });
    try {
      final c = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _eCtrl.text.trim(), password: _pCtrl.text.trim(),
      );
      await c.user?.updateDisplayName(_nCtrl.text.trim());
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        showDialog(
          context: context, barrierDismissible: false,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(children: [
              Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 24),
              SizedBox(width: 10),
              Text('Account Created!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
            ]),
            content: const Text('Account created successfully. Please sign in.', style: TextStyle(color: Colors.white60, fontSize: 14)),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () { Navigator.pop(context); Navigator.pop(context); },
                child: const Text('Go to Sign In', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _err = _friendly(e.code));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendly(String c) {
    switch (c) {
      case 'email-already-in-use': return 'Account with this email already exists.';
      case 'invalid-email':        return 'Enter a valid email.';
      case 'weak-password':        return 'Password too weak.';
      default:                     return 'Something went wrong.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF0A0A0A), Color(0xFF0A1A2E), Color(0xFF0A0A0A)],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fa,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text('Create Account', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  const Text('Join AuraHub and feel the music', style: TextStyle(color: Colors.white38, fontSize: 14)),
                  const SizedBox(height: 32),
                  if (_err != null) ...[_ErrorBox(message: _err!), const SizedBox(height: 16)],
                  const _Label('Full Name'),
                  const SizedBox(height: 6),
                  _Field(ctrl: _nCtrl, hint: 'Enter your full name', icon: Icons.person_outline_rounded),
                  const SizedBox(height: 16),
                  const _Label('Email'),
                  const SizedBox(height: 6),
                  _Field(ctrl: _eCtrl, hint: 'Enter your email', icon: Icons.email_outlined, type: TextInputType.emailAddress),
                  const SizedBox(height: 16),
                  const _Label('Password'),
                  const SizedBox(height: 6),
                  _Field(ctrl: _pCtrl, hint: 'Create a password', icon: Icons.lock_outline_rounded, obs: _obs,
                    suffix: IconButton(
                      icon: Icon(_obs ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.white38, size: 20),
                      onPressed: () => setState(() => _obs = !_obs),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const _Label('Confirm Password'),
                  const SizedBox(height: 6),
                  _Field(ctrl: _cCtrl, hint: 'Repeat your password', icon: Icons.lock_outline_rounded, obs: _obsC,
                    suffix: IconButton(
                      icon: Icon(_obsC ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.white38, size: 20),
                      onPressed: () => setState(() => _obsC = !_obsC),
                    ),
                  ),
                  const SizedBox(height: 28),
                  _BigBtn(label: 'Create Account', loading: _loading, disabled: _loading, onTap: _register),
                  const SizedBox(height: 24),
                  Center(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: RichText(
                        text: const TextSpan(
                          text: 'Already have an account? ',
                          style: TextStyle(color: Colors.white38, fontSize: 14),
                          children: [TextSpan(text: 'Sign in', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, decoration: TextDecoration.underline))],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ADMIN PAGE  — Fixed: logout confirm, delete confirm, YouTube URL support,
//               friendlier UI with header stats, cleaner add-song form.
// ─────────────────────────────────────────────────────────────────────────────

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final _titleCtrl  = TextEditingController();
  final _artistCtrl = TextEditingController();
  final _urlCtrl    = TextEditingController();
  final _artCtrl    = TextEditingController();
  String _mood = 'Joyful';
  bool _adding = false;

  final _moods = ['Joyful', 'Melancholic', 'Calm', 'Energetic', 'Romantic', 'Rock'];

  @override
  void dispose() {
    _titleCtrl.dispose(); _artistCtrl.dispose(); _urlCtrl.dispose(); _artCtrl.dispose();
    super.dispose();
  }

  // Admin Fix 1: Confirm logout
  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.logout_rounded, color: Colors.redAccent, size: 22),
          SizedBox(width: 10),
          Text('Sign Out', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ]),
        content: const Text('Are you sure you want to sign out of Admin?', style: TextStyle(color: Colors.white60, fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () async {
              Navigator.pop(context);
              await globalPlayer.stop();
              await GoogleSignIn().signOut();
              await FirebaseAuth.instance.signOut();
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }
  String _convertToRawUrl(String url) {
    // Convert GitHub blob URL to raw URL automatically
    // https://github.com/user/repo/blob/main/file.mp3
    // → https://raw.githubusercontent.com/user/repo/main/file.mp3
    if (url.contains('github.com') && url.contains('/blob/')) {
      return url
          .replaceFirst('github.com', 'raw.githubusercontent.com')
          .replaceFirst('/blob/', '/');
    }
    return url;
  }

  void _addSong() {
    final title = _titleCtrl.text.trim();
    String url  = _convertToRawUrl(_urlCtrl.text.trim());
    if (title.isEmpty || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title and URL are required.'), backgroundColor: Colors.redAccent),
      );
      return;
    }
    // Block YouTube and show clear explanation
    if (isYouTubeUrl(url)) { _showYouTubeHelp(); return; }
    final artUrl = _artCtrl.text.trim();
    setState(() {
      kSongs.add({
        'title':   title,
        'artist':  _artistCtrl.text.trim().isEmpty ? 'Aura Collective' : _artistCtrl.text.trim(),
        'mood':    _mood,
        'path':    url,
        'art':     artUrl.isEmpty ? 'assets/images/happy_art.png' : artUrl,
        'isAsset': 'false',
      });
      _currentQueue = List.from(kSongs);
      _titleCtrl.clear(); _artistCtrl.clear(); _urlCtrl.clear(); _artCtrl.clear();
      _mood = 'Joyful';
      _adding = false;
    });
    saveSongs();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"$title" added!'), backgroundColor: Colors.greenAccent.shade700),
    );
  }

  /// Explains clearly why YouTube links do not work and what to use instead.
  void _showYouTubeHelp() {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(children: [
        Icon(Icons.block_rounded, color: Colors.redAccent, size: 22), SizedBox(width: 10),
        Expanded(child: Text('YouTube Links Don\'t Work', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15))),
      ]),
      content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3))),
            child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 16), SizedBox(width: 8),
              Expanded(child: Text('YouTube actively blocks apps from streaming audio directly. Pasting a YouTube URL here will not play the song.', style: TextStyle(color: Colors.redAccent, fontSize: 11, height: 1.5))),
            ])),
        const SizedBox(height: 14),
        const Text('✅  What DOES work:', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 8),
        _HelpTile('Direct MP3 link', 'Any URL ending in .mp3 .m4a .ogg or .wav that plays in a browser.\nExample: https://example.com/mysong.mp3'),
        const SizedBox(height: 8),
        _HelpTile('archive.org  (best free option)', '1. Go to archive.org → Upload your MP3 (free account).\n2. Open your uploaded file.\n3. Right-click the audio player → "Copy audio address".\n4. Paste that URL here.'),
        const SizedBox(height: 8),
        _HelpTile('Dropbox', '1. Upload MP3 to Dropbox.\n2. Share → copy link.\n3. Change "?dl=0" at the end to "?dl=1".\n4. Paste here.'),
        const SizedBox(height: 8),
        _HelpTile('GitHub Raw', '1. Upload MP3 to a public GitHub repo.\n2. Click the file → click "Raw".\n3. Copy the URL (starts with raw.githubusercontent.com).\n4. Paste here.'),
        const SizedBox(height: 14),
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.greenAccent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3))),
            child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.lightbulb_outline_rounded, color: Colors.greenAccent, size: 16), SizedBox(width: 8),
              Expanded(child: Text('Easiest: Use archive.org — totally free, no size limit, permanent direct link.', style: TextStyle(color: Colors.greenAccent, fontSize: 11, height: 1.5))),
            ])),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Got it', style: TextStyle(color: Colors.white38))),
        ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () { Navigator.pop(context); _urlCtrl.clear(); setState(() {}); },
            child: const Text('Clear URL & retry', style: TextStyle(fontWeight: FontWeight.w700))),
      ],
    ));
  }

  /// Shows free image hosting options — no database needed.
  void _showImageHelp() {
    const hosts = [
      {'name': 'Imgur',      'desc': 'Free, no account needed. Upload → right-click image → Copy image address', 'url': 'imgur.com/upload'},
      {'name': 'ImgBB',      'desc': 'Free. Upload → click image → copy "Direct link"',                         'url': 'imgbb.com'},
      {'name': 'PostImages', 'desc': 'Free, no account. Upload → copy "Direct link"',                           'url': 'postimages.org'},
      {'name': 'GitHub Raw', 'desc': 'Upload to a public repo → click file → "Raw" button → copy URL',         'url': 'github.com'},
    ];
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(children: [
        Icon(Icons.image_outlined, color: Color(0xFF64B5F6), size: 22), SizedBox(width: 10),
        Text('Free Image Hosting Guide', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
      ]),
      content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.greenAccent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3))),
            child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.lightbulb_outline_rounded, color: Colors.greenAccent, size: 16), SizedBox(width: 8),
              Expanded(child: Text('No database needed! Upload your cover image to any free service and paste the direct link here.', style: TextStyle(color: Colors.greenAccent, fontSize: 11, height: 1.5))),
            ])),
        const SizedBox(height: 14),
        ...hosts.map((h) => Container(
          margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(h['name']!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 3),
            Text(h['desc']!, style: const TextStyle(color: Colors.white54, fontSize: 11, height: 1.5)),
            const SizedBox(height: 2),
            Text(h['url']!, style: const TextStyle(color: Color(0xFF64B5F6), fontSize: 10)),
          ]),
        )),
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF64B5F6).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF64B5F6).withValues(alpha: 0.3))),
            child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.check_circle_outline_rounded, color: Color(0xFF64B5F6), size: 16), SizedBox(width: 8),
              Expanded(child: Text('Make sure the link ends in .jpg .png .webp or .gif and shows only the image when opened in a browser.', style: TextStyle(color: Color(0xFF64B5F6), fontSize: 11, height: 1.5))),
            ])),
      ])),
      actions: [
        ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it', style: TextStyle(fontWeight: FontWeight.w700))),
      ],
    ));
  }

  // Admin Fix 2: Confirm delete
  void _confirmDelete(Map<String, String> song) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.delete_rounded, color: Colors.redAccent, size: 22),
          SizedBox(width: 10),
          Text('Delete Song', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to delete:', style: const TextStyle(color: Colors.white60, fontSize: 14)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(10)),
              child: Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), gradient: LinearGradient(colors: moodCfg(song['mood'] ?? 'Joyful').gradient)),
                    child: Center(child: Icon(moodIcon(song['mood'] ?? 'Joyful'), color: Colors.white, size: 18)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(song['title']!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14))),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text('This action cannot be undone.', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                kSongs.removeWhere((s) => s['title'] == song['title']);
                _currentQueue = List.from(kSongs);
              });
              saveSongs();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('"${song['title']}" deleted.'), backgroundColor: Colors.redAccent),
              );
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final builtIn = kSongs.where((s) => s['isAsset'] == 'true').length;
    final custom  = kSongs.length - builtIn;
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        elevation: 0,
        title: const Row(children: [
          Icon(Icons.admin_panel_settings_rounded, color: Color(0xFFFF1493), size: 22),
          SizedBox(width: 10),
          Text('Admin Panel', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            tooltip: 'Sign Out',
            onPressed: _confirmLogout, // Fix 1: confirm before logout
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Stats header
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF6A0572), Color(0xFFFF1493)]),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                const Icon(Icons.music_note_rounded, color: Colors.white, size: 32),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('AuraHub Admin', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
                      const SizedBox(height: 4),
                      Text('${kSongs.length} total  •  $builtIn built-in  •  $custom custom', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Add song toggle
          GestureDetector(
            onTap: () => setState(() => _adding = !_adding),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: _adding ? const Color(0xFF1A1A2E) : Colors.white10,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _adding ? const Color(0xFFFF1493) : Colors.white12),
              ),
              child: Row(children: [
                Icon(_adding ? Icons.expand_less_rounded : Icons.add_circle_rounded, color: const Color(0xFFFF1493), size: 22),
                const SizedBox(width: 10),
                const Text('Add New Song', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                const Spacer(),
                if (!_adding) const Text('Tap to expand', style: TextStyle(color: Colors.white38, fontSize: 12)),
              ]),
            ),
          ),

          if (_adding) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AdminField(ctrl: _titleCtrl, label: 'Song Title *', hint: 'e.g. Midnight Vibes', icon: Icons.title_rounded),
                  const SizedBox(height: 12),
                  _AdminField(ctrl: _artistCtrl, label: 'Artist', hint: 'e.g. Aura Collective (optional)', icon: Icons.person_outline_rounded),
                  const SizedBox(height: 12),
                  // Audio URL — live YouTube detection
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const _Label('Audio URL *'),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isYouTubeUrl(_urlCtrl.text) ? const Color(0xFFFF8C00) : Colors.white12),
                      ),
                      child: Row(children: [
                        Expanded(child: TextField(
                          controller: _urlCtrl,
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: const InputDecoration(
                            hintText: 'https://...  (direct MP3 link only)',
                            hintStyle: TextStyle(color: Colors.white24, fontSize: 13),
                            prefixIcon: Icon(Icons.link_rounded, color: Colors.white38, size: 18),
                            border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 14),
                          ),
                        )),
                        if (isYouTubeUrl(_urlCtrl.text))
                          GestureDetector(
                            onTap: _showYouTubeHelp,
                            child: Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                              decoration: BoxDecoration(color: const Color(0xFFFF8C00).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.warning_amber_rounded, color: Color(0xFFFF8C00), size: 13),
                                SizedBox(width: 4),
                                Text("Won't work", style: TextStyle(color: Color(0xFFFF8C00), fontSize: 11, fontWeight: FontWeight.w700)),
                              ]),
                            ),
                          ),
                      ]),
                    ),
                    if (isYouTubeUrl(_urlCtrl.text)) ...[
                      const SizedBox(height: 6),
                      Container(padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: const Color(0xFFFF8C00).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFFF8C00).withValues(alpha: 0.3))),
                          child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Icon(Icons.info_outline_rounded, color: Color(0xFFFF8C00), size: 14), SizedBox(width: 8),
                            Expanded(child: Text("YouTube links can't stream in apps. Tap \"Won't work\" above to learn what to use instead.", style: TextStyle(color: Color(0xFFFF8C00), fontSize: 11, height: 1.5))),
                          ])),
                    ],
                  ]),
                  const SizedBox(height: 12),
                  // Cover image URL with help button + live preview
                  Row(children: [
                    const _Label('Cover Image URL'),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _showImageHelp,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0xFF64B5F6).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF64B5F6).withValues(alpha: 0.3))),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.help_outline_rounded, color: Color(0xFF64B5F6), size: 13),
                          SizedBox(width: 4),
                          Text('How to get a free image link', style: TextStyle(color: Color(0xFF64B5F6), fontSize: 10, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)),
                    child: TextField(
                      controller: _artCtrl,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: const InputDecoration(
                        hintText: 'https://i.imgur.com/xxxxx.jpg  (optional)',
                        hintStyle: TextStyle(color: Colors.white24, fontSize: 13),
                        prefixIcon: Icon(Icons.image_outlined, color: Colors.white38, size: 18),
                        border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  if (_artCtrl.text.trim().startsWith('http')) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      const Text('Preview: ', style: TextStyle(color: Colors.white38, fontSize: 11)),
                      const SizedBox(width: 8),
                      ClipRRect(borderRadius: BorderRadius.circular(8),
                          child: Image.network(_artCtrl.text.trim(), width: 52, height: 52, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(width: 52, height: 52, color: Colors.white10, child: const Icon(Icons.broken_image_rounded, color: Colors.white24)))),
                    ]),
                  ],
                  const SizedBox(height: 16),
                  const _Label('Mood'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: _moods.map((m) {
                      final sel = _mood == m;
                      final mc  = moodCfg(m);
                      return GestureDetector(
                        onTap: () => setState(() => _mood = m),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: sel ? mc.accent : Colors.white10,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: sel ? mc.accent : Colors.white24),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(moodIcon(m), size: 14, color: sel ? Colors.white : Colors.white54),
                            const SizedBox(width: 5),
                            Text(m, style: TextStyle(color: sel ? Colors.white : Colors.white54, fontSize: 12, fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
                          ]),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white24), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        onPressed: () => setState(() { _adding = false; _titleCtrl.clear(); _artistCtrl.clear(); _urlCtrl.clear(); _artCtrl.clear(); }),
                        child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF1493), foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add Song', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        onPressed: _addSong,
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),
          Row(children: [
            const Text('SONG LIBRARY', style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 3, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('${kSongs.length} tracks', style: const TextStyle(color: Colors.white24, fontSize: 11)),
          ]),
          const SizedBox(height: 12),

          ...kSongs.map((song) {
            final mc      = moodCfg(song['mood'] ?? 'Joyful');
            final isAsset = song['isAsset'] == 'true';
            final isYT    = song['isYouTube'] == 'true';
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                leading: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), gradient: LinearGradient(colors: mc.gradient)),
                  child: Center(child: Icon(moodIcon(song['mood'] ?? 'Joyful'), color: Colors.white, size: 20)),
                ),
                title: Text(song['title'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                subtitle: Wrap(
                  spacing: 6, runSpacing: 4,
                  children: [
                    Text(song['artist'] ?? '', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                    _Chip(song['mood'] ?? '', mc.accent),
                    if (isAsset) _Chip('BUILT-IN', Colors.white24),
                    if (isYT)    _Chip('YouTube', const Color(0xFFFF0000)),
                  ],
                ),
                trailing: isAsset
                    ? const Icon(Icons.lock_outline_rounded, color: Colors.white24, size: 18)
                    : IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22),
                  tooltip: 'Delete song',
                  onPressed: () => _confirmDelete(song), // Fix 2: confirm delete
                ),
              ),
            );
          }),

          const SizedBox(height: 16),
          const Center(child: Text('Built-in songs cannot be deleted.', style: TextStyle(color: Colors.white24, fontSize: 12))),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip(this.label, this.color);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}

class _AdminField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label, hint;
  final IconData icon;
  const _AdminField({required this.ctrl, required this.label, required this.hint, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty) ...[_Label(label), const SizedBox(height: 6)],
        Container(
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)),
          child: TextField(
            controller: ctrl,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: hint, hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
              prefixIcon: Icon(icon, color: Colors.white38, size: 18),
              border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HOME PAGE  — User Fix 1: animated mood background
//              User Fix 2: mini player on playlists tab
//              User Fix 7: playing indicator on song list
// ─────────────────────────────────────────────────────────────────────────────

class AuraHomePage extends StatefulWidget {
  const AuraHomePage({super.key});
  @override
  State<AuraHomePage> createState() => _AuraHomePageState();
}

class _AuraHomePageState extends State<AuraHomePage> with SingleTickerProviderStateMixin {
  final _searchCtrl = TextEditingController();
  late TabController _tabCtrl;
  int _curIdx = 0;
  String _selMood = 'All';
  String _searchQ  = '';
  bool   _playing  = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    globalPlayer.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() => _playing = state.playing);
      if (state.processingState == ProcessingState.completed) _playNextInQueue();
    });
    currentMoodNotifier.addListener(_rebuild);
    currentSongNotifier.addListener(_rebuild);
  }

  void _rebuild() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    currentMoodNotifier.removeListener(_rebuild);
    currentSongNotifier.removeListener(_rebuild);
    _searchCtrl.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }

  void _playNextInQueue() {
    if (_currentQueue.isEmpty) return;
    _currentQueueIdx = (_currentQueueIdx + 1) % _currentQueue.length;
    _playSongFromQueue(_currentQueueIdx);
  }

  Future<void> _playSongFromQueue(int idx) async {
    if (idx < 0 || idx >= _currentQueue.length) return;
    _currentQueueIdx = idx;
    final song    = _currentQueue[idx];
    final newMood = song['mood'] ?? 'Joyful';
    currentMoodNotifier.value = newMood;
    currentSongNotifier.value = song;
    final gi = kSongs.indexWhere((s) => s['title'] == song['title']);
    if (mounted) setState(() { if (gi != -1) _curIdx = gi; });
    try {
      await globalPlayer.stop();
      final local = downloadedPaths[song['title']];
      if (local != null && File(local).existsSync()) {
        await globalPlayer.setAudioSource(AudioSource.file(local));
      } else if (song['isAsset'] == 'true') {
        await globalPlayer.setAudioSource(AudioSource.asset(song['path']!));
      } else {
        await globalPlayer.setAudioSource(AudioSource.uri(Uri.parse(song['path']!)));
      }
      await globalPlayer.play();
    } catch (_) {}
  }

  Future<void> _playSong(int idx) async {
    _playingFromPlaylist = false;
    _currentPlaylistName = null;
    _currentQueue = List.from(kSongs);
    await _playSongFromQueue(idx);
  }

  Future<void> _playFromPlaylist(Playlist pl, int idx) async {
    _playingFromPlaylist = true;
    _currentPlaylistName = pl.name;
    _currentQueue = List.from(pl.songs);
    await _playSongFromQueue(idx);
  }

  void _next() {
    if (_currentQueue.isEmpty) return;
    _currentQueueIdx = (_currentQueueIdx + 1) % _currentQueue.length;
    _playSongFromQueue(_currentQueueIdx);
  }

  void _prev() {
    if (_currentQueue.isEmpty) return;
    _currentQueueIdx = (_currentQueueIdx - 1 + _currentQueue.length) % _currentQueue.length;
    _playSongFromQueue(_currentQueueIdx);
  }

  void _openNowPlaying(List<Map<String, String>> list, int idx) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, a1, a2) => NowPlayingPage(
          songList: list, initialIndex: idx, globalIdx: _curIdx,
          onIndexChanged: (gi, _) { if (mounted) setState(() => _curIdx = gi); },
        ),
        transitionsBuilder: (_, a1, __, child) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
              .animate(CurvedAnimation(parent: a1, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    );
  }

  void _createPlaylistDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('New Playlist', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: _Field(ctrl: ctrl, hint: 'Playlist name', icon: Icons.playlist_add_rounded),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                setState(() => globalPlaylists.add(Playlist(id: DateTime.now().toString(), name: ctrl.text.trim())));
                Navigator.pop(context);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _deletePlaylist(Playlist pl) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Playlist', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: Text('Delete "${pl.name}"?', style: const TextStyle(color: Colors.white60)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () { setState(() => globalPlaylists.remove(pl)); Navigator.pop(context); },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // Fix 5: Filter out songs already in playlist
  void _addToPlaylistSheet({Map<String, String>? preSelected, Playlist? targetPlaylist}) {
    final selected = <int>{};
    if (preSelected != null) {
      final i = kSongs.indexWhere((s) => s['title'] == preSelected['title']);
      if (i != -1) selected.add(i);
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) {
        return StatefulBuilder(
          builder: (ctx, ss) {
            return DraggableScrollableSheet(
              initialChildSize: 0.7, minChildSize: 0.4, maxChildSize: 0.95, expand: false,
              builder: (_, sc) {
                return Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(height: 16),
                    const Text('Add to Playlist', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17)),
                    const SizedBox(height: 4),
                    if (targetPlaylist != null)
                      Text('Selecting for "${targetPlaylist.name}"', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        controller: sc, itemCount: kSongs.length,
                        itemBuilder: (_, i) {
                          final s    = kSongs[i];
                          final sel  = selected.contains(i);
                          final mc   = moodCfg(s['mood']!);
                          // Fix 5: mark already-added songs
                          final alreadyIn = targetPlaylist != null && targetPlaylist.songs.any((e) => e['title'] == s['title']);
                          return ListTile(
                            leading: Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), gradient: LinearGradient(colors: mc.gradient)),
                              child: sel ? const Icon(Icons.check_rounded, color: Colors.white, size: 20) : null,
                            ),
                            title: Text(s['title']!, style: TextStyle(color: alreadyIn ? Colors.white38 : Colors.white, fontSize: 14)),
                            subtitle: Text(
                              alreadyIn ? '${s['artist']!} · Already added' : s['artist']!,
                              style: TextStyle(color: alreadyIn ? Colors.white24 : Colors.white38, fontSize: 12),
                            ),
                            trailing: alreadyIn ? const Icon(Icons.check_circle_rounded, color: Colors.white24, size: 18) : null,
                            enabled: !alreadyIn,
                            onTap: alreadyIn ? null : () => ss(() => sel ? selected.remove(i) : selected.add(i)),
                          );
                        },
                      ),
                    ),
                    if (selected.isNotEmpty)
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white, foregroundColor: Colors.black,
                              minimumSize: const Size(double.infinity, 50),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: () {
                              if (targetPlaylist != null) {
                                for (final i in selected) {
                                  final s = kSongs[i];
                                  if (!targetPlaylist.songs.any((e) => e['title'] == s['title'])) {
                                    targetPlaylist.songs.add(s);
                                  }
                                }
                                notifyPlaylistChanged();
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Added ${selected.length} song${selected.length == 1 ? '' : 's'} to "${targetPlaylist.name}"'), backgroundColor: Colors.white24),
                                );
                              } else {
                                if (globalPlaylists.isEmpty) { Navigator.pop(context); _createPlaylistDialog(); return; }
                                Navigator.pop(context);
                                _pickPlaylistSheet(selected.map((i) => kSongs[i]).toList());
                              }
                            },
                            child: Text('Add ${selected.length} song${selected.length == 1 ? '' : 's'}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void _pickPlaylistSheet(List<Map<String, String>> songs) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            const Text('Choose Playlist', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17)),
            const SizedBox(height: 8),
            ...globalPlaylists.map((pl) {
              return ListTile(
                leading: const Icon(Icons.queue_music_rounded, color: Colors.white54),
                title: Text(pl.name, style: const TextStyle(color: Colors.white)),
                subtitle: Text('${pl.songs.length} songs', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                onTap: () {
                  for (final s in songs) {
                    if (!pl.songs.any((e) => e['title'] == s['title'])) pl.songs.add(s);
                  }
                  notifyPlaylistChanged();
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added to "${pl.name}"'), backgroundColor: Colors.white24));
                },
              );
            }),
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  void _profileSheet() {
    final user = FirebaseAuth.instance.currentUser;
    final initial = (user?.displayName?.isNotEmpty == true ? user!.displayName![0] : user?.email?[0] ?? 'A').toUpperCase();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72, height: 72,
                decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFF6A0572), Color(0xFFFF1493)])),
                child: Center(child: Text(initial, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800))),
              ),
              const SizedBox(height: 12),
              Text(user?.displayName ?? 'AuraHub User', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(user?.email ?? '', style: const TextStyle(color: Colors.white38, fontSize: 13)),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity, height: 50,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.redAccent), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 20),
                  label: const Text('Sign Out', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700, fontSize: 15)),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (dlg) => AlertDialog(
                        backgroundColor: const Color(0xFF1E1E1E),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        title: const Text('Sign Out', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        content: const Text('Are you sure you want to sign out?', style: TextStyle(color: Colors.white60, fontSize: 14)),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(dlg), child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                            onPressed: () async {
                              Navigator.pop(dlg);
                              Navigator.pop(context);
                              await globalPlayer.stop();
                              await GoogleSignIn().signOut();
                              await FirebaseAuth.instance.signOut();
                            },
                            child: const Text('Sign Out'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user     = FirebaseAuth.instance.currentUser;
    final curMood  = currentMoodNotifier.value;
    final curSong  = currentSongNotifier.value;
    final curColors = moodCfg(curMood).gradient;
    final initial  = (user?.displayName?.isNotEmpty == true ? user!.displayName![0] : user?.email?[0] ?? 'A').toUpperCase();
    final filtered = kSongs.where((s) {
      return (_selMood == 'All' || s['mood'] == _selMood) && s['title']!.toLowerCase().contains(_searchQ.toLowerCase());
    }).toList();

    final isActive = _playing && curSong.isNotEmpty;

    return Scaffold(
      body: Stack(
        children: [
          // ── FULL MOOD BACKGROUND — entire screen changes colour ──
          AnimatedContainer(
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: isActive
                    ? [curColors[0], curColors[1]]
                    : [const Color(0xFF0A0A0A), const Color(0xFF1A1A2E)],
              ),
            ),
            child: const SizedBox.expand(),
          ),
          // ── PARTICLES — same rich engine as NowPlaying ──────────
          MoodParticles(moodName: curMood, active: isActive),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('AURA HUB', style: TextStyle(color: adaptiveText(curColors), fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 3)),
                            Text('${kSongs.length} tracks', style: TextStyle(color: adaptiveText(curColors, secondary: true), fontSize: 12)),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: _profileSheet,
                        child: Container(
                          width: 40, height: 40,
                          decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFF6A0572), Color(0xFFFF1493)])),
                          child: Center(child: Text(initial, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800))),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isActive ? Colors.white.withValues(alpha: 0.15) : Colors.white10,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: TabBar(
                      controller: _tabCtrl,
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicator: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                      labelColor: isActive ? (adaptiveText(curColors) == Colors.white ? Colors.black : Colors.white) : Colors.black,
                      unselectedLabelColor: isActive ? adaptiveText(curColors, secondary: true) : Colors.white54,
                      labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      dividerColor: Colors.transparent,
                      tabs: const [Tab(text: 'Songs'), Tab(text: 'Library')],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: TabBarView(
                    controller: _tabCtrl,
                    children: [
                      _SongsTab(
                        filtered: filtered, selMood: _selMood, searchCtrl: _searchCtrl,
                        onMoodChange: (m) => setState(() => _selMood = m),
                        onSearch: (v) => setState(() => _searchQ = v),
                        onTap: (i) { _playSong(i); _openNowPlaying(kSongs, i); },
                        onLongPress: (s) => _addToPlaylistSheet(preSelected: s),
                        currentSong: curSong,
                        colors: curColors,        // ADD THIS
                        isActive: isActive,       // ADD THIS
                      ),
                      // Fix 2: pass mini player builder to library tab
                      _LibraryTab(
                        playlists: globalPlaylists,
                        downloadedSongs: kSongs.where((s) => isDownloaded(s['title']!)).toList(),
                        onCreate: _createPlaylistDialog,
                        onDelete: _deletePlaylist,
                        onAddSongs: _addToPlaylistSheet,
                        onPlay: (pl, i) { _playFromPlaylist(pl, i); _openNowPlaying(pl.songs, i); },
                        onPlayDownloaded: (s) {
                          final idx = kSongs.indexWhere((x) => x['title'] == s['title']);
                          if (idx != -1) { _playSong(idx); _openNowPlaying(kSongs, idx); }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      // Fix 2: global mini player visible on both tabs
      bottomNavigationBar: StreamBuilder<PlayerState>(
        stream: globalPlayer.playerStateStream,
        builder: (_, snap) {
          final isIdle = snap.data == null || snap.data!.processingState == ProcessingState.idle;
          if (isIdle || curSong.isEmpty) return const SizedBox.shrink();
          return MiniPlayer(
            song: curSong, colors: curColors,
            playlistName: _playingFromPlaylist ? _currentPlaylistName : null,
            onTap: () => _openNowPlaying(_currentQueue, _currentQueueIdx),
            onNext: _next, onPrev: _prev,
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SONGS TAB  — Fix 7: playing indicator per tile
// ─────────────────────────────────────────────────────────────────────────────

class _SongsTab extends StatelessWidget {
  final List<Map<String, String>> filtered;
  final String selMood;
  final TextEditingController searchCtrl;
  final ValueChanged<String> onMoodChange, onSearch;
  final void Function(int) onTap;
  final void Function(Map<String, String>) onLongPress;
  final Map<String, String> currentSong;

  final List<Color> colors;
  final bool isActive;

  const _SongsTab({
    required this.filtered, required this.selMood, required this.searchCtrl,
    required this.onMoodChange, required this.onSearch, required this.onTap,
    required this.onLongPress, required this.currentSong,
    required this.colors,      // ADD
    required this.isActive,    // ADD
  });

  @override
  Widget build(BuildContext context) {
    final moods = ['All', 'Joyful', 'Calm', 'Melancholic', 'Energetic', 'Romantic', 'Rock'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            decoration: BoxDecoration(
              color: isActive ? Colors.white.withValues(alpha: 0.15) : Colors.white10,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: isActive ? Colors.white24 : Colors.white12),
            ),
            child: TextField(
              controller: searchCtrl,
              style: TextStyle(color: adaptiveText(colors)),
              decoration: InputDecoration(
                hintText: 'Search songs...', hintStyle: TextStyle(color: adaptiveText(colors, secondary: true)),
                prefixIcon: Icon(Icons.search, color: adaptiveText(colors, secondary: true)),
                border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
              onChanged: onSearch,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 42,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: moods.length,
            itemBuilder: (_, i) {
              final m   = moods[i];
              final sel = selMood == m;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => onMoodChange(m),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel ? Colors.white : Colors.white10,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: sel ? Colors.white : Colors.white24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (m != 'All') ...[Icon(moodIcon(m), size: 14, color: sel ? Colors.black : Colors.white54), const SizedBox(width: 5)],
                        Text(m, style: TextStyle(color: sel ? Colors.black : Colors.white54, fontSize: 13, fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text('${filtered.length} TRACKS', style: TextStyle(color: adaptiveText(colors, secondary: true), fontSize: 11, letterSpacing: 3, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: filtered.length,
            itemBuilder: (_, i) {
              final s  = filtered[i];
              final gi = kSongs.indexWhere((x) => x['title'] == s['title']);
              // Fix 7: pass isPlaying flag
              final isPlaying = currentSong['title'] == s['title'];
              return _SongTile(song: s, onTap: () => onTap(gi), onLongPress: () => onLongPress(s), isPlaying: isPlaying);
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LIBRARY TAB  — Replaces _PlaylistsTab; adds Downloaded section + fix 2
// ─────────────────────────────────────────────────────────────────────────────

class _LibraryTab extends StatelessWidget {
  final List<Playlist> playlists;
  final List<Map<String, String>> downloadedSongs;
  final VoidCallback onCreate;
  final void Function(Playlist) onDelete;
  final void Function({Map<String, String>? preSelected, Playlist? targetPlaylist}) onAddSongs;
  final void Function(Playlist, int) onPlay;
  final void Function(Map<String, String>) onPlayDownloaded;

  const _LibraryTab({
    required this.playlists, required this.downloadedSongs,
    required this.onCreate, required this.onDelete, required this.onAddSongs,
    required this.onPlay, required this.onPlayDownloaded,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: playlistChangeNotifier,
      builder: (_, __, ___) {
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            // ── Downloaded Section ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
              child: Row(children: [
                const Icon(Icons.download_done_rounded, color: Colors.white38, size: 16),
                const SizedBox(width: 6),
                const Text('DOWNLOADED', style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 3, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('${downloadedSongs.length} songs', style: const TextStyle(color: Colors.white24, fontSize: 11)),
              ]),
            ),
            if (downloadedSongs.isEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.symmetric(vertical: 24),
                decoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: 0.06))),
                child: const Column(
                  children: [
                    Icon(Icons.cloud_download_outlined, color: Colors.white12, size: 40),
                    SizedBox(height: 10),
                    Text('No downloaded songs', style: TextStyle(color: Colors.white38, fontSize: 14)),
                    SizedBox(height: 4),
                    Text('Download songs from the Songs tab', style: TextStyle(color: Colors.white24, fontSize: 12)),
                  ],
                ),
              )
            else
              ...downloadedSongs.map((s) {
                final mc = moodCfg(s['mood']!);
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withValues(alpha: 0.06))),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: s['isAsset'] == 'true'
                          ? Image.asset(s['art']!, width: 44, height: 44, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _ArtFallback(mc: mc, song: s))
                          : _ArtFallback(mc: mc, song: s),
                    ),
                    title: Text(s['title']!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                    subtitle: Text(s['artist']!, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                    trailing: const Icon(Icons.download_done_rounded, color: Colors.greenAccent, size: 20),
                    onTap: () => onPlayDownloaded(s),
                  ),
                );
              }),

            const SizedBox(height: 8),
            const Divider(color: Colors.white12),
            const SizedBox(height: 8),

            // ── Playlists Section ───────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(children: [
                const Icon(Icons.queue_music_rounded, color: Colors.white38, size: 16),
                const SizedBox(width: 6),
                Text('${playlists.length} PLAYLISTS', style: const TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 3, fontWeight: FontWeight.w600)),
                const Spacer(),
                GestureDetector(
                  onTap: onCreate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                    child: const Row(children: [
                      Icon(Icons.add, color: Colors.black, size: 16),
                      SizedBox(width: 4),
                      Text('New', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700, fontSize: 13)),
                    ]),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            if (playlists.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: const Column(
                  children: [
                    Icon(Icons.library_music_rounded, color: Colors.white12, size: 56),
                    SizedBox(height: 12),
                    Text('No playlists yet', style: TextStyle(color: Colors.white38, fontSize: 15)),
                    SizedBox(height: 6),
                    Text('Tap "New" to create your first playlist', style: TextStyle(color: Colors.white24, fontSize: 12)),
                  ],
                ),
              )
            else
              ...playlists.map((pl) {
                final mc = pl.songs.isNotEmpty ? moodCfg(pl.songs[0]['mood']!) : moodCfg('Joyful');
                return GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlaylistDetailPage(playlist: pl, onPlay: onPlay, onAddSongs: () => onAddSongs(targetPlaylist: pl)))),
                  onLongPress: () => onDelete(pl),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: 0.06))),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(children: [
                        Container(
                          width: 52, height: 52,
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), gradient: LinearGradient(colors: mc.gradient)),
                          child: pl.songs.isNotEmpty
                              ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.asset(pl.songs[0]['art']!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.queue_music_rounded, color: Colors.white)),
                          )
                              : const Icon(Icons.queue_music_rounded, color: Colors.white, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(pl.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                              const SizedBox(height: 3),
                              // Fix 6: reactive song count
                              ValueListenableBuilder<int>(
                                valueListenable: playlistChangeNotifier,
                                builder: (_, __, ___) => Text('${pl.songs.length} song${pl.songs.length == 1 ? '' : 's'}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: Colors.white30),
                      ]),
                    ),
                  ),
                );
              }),
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SONG TILE  — Fix 7: isPlaying waveform indicator
// ─────────────────────────────────────────────────────────────────────────────

class _SongTile extends StatelessWidget {
  final Map<String, String> song;
  final VoidCallback onTap, onLongPress;
  final bool isPlaying;
  const _SongTile({required this.song, required this.onTap, required this.onLongPress, this.isPlaying = false});

  @override
  Widget build(BuildContext context) {
    final title   = song['title']!;
    final mc      = moodCfg(song['mood']!);
    final isAsset = song['isAsset'] == 'true';

    return ValueListenableBuilder<Map<String, double>>(
      valueListenable: downloadProgress,
      builder: (_, progress, __) {
        final downloading = progress.containsKey(title);
        final dlProg      = progress[title] ?? 0.0;
        final downloaded  = isDownloaded(title);

        return GestureDetector(
          onTap: onTap,
          onLongPress: onLongPress,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: isPlaying ? mc.accent.withValues(alpha: 0.15) : const Color(0xFF111111),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isPlaying ? mc.accent.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: isAsset
                            ? Image.asset(song['art']!, width: 52, height: 52, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _ArtFallback(mc: mc, song: song))
                            : (song['art']!.startsWith('http')
                            ? Image.network(song['art']!, width: 52, height: 52, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _ArtFallback(mc: mc, song: song))
                            : _ArtFallback(mc: mc, song: song)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title,
                              style: TextStyle(color: isPlaying ? Colors.white : Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Text(song['artist']!, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                          ],
                        ),
                      ),
                      // Fix 7: live waveform if this song is playing
                      if (isPlaying) ...[
                        const SizedBox(width: 8),
                        StreamBuilder<PlayerState>(
                          stream: globalPlayer.playerStateStream,
                          builder: (_, snap) => WaveformBars(playing: snap.data?.playing ?? false, color: mc.accent),
                        ),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: mc.accent.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                          child: Text(song['mood']!, style: TextStyle(color: mc.accent, fontSize: 11, fontWeight: FontWeight.w700)),
                        ),
                      ],
                      if (!isAsset) ...[
                        const SizedBox(width: 8),
                        if (downloading)
                          SizedBox(width: 28, height: 28, child: CircularProgressIndicator(value: dlProg, color: mc.accent, strokeWidth: 2.5))
                        else if (downloaded)
                          const Icon(Icons.download_done_rounded, color: Colors.greenAccent, size: 26)
                        else
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            icon: Icon(Icons.download_rounded, color: mc.accent, size: 26),
                            onPressed: () => downloadSong(song),
                          ),
                      ],
                    ],
                  ),
                ),
                if (downloading)
                  LinearProgressIndicator(value: dlProg, backgroundColor: Colors.white10, valueColor: AlwaysStoppedAnimation<Color>(mc.accent), minHeight: 3),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ArtFallback extends StatelessWidget {
  final MoodConfig mc;
  final Map<String, String> song;
  const _ArtFallback({required this.mc, required this.song});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52, height: 52,
      decoration: BoxDecoration(gradient: LinearGradient(colors: mc.gradient)),
      child: Center(child: Icon(moodIcon(song['mood']!), color: Colors.white, size: 24)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PLAYLIST DETAIL  — Fix 3: rename playlist
//                   Fix 4: add more songs button always visible
//                   Fix 5: skip already-added songs
//                   Fix 6: reactive count via notifier
// ─────────────────────────────────────────────────────────────────────────────

class PlaylistDetailPage extends StatefulWidget {
  final Playlist playlist;
  final void Function(Playlist, int) onPlay;
  final VoidCallback onAddSongs;

  const PlaylistDetailPage({super.key, required this.playlist, required this.onPlay, required this.onAddSongs});

  @override
  State<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends State<PlaylistDetailPage> {
  bool _selectMode = false;
  final Set<int> _selected = {};

  @override
  void initState() { super.initState(); playlistChangeNotifier.addListener(_rebuild); }
  @override
  void dispose() { playlistChangeNotifier.removeListener(_rebuild); super.dispose(); }
  void _rebuild() { if (mounted) setState(() {}); }

  void _toggleSelect(int i) { setState(() => _selected.contains(i) ? _selected.remove(i) : _selected.add(i)); }
  void _toggleSelectMode() { setState(() { _selectMode = !_selectMode; _selected.clear(); }); }

  void _removeSelected() {
    final toRemove = _selected.toList()..sort((a, b) => b.compareTo(a));
    setState(() {
      for (final i in toRemove) widget.playlist.songs.removeAt(i);
      _selected.clear();
      _selectMode = false;
    });
    notifyPlaylistChanged();
  }

  void _confirmRemove() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Remove Songs', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: Text('Remove ${_selected.length} song${_selected.length == 1 ? '' : 's'} from "${widget.playlist.name}"?', style: const TextStyle(color: Colors.white60, fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () { Navigator.pop(context); _removeSelected(); },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  // Fix 3: Rename playlist dialog
  void _renamePlaylist() {
    final ctrl = TextEditingController(text: widget.playlist.name);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Rename Playlist', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: _Field(ctrl: ctrl, hint: 'New playlist name', icon: Icons.edit_rounded),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                setState(() => widget.playlist.name = ctrl.text.trim());
                notifyPlaylistChanged();
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pl = widget.playlist;
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0,
        leading: _selectMode
            ? IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white), onPressed: _toggleSelectMode)
            : IconButton(
          icon: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18)),
          onPressed: () => Navigator.pop(context),
        ),
        title: _selectMode
            ? Text('${_selected.length} selected', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))
            : GestureDetector(
          onTap: _renamePlaylist, // Fix 3: tap name to rename
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(pl.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              const Icon(Icons.edit_outlined, color: Colors.white38, size: 16),
            ],
          ),
        ),
        actions: [
          if (!_selectMode) ...[
            // Fix 4: Add songs button always visible
            IconButton(
              icon: const Icon(Icons.add_rounded, color: Colors.white70),
              tooltip: 'Add songs',
              onPressed: widget.onAddSongs,
            ),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline_rounded, color: Colors.white54),
              tooltip: 'Remove songs',
              onPressed: _toggleSelectMode,
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // Song count header — Fix 6: always live
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Row(children: [
              ValueListenableBuilder<int>(
                valueListenable: playlistChangeNotifier,
                builder: (_, __, ___) => Text(
                  '${pl.songs.length} song${pl.songs.length == 1 ? '' : 's'}',
                  style: const TextStyle(color: Colors.white38, fontSize: 12, letterSpacing: 1),
                ),
              ),
            ]),
          ),
          Expanded(
            child: pl.songs.isEmpty
                ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.music_off_rounded, color: Colors.white12, size: 64),
                  const SizedBox(height: 16),
                  const Text('No songs yet', style: TextStyle(color: Colors.white38)),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    icon: const Icon(Icons.add_rounded),
                    onPressed: widget.onAddSongs,
                    label: const Text('Add Songs', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: pl.songs.length,
              itemBuilder: (_, i) {
                final s   = pl.songs[i];
                final mc  = moodCfg(s['mood']!);
                final sel = _selected.contains(i);
                return GestureDetector(
                  onTap: _selectMode ? () => _toggleSelect(i) : () => widget.onPlay(pl, i),
                  onLongPress: () { if (!_selectMode) _toggleSelectMode(); _toggleSelect(i); },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: sel ? mc.accent.withValues(alpha: 0.2) : const Color(0xFF111111),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: sel ? mc.accent : Colors.white.withValues(alpha: 0.06)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          if (_selectMode)
                            Container(
                              margin: const EdgeInsets.only(right: 10),
                              width: 24, height: 24,
                              decoration: BoxDecoration(shape: BoxShape.circle, color: sel ? mc.accent : Colors.white12, border: Border.all(color: sel ? mc.accent : Colors.white24)),
                              child: sel ? const Icon(Icons.check_rounded, color: Colors.white, size: 16) : null,
                            ),
                          Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), gradient: LinearGradient(colors: mc.gradient)),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.asset(s['art']!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(moodIcon(s['mood']!), color: Colors.white, size: 20)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s['title']!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                                Text(s['artist']!, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      // Fix 4: always show "Add more songs" footer button
      bottomNavigationBar: _selectMode && _selected.isNotEmpty
          ? SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent, foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.delete_rounded),
            label: Text('Remove ${_selected.length} song${_selected.length == 1 ? '' : 's'}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            onPressed: _confirmRemove,
          ),
        ),
      )
          : SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white24),
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.add_rounded, color: Colors.white54),
            label: const Text('Add more songs', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w600)),
            onPressed: widget.onAddSongs,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MINI PLAYER
// ─────────────────────────────────────────────────────────────────────────────

class MiniPlayer extends StatelessWidget {
  final Map<String, String> song;
  final List<Color> colors;
  final String? playlistName;
  final VoidCallback onTap, onNext, onPrev;

  const MiniPlayer({super.key, required this.song, required this.colors, this.playlistName, required this.onTap, required this.onNext, required this.onPrev});

  @override
  Widget build(BuildContext context) {
    if (song.isEmpty) return const SizedBox.shrink();
    final isAsset = song['isAsset'] == 'true';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: colors[0].withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 8))],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: isAsset
                    ? Image.asset(song['art'] ?? '', width: 44, height: 44, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 44, height: 44, color: Colors.white10))
                    : (song['art']?.startsWith('http') == true
                    ? Image.network(song['art']!, width: 44, height: 44, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 44, height: 44, color: Colors.white10))
                    : Container(width: 44, height: 44, color: Colors.white10)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(song['title'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(playlistName ?? song['artist'] ?? '', style: const TextStyle(color: Colors.white60, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              IconButton(icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 24), onPressed: onPrev, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
              const SizedBox(width: 4),
              StreamBuilder<PlayerState>(
                stream: globalPlayer.playerStateStream,
                builder: (_, snap) {
                  final playing = snap.data?.playing ?? false;
                  return IconButton(
                    icon: Icon(playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded, color: Colors.white, size: 40),
                    onPressed: () => playing ? globalPlayer.pause() : globalPlayer.play(),
                    padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                  );
                },
              ),
              const SizedBox(width: 4),
              IconButton(icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 24), onPressed: onNext, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NOW PLAYING  — Fix 1: mood-adaptive background already handled globally
// ─────────────────────────────────────────────────────────────────────────────

class NowPlayingPage extends StatefulWidget {
  final List<Map<String, String>> songList;
  final int initialIndex, globalIdx;
  final void Function(int globalIdx, String mood) onIndexChanged;

  const NowPlayingPage({super.key, required this.songList, required this.initialIndex, required this.globalIdx, required this.onIndexChanged});

  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage> with SingleTickerProviderStateMixin {
  late int _idx;
  late Map<String, String> _song;
  late List<Color> _colors;
  late AnimationController _artCtrl;
  late Animation<double> _artScale;

  @override
  void initState() {
    super.initState();
    _idx    = widget.initialIndex;
    _song   = widget.songList[_idx];
    _colors = moodCfg(_song['mood']!).gradient;
    _artCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _artScale = Tween<double>(begin: 0.85, end: 1.0).animate(CurvedAnimation(parent: _artCtrl, curve: Curves.easeOutBack));
    _artCtrl.forward();
    globalPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed && mounted) _playAt((_idx + 1) % widget.songList.length);
    });
  }

  @override
  void dispose() { _artCtrl.dispose(); super.dispose(); }

  Future<void> _playAt(int idx) async {
    if (idx < 0 || idx >= widget.songList.length) return;
    _artCtrl.reset();
    final s       = widget.songList[idx];
    final newMood = s['mood'] ?? 'Joyful';
    setState(() { _idx = idx; _song = s; _colors = moodCfg(newMood).gradient; });
    _currentQueueIdx = idx;
    currentMoodNotifier.value = newMood;
    currentSongNotifier.value = s;
    try {
      await globalPlayer.stop();
      final local = downloadedPaths[s['title']];
      if (local != null && File(local).existsSync()) {
        await globalPlayer.setAudioSource(AudioSource.file(local));
      } else if (s['isAsset'] == 'true') {
        await globalPlayer.setAudioSource(AudioSource.asset(s['path']!));
      } else {
        await globalPlayer.setAudioSource(AudioSource.uri(Uri.parse(s['path']!)));
      }
      await globalPlayer.play();
    } catch (_) {}
    _artCtrl.forward();
    final gi = kSongs.indexWhere((k) => k['title'] == s['title']);
    widget.onIndexChanged(gi != -1 ? gi : widget.globalIdx, newMood);
  }

  void _next() => _playAt((_idx + 1) % widget.songList.length);
  void _prev() => _playAt((_idx - 1 + widget.songList.length) % widget.songList.length);

  String _fmt(Duration d) =>
      '${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final isAsset = _song['isAsset'] == 'true';
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0, centerTitle: true,
        leading: IconButton(
          icon: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 22)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('NOW PLAYING', style: TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 4, fontWeight: FontWeight.w600)),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 500), curve: Curves.easeInOut,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [_colors[0], _colors[1], Colors.black],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
          MoodParticles(moodName: _song['mood'] ?? 'Joyful', active: true),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 20),
                Expanded(
                  child: Center(
                    child: ScaleTransition(
                      scale: _artScale,
                      child: Container(
                        width: 280, height: 280,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [BoxShadow(color: _colors[0].withValues(alpha: 0.5), blurRadius: 40, offset: const Offset(0, 20))],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: isAsset
                              ? Image.asset(_song['art']!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: _colors[0]))
                              : (_song['art']?.startsWith('http') == true
                              ? Image.network(_song['art']!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: _colors[0]))
                              : Container(color: _colors[0])),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_song['title']!, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            Text(_song['artist']!, style: const TextStyle(color: Colors.white60, fontSize: 15)),
                          ],
                        ),
                      ),
                      StreamBuilder<PlayerState>(
                        stream: globalPlayer.playerStateStream,
                        builder: (_, snap) => WaveformBars(playing: snap.data?.playing ?? false, color: _colors[0]),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: StreamBuilder<Duration>(
                    stream: globalPlayer.positionStream,
                    builder: (_, snap) {
                      final pos = snap.data ?? Duration.zero;
                      final dur = globalPlayer.duration ?? Duration.zero;
                      return Column(
                        children: [
                          Slider(
                            value: dur.inMilliseconds > 0 ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0) : 0.0,
                            onChanged: (v) => globalPlayer.seek(Duration(milliseconds: (v * dur.inMilliseconds).round())),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_fmt(pos), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                Text(_fmt(dur), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 36), onPressed: _prev, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                      StreamBuilder<PlayerState>(
                        stream: globalPlayer.playerStateStream,
                        builder: (_, snap) {
                          final playing = snap.data?.playing ?? false;
                          return IconButton(
                            icon: Icon(playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded, color: Colors.white, size: 72),
                            onPressed: () => playing ? globalPlayer.pause() : globalPlayer.play(),
                            padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                          );
                        },
                      ),
                      IconButton(icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 36), onPressed: _next, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// WAVEFORM BARS
// ─────────────────────────────────────────────────────────────────────────────

class WaveformBars extends StatefulWidget {
  final bool playing;
  final Color color;
  const WaveformBars({super.key, required this.playing, required this.color});
  @override
  State<WaveformBars> createState() => _WaveformBarsState();
}

class _WaveformBarsState extends State<WaveformBars> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (!widget.playing) {
      return SizedBox(
        width: 24, height: 16,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(4, (_) => Container(width: 3, height: 4, decoration: BoxDecoration(color: widget.color.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(2)))),
        ),
      );
    }
    return SizedBox(
      width: 24, height: 16,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(4, (i) {
            final h = 4 + 12 * (0.4 + 0.6 * math.sin(_ctrl.value * math.pi + i * 0.8).abs());
            return Container(width: 3, height: h, decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(2)));
          }),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.w600));
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox({required this.message});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(message, style: const TextStyle(color: Colors.redAccent, fontSize: 13))),
      ]),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final IconData icon;
  final bool obs;
  final Widget? suffix;
  final TextInputType? type;

  const _Field({required this.ctrl, required this.hint, required this.icon, this.obs = false, this.suffix, this.type});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: TextField(
        controller: ctrl, obscureText: obs, keyboardType: type,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint, hintStyle: const TextStyle(color: Colors.white24),
          prefixIcon: Icon(icon, color: Colors.white38, size: 20),
          suffixIcon: suffix, border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }
}

class _BigBtn extends StatelessWidget {
  final String label;
  final bool loading, disabled;
  final VoidCallback? onTap;
  const _BigBtn({required this.label, required this.loading, required this.disabled, this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity, height: 54,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0),
        onPressed: disabled ? null : onTap,
        child: loading
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
            : Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _HelpTile extends StatelessWidget {
  final String title, body;
  const _HelpTile(this.title, this.body);
  @override Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
        const SizedBox(height: 3),
        Text(body,  style: const TextStyle(color: Colors.white54, fontSize: 11, height: 1.5)),
      ]));
}