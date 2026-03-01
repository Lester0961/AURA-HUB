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
  const MoodConfig({required this.gradient, required this.accent});
}

MoodConfig moodCfg(String m) {
  switch (m) {
    case 'Joyful':      return MoodConfig(gradient: [const Color(0xFFFF6B35), const Color(0xFFFF8E53)], accent: const Color(0xFFFF6B35));
    case 'Melancholic': return MoodConfig(gradient: [const Color(0xFF2C3E7A), const Color(0xFF4A5BA0)], accent: const Color(0xFF4A5BA0));
    case 'Calm':        return MoodConfig(gradient: [const Color(0xFF00695C), const Color(0xFF00897B)], accent: const Color(0xFF00897B));
    case 'Energetic':   return MoodConfig(gradient: [const Color(0xFFE53935), const Color(0xFFFF5722)], accent: const Color(0xFFFF5722));
    case 'Romantic':    return MoodConfig(gradient: [const Color(0xFF880E4F), const Color(0xFFAD1457)], accent: const Color(0xFFAD1457));
    case 'Rock':        return MoodConfig(gradient: [const Color(0xFF212121), const Color(0xFF424242)], accent: const Color(0xFF757575));
    default:            return MoodConfig(gradient: [const Color(0xFF1A1A2E), const Color(0xFF16213E)], accent: Colors.white);
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

// ─────────────────────────────────────────────────────────────────────────────
// MAIN
// ─────────────────────────────────────────────────────────────────────────────

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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
    _eCtrl.dispose();
    _pCtrl.dispose();
    _ac.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() { _loading = true; _err = null; });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _eCtrl.text.trim(),
        password: _pCtrl.text.trim(),
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
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
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
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(colors: [Color(0xFF6A0572), Color(0xFFFF1493)]),
                          ),
                          child: const Center(
                            child: Text('♪', style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900)),
                          ),
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
                    ctrl: _pCtrl, hint: 'Enter your password',
                    icon: Icons.lock_outline_rounded, obs: _obs,
                    suffix: IconButton(
                      icon: Icon(_obs ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.white38, size: 20),
                      onPressed: () => setState(() => _obs = !_obs),
                    ),
                  ),
                  const SizedBox(height: 28),
                  _BigBtn(label: 'Sign In', loading: _loading, disabled: _loading || _gLoading, onTap: _login),
                  const SizedBox(height: 16),
                  const Row(
                    children: [
                      Expanded(child: Divider(color: Colors.white12)),
                      Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('or', style: TextStyle(color: Colors.white38, fontSize: 13))),
                      Expanded(child: Divider(color: Colors.white12)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity, height: 54,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white24),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
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
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 24),
                SizedBox(width: 10),
                Text('Account Created!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
              ],
            ),
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
                  _Field(
                    ctrl: _pCtrl, hint: 'Create a password', icon: Icons.lock_outline_rounded, obs: _obs,
                    suffix: IconButton(
                      icon: Icon(_obs ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.white38, size: 20),
                      onPressed: () => setState(() => _obs = !_obs),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const _Label('Confirm Password'),
                  const SizedBox(height: 6),
                  _Field(
                    ctrl: _cCtrl, hint: 'Repeat your password', icon: Icons.lock_outline_rounded, obs: _obsC,
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
// ADMIN PAGE
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

  void _addSong() {
    final title  = _titleCtrl.text.trim();
    final url    = _urlCtrl.text.trim();
    if (title.isEmpty || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Title and MP3 URL are required.'), backgroundColor: Colors.redAccent));
      return;
    }
    setState(() {
      kSongs.add({
        'title':   title,
        'artist':  _artistCtrl.text.trim().isEmpty ? 'Aura Collective' : _artistCtrl.text.trim(),
        'mood':    _mood,
        'path':    url,
        'art':     _artCtrl.text.trim().isEmpty ? 'assets/images/happy_art.png' : _artCtrl.text.trim(),
        'isAsset': 'false',
      });
      _currentQueue = List.from(kSongs);
      _titleCtrl.clear(); _artistCtrl.clear(); _urlCtrl.clear(); _artCtrl.clear();
      _mood = 'Joyful';
      _adding = false;
    });
    saveSongs();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('"$title" added!'), backgroundColor: Colors.greenAccent.shade700));
  }

  void _confirmDelete(Map<String, String> song) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Song', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: Text('Delete "${song['title']}"?', style: const TextStyle(color: Colors.white60, fontSize: 14)),
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
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.admin_panel_settings_rounded, color: Color(0xFFFF1493), size: 22),
            SizedBox(width: 10),
            Text('Admin Panel', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            onPressed: () async {
              await globalPlayer.stop();
              await GoogleSignIn().signOut();
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF6A0572), Color(0xFFFF1493)]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.music_note_rounded, color: Colors.white, size: 28),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('AuraHub Admin', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                    Text('${kSongs.length} songs in library', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
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
              child: Row(
                children: [
                  Icon(_adding ? Icons.expand_less_rounded : Icons.add_circle_rounded, color: const Color(0xFFFF1493), size: 22),
                  const SizedBox(width: 10),
                  const Text('Add New Song', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                ],
              ),
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
                  _AdminField(ctrl: _artistCtrl, label: 'Artist', hint: 'e.g. Aura Collective', icon: Icons.person_outline_rounded),
                  const SizedBox(height: 12),
                  _AdminField(ctrl: _urlCtrl, label: 'MP3 URL *', hint: 'https://example.com/song.mp3', icon: Icons.link_rounded),
                  const SizedBox(height: 12),
                  _AdminField(ctrl: _artCtrl, label: 'Cover Image URL', hint: 'https://example.com/art.png (optional)', icon: Icons.image_outlined),
                  const SizedBox(height: 16),
                  const _Label('Mood'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: _moods.map((m) {
                      final sel = _mood == m;
                      final mc = moodCfg(m);
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
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(moodIcon(m), size: 14, color: sel ? Colors.white : Colors.white54),
                              const SizedBox(width: 5),
                              Text(m, style: TextStyle(color: sel ? Colors.white : Colors.white54, fontSize: 12, fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
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
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),
          Row(
            children: [
              const Text('SONG LIBRARY', style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 3, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('${kSongs.length} tracks', style: const TextStyle(color: Colors.white24, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 12),

          ...kSongs.map((song) {
            final mc = moodCfg(song['mood'] ?? 'Joyful');
            final isAsset = song['isAsset'] == 'true';
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
                subtitle: Row(
                  children: [
                    Text(song['artist'] ?? '', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: mc.accent.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                      child: Text(song['mood'] ?? '', style: TextStyle(color: mc.accent, fontSize: 10, fontWeight: FontWeight.w600)),
                    ),
                    if (isAsset) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(6)),
                        child: const Text('BUILT-IN', style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ],
                ),
                trailing: isAsset
                    ? const Icon(Icons.lock_outline_rounded, color: Colors.white24, size: 18)
                    : IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22),
                  onPressed: () => _confirmDelete(song),
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
        _Label(label),
        const SizedBox(height: 6),
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
// HOME PAGE
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
  String _searchQ = '';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    globalPlayer.playerStateStream.listen((state) {
      if (!mounted) return;
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
    final song = _currentQueue[idx];
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

  void _addToPlaylistSheet({Map<String, String>? preSelected}) {
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
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.builder(
                        controller: sc, itemCount: kSongs.length,
                        itemBuilder: (_, i) {
                          final s = kSongs[i];
                          final sel = selected.contains(i);
                          final mc = moodCfg(s['mood']!);
                          return ListTile(
                            leading: Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), gradient: LinearGradient(colors: mc.gradient)),
                              child: sel ? const Icon(Icons.check_rounded, color: Colors.white, size: 20) : null,
                            ),
                            title: Text(s['title']!, style: const TextStyle(color: Colors.white, fontSize: 14)),
                            subtitle: Text(s['artist']!, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                            onTap: () => ss(() => sel ? selected.remove(i) : selected.add(i)),
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
                              if (globalPlaylists.isEmpty) { Navigator.pop(context); _createPlaylistDialog(); return; }
                              Navigator.pop(context);
                              _pickPlaylistSheet(selected.map((i) => kSongs[i]).toList());
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
                        content: const Text('Are you sure?', style: TextStyle(color: Colors.white60, fontSize: 14)),
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
    final user = FirebaseAuth.instance.currentUser;
    final curMood = currentMoodNotifier.value;
    final curSong = currentSongNotifier.value;
    final curColors = moodCfg(curMood).gradient;
    final initial = (user?.displayName?.isNotEmpty == true ? user!.displayName![0] : user?.email?[0] ?? 'A').toUpperCase();
    final filtered = kSongs.where((s) {
      return (_selMood == 'All' || s['mood'] == _selMood) && s['title']!.toLowerCase().contains(_searchQ.toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
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
                        const Text('AURA HUB', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 3)),
                        Text('${kSongs.length} tracks', style: const TextStyle(color: Colors.white38, fontSize: 12)),
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
                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(14)),
                child: TabBar(
                  controller: _tabCtrl,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                  labelColor: Colors.black,
                  unselectedLabelColor: Colors.white54,
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
                  ),
                  _PlaylistsTab(
                    playlists: globalPlaylists,
                    onCreate: _createPlaylistDialog,
                    onDelete: _deletePlaylist,
                    onAddSongs: () => _addToPlaylistSheet(),
                    onPlay: (pl, i) { _playFromPlaylist(pl, i); _openNowPlaying(pl.songs, i); },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
// SONGS TAB
// ─────────────────────────────────────────────────────────────────────────────

class _SongsTab extends StatelessWidget {
  final List<Map<String, String>> filtered;
  final String selMood;
  final TextEditingController searchCtrl;
  final ValueChanged<String> onMoodChange, onSearch;
  final void Function(int) onTap;
  final void Function(Map<String, String>) onLongPress;

  const _SongsTab({
    required this.filtered, required this.selMood, required this.searchCtrl,
    required this.onMoodChange, required this.onSearch, required this.onTap, required this.onLongPress,
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
            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white12)),
            child: TextField(
              controller: searchCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Search songs...', hintStyle: TextStyle(color: Colors.white38),
                prefixIcon: Icon(Icons.search, color: Colors.white38),
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
              final m = moods[i];
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
          child: Text('${filtered.length} TRACKS', style: const TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 3, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: filtered.length,
            itemBuilder: (_, i) {
              final s = filtered[i];
              final gi = kSongs.indexWhere((x) => x['title'] == s['title']);
              return _SongTile(song: s, onTap: () => onTap(gi), onLongPress: () => onLongPress(s));
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SONG TILE
// ─────────────────────────────────────────────────────────────────────────────

class _SongTile extends StatelessWidget {
  final Map<String, String> song;
  final VoidCallback onTap, onLongPress;
  const _SongTile({required this.song, required this.onTap, required this.onLongPress});

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
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF111111),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
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
                            Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 3),
                            Text(song['artist']!, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: mc.accent.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                        child: Text(song['mood']!, style: TextStyle(color: mc.accent, fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
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
// PLAYLISTS TAB
// ─────────────────────────────────────────────────────────────────────────────

class _PlaylistsTab extends StatelessWidget {
  final List<Playlist> playlists;
  final VoidCallback onCreate, onAddSongs;
  final void Function(Playlist) onDelete;
  final void Function(Playlist, int) onPlay;

  const _PlaylistsTab({
    required this.playlists, required this.onCreate, required this.onDelete,
    required this.onAddSongs, required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${playlists.length} PLAYLISTS', style: const TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 3, fontWeight: FontWeight.w600)),
              GestureDetector(
                onTap: onCreate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                  child: const Row(
                    children: [
                      Icon(Icons.add, color: Colors.black, size: 16),
                      SizedBox(width: 4),
                      Text('New Playlist', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: playlists.isEmpty
              ? const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.library_music_rounded, color: Colors.white12, size: 64),
                SizedBox(height: 16),
                Text('No playlists yet', style: TextStyle(color: Colors.white38, fontSize: 16)),
                SizedBox(height: 8),
                Text('Tap "New Playlist" to get started', style: TextStyle(color: Colors.white24, fontSize: 13)),
              ],
            ),
          )
              : ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: playlists.length,
            itemBuilder: (_, i) {
              final pl = playlists[i];
              final mc = pl.songs.isNotEmpty ? moodCfg(pl.songs[0]['mood']!) : moodCfg('Joyful');
              return GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlaylistDetailPage(playlist: pl, onPlay: onPlay, onAddSongs: onAddSongs))),
                onLongPress: () => onDelete(pl),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: 0.06))),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
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
                              Text('${pl.songs.length} song${pl.songs.length == 1 ? '' : 's'}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: Colors.white30),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PLAYLIST DETAIL
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
        title: Text(_selectMode ? '${_selected.length} selected' : pl.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        actions: [
          if (!_selectMode) IconButton(icon: const Icon(Icons.edit_outlined, color: Colors.white54), onPressed: _toggleSelectMode),
        ],
      ),
      body: pl.songs.isEmpty
          ? Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.music_off_rounded, color: Colors.white12, size: 64),
            const SizedBox(height: 16),
            const Text('No songs yet', style: TextStyle(color: Colors.white38)),
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: widget.onAddSongs,
              child: const Text('Add Songs', style: TextStyle(fontWeight: FontWeight.w700)),
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
      bottomNavigationBar: (_selectMode && _selected.isNotEmpty)
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
          : null,
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
// NOW PLAYING
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
    final s = widget.songList[idx];
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
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [_colors[0], _colors[1], Colors.black],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
          Positioned.fill(child: _ParticlesBg(color: _colors[0], mood: _song['mood'] ?? 'Joyful')),
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
                      WaveformBars(playing: true, color: _colors[0]),
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
// PARTICLES BACKGROUND
// ─────────────────────────────────────────────────────────────────────────────

class _ParticlesBg extends StatefulWidget {
  final Color color;
  final String mood;
  const _ParticlesBg({required this.color, required this.mood});
  @override
  State<_ParticlesBg> createState() => _ParticlesBgState();
}

class _ParticlesBgState extends State<_ParticlesBg> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    _particles = List.generate(18, (_) => _Particle.random());
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => CustomPaint(
        painter: _PPainter(_ctrl.value, widget.color, _particles),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _Particle {
  final double x, y, size, speed, phase;
  final int type;
  _Particle({required this.x, required this.y, required this.size, required this.speed, required this.phase, required this.type});
  static _Particle random() {
    final r = math.Random();
    return _Particle(x: r.nextDouble(), y: r.nextDouble(), size: 8 + r.nextDouble() * 16, speed: 0.3 + r.nextDouble() * 0.7, phase: r.nextDouble() * math.pi * 2, type: r.nextInt(4));
  }
}

class _PPainter extends CustomPainter {
  final double t;
  final Color color;
  final List<_Particle> particles;
  _PPainter(this.t, this.color, this.particles);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final y = (p.y - t * p.speed * 0.15 + 1) % 1;
      final x = p.x + math.sin(t * math.pi * 2 * p.speed + p.phase) * 0.03;
      final opacity = (0.15 + 0.2 * math.sin(t * math.pi * 2 + p.phase)).clamp(0.0, 1.0);
      final paint = Paint()..color = color.withValues(alpha: opacity)..style = PaintingStyle.stroke..strokeWidth = 1;
      canvas.save();
      canvas.translate(x * size.width, y * size.height);
      switch (p.type) {
        case 0: _star(canvas, p.size, paint); break;
        case 1: _heart(canvas, p.size, paint); break;
        case 2: _bolt(canvas, p.size, paint); break;
        default: _drop(canvas, p.size, paint);
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
    final path = Path()
      ..moveTo(0, s / 4)
      ..cubicTo(-s / 2, -s / 6, -s / 2, -s / 2, 0, -s / 6)
      ..cubicTo(s / 2, -s / 2, s / 2, -s / 6, 0, s / 4);
    c.drawPath(path, p);
  }

  void _bolt(Canvas c, double s, Paint p) {
    final path = Path()
      ..moveTo(s * 0.1, -s / 2)..lineTo(-s * 0.1, -s * 0.05)..lineTo(s * 0.15, -s * 0.05)
      ..lineTo(-s * 0.1, s / 2)..lineTo(s * 0.3, -s * 0.1)..lineTo(s * 0.05, -s * 0.1)..close();
    c.drawPath(path, p);
  }

  void _drop(Canvas c, double s, Paint p) {
    final path = Path()
      ..moveTo(0, -s / 2)..cubicTo(s / 3, -s / 4, s / 3, s / 4, 0, s / 2)
      ..cubicTo(-s / 3, s / 4, -s / 3, -s / 4, 0, -s / 2)..close();
    c.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_PPainter o) => o.t != t || o.color != color;
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
    if (!widget.playing) return const SizedBox(width: 24, height: 16);
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
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: const TextStyle(color: Colors.redAccent, fontSize: 13))),
        ],
      ),
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