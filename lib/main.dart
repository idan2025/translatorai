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
  // The GPU crash guard runs once per app start: if the last run died while the
  // GPU route was being tried, switch it off so it cannot crash again.
  final gpuReset = settings.accelTrying;
  if (gpuReset) {
    settings.accel = false;
    settings.accelTrying = false;
  }
  final dir = Directory('${(await getApplicationSupportDirectory()).path}/models');
  // must match res/xml/update_paths.xml: the cache's "updates" folder
  final updater = Updater(dir: Directory('${(await getTemporaryDirectory()).path}/updates'));
  // an APK left from the update that started this version, or an abandoned download
  updater.cleanUp().ignore();
  final info = await PackageInfo.fromPlatform();
  runApp(TranslatorApp(settings: settings, store: ModelStore(dir), updater: updater, version: info.version, gpuReset: gpuReset));
}

class TranslatorApp extends StatelessWidget {
  const TranslatorApp(
      {super.key, required this.settings, required this.store, required this.updater, required this.version, this.gpuReset = false});
  final Settings settings;
  final ModelStore store;
  final Updater updater;
  final String version;
  final bool gpuReset;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2E7D6B);
    return MaterialApp(
      title: 'TranslatorAI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
      home: Gate(settings: settings, store: store, updater: updater, version: version, gpuReset: gpuReset),
    );
  }
}

/// Shows setup until the speech model is on the phone, then the translator.
class Gate extends StatefulWidget {
  const Gate(
      {super.key, required this.settings, required this.store, required this.updater, required this.version, this.gpuReset = false});
  final Settings settings;
  final ModelStore store;
  final Updater updater;
  final String version;
  final bool gpuReset;
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
      gpuReset: widget.gpuReset,
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
      this.gpuReset = false,
      required this.onChangeModel});
  final Settings settings;
  final ModelStore store;
  final Updater updater;
  final String version;
  final SpeechModel model;
  final bool gpuReset;
  final VoidCallback onChangeModel;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// The GPU reset is told once per app start, not again on every model switch.
bool _gpuToldOnce = false;

const _system = MethodChannel('translatorai/system');

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final LiveTranslator live;
  final scroll = ScrollController();
  String? preparing;
  bool _screenOn = false;
  int _lineCount = 0;

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
    if (widget.gpuReset && !_gpuToldOnce) {
      _gpuToldOnce = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Hardware acceleration stopped the app last time, so it was turned off.')));
        }
      });
    }
    WidgetsBinding.instance.addObserver(this);
    live.addListener(() {
      if (!mounted) return;
      // the GPU route survived loading and a first sentence: it is not crashing
      if (widget.settings.accelTrying && live.decodes > 0) widget.settings.accelTrying = false;
      // the screen stays on while the microphone is open
      if (live.running != _screenOn) {
        _screenOn = live.running;
        _system.invokeMethod('keepScreenOn', {'on': _screenOn}).ignore();
      }
      setState(() {});
      // follow new lines only, so a status change never yanks the list
      if (live.lines.length != _lineCount) {
        _lineCount = live.lines.length;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (scroll.hasClients) {
            scroll.animateTo(scroll.position.maxScrollExtent,
                duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
          }
        });
      }
    });
    // load the speech model now, so the first tap does not wait for it
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) live.preload(asrConfig);
    });
    _prepare([live.mine, if (live.mode == Mode.conversation) live.theirs, if (live.listenFrom.isNotEmpty) live.listenFrom]);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // never listen in the background: the microphone is released when the app leaves the screen
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) live.stop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_screenOn) _system.invokeMethod('keepScreenOn', {'on': false}).ignore();
    live.dispose();
    scroll.dispose();
    super.dispose();
  }

  /// A translation filling the screen, for showing to someone in a noisy place.
  void showBig(Line line) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => BigText(text: line.translation ?? line.heard.text, language: nameOf(line.direction.to)),
    ));
  }

  void copyLine(Line line) {
    Clipboard.setData(ClipboardData(text: '${line.heard.text}\n${line.translation ?? ''}'.trim()));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)));
  }

  AsrConfig get asrConfig => AsrConfig(
        vad: widget.store.pathOf(vadModel.name),
        encoder: widget.store.pathOf(widget.model.encoder.name),
        decoder: widget.store.pathOf(widget.model.decoder.name),
        tokens: widget.store.pathOf(widget.model.tokens.name),
        threads: math.min(4, math.max(1, Platform.numberOfProcessors ~/ 2)),
        provider: widget.settings.accel ? 'nnapi' : 'cpu',
        // you tap your side, so you are expected to finish: close a sentence sooner
        endSilence: live.mode == Mode.conversation && !live.autoSpeaker ? 0.4 : 0.5,
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

  /// Marks the hardware route as "being tried" for the crash guard, then starts.
  AsrConfig startConfig() {
    final c = asrConfig;
    if (c.provider != 'cpu') widget.settings.accelTrying = true;
    return c;
  }

  Future<void> toggle() async {
    if (live.running) {
      await live.stop();
    } else {
      await live.start(startConfig());
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
          onPressed: () => live.tapSide(which, startConfig()),
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
                    leadingIcon: Icon(widget.settings.accel ? Icons.check_box : Icons.check_box_outline_blank),
                    onPressed: locked
                        ? null
                        : () => setState(() => widget.settings.accel = !widget.settings.accel),
                    child: const Text('Use the GPU (experimental)'),
                  ),
                  MenuItemButton(
                      leadingIcon: const Icon(Icons.system_update), onPressed: checkForUpdates, child: const Text('Check for updates')),
                  MenuItemButton(
                    leadingIcon: const Icon(Icons.download_for_offline_outlined),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => OfflineLanguages(engine: live.engine, inUse: {live.mine, live.theirs, live.listenFrom}))),
                    child: const Text('Offline languages…'),
                  ),
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
        if (live.notice != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(live.notice!, style: TextStyle(color: cs.tertiary)),
          ),
        if (live.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(child: Text(live.error!, style: TextStyle(color: cs.error))),
              if (live.error!.contains('permission'))
                TextButton(
                    onPressed: () => _system.invokeMethod('openAppSettings').ignore(), child: const Text('Open settings')),
            ]),
          ),
        Expanded(
          child: live.lines.isEmpty
              ? _Empty(mode: live.mode, running: live.running, auto: live.autoSpeaker)
              : ListView.builder(
                  controller: scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: live.lines.length,
                  itemBuilder: (_, i) => _LineView(
                    line: live.lines[i],
                    mine: live.mine,
                    mode: live.mode,
                    onReplay: () => live.replay(live.lines[i]),
                    onCopy: () => copyLine(live.lines[i]),
                    onShow: () => showBig(live.lines[i]),
                  ),
                ),
        ),
        if (live.modelState == 'loading' || live.modelState == 'failed')
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(children: [
              if (live.modelState == 'loading')
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              else
                Icon(Icons.error_outline, size: 16, color: cs.error),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  live.modelState == 'loading'
                      ? 'Loading the ${widget.model.label} speech model…'
                      : 'The speech model could not be loaded.',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ]),
          )
        else if (live.running || live.phase == 'decoding' || live.phase == 'missed')
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              if (live.phase == 'decoding')
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              else
                Icon(live.phase == 'missed' ? Icons.hearing_disabled : Icons.graphic_eq,
                    size: 16, color: live.phase == 'hearing' ? cs.primary : cs.outline),
              const SizedBox(width: 8),
              Text(
                switch (live.phase) {
                  'hearing' => 'Hearing you…',
                  'decoding' => 'Writing it down…',
                  'missed' => "Didn't catch that. Try again, a little closer.",
                  _ => live.tapMode && live.side == null ? 'Tap a language to speak' : 'Listening',
                },
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ]),
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
  const _LineView(
      {required this.line, required this.mine, required this.mode, required this.onReplay, required this.onCopy, required this.onShow});
  final Line line;
  final String mine;
  final Mode mode;
  final VoidCallback onReplay, onCopy, onShow;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final d = line.direction;
    // in a conversation, what the other person said sits left and is for you; yours sits right
    final forMe = mode == Mode.listen || d.to == mine;
    final hasTranslation = line.translation != null && d.from != d.to;
    return Align(
      alignment: forMe ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
        margin: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: forMe ? cs.secondaryContainer : cs.tertiaryContainer,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            // tap: say it again; long press: copy
            onTap: hasTranslation ? onReplay : null,
            onLongPress: onCopy,
            child: Padding(
        padding: const EdgeInsets.all(12),
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
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Text(line.translation!, style: t.titleMedium)),
              IconButton(
                tooltip: 'Show full screen',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.open_in_full, size: 18),
                onPressed: onShow,
              ),
            ]),
        ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// One translation, as big as the screen allows: hand the phone over, or hold
/// it up in a noisy place. The flip button turns it to face the person across
/// the table.
class BigText extends StatefulWidget {
  const BigText({super.key, required this.text, required this.language});
  final String text, language;
  @override
  State<BigText> createState() => _BigTextState();
}

class _BigTextState extends State<BigText> {
  bool flipped = false;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.language),
        actions: [
          IconButton(
            tooltip: 'Turn to face the other person',
            icon: const Icon(Icons.screen_rotation_alt),
            onPressed: () => setState(() => flipped = !flipped),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: RotatedBox(
            quarterTurns: flipped ? 2 : 0,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width - 48),
                  child: Text(widget.text,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w600, height: 1.25)),
                ),
              ),
            ),
          ),
        ),
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

/// Translation packs on this phone: download before a trip (works offline
/// after), delete to free space. The languages in use cannot be deleted here.
class OfflineLanguages extends StatefulWidget {
  const OfflineLanguages({super.key, required this.engine, required this.inUse});
  final TranslationEngine engine;
  final Set<String> inUse;
  @override
  State<OfflineLanguages> createState() => _OfflineLanguagesState();
}

class _OfflineLanguagesState extends State<OfflineLanguages> {
  final ready = <String, bool>{};
  final busy = <String>{};
  String q = '';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    for (final l in allLanguages().where((l) => widget.engine.supports(l.code))) {
      final r = await widget.engine.isReady(l.code);
      if (!mounted) return;
      setState(() => ready[l.code] = r);
    }
  }

  Future<void> _toggle(Language l) async {
    setState(() => busy.add(l.code));
    try {
      if (ready[l.code] == true) {
        await widget.engine.delete(l.code);
      } else {
        await widget.engine.prepare(l.code);
      }
      ready[l.code] = await widget.engine.isReady(l.code);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
    if (mounted) setState(() => busy.remove(l.code));
  }

  @override
  Widget build(BuildContext context) {
    final langs = allLanguages()
        .where((l) => widget.engine.supports(l.code) && l.name.toLowerCase().contains(q.toLowerCase()))
        .toList()
      ..sort((a, b) => (ready[a.code] == true ? 0 : 1).compareTo(ready[b.code] == true ? 0 : 1));
    final count = ready.values.where((v) => v).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Offline languages')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text('$count on this phone. Download the languages of your trip while you have Wi-Fi: '
              'after that, translation works with no connection. About 30 MB each.'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search languages'),
            onChanged: (v) => setState(() => q = v.trim()),
          ),
        ),
        Expanded(
          child: ListView(children: [
            for (final l in langs)
              ListTile(
                title: Text(l.name),
                subtitle: Text(l.code == 'en'
                    ? 'Built in'
                    : ready[l.code] == true
                        ? (widget.inUse.contains(l.code) ? 'On this phone · in use' : 'On this phone')
                        : 'Not downloaded'),
                trailing: busy.contains(l.code)
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : l.code == 'en'
                        ? null
                        : ready[l.code] == true
                            ? IconButton(
                                tooltip: 'Delete',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: widget.inUse.contains(l.code) ? null : () => _toggle(l),
                              )
                            : IconButton(tooltip: 'Download', icon: const Icon(Icons.download), onPressed: () => _toggle(l)),
              ),
          ]),
        ),
      ]),
    );
  }
}
