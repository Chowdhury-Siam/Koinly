part of '../main.dart';

enum _ProfilePermissionAction { retry, openSettings, cancel }

Future<bool> requestProfileMediaPermissionFlow(
  BuildContext context,
  AppController state,
) async {
  // Do not request Android media access during startup or onboarding. This
  // flow is entered only after the user explicitly taps the profile-media
  // upload action.
  var permission = await state.profileMediaPermissions.check();

  if (permission == ProfileMediaPermissionState.denied) {
    permission = await state.profileMediaPermissions.request();
  }

  while (context.mounted) {
    if (permission == ProfileMediaPermissionState.granted ||
        permission == ProfileMediaPermissionState.notRequired) {
      return true;
    }

    final action = await showProfileMediaPermissionDialog(context, permission);
    if (!context.mounted || action == null || action == _ProfilePermissionAction.cancel) {
      return false;
    }
    if (action == _ProfilePermissionAction.openSettings) {
      await state.profileMediaPermissions.openSettings();
      return false;
    }
    permission = await state.profileMediaPermissions.request();
  }
  return false;
}

Future<_ProfilePermissionAction?> showProfileMediaPermissionDialog(
  BuildContext context,
  ProfileMediaPermissionState permission,
) {
  final permanentlyDenied = permission == ProfileMediaPermissionState.permanentlyDenied;
  return showDialog<_ProfilePermissionAction>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.perm_media_rounded, color: kSleekAccent, size: 34),
      title: const Text('Photos and videos access'),
      content: Text(
        permanentlyDenied
            ? 'Access is turned off in Android settings. Enable Photos and videos access so you can choose profile media.'
            : 'Koinly needs Photos and videos access only when you choose a photo, GIF, or short video for your profile.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, _ProfilePermissionAction.cancel),
          child: const Text('Not now'),
        ),
        if (permanentlyDenied)
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, _ProfilePermissionAction.openSettings),
            icon: const Icon(Icons.settings_rounded),
            label: const Text('Open settings'),
          )
        else
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, _ProfilePermissionAction.retry),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
      ],
    ),
  );
}

Future<void> pickAndSaveProfileMedia(BuildContext context, AppController state) async {
  final allowed = await requestProfileMediaPermissionFlow(context, state);
  if (!context.mounted || !allowed) return;

  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ProfileMediaStorage.allowedExtensions,
    allowMultiple: false,
    withData: false,
    lockParentWindow: true,
  );
  if (!context.mounted || result == null || result.files.isEmpty) return;

  final picked = result.files.single;
  try {
    if (picked.size > kProfileMediaMaxBytes) {
      throw const ProfileMediaException(kProfileMediaSizeMessage);
    }
    if (ProfileMediaStorage.kindForFileName(picked.name) == null) {
      throw const ProfileMediaException('Choose a JPG, PNG, WebP, GIF, MP4, MOV, M4V, or WebM file.');
    }
    await state.replaceProfileMedia(
      originalName: picked.name,
      bytes: picked.bytes,
      sourcePath: picked.path,
    );
    if (context.mounted) showSnack(context, 'Profile media updated.');
  } on ProfileMediaException catch (error) {
    if (context.mounted) showSnack(context, error.message);
  } on FileSystemException {
    if (context.mounted) showSnack(context, 'The selected profile media could not be read.');
  } catch (_) {
    if (context.mounted) showSnack(context, 'Could not update profile media. Please try another file.');
  }
}

class ProfileAvatarButton extends StatelessWidget {
  const ProfileAvatarButton({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    return Tooltip(
      message: 'Open profile',
      child: Semantics(
        button: true,
        label: 'Open profile',
        child: MotionPressable(
          borderRadius: AppShapes.full,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProfileScreen()),
          ),
          child: Container(
            width: 48,
            height: 48,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: kSleekAccent.withOpacity(.14),
              border: Border.all(color: kSleekAccent.withOpacity(.70), width: 1.4),
            ),
            child: ProfileMediaView(
              path: state.hasProfileMedia ? state.profileMediaPath : '',
              kind: state.hasProfileMedia ? state.profileMediaKind : null,
              displayName: state.profileDisplayLabel,
              scale: state.profileMediaScale,
              alignmentX: state.profileMediaAlignmentX,
              alignmentY: state.profileMediaAlignmentY,
              borderRadius: 999,
            ),
          ),
        ),
      ),
    );
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController displayName;
  bool mediaBusy = false;
  bool profileBusy = false;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppController>();
    displayName = TextEditingController(text: state.profileDisplayName);
  }

  @override
  void dispose() {
    displayName.dispose();
    super.dispose();
  }

  Future<void> _pickMedia() async {
    if (mediaBusy) return;
    setState(() => mediaBusy = true);
    try {
      await pickAndSaveProfileMedia(context, context.read<AppController>());
    } finally {
      if (mounted) setState(() => mediaBusy = false);
    }
  }

  Future<void> _removeMedia() async {
    if (mediaBusy) return;
    final remove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove profile media?'),
        content: const Text('Your profile will return to the default avatar.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Remove')),
        ],
      ),
    );
    if (remove != true || !mounted) return;
    setState(() => mediaBusy = true);
    await context.read<AppController>().removeProfileMedia();
    if (mounted) {
      setState(() => mediaBusy = false);
      showSnack(context, 'Profile media removed.');
    }
  }

  Future<void> _saveProfile() async {
    if (profileBusy) return;
    setState(() => profileBusy = true);
    await context.read<AppController>().saveUserProfile(
          displayName: displayName.text,
        );
    if (mounted) {
      setState(() => profileBusy = false);
      showSnack(context, 'Profile information saved.');
    }
  }

  Future<void> _editMediaFraming() async {
    final state = context.read<AppController>();
    if (!state.hasProfileMedia || mediaBusy) return;
    await showKoinlyPopup<void>(
      context,
      maxWidth: 620,
      maxHeight: 760,
      child: const ProfileMediaFramingEditor(),
    );
  }

  void _previewMedia() {
    final state = context.read<AppController>();
    if (!state.hasProfileMedia) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Profile media preview', style: Theme.of(dialogContext).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                    ),
                    IconButton(onPressed: () => Navigator.pop(dialogContext), icon: const Icon(Icons.close_rounded)),
                  ],
                ),
                const SizedBox(height: 12),
                Center(
                  child: SizedBox(
                    width: math.min(420.0, MediaQuery.sizeOf(dialogContext).width - 72),
                    height: math.min(420.0, MediaQuery.sizeOf(dialogContext).width - 72),
                    child: ProfileMediaView(
                      path: state.profileMediaPath,
                      kind: state.profileMediaKind,
                      displayName: state.profileDisplayLabel,
                      scale: state.profileMediaScale,
                      alignmentX: state.profileMediaAlignmentX,
                      alignmentY: state.profileMediaAlignmentY,
                      borderRadius: 28,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    return PageScaffold(
      title: 'Profile',
      subtitle: 'Personal details and media',
      child: ResponsiveContent(
        mobileMaxWidth: 760,
        desktopMaxWidth: 1180,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final mediaCard = _ProfileMediaCard(
              state: state,
              busy: mediaBusy,
              onPick: _pickMedia,
              onEditFraming: _editMediaFraming,
              onPreview: _previewMedia,
              onRemove: _removeMedia,
            );
            final informationCard = _ProfileInformationCard(
              displayName: displayName,
              username: state.syncAccountUsername,
              busy: profileBusy,
              onSave: _saveProfile,
            );

            if (constraints.maxWidth >= 820) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: mediaCard),
                  const SizedBox(width: 16),
                  Expanded(child: informationCard),
                ],
              );
            }
            return Column(
              children: [
                mediaCard,
                const SizedBox(height: 14),
                informationCard,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProfileMediaCard extends StatelessWidget {
  const _ProfileMediaCard({
    required this.state,
    required this.busy,
    required this.onPick,
    required this.onEditFraming,
    required this.onPreview,
    required this.onRemove,
  });

  final AppController state;
  final bool busy;
  final VoidCallback onPick;
  final VoidCallback onEditFraming;
  final VoidCallback onPreview;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final hasMedia = state.hasProfileMedia;
    final mediaKind = state.profileMediaKind;
    return ExpressiveCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.perm_media_rounded, color: kSleekAccent),
              const SizedBox(width: 10),
              Expanded(child: Text('Profile media', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: Container(
              width: 156,
              height: 156,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: kSleekAccent.withOpacity(.62), width: 2),
                boxShadow: [BoxShadow(color: kSleekAccent.withOpacity(.14), blurRadius: 28, offset: const Offset(0, 12))],
              ),
              child: ProfileMediaView(
                path: hasMedia ? state.profileMediaPath : '',
                kind: hasMedia ? mediaKind : null,
                displayName: state.profileDisplayLabel,
                scale: state.profileMediaScale,
                alignmentX: state.profileMediaAlignmentX,
                alignmentY: state.profileMediaAlignmentY,
                borderRadius: 999,
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (!hasMedia)
            Text(
              'Add a photo, animated GIF, or short video.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
            )
          else
            Text(
              'You can reposition and crop the current media without choosing it again.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
            ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: busy ? null : onPick,
                icon: busy
                    ? const KoinlyInlineLoader(size: 18)
                    : Icon(hasMedia ? Icons.swap_horiz_rounded : Icons.add_photo_alternate_rounded),
                label: Text(hasMedia ? 'Replace' : 'Add media'),
              ),
              if (hasMedia)
                OutlinedButton.icon(
                  onPressed: busy ? null : onEditFraming,
                  icon: const Icon(Icons.crop_rounded),
                  label: const Text('Reposition & crop'),
                ),
              if (hasMedia)
                OutlinedButton.icon(
                  onPressed: busy ? null : onPreview,
                  icon: const Icon(Icons.visibility_rounded),
                  label: const Text('Preview'),
                ),
              if (hasMedia)
                TextButton.icon(
                  onPressed: busy ? null : onRemove,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Remove'),
                ),
            ],
          ),
          if (!hasMedia) ...[
            const SizedBox(height: 12),
            Text(
              'JPG, PNG, WebP, GIF, MP4, MOV, M4V, or WebM • maximum 50 MB',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileInformationCard extends StatelessWidget {
  const _ProfileInformationCard({
    required this.displayName,
    required this.username,
    required this.busy,
    required this.onSave,
  });

  final TextEditingController displayName;
  final String username;
  final bool busy;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return ExpressiveCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.badge_rounded, color: kSleekAccent),
              const SizedBox(width: 10),
              Expanded(child: Text('Profile information', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
            ],
          ),
          const SizedBox(height: 16),
          TextField(contextMenuBuilder: koinlyTextFieldContextMenu, enableInteractiveSelection: true, 
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            controller: displayName,
            maxLength: 60,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Display name', hintText: 'How should Koinly address you?'),
          ),
          if (username.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_rounded, color: kSleekAccent),
              title: const Text('Sync account'),
              subtitle: Text(username.trim()),
            ),
          ],
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: busy ? null : onSave,
            icon: const Icon(Icons.save_rounded),
            label: const Text('Save profile information'),
          ),
        ],
      ),
    );
  }
}

class ProfileMediaFramingEditor extends StatefulWidget {
  const ProfileMediaFramingEditor({super.key});

  @override
  State<ProfileMediaFramingEditor> createState() => _ProfileMediaFramingEditorState();
}

class _ProfileMediaFramingEditorState extends State<ProfileMediaFramingEditor> {
  late double scale;
  late double alignmentX;
  late double alignmentY;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppController>();
    scale = state.profileMediaScale;
    alignmentX = state.profileMediaAlignmentX;
    alignmentY = state.profileMediaAlignmentY;
  }

  void _reset() {
    setState(() {
      scale = 1.0;
      alignmentX = 0.0;
      alignmentY = 0.0;
    });
  }

  void _move(DragUpdateDetails details) {
    setState(() {
      // Alignment is intentionally inverted so the media follows the finger:
      // dragging right reveals more of the left side of the source.
      alignmentX = (alignmentX - details.delta.dx / 110).clamp(-1.0, 1.0).toDouble();
      alignmentY = (alignmentY - details.delta.dy / 110).clamp(-1.0, 1.0).toDouble();
    });
  }

  Future<void> _save() async {
    if (saving) return;
    setState(() => saving = true);
    await context.read<AppController>().saveProfileMediaFraming(
          scale: scale,
          alignmentX: alignmentX,
          alignmentY: alignmentY,
        );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    if (!state.hasProfileMedia) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('Profile media is no longer available.'),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: KoinlyPopupContent(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Reposition & crop',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'Drag the media to reposition it. Increase zoom to crop tighter.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: _move,
                child: Container(
                  width: 300,
                  height: 300,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: kSleekAccent.withOpacity(.75), width: 2),
                  ),
                  child: ProfileMediaView(
                    path: state.profileMediaPath,
                    kind: state.profileMediaKind,
                    displayName: state.profileDisplayLabel,
                    scale: scale,
                    alignmentX: alignmentX,
                    alignmentY: alignmentY,
                    borderRadius: 999,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const Icon(Icons.zoom_in_rounded, color: kSleekAccent),
                const SizedBox(width: 10),
                const Text('Zoom', style: TextStyle(fontWeight: FontWeight.w800)),
                const Spacer(),
                Text('${scale.toStringAsFixed(2)}×', style: const TextStyle(color: kSleekAccent, fontWeight: FontWeight.w900)),
              ],
            ),
            Slider(
              min: 1.0,
              max: 3.0,
              divisions: 40,
              value: scale.clamp(1.0, 3.0).toDouble(),
              onChanged: (value) => setState(() => scale = value),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: saving ? null : _reset,
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text('Reset'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: saving ? null : _save,
                    icon: saving
                        ? const KoinlyInlineLoader(size: 18)
                        : const Icon(Icons.check_rounded),
                    label: const Text('Save crop'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ProfileMediaView extends StatelessWidget {
  const ProfileMediaView({
    super.key,
    required this.path,
    required this.kind,
    required this.displayName,
    this.fit = BoxFit.cover,
    this.scale = 1.0,
    this.alignmentX = 0.0,
    this.alignmentY = 0.0,
    this.borderRadius = 0,
  });

  final String path;
  final ProfileMediaKind? kind;
  final String displayName;
  final BoxFit fit;
  final double scale;
  final double alignmentX;
  final double alignmentY;
  final double borderRadius;

  String get _initials {
    final words = displayName.trim().split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();
    if (words.isEmpty || displayName == 'Profile') return '';
    return words.take(2).map((word) => word.substring(0, 1).toUpperCase()).join();
  }

  Widget _fallback(BuildContext context) {
    final initials = _initials;
    return ColoredBox(
      color: kSleekAccent.withOpacity(.16),
      child: Center(
        child: initials.isEmpty
            ? const Icon(Icons.person_rounded, color: kSleekAccent, size: 30)
            : Text(initials, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: kSleekAccent, fontWeight: FontWeight.w900)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    final fileExists = path.trim().isNotEmpty && File(path).existsSync();
    if (!fileExists || kind == null) {
      child = _fallback(context);
    } else if (kind == ProfileMediaKind.video) {
      child = _ProfileVideoView(
        key: ValueKey(path),
        path: path,
        fit: fit,
        alignment: Alignment(
          alignmentX.clamp(-1.0, 1.0).toDouble(),
          alignmentY.clamp(-1.0, 1.0).toDouble(),
        ),
      );
    } else {
      child = Image.file(
        File(path),
        fit: fit,
        alignment: Alignment(
          alignmentX.clamp(-1.0, 1.0).toDouble(),
          alignmentY.clamp(-1.0, 1.0).toDouble(),
        ),
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => _fallback(context),
      );
    }
    final framed = Transform.scale(
      scale: scale.clamp(1.0, 3.0).toDouble(),
      alignment: Alignment(
        alignmentX.clamp(-1.0, 1.0).toDouble(),
        alignmentY.clamp(-1.0, 1.0).toDouble(),
      ),
      child: child,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: ClipRect(child: SizedBox.expand(child: framed)),
      ),
    );
  }
}

class _ProfileVideoView extends StatefulWidget {
  const _ProfileVideoView({
    super.key,
    required this.path,
    required this.fit,
    required this.alignment,
  });

  final String path;
  final BoxFit fit;
  final Alignment alignment;

  @override
  State<_ProfileVideoView> createState() => _ProfileVideoViewState();
}

class _ProfileVideoViewState extends State<_ProfileVideoView> {
  VideoPlayerController? controller;
  bool ready = false;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _ProfileVideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _load();
  }

  Future<void> _load() async {
    final previous = controller;
    controller = null;
    if (previous != null) await previous.dispose();
    if (!mounted) return;
    setState(() {
      ready = false;
      failed = false;
    });
    final next = VideoPlayerController.file(File(widget.path));
    controller = next;
    try {
      await next.initialize();
      await next.setLooping(true);
      await next.setVolume(0);
      await next.play();
      if (!mounted || controller != next) {
        await next.dispose();
        return;
      }
      setState(() => ready = true);
    } catch (_) {
      if (controller == next) {
        controller = null;
        await next.dispose();
      }
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  void dispose() {
    final current = controller;
    controller = null;
    if (current != null) unawaited(current.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = controller;
    if (failed) {
      return const Center(child: Icon(Icons.videocam_off_rounded, color: kSleekMuted));
    }
    if (!ready || current == null || !current.value.isInitialized) {
      return const KoinlyInlineLoader(size: 24);
    }
    final size = current.value.size;
    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: widget.fit,
          alignment: widget.alignment,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: math.max(1.0, size.width).toDouble(),
            height: math.max(1.0, size.height).toDouble(),
            child: VideoPlayer(current),
          ),
        ),
      ),
    );
  }
}
