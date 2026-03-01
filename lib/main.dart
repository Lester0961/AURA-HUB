import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'firebase_options.dart';

final AudioPlayer globalPlayer = AudioPlayer();

// Global playback queue — shared between home and playlist playback
List<Map<String, String>> _currentQueue = [];
int _currentQueueIdx = 0;
bool _playingFromPlaylist = false;
String? _currentPlaylistName;

// ValueNotifiers — home rebuilds reactively even while NowPlaying is on top
final ValueNotifier<String> currentMoodNotifier = ValueNotifier<String>('Joyful');
final ValueNotifier<Map<String, String>> currentSongNotifier = ValueNotifier<Map<String, String>>({});

// Global playlists — survive sign-out/sign-in cycles
final List<Playlist> globalPlaylists = [];

// Notifier to force PlaylistDetailPage to rebuild when songs are added externally
final ValueNotifier<int> playlistChangeNotifier = ValueNotifier<int>(0);
void notifyPlaylistChanged() => playlistChangeNotifier.value++;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  _currentQueue = List.from(kSongs);
  runApp(const AuraHubApp());
}

/* ===================== SONG LIST ===================== */

final List<Map<String, String>> kSongs = [
  {'title': 'Happy',     'artist': 'Aura Collective', 'mood': 'Joyful',
    'path': 'assets/audio/Happy.mp3',      'art': 'assets/images/happy_art.png'},
  {'title': 'Sad',       'artist': 'Aura Collective', 'mood': 'Melancholic',
    'path': 'assets/audio/Sad.mp3',        'art': 'assets/images/sad_art.png'},
  {'title': 'Calm',      'artist': 'Aura Collective', 'mood': 'Calm',
    'path': 'assets/audio/Calm.mp3',       'art': 'assets/images/calm_art.png'},
  {'title': 'Energetic', 'artist': 'Aura Collective', 'mood': 'Energetic',
    'path': 'assets/audio/Energetic.mp3',  'art': 'assets/images/energetic_art.png'},
  {'title': 'Romantic',  'artist': 'Aura Collective', 'mood': 'Romantic',
    'path': 'assets/audio/Love.mp3',       'art': 'assets/images/love_art.png'},
  {'title': 'Rock',      'artist': 'Aura Collective', 'mood': 'Rock',
    'path': 'assets/audio/Rock.mp3',       'art': 'assets/images/rock_art.png'},
];

/* ===================== PLAYLIST MODEL ===================== */

class Playlist {
  final String id;
  String name;
  final List<Map<String, String>> songs;
  Playlist({required this.id, required this.name, List<Map<String, String>>? songs})
      : songs = songs ?? [];
}

/* ===================== MOOD CONFIG ===================== */

class MoodConfig {
  final List<Color> gradient;
  final Color primary;
  final Color particle;
  final String shape;
  final int count;
  final double speed;
  const MoodConfig({required this.gradient, required this.primary,
    required this.particle, required this.shape,
    required this.count, required this.speed});
}

const Map<String, MoodConfig> kMoods = {
  'Joyful': MoodConfig(
      gradient: [Color(0xFFFF6B35), Color(0xFFFF1493)],
      primary: Color(0xFFFF6B35), particle: Color(0xFFFFD700),
      shape: 'star', count: 28, speed: 1.6),
  'Calm': MoodConfig(
      gradient: [Color(0xFF0F3460), Color(0xFF16C79A)],
      primary: Color(0xFF16C79A), particle: Color(0xFF7FFFD4),
      shape: 'drop', count: 16, speed: 0.45),
  'Melancholic': MoodConfig(
      gradient: [Color(0xFF1A1A2E), Color(0xFF6A0572)],
      primary: Color(0xFF6A0572), particle: Color(0xFFCE93D8),
      shape: 'circle', count: 20, speed: 0.55),
  'Energetic': MoodConfig(
      gradient: [Color(0xFF0052D4), Color(0xFFFFD700)],
      primary: Color(0xFF0052D4), particle: Color(0xFFFFD700),
      shape: 'bolt', count: 30, speed: 2.5),
  'Romantic': MoodConfig(
      gradient: [Color(0xFF8B0000), Color(0xFFFF69B4)],
      primary: Color(0xFFFF69B4), particle: Color(0xFFFF69B4),
      shape: 'heart', count: 22, speed: 0.9),
  'Rock': MoodConfig(
      gradient: [Color(0xFF1C1C1C), Color(0xFF434343)],
      primary: Color(0xFFFF4500), particle: Color(0xFFFF4500),
      shape: 'bolt', count: 26, speed: 2.2),
};

MoodConfig mood(String m) => kMoods[m] ?? const MoodConfig(
    gradient: [Color(0xFF1A1A1A), Color(0xFF2D2D2D)],
    primary: Color(0xFF555555), particle: Color(0x55FFFFFF),
    shape: 'circle', count: 10, speed: 0.5);

/* ===================== PARTICLE ENGINE ===================== */

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
    final cfg = mood(m);
    _ps = List.generate(cfg.count, (_) {
      final angle = _rng.nextDouble() * math.pi * 2;
      final spd = (0.001 + _rng.nextDouble() * 0.003) * cfg.speed;
      return _P(
        x: _rng.nextDouble(), y: _rng.nextDouble(),
        vx: math.cos(angle) * spd * 0.3, vy: -spd,
        size: 5 + _rng.nextDouble() * 14,
        opacity: 0.25 + _rng.nextDouble() * 0.65,
        phase: _rng.nextDouble() * math.pi * 2,
        rot: _rng.nextDouble() * math.pi * 2,
        rotSpeed: (_rng.nextDouble() - 0.5) * 0.04,
      );
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
    final cfg = mood(_lastMood);
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
      final x = (p.x + p.vx * t * 120 + math.sin(t * math.pi * 2 + p.phase) * 0.035) % 1.0;
      final dx = x * sz.width;
      final dy = y * sz.height;
      final pulse = 0.6 + 0.4 * math.sin(t * math.pi * 4 + p.phase);
      final paint = Paint()
        ..color = color.withValues(alpha: (p.opacity * pulse).clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;

      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(p.rot + p.rotSpeed * t * 120);

      switch (shape) {
        case 'star': _star(canvas, p.size, paint); break;
        case 'heart': _heart(canvas, p.size, paint); break;
        case 'bolt': _bolt(canvas, p.size, paint); break;
        case 'drop': _drop(canvas, p.size, paint); break;
        default:
          canvas.drawCircle(Offset.zero, p.size / 2, paint);
          canvas.drawCircle(Offset.zero, p.size * 0.8,
              Paint()..color = color.withValues(alpha: (p.opacity * pulse * 0.3).clamp(0.0, 1.0))
                ..style = PaintingStyle.stroke ..strokeWidth = 1);
      }
      canvas.restore();
    }
  }

  void _star(Canvas c, double s, Paint p) {
    final path = Path();
    for (int i = 0; i < 5; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / 5;
      final b = a + math.pi / 5;
      if (i == 0) path.moveTo(math.cos(a) * s / 2, math.sin(a) * s / 2);
      else path.lineTo(math.cos(a) * s / 2, math.sin(a) * s / 2);
      path.lineTo(math.cos(b) * s / 4, math.sin(b) * s / 4);
    }
    path.close();
    c.drawPath(path, p);
  }

  void _heart(Canvas c, double s, Paint p) {
    final path = Path();
    path.moveTo(0, s / 4);
    path.cubicTo(-s / 2, -s / 6, -s / 2, -s / 2, 0, -s / 6);
    path.cubicTo(s / 2, -s / 2, s / 2, -s / 6, 0, s / 4);
    c.drawPath(path, p);
  }

  void _bolt(Canvas c, double s, Paint p) {
    final path = Path()
      ..moveTo(s * 0.1, -s / 2)
      ..lineTo(-s * 0.1, -s * 0.05)
      ..lineTo(s * 0.15, -s * 0.05)
      ..lineTo(-s * 0.1, s / 2)
      ..lineTo(s * 0.3, -s * 0.1)
      ..lineTo(s * 0.05, -s * 0.1)
      ..close();
    c.drawPath(path, p);
  }

  void _drop(Canvas c, double s, Paint p) {
    final path = Path()
      ..moveTo(0, -s / 2)
      ..cubicTo(s / 3, -s / 4, s / 3, s / 4, 0, s / 2)
      ..cubicTo(-s / 3, s / 4, -s / 3, -s / 4, 0, -s / 2)
      ..close();
    c.drawPath(path, p);
  }

  @override bool shouldRepaint(_PPainter o) => o.t != t || o.color != color;
}

/* ===================== WAVEFORM BARS ===================== */

class WaveformBars extends StatefulWidget {
  final bool playing;
  final Color color;
  const WaveformBars({super.key, required this.playing, required this.color});
  @override State<WaveformBars> createState() => _WaveformBarsState();
}

class _WaveformBarsState extends State<WaveformBars> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (!widget.playing) return const SizedBox(width: 24, height: 16);
    return SizedBox(width: 24, height: 16,
        child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(4, (i) {
                  final h = 4 + 12 * (0.4 + 0.6 * math.sin(_ctrl.value * math.pi + i * 0.8).abs());
                  return Container(width: 3, height: h,
                      decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(2)));
                }))));
  }
}

/* ===================== APP ===================== */

class AuraHubApp extends StatelessWidget {
  const AuraHubApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AuraHub',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        sliderTheme: SliderThemeData(
          thumbColor: Colors.white, activeTrackColor: Colors.white,
          inactiveTrackColor: Colors.white24, overlayColor: Colors.white24,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          trackHeight: 3,
        ),
      ),
      home: StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) return const _Loader();
            return snap.hasData ? const AuraHomePage() : const LoginPage();
          }),
    );
  }
}

class _Loader extends StatelessWidget {
  const _Loader();
  @override Widget build(BuildContext context) => const Scaffold(
      backgroundColor: Colors.black,
      body: Center(child: CircularProgressIndicator(color: Colors.white)));
}

/* ===================== LOGIN PAGE ===================== */

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override State<LoginPage> createState() => _LoginPageState();
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

  @override void dispose() { _eCtrl.dispose(); _pCtrl.dispose(); _ac.dispose(); super.dispose(); }

  Future<void> _emailLogin() async {
    setState(() { _loading = true; _err = null; });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _eCtrl.text.trim(), password: _pCtrl.text.trim());
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _err = _friendly(e.code));
    } finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _googleLogin() async {
    setState(() { _gLoading = true; _err = null; });
    try {
      final gsi = GoogleSignIn();
      await gsi.signOut();
      final u = await gsi.signIn();
      if (u == null) return;
      final a = await u.authentication;
      await FirebaseAuth.instance.signInWithCredential(
          GoogleAuthProvider.credential(accessToken: a.accessToken, idToken: a.idToken));
    } catch (_) {
      if (mounted) setState(() => _err = 'Google sign-in failed. Try again.');
    } finally { if (mounted) setState(() => _gLoading = false); }
  }

  String _friendly(String c) {
    switch (c) {
      case 'user-not-found': return 'No account with this email.';
      case 'wrong-password': case 'invalid-credential': return 'Invalid email or password.';
      case 'invalid-email': return 'Enter a valid email.';
      case 'too-many-requests': return 'Too many attempts. Try later.';
      default: return 'Something went wrong.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _loading || _gLoading;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF0A0A0A), Color(0xFF1A0A2E), Color(0xFF0A0A0A)])),
        child: SafeArea(child: FadeTransition(opacity: _fa,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 60),
                Center(child: Column(children: [
                  Container(width: 80, height: 80,
                      decoration: BoxDecoration(shape: BoxShape.circle,
                          gradient: const LinearGradient(colors: [Color(0xFF6A0572), Color(0xFFFF1493)]),
                          boxShadow: [BoxShadow(color: const Color(0xFFFF1493).withValues(alpha: 0.4),
                              blurRadius: 24, spreadRadius: 4)]),
                      child: const Center(child: Text('A',
                          style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900)))),
                  const SizedBox(height: 16),
                  const Text('AURAHUB', style: TextStyle(color: Colors.white,
                      fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 6)),
                  const SizedBox(height: 4),
                  const Text('feel the music', style: TextStyle(color: Colors.white38, fontSize: 12, letterSpacing: 3)),
                ])),
                const SizedBox(height: 48),
                // SUGGESTION 4: Changed "Welcome back" to "Welcome"
                const Text('Welcome', style: TextStyle(color: Colors.white,
                    fontSize: 28, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text('Sign in to continue', style: TextStyle(color: Colors.white38, fontSize: 14)),
                const SizedBox(height: 28),
                if (_err != null) ...[
                  Container(padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4))),
                      child: Row(children: [
                        const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_err!, style: const TextStyle(color: Colors.redAccent, fontSize: 13))),
                      ])),
                  const SizedBox(height: 16),
                ],
                // SUGGESTION 5: Label above text fields
                const Text('Email', style: TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                _Field(ctrl: _eCtrl, hint: 'Enter your email', icon: Icons.email_outlined,
                    type: TextInputType.emailAddress),
                const SizedBox(height: 16),
                const Text('Password', style: TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                _Field(ctrl: _pCtrl, hint: 'Enter your password', icon: Icons.lock_outline_rounded, obs: _obs,
                    suffix: IconButton(icon: Icon(_obs ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: Colors.white38, size: 20), onPressed: () => setState(() => _obs = !_obs))),
                const SizedBox(height: 28),
                _BigBtn(label: 'Sign In', loading: _loading, disabled: busy, onTap: _emailLogin),
                const SizedBox(height: 14),
                Row(children: [Expanded(child: Divider(color: Colors.white12)),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('or', style: TextStyle(color: Colors.white38))),
                  Expanded(child: Divider(color: Colors.white12))]),
                const SizedBox(height: 14),
                SizedBox(width: double.infinity, height: 54,
                    child: OutlinedButton(
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white24),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                        onPressed: busy ? null : _googleLogin,
                        child: _gLoading
                            ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Container(width: 24, height: 24,
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
                              child: const Center(child: Text('G', style: TextStyle(
                                  color: Color(0xFF4285F4), fontWeight: FontWeight.w900, fontSize: 16)))),
                          const SizedBox(width: 12),
                          const Text('Continue with Google', style: TextStyle(
                              color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                        ]))),
                const SizedBox(height: 32),
                Center(child: GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterPage())),
                    child: RichText(text: const TextSpan(
                        text: "Don't have an account? ",
                        style: TextStyle(color: Colors.white38, fontSize: 14),
                        children: [TextSpan(text: 'Create one',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700,
                                decoration: TextDecoration.underline))])))),
                const SizedBox(height: 40),
              ]),
            ))),
      ),
    );
  }
}

/* ===================== REGISTER PAGE ===================== */

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override State<RegisterPage> createState() => _RegisterPageState();
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

  // BUG 4 FIX: After registration, sign out immediately and show success dialog
  Future<void> _register() async {
    if (_pCtrl.text != _cCtrl.text) { setState(() => _err = 'Passwords do not match.'); return; }
    if (_pCtrl.text.length < 6) { setState(() => _err = 'Password must be at least 6 characters.'); return; }
    setState(() { _loading = true; _err = null; });
    try {
      final c = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _eCtrl.text.trim(), password: _pCtrl.text.trim());
      await c.user?.updateDisplayName(_nCtrl.text.trim());
      // Immediately sign out so user is not auto-logged in
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(children: [
              Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 24),
              SizedBox(width: 10),
              Text('Account Created!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
            ]),
            content: const Text(
              'Your account has been created successfully. Please sign in with your credentials.',
              style: TextStyle(color: Colors.white60, fontSize: 14),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white, foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () {
                  Navigator.pop(context); // close dialog
                  Navigator.pop(context); // go back to login
                },
                child: const Text('Go to Sign In', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _err = _friendly(e.code));
    } finally { if (mounted) setState(() => _loading = false); }
  }

  String _friendly(String c) {
    switch (c) {
      case 'email-already-in-use': return 'Account with this email already exists.';
      case 'invalid-email': return 'Enter a valid email.';
      case 'weak-password': return 'Password too weak.';
      default: return 'Something went wrong.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: Colors.black,
      body: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF0A0A0A), Color(0xFF0A1A2E), Color(0xFF0A0A0A)])),
        child: SafeArea(child: FadeTransition(opacity: _fa,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 24),
                GestureDetector(onTap: () => Navigator.pop(context),
                    child: Container(padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18))),
                const SizedBox(height: 32),
                const Text('Create Account', style: TextStyle(color: Colors.white,
                    fontSize: 28, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text('Join AuraHub and feel the music',
                    style: TextStyle(color: Colors.white38, fontSize: 14)),
                const SizedBox(height: 32),
                if (_err != null) ...[
                  Container(padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4))),
                      child: Row(children: [
                        const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_err!, style: const TextStyle(color: Colors.redAccent, fontSize: 13))),
                      ])),
                  const SizedBox(height: 16),
                ],
                // SUGGESTION 5: Labels above fields on register page too
                const Text('Full Name', style: TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                _Field(ctrl: _nCtrl, hint: 'Enter your full name', icon: Icons.person_outline_rounded),
                const SizedBox(height: 16),
                const Text('Email', style: TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                _Field(ctrl: _eCtrl, hint: 'Enter your email', icon: Icons.email_outlined,
                    type: TextInputType.emailAddress),
                const SizedBox(height: 16),
                const Text('Password', style: TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                _Field(ctrl: _pCtrl, hint: 'Create a password', icon: Icons.lock_outline_rounded, obs: _obs,
                    suffix: IconButton(icon: Icon(_obs ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: Colors.white38, size: 20), onPressed: () => setState(() => _obs = !_obs))),
                const SizedBox(height: 16),
                const Text('Confirm Password', style: TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                _Field(ctrl: _cCtrl, hint: 'Repeat your password', icon: Icons.lock_outline_rounded, obs: _obsC,
                    suffix: IconButton(icon: Icon(_obsC ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: Colors.white38, size: 20), onPressed: () => setState(() => _obsC = !_obsC))),
                const SizedBox(height: 28),
                _BigBtn(label: 'Create Account', loading: _loading, disabled: _loading, onTap: _register),
                const SizedBox(height: 24),
                Center(child: GestureDetector(onTap: () => Navigator.pop(context),
                    child: RichText(text: const TextSpan(
                        text: 'Already have an account? ',
                        style: TextStyle(color: Colors.white38, fontSize: 14),
                        children: [TextSpan(text: 'Sign in',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700,
                                decoration: TextDecoration.underline))])))),
                const SizedBox(height: 40),
              ]),
            ))),
      ),
    );
  }
}

/* ===================== SHARED WIDGETS ===================== */

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final IconData icon;
  final bool obs;
  final Widget? suffix;
  final TextInputType? type;
  const _Field({required this.ctrl, required this.hint, required this.icon,
    this.obs = false, this.suffix, this.type});
  @override
  Widget build(BuildContext context) => Container(
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white12)),
      child: TextField(controller: ctrl, obscureText: obs, keyboardType: type,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          decoration: InputDecoration(hintText: hint, hintStyle: const TextStyle(color: Colors.white30),
              prefixIcon: Icon(icon, color: Colors.white38, size: 20), suffixIcon: suffix,
              border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16))));
}

class _BigBtn extends StatelessWidget {
  final String label;
  final bool loading, disabled;
  final VoidCallback onTap;
  const _BigBtn({required this.label, required this.loading, required this.disabled, required this.onTap});
  @override
  Widget build(BuildContext context) => SizedBox(width: double.infinity, height: 54,
      child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black,
              elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          onPressed: disabled ? null : onTap,
          child: loading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
              : Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))));
}

/* ===================== HOME ===================== */

class AuraHomePage extends StatefulWidget {
  const AuraHomePage({super.key});
  @override State<AuraHomePage> createState() => _AuraHomePageState();
}

class _AuraHomePageState extends State<AuraHomePage> with SingleTickerProviderStateMixin {
  final _searchCtrl = TextEditingController();
  late TabController _tabCtrl;

  int _curIdx = 0;
  String _selMood = 'All';
  String _searchQ = '';
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);

    // Listen to global player state
    globalPlayer.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() => _playing = state.playing);
      if (state.processingState == ProcessingState.completed) {
        _playNextInQueue();
      }
    });

    // React to mood/song changes immediately — even when NowPlaying is on top
    currentMoodNotifier.addListener(_onMoodChanged);
    currentSongNotifier.addListener(_onSongChanged);
  }

  void _onMoodChanged() {
    if (mounted) setState(() {});
  }

  void _onSongChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    currentMoodNotifier.removeListener(_onMoodChanged);
    currentSongNotifier.removeListener(_onSongChanged);
    _searchCtrl.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }

  // BUG 2 FIX: advance within current queue (global songs OR playlist)
  void _playNextInQueue() {
    if (_currentQueue.isEmpty) return;
    _currentQueueIdx = (_currentQueueIdx + 1) % _currentQueue.length;
    _playSongFromQueue(_currentQueueIdx);
  }

  void _playPrevInQueue() {
    if (_currentQueue.isEmpty) return;
    _currentQueueIdx = (_currentQueueIdx - 1 + _currentQueue.length) % _currentQueue.length;
    _playSongFromQueue(_currentQueueIdx);
  }

  // Unified playback from current queue
  Future<void> _playSongFromQueue(int queueIdx) async {
    if (queueIdx < 0 || queueIdx >= _currentQueue.length) return;
    _currentQueueIdx = queueIdx;
    final song = _currentQueue[queueIdx];
    final newMood = song['mood'] ?? 'Joyful';

    // Push to global notifiers immediately — home reacts even if covered by NowPlaying
    currentMoodNotifier.value = newMood;
    currentSongNotifier.value = song;

    // Also update local state for curIdx tracking
    final gi = kSongs.indexWhere((s) => s['title'] == song['title']);
    if (mounted) setState(() {
      if (gi != -1) _curIdx = gi;
    });

    try {
      await globalPlayer.stop();
      await globalPlayer.setAudioSource(AudioSource.asset(song['path']!));
      await globalPlayer.play();
    } catch (_) {}
  }

  // Play from the main songs list
  Future<void> _playSong(int index) async {
    if (index < 0 || index >= kSongs.length) return;
    _currentQueue = List.from(kSongs);
    _currentQueueIdx = index;
    _playingFromPlaylist = false;
    _currentPlaylistName = null;
    await _playSongFromQueue(index);
  }

  // Play from a playlist
  Future<void> _playFromPlaylist(Playlist pl, int index) async {
    if (pl.songs.isEmpty) return;
    _currentQueue = List.from(pl.songs);
    _currentQueueIdx = index;
    _playingFromPlaylist = true;
    _currentPlaylistName = pl.name;
    await _playSongFromQueue(index);
  }

  void _next() => _playNextInQueue();
  void _prev() => _playPrevInQueue();

  IconData _moodIcon(String m) {
    switch (m) {
      case 'Joyful': return Icons.wb_sunny_rounded;
      case 'Calm': return Icons.water_rounded;
      case 'Melancholic': return Icons.nights_stay_rounded;
      case 'Energetic': return Icons.bolt_rounded;
      case 'Romantic': return Icons.favorite_rounded;
      case 'Rock': return Icons.music_note_rounded;
      default: return Icons.queue_music_rounded;
    }
  }

  void _createPlaylistDialog() {
    final c = TextEditingController();
    showDialog(context: context, builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('New Playlist', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: TextField(controller: c, autofocus: true, style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(hintText: 'Playlist name...', hintStyle: const TextStyle(color: Colors.white38),
                filled: true, fillColor: Colors.white10,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.white,
              foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: () {
                final name = c.text.trim();
                if (name.isNotEmpty) {
                  setState(() => globalPlaylists.add(Playlist(
                      id: DateTime.now().millisecondsSinceEpoch.toString(), name: name)));
                  Navigator.pop(context);
                }
              }, child: const Text('Create')),
        ]));
  }

  // SUGGESTION 2: Multi-select sheet — select multiple songs at once
  void _multiSelectAddToPlaylistSheet({Map<String, String>? preSelectedSong}) {
    final Set<String> selected = preSelectedSong != null ? {preSelectedSong['title']!} : {};
    Playlist? targetPlaylist;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(builder: (ctx, set) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.92,
          minChildSize: 0.4,
          builder: (_, scrollCtrl) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Handle bar
              Center(child: Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Add to Playlist', style: TextStyle(color: Colors.white,
                    fontSize: 18, fontWeight: FontWeight.w700)),
                GestureDetector(onTap: () { Navigator.pop(context); _createPlaylistDialog(); },
                    child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                        child: const Row(children: [
                          Icon(Icons.add, color: Colors.black, size: 16), SizedBox(width: 4),
                          Text('New', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700, fontSize: 13)),
                        ]))),
              ]),
              const SizedBox(height: 12),
              // Choose playlist
              if (globalPlaylists.isEmpty)
                const Padding(padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('No playlists yet. Create one!', style: TextStyle(color: Colors.white38)))
              else Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Select playlist:', style: TextStyle(color: Colors.white54, fontSize: 13)),
                const SizedBox(height: 8),
                SizedBox(height: 44,
                  child: ListView(scrollDirection: Axis.horizontal, children: globalPlaylists.map((pl) {
                    final isSel = targetPlaylist?.id == pl.id;
                    return Padding(padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(onTap: () => set(() => targetPlaylist = pl),
                            child: AnimatedContainer(duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                    color: isSel ? Colors.white : Colors.white10,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: isSel ? Colors.white : Colors.white24)),
                                child: Text(pl.name, style: TextStyle(
                                    color: isSel ? Colors.black : Colors.white70,
                                    fontWeight: isSel ? FontWeight.w700 : FontWeight.w400,
                                    fontSize: 13)))));
                  }).toList()),
                ),
              ]),
              const SizedBox(height: 16),
              const Text('Select songs:', style: TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 8),
              Expanded(child: ListView.builder(
                controller: scrollCtrl,
                itemCount: kSongs.length,
                itemBuilder: (_, i) {
                  final s = kSongs[i];
                  final mc = mood(s['mood']!);
                  final isChecked = selected.contains(s['title']);
                  // Already in target playlist — disable selection
                  final alreadyAdded = targetPlaylist != null &&
                      targetPlaylist!.songs.any((x) => x['title'] == s['title']);
                  return GestureDetector(
                    onTap: alreadyAdded ? null : () => set(() {
                      if (isChecked) selected.remove(s['title']!);
                      else selected.add(s['title']!);
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: alreadyAdded
                            ? Colors.white.withValues(alpha: 0.02)
                            : isChecked
                            ? Colors.white.withValues(alpha: 0.12)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: alreadyAdded
                                ? Colors.white10
                                : isChecked ? Colors.white38 : Colors.white10),
                      ),
                      child: Row(children: [
                        // Checkbox / already-added indicator
                        AnimatedContainer(duration: const Duration(milliseconds: 200),
                            width: 24, height: 24,
                            decoration: BoxDecoration(
                                color: alreadyAdded
                                    ? Colors.white12
                                    : isChecked ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: alreadyAdded
                                        ? Colors.white24
                                        : isChecked ? Colors.white : Colors.white38,
                                    width: 2)),
                            child: alreadyAdded
                                ? const Icon(Icons.check_rounded, color: Colors.white38, size: 16)
                                : isChecked
                                ? const Icon(Icons.check_rounded, color: Colors.black, size: 16)
                                : null),
                        const SizedBox(width: 12),
                        Opacity(
                          opacity: alreadyAdded ? 0.38 : 1.0,
                          child: ClipRRect(borderRadius: BorderRadius.circular(8),
                              child: Image.asset(s['art']!, width: 44, height: 44, fit: BoxFit.cover)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(s['title']!, style: TextStyle(
                              color: alreadyAdded ? Colors.white38 : Colors.white,
                              fontWeight: FontWeight.w600, fontSize: 14)),
                          Text(alreadyAdded ? 'Already in playlist' : s['artist']!,
                              style: TextStyle(
                                  color: alreadyAdded ? Colors.white24 : Colors.white54,
                                  fontSize: 12)),
                        ])),
                        if (!alreadyAdded)
                          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(gradient: LinearGradient(colors: mc.gradient),
                                  borderRadius: BorderRadius.circular(20)),
                              child: Text(s['mood']!, style: const TextStyle(
                                  color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600))),
                      ]),
                    ),
                  );
                },
              )),
              const SizedBox(height: 12),
              // Confirm button
              SizedBox(width: double.infinity, height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white, foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      disabledBackgroundColor: Colors.white24),
                  onPressed: (selected.isEmpty || targetPlaylist == null ||
                      selected.every((title) => targetPlaylist!.songs.any((s) => s['title'] == title)))
                      ? null : () {
                    final pl = globalPlaylists.firstWhere((p) => p.id == targetPlaylist!.id);
                    int added = 0;
                    for (final title in selected) {
                      final song = kSongs.firstWhere((s) => s['title'] == title);
                      if (!pl.songs.any((s) => s['title'] == title)) {
                        pl.songs.add(song);
                        added++;
                      }
                    }
                    setState(() {});
                    notifyPlaylistChanged(); // rebuild PlaylistDetailPage immediately
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(added == 0 ? 'Songs already in playlist'
                            : 'Added $added song${added == 1 ? '' : 's'} to ${pl.name}'),
                        backgroundColor: const Color(0xFF2A2A2A),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        duration: const Duration(seconds: 2)));
                  },
                  child: Builder(builder: (_) {
                    // Count only selected songs that are NOT already in the playlist
                    final addableCount = targetPlaylist == null ? selected.length
                        : selected.where((title) =>
                    !targetPlaylist!.songs.any((s) => s['title'] == title)).length;
                    String label;
                    if (selected.isEmpty) {
                      label = 'Select songs to add';
                    } else if (targetPlaylist == null) {
                      label = 'Select a playlist';
                    } else if (addableCount == 0) {
                      label = 'All selected songs already added';
                    } else {
                      label = 'Add $addableCount song${addableCount == 1 ? '' : 's'}';
                    }
                    return Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700));
                  }),
                ),
              ),
              const SizedBox(height: 20),
            ]),
          ),
        );
      }),
    );
  }

  void _deletePlaylist(Playlist pl) {
    showDialog(context: context, builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Playlist', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: Text('Delete "${pl.name}"?', style: const TextStyle(color: Colors.white60)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: () { setState(() => globalPlaylists.remove(pl)); Navigator.pop(context); },
              child: const Text('Delete')),
        ]));
  }

  // SUGGESTION 3: Confirmation dialog before sign out
  // BUG 3 FIX: Stop player on sign out
  void _profileSheet() {
    final user = FirebaseAuth.instance.currentUser;
    showModalBottomSheet(context: context, backgroundColor: const Color(0xFF1E1E1E),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => Padding(padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 72, height: 72,
                  decoration: const BoxDecoration(shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [Color(0xFF6A0572), Color(0xFFFF1493)])),
                  child: Center(child: Text(
                      (user?.displayName?.isNotEmpty == true ? user!.displayName![0] : user?.email?[0] ?? 'A').toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)))),
              const SizedBox(height: 12),
              Text(user?.displayName ?? 'AuraHub User',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(user?.email ?? '', style: const TextStyle(color: Colors.white38, fontSize: 13)),
              const SizedBox(height: 28),
              SizedBox(width: double.infinity, height: 50,
                  child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.redAccent),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                      icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 20),
                      label: const Text('Sign Out', style: TextStyle(color: Colors.redAccent,
                          fontWeight: FontWeight.w700, fontSize: 15)),
                      onPressed: () {
                        // SUGGESTION 3: Show confirmation before signing out
                        showDialog(
                          context: context,
                          builder: (dialogCtx) => AlertDialog(
                            backgroundColor: const Color(0xFF1E1E1E),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            title: const Text('Sign Out', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                            content: const Text('Are you sure you want to sign out?',
                                style: TextStyle(color: Colors.white60, fontSize: 14)),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dialogCtx),
                                child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.redAccent,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                                onPressed: () async {
                                  Navigator.pop(dialogCtx);
                                  Navigator.pop(context); // close profile sheet
                                  // BUG 3 FIX: Stop audio before signing out
                                  await globalPlayer.stop();
                                  await GoogleSignIn().signOut();
                                  await FirebaseAuth.instance.signOut();
                                },
                                child: const Text('Sign Out'),
                              ),
                            ],
                          ),
                        );
                      })),
              const SizedBox(height: 8),
            ])));
  }

  void _openNowPlaying(List<Map<String, String>> list, int index) {
    Navigator.push(context, PageRouteBuilder(
        pageBuilder: (_, a1, a2) => NowPlayingPage(
            songList: list,
            initialIndex: index,
            globalIdx: _curIdx,
            onIndexChanged: (newGlobalIdx, newMood) {
              // notifiers already updated by _playSongFromQueue;
              // just keep _curIdx in sync for song list highlight
              if (mounted) setState(() => _curIdx = newGlobalIdx);
            }),
        transitionsBuilder: (_, a1, __, child) => SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                .animate(CurvedAnimation(parent: a1, curve: Curves.easeOutCubic)),
            child: child)));
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final curMood = currentMoodNotifier.value;
    final filtered = kSongs.where((s) {
      final mMatch = _selMood == 'All' || s['mood'] == _selMood;
      final qMatch = s['title']!.toLowerCase().contains(_searchQ.toLowerCase());
      return mMatch && qMatch;
    }).toList();

    final curSong = _currentQueue.isNotEmpty ? _currentQueue[_currentQueueIdx] : kSongs[_curIdx];
    final curColors = mood(curMood).gradient;

    return Scaffold(
      body: Stack(children: [
        // ANIMATED BG — driven by ValueNotifier, updates instantly even behind NowPlaying
        AnimatedContainer(duration: const Duration(milliseconds: 700), curve: Curves.easeInOut,
            decoration: BoxDecoration(gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: _playing
                    ? [curColors[0], curColors[1]]
                    : [const Color(0xFF0A0A0A), const Color(0xFF1A1A1A)]))),

        // PARTICLES
        MoodParticles(moodName: curMood, active: _playing),

        // CONTENT
        Column(children: [
          Expanded(child: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // HEADER
            Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('AURAHUB', style: TextStyle(color: Colors.white, fontSize: 22,
                        fontWeight: FontWeight.w800, letterSpacing: 6)),
                    Text('feel the music', style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 3)),
                  ]),
                  GestureDetector(onTap: _profileSheet,
                      child: Container(width: 40, height: 40,
                          decoration: const BoxDecoration(shape: BoxShape.circle,
                              gradient: LinearGradient(colors: [Color(0xFF6A0572), Color(0xFFFF1493)])),
                          child: Center(child: Text(
                              (user?.displayName?.isNotEmpty == true ? user!.displayName![0] : user?.email?[0] ?? 'A').toUpperCase(),
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800))))),
                ])),

            const SizedBox(height: 16),

            // TABS — SUGGESTION 1: "Playlists" renamed to "Library"
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                    decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(14)),
                    child: TabBar(controller: _tabCtrl,
                        indicatorSize: TabBarIndicatorSize.tab,
                        indicator: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                        labelColor: Colors.black, unselectedLabelColor: Colors.white54,
                        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        dividerColor: Colors.transparent,
                        tabs: const [Tab(text: 'Songs'), Tab(text: 'Library')]))),

            const SizedBox(height: 12),

            Expanded(child: TabBarView(controller: _tabCtrl, children: [
              // SONGS TAB
              _SongsTab(
                filtered: filtered, songs: kSongs, selMood: _selMood,
                searchCtrl: _searchCtrl, player: globalPlayer,
                moodIcon: _moodIcon,
                onMoodChange: (m) => setState(() => _selMood = m),
                onSearch: (v) => setState(() => _searchQ = v),
                onTap: (i, s) {
                  _playSong(i);
                  _openNowPlaying(kSongs, i);
                },
                // SUGGESTION 2: Long press opens multi-select sheet
                onLongPress: (s) => _multiSelectAddToPlaylistSheet(preSelectedSong: s),
              ),

              // LIBRARY TAB (was Playlists)
              _PlaylistsTab(
                playlists: globalPlaylists,
                player: globalPlayer,
                onCreate: _createPlaylistDialog,
                onDelete: _deletePlaylist,
                onAddSongs: () => _multiSelectAddToPlaylistSheet(),
                // BUG 2 FIX: play from playlist uses _playFromPlaylist to set correct queue
                onPlay: (pl, i) {
                  _playFromPlaylist(pl, i);
                  _openNowPlaying(pl.songs, i);
                },
              ),
            ])),
          ]))),

          // MINI PLAYER — BUG 2 FIX: use playerStateStream so it always appears
          StreamBuilder<PlayerState>(
            stream: globalPlayer.playerStateStream,
            builder: (_, snap) {
              final state = snap.data;
              final isIdle = state == null ||
                  state.processingState == ProcessingState.idle;
              if (isIdle) return const SizedBox.shrink();
              return MiniPlayer(
                song: curSong,
                colors: curColors,
                playlistName: _playingFromPlaylist ? _currentPlaylistName : null,
                onTap: () => _openNowPlaying(_currentQueue, _currentQueueIdx),
                onNext: _next,
                onPrev: _prev,
              );
            },
          ),
        ]),
      ]),
    );
  }
}

/* ===================== SONGS TAB ===================== */

class _SongsTab extends StatelessWidget {
  final List<Map<String, String>> filtered, songs;
  final String selMood;
  final TextEditingController searchCtrl;
  final AudioPlayer player;
  final IconData Function(String) moodIcon;
  final ValueChanged<String> onMoodChange, onSearch;
  final void Function(int, Map<String, String>) onTap;
  final void Function(Map<String, String>) onLongPress;

  const _SongsTab({required this.filtered, required this.songs, required this.selMood,
    required this.searchCtrl, required this.player,
    required this.moodIcon, required this.onMoodChange, required this.onSearch,
    required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12)),
              child: TextField(controller: searchCtrl, style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(hintText: 'Search songs...',
                      hintStyle: TextStyle(color: Colors.white38),
                      prefixIcon: Icon(Icons.search, color: Colors.white38),
                      border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 14)),
                  onChanged: onSearch))),
      const SizedBox(height: 12),
      SizedBox(height: 42, child: ListView(scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: ['All', 'Joyful', 'Calm', 'Melancholic', 'Energetic', 'Romantic', 'Rock'].map((m) {
            final sel = selMood == m;
            return Padding(padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(onTap: () => onMoodChange(m),
                    child: AnimatedContainer(duration: const Duration(milliseconds: 250),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(color: sel ? Colors.white : Colors.white10,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: sel ? Colors.white : Colors.white24)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (m != 'All') ...[Icon(moodIcon(m), size: 14, color: sel ? Colors.black : Colors.white70), const SizedBox(width: 4)],
                          Text(m, style: TextStyle(color: sel ? Colors.black : Colors.white70,
                              fontWeight: sel ? FontWeight.w700 : FontWeight.w400, fontSize: 13)),
                        ]))));
          }).toList())),
      const SizedBox(height: 10),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text('${filtered.length} TRACKS', style: const TextStyle(
              color: Colors.white38, fontSize: 11, letterSpacing: 3, fontWeight: FontWeight.w600))),
      const SizedBox(height: 8),
      // ValueListenableBuilder drives playing highlight from the global notifier
      // so it updates instantly even when NowPlaying is on top of the stack
      Expanded(child: ValueListenableBuilder<Map<String, String>>(
        valueListenable: currentSongNotifier,
        builder: (_, curSongMap, __) {
          return ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final s = filtered[i];
                final idx = songs.indexOf(s);
                // playing = this song is the currently active song globally
                final playing = curSongMap['title'] != null &&
                    curSongMap['title'] == s['title'];
                final mc = mood(s['mood']!);
                return Padding(padding: const EdgeInsets.only(bottom: 8),
                    child: GestureDetector(
                        onTap: () => onTap(idx, s),
                        onLongPress: () => onLongPress(s),
                        child: AnimatedContainer(duration: const Duration(milliseconds: 300),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: playing ? Colors.white12 : Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: playing ? Colors.white30 : Colors.white10),
                                boxShadow: playing ? [BoxShadow(color: mc.primary.withValues(alpha: 0.25),
                                    blurRadius: 12, spreadRadius: 0)] : null),
                            child: Row(children: [
                              Container(width: 52, height: 52,
                                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(12),
                                      gradient: LinearGradient(colors: mc.gradient)),
                                  child: ClipRRect(borderRadius: BorderRadius.circular(12),
                                      child: Image.asset(s['art']!, fit: BoxFit.cover))),
                              const SizedBox(width: 14),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(s['title']!, style: TextStyle(color: Colors.white,
                                    fontWeight: playing ? FontWeight.w700 : FontWeight.w500, fontSize: 15)),
                                const SizedBox(height: 3),
                                Text(s['artist']!, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                              ])),
                              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(gradient: LinearGradient(colors: mc.gradient),
                                      borderRadius: BorderRadius.circular(20)),
                                  child: Text(s['mood']!, style: const TextStyle(
                                      color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600))),
                              const SizedBox(width: 8),
                              StreamBuilder<PlayerState>(
                                  stream: globalPlayer.playerStateStream,
                                  builder: (_, snap) => WaveformBars(
                                      playing: playing && (snap.data?.playing ?? false),
                                      color: mc.primary)),
                            ]))));
              });
        },
      )),
    ]);
  }
}

/* ===================== PLAYLISTS TAB ===================== */

class _PlaylistsTab extends StatelessWidget {
  final List<Playlist> playlists;
  final AudioPlayer player;
  final VoidCallback onCreate;
  final VoidCallback onAddSongs;
  final void Function(Playlist) onDelete;
  final void Function(Playlist, int) onPlay;

  const _PlaylistsTab({required this.playlists, required this.player,
    required this.onCreate, required this.onDelete,
    required this.onAddSongs, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.fromLTRB(20, 4, 16, 12),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('${playlists.length} PLAYLISTS', style: const TextStyle(
                color: Colors.white38, fontSize: 11, letterSpacing: 3, fontWeight: FontWeight.w600)),
            GestureDetector(onTap: onCreate,
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                    child: const Row(children: [
                      Icon(Icons.add, color: Colors.black, size: 16), SizedBox(width: 4),
                      Text('New Playlist', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700, fontSize: 13))]))),
          ])),
      Expanded(child: playlists.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.library_music_rounded, color: Colors.white12, size: 64),
        const SizedBox(height: 16),
        const Text('No playlists yet', style: TextStyle(color: Colors.white38, fontSize: 16)),
        const SizedBox(height: 8),
        const Text('Tap "New Playlist" to get started', style: TextStyle(color: Colors.white24, fontSize: 13)),
      ]))
          : ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: playlists.length,
          itemBuilder: (_, i) {
            final pl = playlists[i];
            final gi = pl.songs.isNotEmpty ? 0 : -1;
            return Padding(padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onLongPress: () {
                    showModalBottomSheet(context: context, backgroundColor: const Color(0xFF1E1E1E),
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                        builder: (_) => Padding(padding: const EdgeInsets.all(20),
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              ListTile(leading: const Icon(Icons.delete_rounded, color: Colors.redAccent),
                                  title: const Text('Delete Playlist', style: TextStyle(color: Colors.white)),
                                  onTap: () { Navigator.pop(context); onDelete(pl); }),
                            ])));
                  },
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => PlaylistDetailPage(
                          playlist: pl,
                          onPlay: (list, idx) => onPlay(pl, idx),
                          onAddSongs: onAddSongs))),
                  child: Container(padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white10)),
                      child: Row(children: [
                        ClipRRect(borderRadius: BorderRadius.circular(10),
                            child: SizedBox(width: 56, height: 56,
                                child: pl.songs.isEmpty
                                    ? Container(color: Colors.white10,
                                    child: const Icon(Icons.queue_music_rounded, color: Colors.white24))
                                    : Image.asset(pl.songs[gi >= 0 ? gi : 0]['art']!, fit: BoxFit.cover))),
                        const SizedBox(width: 14),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(pl.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                          const SizedBox(height: 3),
                          Text('${pl.songs.length} song${pl.songs.length == 1 ? '' : 's'}',
                              style: const TextStyle(color: Colors.white38, fontSize: 12))])),
                        const Icon(Icons.chevron_right_rounded, color: Colors.white30),
                      ])),
                ));
          })),
    ]);
  }
}

/* ===================== PLAYLIST DETAIL ===================== */

class PlaylistDetailPage extends StatefulWidget {
  final Playlist playlist;
  final void Function(List<Map<String, String>>, int) onPlay;
  final VoidCallback onAddSongs;
  const PlaylistDetailPage({super.key, required this.playlist, required this.onPlay, required this.onAddSongs});
  @override State<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends State<PlaylistDetailPage> {
  bool _selectMode = false;
  final Set<int> _selectedIndices = {};

  @override
  void initState() {
    super.initState();
    playlistChangeNotifier.addListener(_onPlaylistChanged);
  }

  @override
  void dispose() {
    playlistChangeNotifier.removeListener(_onPlaylistChanged);
    super.dispose();
  }

  void _onPlaylistChanged() { if (mounted) setState(() {}); }

  void _removeSelected() {
    final indices = _selectedIndices.toList()..sort((a, b) => b.compareTo(a));
    setState(() {
      for (final i in indices) widget.playlist.songs.removeAt(i);
      _selectedIndices.clear();
      _selectMode = false;
    });
    notifyPlaylistChanged();
  }

  void _toggleSelectMode() => setState(() {
    _selectMode = !_selectMode;
    _selectedIndices.clear();
  });

  void _toggleSelect(int i) => setState(() {
    if (_selectedIndices.contains(i)) _selectedIndices.remove(i);
    else _selectedIndices.add(i);
  });

  @override
  Widget build(BuildContext context) {
    final pl = widget.playlist;
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: _selectMode
            ? IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: _toggleSelectMode)
            : IconButton(
            icon: Container(padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18)),
            onPressed: () => Navigator.pop(context)),
        title: _selectMode
            ? Text('${_selectedIndices.length} selected',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18))
            : Text(pl.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
        centerTitle: true,
        actions: _selectMode
            ? [
          // Select all toggle
          IconButton(
            icon: Icon(
                _selectedIndices.length == pl.songs.length
                    ? Icons.deselect_rounded : Icons.select_all_rounded,
                color: Colors.white70),
            tooltip: _selectedIndices.length == pl.songs.length ? 'Deselect all' : 'Select all',
            onPressed: () => setState(() {
              if (_selectedIndices.length == pl.songs.length) _selectedIndices.clear();
              else _selectedIndices.addAll(List.generate(pl.songs.length, (i) => i));
            }),
          ),
          // Delete selected
          IconButton(
            icon: const Icon(Icons.delete_rounded, color: Colors.redAccent, size: 24),
            tooltip: 'Remove selected',
            onPressed: _selectedIndices.isEmpty ? null : () {
              showDialog(context: context, builder: (_) => AlertDialog(
                backgroundColor: const Color(0xFF1E1E1E),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: const Text('Remove Songs', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                content: Text(
                    'Remove ${_selectedIndices.length} song${_selectedIndices.length == 1 ? '' : 's'} from "${pl.name}"?',
                    style: const TextStyle(color: Colors.white60, fontSize: 14)),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    onPressed: () { Navigator.pop(context); _removeSelected(); },
                    child: const Text('Remove'),
                  ),
                ],
              ));
            },
          ),
        ]
            : [
          // Enter select mode
          if (pl.songs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.remove_circle_outline_rounded, color: Colors.redAccent, size: 24),
              tooltip: 'Remove songs',
              onPressed: _toggleSelectMode,
            ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.white70, size: 26),
            tooltip: 'Add songs',
            onPressed: widget.onAddSongs,
          ),
        ],
      ),
      body: pl.songs.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.music_off_rounded, color: Colors.white24, size: 64),
        const SizedBox(height: 16),
        const Text('No songs in this playlist', style: TextStyle(color: Colors.white38, fontSize: 16)),
        const SizedBox(height: 8),
        const Text('Tap + to add songs', style: TextStyle(color: Colors.white24, fontSize: 13)),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          icon: const Icon(Icons.add),
          label: const Text('Add Songs', style: TextStyle(fontWeight: FontWeight.w700)),
          onPressed: widget.onAddSongs,
        ),
      ]))
          : ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
        itemCount: pl.songs.length,
        itemBuilder: (_, i) {
          final s = pl.songs[i];
          final mc = mood(s['mood']!);
          final isSelected = _selectedIndices.contains(i);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: _selectMode
                  ? () => _toggleSelect(i)
                  : () => widget.onPlay(pl.songs, i),
              onLongPress: !_selectMode ? () {
                _toggleSelectMode();
                _toggleSelect(i);
              } : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.redAccent.withValues(alpha: 0.12)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? Colors.redAccent.withValues(alpha: 0.5) : Colors.white10,
                  ),
                ),
                child: Row(children: [
                  // Checkbox (only in select mode)
                  if (_selectMode) ...[
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 24, height: 24,
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.redAccent : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: isSelected ? Colors.redAccent : Colors.white38,
                            width: 2),
                      ),
                      child: isSelected
                          ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                          : null,
                    ),
                    const SizedBox(width: 10),
                  ],
                  ClipRRect(borderRadius: BorderRadius.circular(12),
                      child: Image.asset(s['art']!, width: 52, height: 52, fit: BoxFit.cover)),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s['title']!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 3),
                    Text(s['artist']!, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  ])),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                        gradient: LinearGradient(colors: mc.gradient),
                        borderRadius: BorderRadius.circular(20)),
                    child: Text(s['mood']!, style: const TextStyle(
                        color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
            ),
          );
        },
      ),
      // Floating remove bar when in select mode
      bottomNavigationBar: _selectMode && _selectedIndices.isNotEmpty
          ? SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.delete_rounded),
            label: Text(
              'Remove ${_selectedIndices.length} song${_selectedIndices.length == 1 ? '' : 's'}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            onPressed: () => showDialog(context: context, builder: (_) => AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('Remove Songs', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              content: Text(
                  'Remove ${_selectedIndices.length} song${_selectedIndices.length == 1 ? '' : 's'} from "${pl.name}"?',
                  style: const TextStyle(color: Colors.white60, fontSize: 14)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: () { Navigator.pop(context); _removeSelected(); },
                  child: const Text('Remove'),
                ),
              ],
            )),
          ),
        ),
      )
          : null,
    );
  }
}

/* ===================== MINI PLAYER ===================== */

class MiniPlayer extends StatelessWidget {
  final Map<String, String> song;
  final List<Color> colors;
  final String? playlistName;
  final VoidCallback onTap, onNext, onPrev;

  const MiniPlayer({super.key, required this.song, required this.colors,
    required this.onTap, required this.onNext, required this.onPrev,
    this.playlistName});

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(onTap: onTap,
        child: AnimatedContainer(duration: const Duration(milliseconds: 500), curve: Curves.easeInOut,
            decoration: BoxDecoration(
                gradient: LinearGradient(colors: [colors[0].withValues(alpha: 0.97), colors[1].withValues(alpha: 0.97)]),
                boxShadow: [BoxShadow(color: colors[0].withValues(alpha: 0.5), blurRadius: 28, offset: const Offset(0, -4))]),
            child: SafeArea(top: false, child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  // SEEK BAR
                  StreamBuilder<Duration>(stream: globalPlayer.positionStream, builder: (_, snap) {
                    final pos = snap.data ?? Duration.zero;
                    final dur = globalPlayer.duration ?? Duration.zero;
                    final progress = dur.inMilliseconds > 0
                        ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0) : 0.0;
                    return Column(children: [
                      SliderTheme(data: SliderThemeData(
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                          trackHeight: 2, overlayShape: SliderComponentShape.noOverlay),
                          child: Slider(value: progress, onChanged: (v) {
                            final seek = Duration(milliseconds: (v * dur.inMilliseconds).round());
                            globalPlayer.seek(seek);
                          })),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Text(_fmt(pos), style: const TextStyle(color: Colors.white54, fontSize: 10)),
                            Text(_fmt(dur), style: const TextStyle(color: Colors.white54, fontSize: 10)),
                          ])),
                    ]);
                  }),
                  const SizedBox(height: 4),
                  Row(children: [
                    ClipRRect(borderRadius: BorderRadius.circular(8),
                        child: Image.asset(song['art']!, width: 44, height: 44, fit: BoxFit.cover)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(song['title']!, style: const TextStyle(color: Colors.white,
                          fontWeight: FontWeight.w700, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                      // BUG 2 FIX: Show playlist name when playing from a playlist
                      if (playlistName != null)
                        Text('From: $playlistName', style: const TextStyle(color: Colors.white60, fontSize: 11),
                            maxLines: 1, overflow: TextOverflow.ellipsis)
                      else
                        Text(song['artist']!, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    ])),
                    IconButton(icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 28),
                        onPressed: onPrev, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                    StreamBuilder<PlayerState>(
                        stream: globalPlayer.playerStateStream,
                        builder: (_, snap) {
                          final pl = snap.data?.playing ?? false;
                          return IconButton(
                              icon: Icon(pl ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
                                  color: Colors.white, size: 44),
                              onPressed: () => pl ? globalPlayer.pause() : globalPlayer.play(),
                              padding: EdgeInsets.zero, constraints: const BoxConstraints());
                        }),
                    IconButton(icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 28),
                        onPressed: onNext, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                  ]),
                ])))));
  }
}

/* ===================== NOW PLAYING ===================== */

class NowPlayingPage extends StatefulWidget {
  final List<Map<String, String>> songList;
  final int initialIndex;
  final int globalIdx;
  // BUG 1 FIX: callback now passes both globalIdx AND mood so home always stays in sync
  final void Function(int globalIdx, String mood) onIndexChanged;

  const NowPlayingPage({super.key, required this.songList,
    required this.initialIndex, required this.globalIdx,
    required this.onIndexChanged});

  @override State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage> with SingleTickerProviderStateMixin {
  late int _listIdx;
  late Map<String, String> _song;
  late List<Color> _colors;
  late AnimationController _artCtrl;
  late Animation<double> _artScale;

  @override
  void initState() {
    super.initState();
    _listIdx = widget.initialIndex;
    _song = widget.songList[_listIdx];
    _colors = mood(_song['mood']!).gradient;

    _artCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _artScale = Tween<double>(begin: 0.85, end: 1.0)
        .animate(CurvedAnimation(parent: _artCtrl, curve: Curves.easeOutBack));
    _artCtrl.forward();

    // Sync NowPlaying if autoplay advances from global queue
    globalPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed && mounted) {
        // Check if global queue advanced (e.g., from home auto-advance)
        // Just advance within own list for now
        _playAt((_listIdx + 1) % widget.songList.length);
      }
    });
  }

  @override void dispose() { _artCtrl.dispose(); super.dispose(); }

  Future<void> _playAt(int listIdx) async {
    if (listIdx < 0 || listIdx >= widget.songList.length) return;
    _artCtrl.reset();

    final s = widget.songList[listIdx];
    final newMood = s['mood'] ?? 'Joyful';

    setState(() {
      _listIdx = listIdx;
      _song = s;
      _colors = mood(newMood).gradient;
    });

    // Update global queue index
    _currentQueueIdx = listIdx;

    // Push to notifiers — home page reacts immediately even while we're on top
    currentMoodNotifier.value = newMood;
    currentSongNotifier.value = s;

    try {
      await globalPlayer.stop();
      await globalPlayer.setAudioSource(AudioSource.asset(s['path']!));
      await globalPlayer.play();
    } catch (_) {}

    _artCtrl.forward();

    // Notify home of globalIdx for song list highlight
    final gi = kSongs.indexWhere((k) => k['title'] == s['title']);
    widget.onIndexChanged(gi != -1 ? gi : widget.globalIdx, newMood);
  }

  void _next() => _playAt((_listIdx + 1) % widget.songList.length);
  void _prev() => _playAt((_listIdx - 1 + widget.songList.length) % widget.songList.length);

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0,
          leading: IconButton(
              icon: Container(padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 22)),
              onPressed: () => Navigator.pop(context)),
          title: const Text('NOW PLAYING', style: TextStyle(color: Colors.white70,
              fontSize: 12, letterSpacing: 4, fontWeight: FontWeight.w600)),
          centerTitle: true),
      body: Stack(children: [
        // BG — updates per song
        AnimatedContainer(duration: const Duration(milliseconds: 500), curve: Curves.easeInOut,
            decoration: BoxDecoration(gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [_colors[0], _colors[1], Colors.black], stops: const [0.0, 0.55, 1.0]))),

        // PARTICLES
        MoodParticles(moodName: _song['mood']!, active: true),

        // CONTENT
        SafeArea(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(children: [
            const SizedBox(height: 12),

            // ALBUM ART with bounce + slide
            Expanded(child: Center(
                child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    transitionBuilder: (child, anim) {
                      final slide = Tween<Offset>(begin: const Offset(0.15, 0), end: Offset.zero)
                          .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));
                      return SlideTransition(position: slide,
                          child: FadeTransition(opacity: anim, child: child));
                    },
                    child: ScaleTransition(scale: _artScale,
                        child: Container(
                            key: ValueKey(_song['title']),
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(28),
                                boxShadow: [
                                  BoxShadow(color: _colors[0].withValues(alpha: 0.7),
                                      blurRadius: 60, spreadRadius: 8, offset: const Offset(0, 16)),
                                  BoxShadow(color: _colors[1].withValues(alpha: 0.3),
                                      blurRadius: 30, spreadRadius: 2),
                                ]),
                            child: ClipRRect(borderRadius: BorderRadius.circular(28),
                                child: Image.asset(_song['art']!, fit: BoxFit.cover,
                                    width: MediaQuery.of(context).size.width * 0.78,
                                    height: MediaQuery.of(context).size.width * 0.78))))))),

            const SizedBox(height: 28),

            // SONG INFO
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_song['title']!, style: const TextStyle(color: Colors.white,
                    fontSize: 28, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(_song['artist']!, style: const TextStyle(color: Colors.white60, fontSize: 16)),
              ])),
              Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24)),
                  child: Text(_song['mood']!, style: const TextStyle(
                      color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600))),
            ]),

            const SizedBox(height: 24),

            // PROGRESS
            StreamBuilder<Duration>(stream: globalPlayer.positionStream, builder: (_, snap) {
              final pos = snap.data ?? Duration.zero;
              final dur = globalPlayer.duration ?? Duration.zero;
              final progress = dur.inMilliseconds > 0
                  ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0) : 0.0;
              return Column(children: [
                Slider(value: progress.toDouble(), onChanged: (v) {
                  final seek = Duration(milliseconds: (v * dur.inMilliseconds).round());
                  globalPlayer.seek(seek);
                }),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(_fmt(pos), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      Text(_fmt(dur), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    ])),
              ]);
            }),

            const SizedBox(height: 16),

            // CONTROLS
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              IconButton(icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 36),
                  onPressed: _prev, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
              StreamBuilder<PlayerState>(
                  stream: globalPlayer.playerStateStream,
                  builder: (_, snap) {
                    final pl = snap.data?.playing ?? false;
                    return GestureDetector(
                      onTap: () => pl ? globalPlayer.pause() : globalPlayer.play(),
                      child: AnimatedContainer(duration: const Duration(milliseconds: 200),
                          width: 72, height: 72,
                          decoration: BoxDecoration(shape: BoxShape.circle,
                              color: Colors.white,
                              boxShadow: [BoxShadow(color: Colors.white.withValues(alpha: 0.4),
                                  blurRadius: pl ? 28 : 0, spreadRadius: pl ? 4 : 0)]),
                          child: Icon(pl ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: Colors.black, size: 36)),
                    );
                  }),
              IconButton(icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 36),
                  onPressed: _next, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
            ]),

            const SizedBox(height: 32),
          ]),
        )),
      ]),
    );
  }
}