import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;

// Render ka https URL yahan daalo (README dekho)
const String kServerUrl = 'https://YOUR-SERVER.onrender.com';
const Color kSeed = Color(0xFF6C4DF6);

void main() => runApp(const LakshyaApp());

class LakshyaApp extends StatelessWidget {
  const LakshyaApp({super.key});

  ThemeData _theme(Brightness b) =>
      ThemeData(useMaterial3: true, colorSchemeSeed: kSeed, brightness: b);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lakshya GPT',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: const HomePage(),
    );
  }
}

// ---------------------------------------------------------------- models

class Mcq {
  final String q, explanation;
  final List<String> options;
  final int answer;
  Mcq(this.q, this.explanation, this.options, this.answer);

  static Mcq? tryParse(dynamic j) {
    if (j is! Map) return null;
    final opts = j['options'] is List
        ? (j['options'] as List).map((e) => e.toString()).toList()
        : <String>[];
    if (opts.length < 2) return null;
    final raw = j['answer'];
    int a = raw is num ? raw.toInt() : 0;
    if (a < 0 || a >= opts.length) a = 0;
    return Mcq('${j['q'] ?? ''}', '${j['explanation'] ?? ''}', opts, a);
  }
}

class Result {
  final String answer, svg;
  final List<String> points;
  final List<Mcq> mcqs;
  Result(this.answer, this.svg, this.points, this.mcqs);

  static String _cleanSvg(String s) {
    var t = s.trim();
    if (!t.startsWith('<svg')) return '';
    t = t.replaceAll(
        RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), '');
    if (!t.contains('xmlns=')) {
      t = t.replaceFirst('<svg', '<svg xmlns="http://www.w3.org/2000/svg"');
    }
    return t;
  }

  factory Result.fromJson(Map j) {
    final pts = j['points'] is List
        ? (j['points'] as List).map((e) => e.toString()).toList()
        : <String>[];
    final mcqs = <Mcq>[];
    if (j['mcqs'] is List) {
      for (final m in (j['mcqs'] as List)) {
        final p = Mcq.tryParse(m);
        if (p != null) mcqs.add(p);
      }
    }
    return Result('${j['answer'] ?? ''}', _cleanSvg('${j['svg'] ?? ''}'), pts, mcqs);
  }
}

// ------------------------------------------------------- small animations

/// Fade + slide-up entrance, with optional delay.
class Reveal extends StatefulWidget {
  final Widget child;
  final int delayMs;
  const Reveal({super.key, required this.child, this.delayMs = 0});
  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 550));
  late final Animation<double> _a =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _a,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
            .animate(_a),
        child: widget.child,
      ),
    );
  }
}

/// Gently pulsing widget (used for the logo).
class Pulse extends StatefulWidget {
  final Widget child;
  const Pulse({super.key, required this.child});
  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.92, end: 1.12)
          .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: widget.child,
    );
  }
}

/// Three bouncing dots shown while the answer is loading.
class ThinkingDots extends StatefulWidget {
  const ThinkingDots({super.key});
  @override
  State<ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<ThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final v = math.sin(_c.value * 2 * math.pi - i * 0.9);
            return Transform.translate(
              offset: Offset(0, -8 * math.max(0.0, v)),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            );
          }),
        );
      },
    );
  }
}

/// Slowly moving gradient with floating glowing blobs.
class FloatingBg extends StatefulWidget {
  const FloatingBg({super.key});
  @override
  State<FloatingBg> createState() => _FloatingBgState();
}

class _FloatingBgState extends State<FloatingBg>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 16))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _blob(Color c, double s) => Container(
        width: s,
        height: s,
        decoration: BoxDecoration(shape: BoxShape.circle, color: c.withAlpha(45)),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value * 2 * math.pi;
            return Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(math.cos(t), -1),
                      end: Alignment(-math.cos(t), 1),
                      colors: [
                        cs.primaryContainer.withAlpha(130),
                        cs.surface,
                        cs.tertiaryContainer.withAlpha(130),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: size.width * 0.5 + math.cos(t) * size.width * 0.35 - 110,
                  top: 60 + math.sin(t) * 50,
                  child: _blob(cs.primary, 220),
                ),
                Positioned(
                  left: size.width * 0.1 + math.sin(t) * size.width * 0.3,
                  top: size.height * 0.55 + math.cos(t) * 60,
                  child: _blob(cs.tertiary, 180),
                ),
                Positioned(
                  left: size.width * 0.7 + math.cos(t + 2) * 40,
                  top: size.height * 0.8 + math.sin(t + 1) * 40,
                  child: _blob(cs.secondary, 140),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ page

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _resKey = GlobalKey();

  static const _langs = {
    'Hinglish': 'Hinglish (Hindi in Roman script)',
    'हिंदी': 'Hindi (Devanagari)',
    'English': 'English',
  };
  static const _hints = [
    'Photosynthesis kya hai?',
    'Newton ke gati ke niyam',
    'Mughal Empire ka patan',
    'Bharat ka Samvidhan',
    'DNA kaise kaam karta hai?',
  ];

  String _lang = 'Hinglish';
  bool _loading = false;
  String? _error;
  Result? _result;
  final Map<int, int> _picked = {};
  int _hintIdx = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) setState(() => _hintIdx = (_hintIdx + 1) % _hints.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty || _loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
      _picked.clear();
    });
    try {
      final r = await http
          .post(
            Uri.parse('$kServerUrl/ask'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'question': q, 'language': _langs[_lang]}),
          )
          .timeout(const Duration(seconds: 90));
      final body = jsonDecode(utf8.decode(r.bodyBytes));
      if (r.statusCode != 200 || body is! Map) {
        throw Exception('server error');
      }
      if (!mounted) return;
      setState(() => _result = Result.fromJson(body));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _resKey.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(ctx,
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            'Jawab nahi aa paya. Internet check karo ya thodi der baad dobara try karo.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ------------------------------------------------------------- pieces

  Widget _header(ColorScheme cs) {
    return Reveal(
      child: Column(
        children: [
          const Pulse(child: Text('🎯', style: TextStyle(fontSize: 54))),
          const SizedBox(height: 6),
          ShaderMask(
            shaderCallback: (r) =>
                LinearGradient(colors: [cs.primary, cs.tertiary]).createShader(r),
            child: const Text(
              'Lakshya GPT',
              style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.5),
            ),
          ),
          const SizedBox(height: 4),
          Text('Sawal puchho • Jawab, diagram, points aur MCQ pao',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _glass(ColorScheme cs, Widget child) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface.withAlpha(225),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withAlpha(150)),
        boxShadow: [
          BoxShadow(
              color: cs.primary.withAlpha(30),
              blurRadius: 24,
              offset: const Offset(0, 10)),
        ],
      ),
      child: child,
    );
  }

  Widget _inputCard(ColorScheme cs) {
    return Reveal(
      delayMs: 120,
      child: _glass(
        cs,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _ctrl,
              minLines: 2,
              maxLines: 4,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: _hints[_hintIdx],
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: _langs.keys
                    .map((k) => ButtonSegment<String>(value: k, label: Text(k)))
                    .toList(),
                selected: {_lang},
                onSelectionChanged: (s) => setState(() => _lang = s.first),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _loading ? null : _ask,
                icon: const Icon(Icons.auto_awesome),
                label: Text(_loading ? 'Soch raha hoon…' : 'Jawab do',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 0,
              children: _hints
                  .take(3)
                  .map((t) => ActionChip(
                        label: Text(t),
                        onPressed: _loading
                            ? null
                            : () {
                                _ctrl.text = t;
                                _ask();
                              },
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(ColorScheme cs, IconData icon, String title, Widget child,
      {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: _glass(
        cs,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      style: TextStyle(
                          color: cs.primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          letterSpacing: 0.4)),
                ),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Widget _loadingView(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          const ThinkingDots(),
          const SizedBox(height: 14),
          Text('Aapke liye jawab, diagram aur MCQ ban rahe hain…',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _errorView(ColorScheme cs) {
    return Reveal(
      child: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: _glass(
          cs,
          Column(
            children: [
              const Text('😕', style: TextStyle(fontSize: 36)),
              const SizedBox(height: 6),
              Text(_error ?? '', textAlign: TextAlign.center),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _ask,
                icon: const Icon(Icons.refresh),
                label: const Text('Dobara try karo'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _option(ColorScheme cs, int i, Mcq m, int j) {
    final picked = _picked[i];
    Color border = cs.outlineVariant;
    Color? fill;
    IconData? icon;
    Color? iconColor;
    if (picked != null) {
      if (j == m.answer) {
        border = Colors.green;
        fill = Colors.green.withAlpha(40);
        icon = Icons.check_circle;
        iconColor = Colors.green;
      } else if (j == picked) {
        border = Colors.red;
        fill = Colors.red.withAlpha(40);
        icon = Icons.cancel;
        iconColor = Colors.red;
      }
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: picked == null ? () => setState(() => _picked[i] = j) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: border, width: icon != null ? 2 : 1),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: cs.primaryContainer,
                  child: Text(String.fromCharCode(65 + j),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: cs.onPrimaryContainer)),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(m.options[j])),
                if (icon != null) Icon(icon, color: iconColor),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _mcqItem(ColorScheme cs, int i, Mcq m) {
    final picked = _picked[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Q${i + 1}. ${m.q}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          for (var j = 0; j < m.options.length; j++) _option(cs, i, m, j),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            alignment: Alignment.topCenter,
            child: picked == null || m.explanation.isEmpty
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('💡 ${m.explanation}',
                        style: TextStyle(
                            color: cs.onSurfaceVariant, fontSize: 13.5)),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _scoreBar(ColorScheme cs, Result res) {
    final total = res.mcqs.length;
    final answered = _picked.length;
    final correct =
        _picked.entries.where((e) => res.mcqs[e.key].answer == e.value).length;
    final ratio = total == 0 ? 0.0 : correct / total;
    final done = answered == total && total > 0;
    String msg = '';
    if (done) {
      msg = ratio >= 0.8
          ? '🏆 Shandar! Aap toh topper ho!'
          : ratio >= 0.5
              ? '👍 Accha kiya! Thoda aur practice karo.'            : '📚 Aur mehnat karo!';
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Score: $correct / $total',
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 16)),
          if (msg.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(msg),
            ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
              value: total == 0 ? 0 : answered / total),
        ],
      ),
    );
  }
}
         
