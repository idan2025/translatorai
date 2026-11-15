import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'src/asr.dart';
import 'src/languages.dart';
import 'src/model_store.dart';
import 'src/models.dart';

import 'src/pipeline.dart';
import 'src/settings.dart';
import 'src/speaker.dart';
import 'src/translator.dart';
import 'src/updater.dart';
import 'src/lid.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await Settings.load();
  final dir = Directory('${(await getApplicationSupportDirectory()).path}/models');
  // must match res/xml/update_paths.xml: the cache's "updates" folder
  final updater = Updater(dir: Directory('${(await getTemporaryDirectory()).path}/updates'));
  // an APK left from the update that started this version, or an abandoned download
  updater.cleanUp().ignore();
  final info = await PackageInfo.fromPlatform();
  runApp(TranslatorApp(settings: settings, store: ModelStore(dir), updater: updater, version: info.version));
}

class TranslatorApp extends StatelessWidget {
  const TranslatorApp(
      {super.key, required this.settings, required this.store, required this.updater, required this.version});
  final Settings settings;
  final ModelStore store;
  final Updater updater;
  final String version;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2E7D6B);
    return MaterialApp(
      title: 'TranslatorAI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
      home: Gate(settings: settings, store: store, updater: updater, version: version),
    );
  }
}

/// Shows setup until the speech model is on the phone, then the translator.
class Gate extends StatefulWidget {
  const Gate({super.key, required this.settings, required this.store, required this.updater, required this.version});
  final Settings settings;
  final ModelStore store;
  final Updater updater;
  final String version;
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
      updater: widget.updater,
      version: widget.version,
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
      // keep every known model so switching back needs no download; drop only leftovers
      // (partial downloads, files of models this version no longer uses)
      await widget.store.prune(allModelFiles);
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
                    subtitle: Text('${m.note}${widget.store.hasAll(m.files) ? '\nDownloaded' : ''}'),
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
                onPressed: download,
                icon: Icon(widget.store.hasAll([vadModel, ...picked.files]) ? Icons.check : Icons.download),
                label: Text(widget.store.hasAll([vadModel, ...picked.files]) ? 'Use this model' : 'Download and start')),
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
      {super.key,
      required this.settings,
      required this.store,
      required this.model,
      required this.updater,
      required this.version,
      required this.onChangeModel});
  final Settings settings;
  final ModelStore store;
  final Updater updater;
  final String version;
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
    live = LiveTranslator(engine: MlKitEngine(), speaker: Speaker(), guesser: MlKitGuesser())
      ..mode = s.mode
      ..mine = s.mine
      ..theirs = s.theirs
      ..listenFrom = s.listenFrom
      ..autoSpeaker = s.autoSpeaker
      ..speak = s.speak;
    live.addListener(() {
      if (!mounted) return;
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) scroll.jumpTo(scroll.position.maxScrollExtent);
      });
    });
    _prepare([live.mine, if (live.mode == Mode.conversation) live.theirs, if (live.listenFrom.isNotEmpty) live.listenFrom]);
  }

  @override
  void dispose() {
    live.dispose();
    scroll.dispose();
    super.dispose();
  }

  AsrConfig get asrConfig => AsrConfig(
        vad: widget.store.pathOf(vadModel.name),
        encoder: widget.store.pathOf(widget.model.encoder.name),
        decoder: widget.store.pathOf(widget.model.decoder.name),
        tokens: widget.store.pathOf(widget.model.tokens.name),
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

  /// [which]: 'mine', 'theirs', or 'from' (Listen's spoken language, which may be "any").
  Future<void> pick(String which) async {
    final current = switch (which) { 'mine' => live.mine, 'theirs' => live.theirs, _ => live.listenFrom };
    final choice = await showModalBottomSheet<Language>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => LanguagePicker(
        current: current,
        allowAny: which == 'from',
        // a spoken side must be heard as well as written; Listen's own language only written
        allowed: (l) => live.engine.supports(l.code) && (which == 'mine' && live.mode == Mode.listen || hearable.contains(l.code)),
      ),
    );
    if (choice == null) return;
    setState(() {
      switch (which) {
        case 'mine':
          live.mine = widget.settings.mine = choice.code;
        case 'theirs':
          live.theirs = widget.settings.theirs = choice.code;
        default:
          live.listenFrom = widget.settings.listenFrom = choice.code;
      }
    });
    if (choice.code.isNotEmpty) _prepare([choice.code]);
  }

  // ------------------------------------------------------------ settings

  Future<void> checkForUpdates() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Checking for updates…'), duration: Duration(seconds: 2)));
    Update? u;
    try {
      u = await widget.updater.check(widget.version);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
      return;
    }
    if (!mounted) return;
    if (u == null) {
      messenger.showSnackBar(SnackBar(content: Text('You have the latest version (${widget.version}).')));
      return;
    }
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Version ${u!.version} is available'),
        content: SingleChildScrollView(
          child: Text('You have ${widget.version}. Download ${(u.bytes / 1e6).round()} MB and install?\n\n'
              '${u.notes.trim()}'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Later')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Update')),
        ],
      ),
    );
    if (go != true || !mounted) return;
    final progress = ValueNotifier<double?>(0);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Downloading update'),
        content: ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (_, v, _) => LinearProgressIndicator(value: v),
        ),
      ),
    );
    try {
      final apk = await widget.updater.download(u, onProgress: (d, t) => progress.value = d / t);
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      await widget.updater.install(apk); // the file is deleted at the next start
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
        messenger.showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      progress.dispose();
    }
  }

  void about() {
    showAboutDialog(
      context: context,
      applicationName: 'TranslatorAI',
      applicationVersion: widget.version,
      applicationIcon: Icon(Icons.translate, size: 40, color: Theme.of(context).colorScheme.primary),
      applicationLegalese: 'Free and open source. Speech is heard, translated and spoken on this phone; '
          'the network is used only to download models and updates.',
      children: [
        const SizedBox(height: 16),
        Text('Speech model: ${widget.model.note}'),
        const SizedBox(height: 8),
        const Text('Speech recognition: OpenAI Whisper (MIT) via sherpa-onnx. '
            'Voice detection: Silero VAD (MIT). Translation and language identification: Google ML Kit, on-device. '
            "Voice: this phone's text-to-speech."),
        const SizedBox(height: 8),
        const SelectableText(releasesPage),
      ],
    );
  }

  Future<void> exitApp() async {
    await live.stop();
    await SystemNavigator.pop();
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

  /// The two big buttons of a tap conversation: each listens in its own language.
  Widget sideButton(String which, ColorScheme cs) {
    final code = which == 'mine' ? live.mine : live.theirs;
    final active = live.running && live.side == which;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: FilledButton.tonal(
          onPressed: () => live.tapSide(which, asrConfig),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(88),
            backgroundColor: active ? cs.error : null,
            foregroundColor: active ? cs.onError : null,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(active ? Icons.stop : Icons.mic, size: 32),
            const SizedBox(height: 4),
            Text(nameOf(code), overflow: TextOverflow.ellipsis),
            Text(active ? 'Tap to stop' : 'Tap, then speak', style: Theme.of(context).textTheme.labelSmall),
          ]),
        ),
      ),
    );
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
          MenuAnchor(
            builder: (_, menu, _) => IconButton(
              tooltip: 'Menu',
              icon: const Icon(Icons.more_vert),
              onPressed: () => menu.isOpen ? menu.close() : menu.open(),
            ),
            menuChildren: [
              MenuItemButton(leadingIcon: const Icon(Icons.delete_sweep), onPressed: live.clear, child: const Text('Clear transcript')),
              SubmenuButton(
                leadingIcon: const Icon(Icons.settings),
                menuChildren: [
                  MenuItemButton(
                    leadingIcon: const Icon(Icons.record_voice_over),
                    onPressed: locked ? null : widget.onChangeModel,
                    child: Text('Speech model: ${widget.model.label}'),
                  ),
                  // downloaded models are kept so switching back is instant; this frees the space
                  for (final m in speechModels)
                    if (m.id != widget.model.id && widget.store.hasAny(m.files))
                      MenuItemButton(
                        leadingIcon: const Icon(Icons.delete_outline),
                        onPressed: locked
                            ? null
                            : () async {
                                await widget.store.deleteModel(m.files, except: widget.model.files);
                                if (mounted) setState(() {});
                              },
                        child: Text('Delete the ${m.label} model (${(m.bytes / 1e6).round()} MB)'),
                      ),
                  MenuItemButton(
                    leadingIcon: Icon(live.autoSpeaker ? Icons.check_box : Icons.check_box_outline_blank),
                    onPressed: locked
                        ? null
                        : () => setState(() => live.autoSpeaker = widget.settings.autoSpeaker = !live.autoSpeaker),
                    child: const Text('Conversation: detect who speaks (slower)'),
                  ),
                  MenuItemButton(
                      leadingIcon: const Icon(Icons.system_update), onPressed: checkForUpdates, child: const Text('Check for updates')),
                  MenuItemButton(leadingIcon: const Icon(Icons.info_outline), onPressed: about, child: const Text('About')),
                  MenuItemButton(leadingIcon: const Icon(Icons.exit_to_app), onPressed: exitApp, child: const Text('Exit')),
                ],
                child: const Text('Settings'),
              ),
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
                  Expanded(
                      child: _Chip(
                          label: live.listenFrom.isEmpty ? 'Any language' : nameOf(live.listenFrom),
                          icon: live.listenFrom.isEmpty ? Icons.auto_awesome : null,
                          onTap: locked ? null : () => pick('from'))),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.arrow_forward)),
                  Expanded(child: _Chip(label: nameOf(live.mine), onTap: locked ? null : () => pick('mine'))),
                ])
              : Row(children: [
                  Expanded(child: _Chip(label: nameOf(live.mine), onTap: locked ? null : () => pick('mine'))),
                  IconButton(onPressed: locked ? null : swap, icon: const Icon(Icons.swap_horiz)),
                  Expanded(child: _Chip(label: nameOf(live.theirs), onTap: locked ? null : () => pick('theirs'))),
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
        if (live.behind)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'The phone cannot keep up with this speech model. Switch to the Standard model in Settings, '
              'or speak in shorter sentences.',
              style: TextStyle(color: cs.tertiary),
            ),
          ),
        if (live.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(live.error!, style: TextStyle(color: cs.error)),
          ),
        Expanded(
          child: live.lines.isEmpty
              ? _Empty(mode: live.mode, running: live.running, auto: live.autoSpeaker)
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
            child: live.mode == Mode.conversation && !live.autoSpeaker
                ? Row(children: [sideButton('mine', cs), sideButton('theirs', cs)])
                : FloatingActionButton.large(
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
  const _Empty({required this.mode, required this.running, required this.auto});
  final Mode mode;
  final bool running;
  final bool auto;
  @override
  Widget build(BuildContext context) {
    final text = running
        ? 'Listening…'
        : mode == Mode.listen
            ? 'Tap the microphone. Everything said around you is translated into your language. Put in earbuds to hear it.'
            : auto
                ? 'Tap the microphone and put the phone between you. The app works out who is talking from the sound: slower, and it can be wrong.'
                : 'Tap your language, then speak. The other person taps theirs. One pass per sentence: fast and exact.';
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
          Text(
              '${nameOf(d.from)}${d.guessed ? ' (guessed)' : ''} → ${nameOf(d.to)}'
              '  ·  ${line.heard.seconds.toStringAsFixed(1)} s heard, ${(line.heard.decodeMs / 1000).toStringAsFixed(1)} s to write',
              style: t.labelSmall),
          const SizedBox(height: 4),
          Text(sentenceCase(line.heard.text), style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
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
  const LanguagePicker({super.key, required this.current, required this.allowed, this.allowAny = false});
  final String current;

  /// Offer "Any language" (an empty code) first.
  final bool allowAny;
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
            if (widget.allowAny && query.isEmpty)
              ListTile(
                leading: const Icon(Icons.auto_awesome),
                title: const Text('Any language'),
                subtitle: const Text('Told from what is said. Pick the language when you know it: more accurate.'),
                trailing: widget.current.isEmpty ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, const Language('', 'Any language')),
              ),
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

/// The recogniser writes without capitals; start the sentence with one.
String sentenceCase(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
