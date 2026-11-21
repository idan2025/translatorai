import 'package:flutter/material.dart';

import 'src/model_store.dart';
import 'src/models.dart';
import 'src/languages.dart';
import 'src/pipeline.dart';
import 'src/settings.dart';

/// What the settings screen needs from the home screen: the app's state, and
/// the few actions that touch the running translator.
class SettingsActions {
  const SettingsActions({
    required this.useModel,
    required this.packsChanged,
    required this.settle,
    required this.isBusy,
    required this.freeTranslationPack,
    required this.checkForUpdates,
    required this.offlineLanguages,
    required this.qualityTest,
    required this.about,
    required this.exit,
  });

  /// Makes a downloaded speech model the one in use (closes this screen).
  final void Function(SpeechModel) useModel;

  /// A speech or translation pack came or went: reload what the translator may load.
  final Future<void> Function() packsChanged;

  /// Closes a microphone that is only waiting.
  final Future<void> Function() settle;

  /// Listening for real: nothing may be switched or deleted now.
  final bool Function() isBusy;

  /// Unloads the translation pack's models, before its files are deleted.
  final Future<void> Function() freeTranslationPack;

  final VoidCallback checkForUpdates, offlineLanguages, qualityTest, about, exit;
}

/// All settings on one tidy screen: what is downloaded (and what can be
/// downloaded ahead of time, one item at a time), how listening behaves, and the app.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    required this.store,
    required this.live,
    required this.model,
    required this.version,
    required this.ramGb,
    required this.actions,
  });

  final Settings settings;
  final ModelStore store;
  final LiveTranslator live;
  final SpeechModel model;
  final String version;
  final double ramGb;
  final SettingsActions actions;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// The item being downloaded (one at a time) and how far along it is.
  String? _loading;
  double _progress = 0;

  Settings get s => widget.settings;
  ModelStore get store => widget.store;
  SettingsActions get a => widget.actions;

  void _say(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _download(String id, List<ModelFile> files, {Future<void> Function()? after}) async {
    if (_loading != null) return;
    setState(() {
      _loading = id;
      _progress = 0;
    });
    try {
      await store.ensure([vadModel, ...files], onProgress: (d, t) {
        if (mounted) setState(() => _progress = d / t);
      });
      await after?.call();
    } catch (e) {
      if (mounted) _say('$e');
    }
    if (mounted) setState(() => _loading = null);
  }

  Future<bool> _confirmDelete(String what, int bytes) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete $what?'),
        content: Text('This frees ${_size(bytes)}. You can download it again later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    return ok == true;
  }

  static String _size(int bytes) => bytes >= 1e9 ? '${(bytes / 1e9).toStringAsFixed(1)} GB' : '${(bytes / 1e6).round()} MB';

  /// One row of the Downloads section.
  Widget _item({
    required String id,
    required IconData icon,
    required String title,
    required String note,
    required int bytes,
    required bool installed,
    required VoidCallback onDownload,
    VoidCallback? onDelete,
    VoidCallback? onUse,
    bool inUse = false,
    String? warning,
  }) {
    final cs = Theme.of(context).colorScheme;
    final loading = _loading == id;
    final other = _loading != null && !loading;
    Widget trailing;
    if (loading) {
      trailing = SizedBox(
          width: 40, height: 40, child: Center(child: Text('${(_progress * 100).round()}%', style: Theme.of(context).textTheme.labelMedium)));
    } else if (!installed) {
      trailing = FilledButton.tonal(onPressed: other ? null : onDownload, child: Text('Get ${_size(bytes)}'));
    } else if (inUse) {
      trailing = Chip(label: const Text('In use'), visualDensity: VisualDensity.compact, side: BorderSide(color: cs.primary));
    } else if (onUse != null) {
      trailing = OutlinedButton(onPressed: other ? null : onUse, child: const Text('Use'));
    } else {
      trailing = Icon(Icons.check_circle, color: cs.primary);
    }
    return Column(children: [
      ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text('$note${installed ? '\nOn this phone · ${_size(bytes)}' : ''}${warning == null ? '' : '\n$warning'}'),
        isThreeLine: true,
        trailing: trailing,
        // a long press / menu is not needed: delete has its own visible button below
      ),
      if (loading) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: LinearProgressIndicator(value: _progress)),
      if (installed && onDelete != null && !inUse && !loading)
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: other ? null : onDelete,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Delete'),
            ),
          ),
        ),
    ]);
  }

  Widget _section(String title, List<Widget> children, {String? hint}) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: t.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
        if (hint != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(hint, style: t.bodySmall)),
        const SizedBox(height: 8),
        Card(margin: EdgeInsets.zero, clipBehavior: Clip.antiAlias, child: Column(children: _divided(children))),
      ]),
    );
  }

  static List<Widget> _divided(List<Widget> items) =>
      [for (var i = 0; i < items.length; i++) ...[if (i > 0) const Divider(height: 1), items[i]]];

  int get _onPhone {
    var n = 0;
    final seen = <String>{};
    void add(List<ModelFile> files) {
      for (final f in files) {
        if (store.has(f) && seen.add(f.name)) n += f.bytes;
      }
    }

    add([vadModel]);
    for (final m in speechModels) {
      add(m.files);
    }
    for (final k in languagePacks) {
      add(k.files);
    }
    for (final t in translationPacks) {
      add(t.files);
    }
    return n;
  }

  Widget _speechModels() {
    return _section(
      'Speech model',
      [
        for (final m in speechModels)
          _item(
            id: m.id,
            icon: Icons.record_voice_over,
            title: m.label,
            note: m.note,
            bytes: m.bytes,
            installed: store.hasAll(m.files),
            inUse: m.id == widget.model.id,
            onDownload: () => _download(m.id, m.files),
            onUse: a.isBusy() ? null : () => a.useModel(m),
            onDelete: () async {
              if (a.isBusy() || !await _confirmDelete('the ${m.label} model', m.bytes)) return;
              await store.deleteModel(m.files, except: widget.model.files);
              if (mounted) setState(() {});
            },
          ),
      ],
      hint: 'Pick one to listen with. Download others ahead of time to switch without waiting.',
    );
  }

  Widget _packs() {
    final he = hebrewPack, mt = hebrewTranslationPack;
    final lowRam = widget.ramGb > 0 && widget.ramGb < 5;
    return _section(
      'Hebrew packs',
      [
        _item(
          id: he.id,
          icon: Icons.graphic_eq,
          title: he.label,
          note: 'Understands Hebrew much better (about a quarter fewer wrong words). Used only when Hebrew is spoken.',
          bytes: he.bytes,
          installed: store.hasAll(he.files),
          warning: lowRam ? 'This phone has ${widget.ramGb.toStringAsFixed(1)} GB of memory; it may run out of memory with this pack.' : null,
          onDownload: () => _download(he.id, he.files, after: () async {
            s.hebrewPack = true;
            await a.packsChanged();
          }),
          onDelete: () async {
            if (a.isBusy() || !await _confirmDelete('the ${he.label.toLowerCase()}', he.bytes)) return;
            await a.settle();
            await store.deleteModel(he.files, except: widget.model.files);
            await a.packsChanged();
            if (mounted) setState(() {});
          },
        ),
        _item(
          id: mt.id,
          icon: Icons.translate,
          title: mt.label,
          note: 'More fluent Hebrew ⇄ English translation, fully offline.',
          bytes: mt.bytes,
          installed: store.hasAll(mt.files),
          onDownload: () => _download(mt.id, mt.files, after: a.packsChanged),
          onDelete: () async {
            if (!await _confirmDelete('the ${mt.label.toLowerCase()}', mt.bytes)) return;
            await a.freeTranslationPack(); // its models leave memory before their files go
            await store.deleteModel(mt.files);
            if (mounted) setState(() {});
          },
        ),
      ],
      hint: 'Optional. Download only what you will use.',
    );
  }

  Widget _languages() => _section(
        'Translation languages',
        [
          ListTile(
            leading: const Icon(Icons.download_for_offline_outlined),
            title: const Text('Offline languages'),
            subtitle: const Text('Download or delete the translator for each language (about 30 MB each).'),
            trailing: const Icon(Icons.chevron_right),
            onTap: a.offlineLanguages,
          ),
        ],
      );

  /// A short sentence in each common language, to hear a voice before picking it.
  static const _sample = {
    'en': 'Hello, this is my voice.',
    'he': 'שלום, זה הקול שלי.',
    'es': 'Hola, esta es mi voz.',
    'fr': 'Bonjour, voici ma voix.',
    'de': 'Hallo, das ist meine Stimme.',
    'it': 'Ciao, questa è la mia voce.',
    'pt': 'Olá, esta é a minha voz.',
    'ru': 'Привет, это мой голос.',
    'ar': 'مرحبا، هذا صوتي.',
    'tr': 'Merhaba, bu benim sesim.',
    'zh': '你好，这是我的声音。',
    'ja': 'こんにちは、これは私の声です。',
  };

  Widget _voiceRow(String code) {
    final picked = s.voiceFor(code);
    return ListTile(
      leading: const Icon(Icons.record_voice_over_outlined),
      title: Text(nameOf(code)),
      subtitle: Text(picked.isEmpty ? 'Phone default' : picked),
      trailing: IconButton(
        tooltip: 'Hear it',
        icon: const Icon(Icons.play_circle_outline),
        onPressed: () => widget.live.speaker.say(_sample[code] ?? _sample['en']!, code),
      ),
      onTap: () => _pickVoice(code),
    );
  }

  Future<void> _pickVoice(String code) async {
    final speaker = widget.live.speaker;
    final voices = await speaker.voices(code);
    final engine = await speaker.engineName();
    if (!mounted) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.7),
          child: RadioGroup<String>(
            groupValue: s.voiceFor(code),
            onChanged: (v) => Navigator.pop(c, v ?? ''),
            child: ListView(shrinkWrap: true, children: [
              ListTile(
                title: Text('Voice for ${nameOf(code)}', style: Theme.of(c).textTheme.titleMedium),
                subtitle: Text(voices.isEmpty
                    ? 'The phone has no voice for this language. Install one in Android Settings › Text-to-speech output.'
                    : '${voices.length} voice${voices.length == 1 ? '' : 's'} on this phone · engine $engine'),
              ),
              const RadioListTile<String>(value: '', title: Text('Phone default')),
              for (final v in voices)
                RadioListTile<String>(
                    value: v,
                    title: Text(v, overflow: TextOverflow.ellipsis),
                    subtitle: speaker.needsNetwork(v) ? const Text('needs internet') : null),
            ]),
          ),
        ),
      ),
    );
    if (choice == null) return;
    s.setVoiceFor(code, choice);
    if (mounted) setState(() {});
    await speaker.say(_sample[code] ?? _sample['en']!, code);
    if (mounted) _say('Speaking with: ${speaker.voiceStatus}');
  }

  Widget _voices() {
    final codes = {widget.live.mine, widget.live.theirs}.toList();
    return _section(
      'Voices',
      [for (final c in codes) _voiceRow(c)],
      hint: 'The voice that reads a translation aloud, per language. Tap to choose; the play button tries it.',
    );
  }

  Widget _listening() {
    final locked = a.isBusy();
    Widget toggle(String title, String note, bool value, ValueChanged<bool>? onChanged) =>
        SwitchListTile(title: Text(title), subtitle: Text(note), value: value, onChanged: onChanged);
    return _section('Listening', [
      toggle('Words while I speak', 'Show the words so far, and their translation, before the sentence ends.', widget.live.showPartials,
          (v) => setState(() => widget.live.showPartials = s.partials = v)),
      toggle('Detect who speaks', 'In conversation mode, tell the two voices apart. Slower.', widget.live.autoSpeaker, locked
          ? null
          : (v) async {
              await a.settle();
              setState(() => widget.live.autoSpeaker = s.autoSpeaker = v);
            }),
      if (widget.live.mine == 'he' || widget.live.theirs == 'he')
        ListTile(
          title: const Text('I speak Hebrew as'),
          subtitle: const Text('Hebrew you say aloud for a woman: "אני עייפה", not "אני עייף".'),
          trailing: DropdownButton<String>(
            value: s.gender,
            items: const [
              DropdownMenuItem(value: '', child: Text('Not set')),
              DropdownMenuItem(value: 'f', child: Text('A woman')),
              DropdownMenuItem(value: 'm', child: Text('A man')),
            ],
            onChanged: (v) => setState(() => s.gender = v ?? ''),
          ),
        ),
      toggle('Use the GPU', 'Experimental. Turns itself off if it crashes.', s.accel, locked ? null : (v) => setState(() => s.accel = v)),
    ]);
  }

  Widget _app() => _section('App', [
        ListTile(leading: const Icon(Icons.system_update), title: const Text('Check for updates'), onTap: a.checkForUpdates),
        ListTile(leading: const Icon(Icons.science_outlined), title: const Text('Translation quality test'), onTap: a.qualityTest),
        ListTile(leading: const Icon(Icons.info_outline), title: Text('About · version ${widget.version}'), onTap: a.about),
        ListTile(leading: const Icon(Icons.exit_to_app), title: const Text('Exit'), onTap: a.exit),
      ]);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _loading == null, // leaving would orphan a download's progress
      child: Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text('Models on this phone: ${_size(_onPhone)}', style: Theme.of(context).textTheme.bodySmall),
          ),
          _speechModels(),
          _packs(),
          _voices(),
          _languages(),
          _listening(),
          _app(),
        ]),
      ),
    );
  }
}
