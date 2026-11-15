import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'src/asr.dart';
import 'src/languages.dart';
import 'src/model_store.dart';
import 'src/models.dart';
import 'src/pipeline.dart';
import 'src/settings.dart';
import 'src/speaker.dart';
import 'src/translator.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await Settings.load();
  final dir = Directory('${(await getApplicationSupportDirectory()).path}/models');
  runApp(TranslatorApp(settings: settings, store: ModelStore(dir)));
}

class TranslatorApp extends StatelessWidget {
  const TranslatorApp({super.key, required this.settings, required this.store});
  final Settings settings;
  final ModelStore store;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2E7D6B);
    return MaterialApp(
      title: 'TranslatorAI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
      home: Gate(settings: settings, store: store),
    );
  }
}

/// Shows setup until the speech model is on the phone, then the translator.
class Gate extends StatefulWidget {
  const Gate({super.key, required this.settings, required this.store});
  final Settings settings;
  final ModelStore store;
  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> {
  late SpeechModel model = speechModelById(widget.settings.model);
  bool choosing = false;

  bool get ready => !choosing && widget.store.hasAll([vadModel, ...model.files]);

  @override
  Widget build(BuildContext context) {
    if (!ready) {
      return SetupScreen(
        store: widget.store,
        initial: model,
        onDone: (m) => setState(() {
          widget.settings.model = m.id;
          model = m;
          choosing = false;
        }),
      );
    }
    return HomeScreen(
      key: ValueKey(model.id),
      settings: widget.settings,
      store: widget.store,
      model: model,
      onChangeModel: () => setState(() => choosing = true),
    );
  }
}

// ---------------------------------------------------------------- setup

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.store, required this.initial, required this.onDone});
  final ModelStore store;
  final SpeechModel initial;
  final void Function(SpeechModel) onDone;
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late SpeechModel picked = widget.initial;
  double? progress;
  String? error;

  Future<void> download() async {
    setState(() {
      progress = 0;
      error = null;
    });
    try {
      final files = [vadModel, ...picked.files];
      await widget.store.ensure(files, onProgress: (d, t) {
        if (mounted) setState(() => progress = d / t);
      });
      await widget.store.prune(files); // switching models frees the old one's space
      widget.onDone(picked);
    } catch (e) {
      if (mounted) {
        setState(() {
          progress = null;
          error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final busy = progress != null;
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const SizedBox(height: 24),
          Icon(Icons.translate, size: 56, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text('Live translation that stays on your phone', style: t.headlineSmall),
          const SizedBox(height: 8),
          Text(
              'Speech is heard, translated and spoken on this device. Nothing you say is sent anywhere. '
              'Works with any earbuds, no special headset.',
              style: t.bodyMedium),
          const SizedBox(height: 24),
          Text('Pick a speech model (one-time download)', style: t.titleSmall),
          const SizedBox(height: 8),
          RadioGroup<String>(
            groupValue: picked.id,
            onChanged: (v) {
              if (!busy && v != null) setState(() => picked = speechModelById(v));
            },
            child: Column(children: [
              for (final m in speechModels)
                Card(
                  child: RadioListTile<String>(
                    value: m.id,
                    enabled: !busy,
                    title: Text(m.label),
                    subtitle: Text(m.note),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 16),
          if (busy) ...[
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 8),
            Text('${(progress! * 100).toStringAsFixed(0)}% of ${(picked.bytes / 1e6).round()} MB'),
          ] else
            FilledButton.icon(
                onPressed: download, icon: const Icon(Icons.download), label: const Text('Download and start')),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          Text('Translation models (~30 MB per language) download the first time you pick a language.',
              style: t.bodySmall),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- home

class HomeScreen extends StatefulWidget {
  const HomeScreen(
      {super.key, required this.settings, required this.store, required this.model, required this.onChangeModel});
  final Settings settings;
  final ModelStore store;
  final SpeechModel model;
  final VoidCallback onChangeModel;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final LiveTranslator live;
  final scroll = ScrollController();
  String? preparing;

  @override
  void initState() {
    super.initState();
    final s = widget.settings;
    live = LiveTranslator(engine: MlKitEngine(), speaker: Speaker())
      ..mode = s.mode
      ..mine = s.mine
      ..theirs = s.theirs
      ..speak = s.speak;
    live.addListener(() {
      if (!mounted) return;
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) scroll.jumpTo(scroll.position.maxScrollExtent);
      });
    });
    _prepare([live.mine, if (live.mode == Mode.conversation) live.theirs]);
  }

  @override
  void dispose() {
    live.dispose();
    scroll.dispose();
    super.dispose();
  }

  AsrConfig get asrConfig => AsrConfig(
        vad: widget.store.pathOf(vadModel.name),
        encoder: widget.store.pathOf(widget.model.encoder),
        decoder: widget.store.pathOf(widget.model.decoder),
        tokens: widget.store.pathOf(widget.model.tokens),
        threads: math.min(4, math.max(1, Platform.numberOfProcessors ~/ 2)),
      );

  /// Fetches translation models ahead of time, so the first sentence is not
  /// the one that waits for a download.
  Future<void> _prepare(List<String> codes) async {
    for (final c in codes) {
      if (!live.engine.supports(c) || await live.engine.isReady(c)) continue;
      if (!mounted) return;
      setState(() => preparing = nameOf(c));
      try {
        await live.engine.prepare(c);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
    if (mounted) setState(() => preparing = null);
  }

  Future<void> pick({required bool mine}) async {
    final current = mine ? live.mine : live.theirs;
    // in Listen your language only has to be written; in a conversation both sides are also heard
    final needHear = !(mine && live.mode == Mode.listen);
    final choice = await showModalBottomSheet<Language>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => LanguagePicker(
        current: current,
        allowed: (l) => live.engine.supports(l.code) && (!needHear || hearable.contains(l.code)),
      ),
    );
    if (choice == null) return;
    setState(() {
      if (mine) {
        live.mine = widget.settings.mine = choice.code;
      } else {
        live.theirs = widget.settings.theirs = choice.code;
      }
    });
    _prepare([choice.code]);
  }

  void swap() => setState(() {
        final m = live.mine;
        live.mine = widget.settings.mine = live.theirs;
        live.theirs = widget.settings.theirs = m;
      });

  Future<void> toggle() async {
    if (live.running) {
      await live.stop();
    } else {
      await live.start(asrConfig);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final locked = live.running;
    return Scaffold(
      appBar: AppBar(
        title: const Text('TranslatorAI'),
        actions: [
          IconButton(
            tooltip: live.speak ? 'Speaking translations' : 'Text only',
            icon: Icon(live.speak ? Icons.volume_up : Icons.volume_off),
            onPressed: () => setState(() => live.speak = widget.settings.speak = !live.speak),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'clear') live.clear();
              if (v == 'model') widget.onChangeModel();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'clear', child: Text('Clear transcript')),
              PopupMenuItem(value: 'model', enabled: !locked, child: Text('Speech model: ${widget.model.label}')),
            ],
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SegmentedButton<Mode>(
            segments: const [
              ButtonSegment(value: Mode.listen, icon: Icon(Icons.hearing), label: Text('Listen')),
              ButtonSegment(value: Mode.conversation, icon: Icon(Icons.forum), label: Text('Conversation')),
            ],
            selected: {live.mode},
            onSelectionChanged: locked
                ? null
                : (s) {
                    setState(() => live.mode = widget.settings.mode = s.first);
                    if (s.first == Mode.conversation) _prepare([live.theirs]);
                  },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: live.mode == Mode.listen
              ? Row(children: [
                  const Expanded(child: _Chip(label: 'Any language', icon: Icons.auto_awesome)),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.arrow_forward)),
                  Expanded(child: _Chip(label: nameOf(live.mine), onTap: locked ? null : () => pick(mine: true))),
                ])
              : Row(children: [
                  Expanded(child: _Chip(label: nameOf(live.mine), onTap: locked ? null : () => pick(mine: true))),
                  IconButton(onPressed: locked ? null : swap, icon: const Icon(Icons.swap_horiz)),
                  Expanded(child: _Chip(label: nameOf(live.theirs), onTap: locked ? null : () => pick(mine: false))),
                ]),
        ),
        if (preparing != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 8),
              Flexible(child: Text('Downloading the $preparing translation model…')),
            ]),
          ),
        if (live.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(live.error!, style: TextStyle(color: cs.error)),
          ),
        Expanded(
          child: live.lines.isEmpty
              ? _Empty(mode: live.mode, running: live.running)
              : ListView.builder(
                  controller: scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: live.lines.length,
                  itemBuilder: (_, i) => _LineView(line: live.lines[i], mine: live.mine, mode: live.mode),
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16, top: 8),
            child: FloatingActionButton.large(
              heroTag: 'mic',
              tooltip: live.running ? 'Stop' : 'Start listening',
              onPressed: toggle,
              backgroundColor: live.running ? cs.error : cs.primary,
              foregroundColor: live.running ? cs.onError : cs.onPrimary,
              child: Icon(live.running ? Icons.stop : Icons.mic, size: 40),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.onTap, this.icon});
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon ?? Icons.language, size: 18),
      label: Text(label, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.mode, required this.running});
  final Mode mode;
  final bool running;
  @override
  Widget build(BuildContext context) {
    final text = running
        ? 'Listening…'
        : mode == Mode.listen
            ? 'Tap the microphone. Everything said around you is translated into your language. Put in earbuds to hear it.'
            : 'Tap the microphone and put the phone between you. Each of you speaks your own language; '
                'the app works out who is talking.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
      ),
    );
  }
}

class _LineView extends StatelessWidget {
  const _LineView({required this.line, required this.mine, required this.mode});
  final Line line;
  final String mine;
  final Mode mode;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final d = line.direction;
    // in a conversation, what the other person said sits left and is for you; yours sits right
    final forMe = mode == Mode.listen || d.to == mine;
    return Align(
      alignment: forMe ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: forMe ? cs.secondaryContainer : cs.tertiaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${nameOf(d.from)}${d.guessed ? ' (guessed)' : ''} → ${nameOf(d.to)}', style: t.labelSmall),
          const SizedBox(height: 4),
          Text(line.heard.text, style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 6),
          if (line.pending)
            const LinearProgressIndicator()
          else if (line.problem != null)
            Text(line.problem!, style: t.bodyMedium?.copyWith(color: cs.error))
          else if (d.from != d.to)
            Text(line.translation!, style: t.titleMedium),
        ]),
      ),
    );
  }
}

class LanguagePicker extends StatefulWidget {
  const LanguagePicker({super.key, required this.current, required this.allowed});
  final String current;
  final bool Function(Language) allowed;
  @override
  State<LanguagePicker> createState() => _LanguagePickerState();
}

class _LanguagePickerState extends State<LanguagePicker> {
  String q = '';
  @override
  Widget build(BuildContext context) {
    final query = q.trim().toLowerCase();
    final shown = allLanguages().where((l) => l.name.toLowerCase().contains(query) || l.code == query).toList()
      ..sort((a, b) => (widget.allowed(a) ? 0 : 1).compareTo(widget.allowed(b) ? 0 : 1));
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search languages'),
            onChanged: (v) => setState(() => q = v),
          ),
        ),
        Expanded(
          child: ListView(children: [
            for (final l in shown)
              ListTile(
                enabled: widget.allowed(l),
                title: Text(l.name),
                subtitle: widget.allowed(l) ? null : const Text('Not translatable on this device yet'),
                trailing: l.code == widget.current ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, l),
              ),
          ]),
        ),
      ]),
    );
  }
}
