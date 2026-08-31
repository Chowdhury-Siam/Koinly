part of '../main.dart';

enum _ProfilePermissionAction { retry, openSettings, cancel }

class ProfileMediaPermissionGate extends StatefulWidget {
  const ProfileMediaPermissionGate({super.key, required this.child});

  final Widget child;

  @override
  State<ProfileMediaPermissionGate> createState() => _ProfileMediaPermissionGateState();
}

class _ProfileMediaPermissionGateState extends State<ProfileMediaPermissionGate> {
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scheduled || !Platform.isAndroid) return;
    final state = context.read<AppController>();
    if (state.profileMediaPermissionPrompted) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await state.markProfileMediaPermissionPrompted();
      if (!mounted) return;
      await requestProfileMediaPermissionFlow(
        context,
        state,
        requestImmediately: true,
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<bool> requestProfileMediaPermissionFlow(
  BuildContext context,
  AppController state, {
  bool requestImmediately = false,
}) async {
  var permission = requestImmediately
      ? await state.profileMediaPermissions.request()
      : await state.profileMediaPermissions.check();

  if (!requestImmediately && permission == ProfileMediaPermissionState.denied) {
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
  late final TextEditingController bio;
  late final TextEditingController hobby;
  late final TextEditingController occupation;
  late final TextEditingController age;
  late final TextEditingController goal;
  late final TextEditingController spendingPreference;
  late final TextEditingController extraDetails;
  bool mediaBusy = false;
  bool profileBusy = false;
  bool savingsBusy = false;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppController>();
    final savings = state.savingsSuggestionProfile;
    displayName = TextEditingController(text: state.profileDisplayName);
    bio = TextEditingController(text: state.profileBio);
    hobby = TextEditingController(text: savings.hobby);
    occupation = TextEditingController(text: savings.occupation);
    age = TextEditingController(text: savings.age <= 0 ? '' : '${savings.age}');
    goal = TextEditingController(text: savings.savingsGoal);
    spendingPreference = TextEditingController(text: savings.spendingPreference);
    extraDetails = TextEditingController(text: savings.extraDetails);
  }

  @override
  void dispose() {
    displayName.dispose();
    bio.dispose();
    hobby.dispose();
    occupation.dispose();
    age.dispose();
    goal.dispose();
    spendingPreference.dispose();
    extraDetails.dispose();
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
          bio: bio.text,
        );
    if (mounted) {
      setState(() => profileBusy = false);
      showSnack(context, 'Profile information saved.');
    }
  }

  Future<void> _saveSavings() async {
    if (savingsBusy) return;
    setState(() => savingsBusy = true);
    final profile = SavingsSuggestionProfile(
      completed: true,
      hobby: hobby.text.trim(),
      occupation: occupation.text.trim(),
      age: int.tryParse(age.text.trim()) ?? 0,
      savingsGoal: goal.text.trim(),
      spendingPreference: spendingPreference.text.trim(),
      extraDetails: extraDetails.text.trim(),
      updatedOn: DateTime.now(),
    );
    await context.read<AppController>().saveSavingsSuggestionProfile(profile);
    if (mounted) {
      setState(() => savingsBusy = false);
      showSnack(context, 'Savings Suggestion preferences saved.');
    }
  }

  Future<void> _resetSavings() async {
    final reset = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset Savings Suggestion preferences?'),
        content: const Text('This clears the personal details used to tailor optional savings ideas.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Reset')),
        ],
      ),
    );
    if (reset != true || !mounted) return;
    hobby.clear();
    occupation.clear();
    age.clear();
    goal.clear();
    spendingPreference.clear();
    extraDetails.clear();
    await context.read<AppController>().saveSavingsSuggestionProfile(
          SavingsSuggestionProfile.empty.copyWith(
            completed: true,
            updatedOn: DateTime.now(),
          ),
        );
    if (mounted) showSnack(context, 'Savings Suggestion preferences reset.');
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
                SizedBox(
                  height: math.min(420.0, MediaQuery.sizeOf(dialogContext).height * .58),
                  child: ProfileMediaView(
                    path: state.profileMediaPath,
                    kind: state.profileMediaKind,
                    displayName: state.profileDisplayLabel,
                    fit: BoxFit.contain,
                    borderRadius: 24,
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
      subtitle: 'Personal details, media, and savings preferences',
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
              onPreview: _previewMedia,
              onRemove: _removeMedia,
            );
            final informationCard = _ProfileInformationCard(
              displayName: displayName,
              bio: bio,
              email: state.syncAccountEmail,
              busy: profileBusy,
              onSave: _saveProfile,
            );
            final savingsCard = _SavingsSuggestionProfileCard(
              hobby: hobby,
              occupation: occupation,
              age: age,
              goal: goal,
              spendingPreference: spendingPreference,
              extraDetails: extraDetails,
              busy: savingsBusy,
              onSave: _saveSavings,
              onReset: _resetSavings,
            );

            if (constraints.maxWidth >= 820) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(children: [mediaCard, const SizedBox(height: 14), informationCard]),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: savingsCard),
                ],
              );
            }
            return Column(
              children: [
                mediaCard,
                const SizedBox(height: 14),
                informationCard,
                const SizedBox(height: 14),
                savingsCard,
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
    required this.onPreview,
    required this.onRemove,
  });

  final AppController state;
  final bool busy;
  final VoidCallback onPick;
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
                borderRadius: 999,
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (hasMedia && mediaKind != null) ...[
            Text(
              '${profileMediaKindLabel(mediaKind)} • ${formatProfileMediaSize(state.profileMediaSizeBytes)}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 3),
            Text(
              state.profileMediaOriginalName,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
            ),
          ] else
            Text(
              'Add a photo, animated GIF, or short video.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
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
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(hasMedia ? Icons.swap_horiz_rounded : Icons.add_photo_alternate_rounded),
                label: Text(hasMedia ? 'Replace' : 'Add media'),
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
          const SizedBox(height: 12),
          Text(
            'JPG, PNG, WebP, GIF, MP4, MOV, M4V, or WebM • maximum 500 KB',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _ProfileInformationCard extends StatelessWidget {
  const _ProfileInformationCard({
    required this.displayName,
    required this.bio,
    required this.email,
    required this.busy,
    required this.onSave,
  });

  final TextEditingController displayName;
  final TextEditingController bio;
  final String email;
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
          TextField(
            controller: displayName,
            maxLength: 60,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Display name', hintText: 'How should Koinly address you?'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: bio,
            maxLength: 160,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Bio', hintText: 'A short note about you'),
          ),
          if (email.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.alternate_email_rounded, color: kSleekAccent),
              title: const Text('Sync account'),
              subtitle: Text(email.trim()),
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

class _SavingsSuggestionProfileCard extends StatelessWidget {
  const _SavingsSuggestionProfileCard({
    required this.hobby,
    required this.occupation,
    required this.age,
    required this.goal,
    required this.spendingPreference,
    required this.extraDetails,
    required this.busy,
    required this.onSave,
    required this.onReset,
  });

  final TextEditingController hobby;
  final TextEditingController occupation;
  final TextEditingController age;
  final TextEditingController goal;
  final TextEditingController spendingPreference;
  final TextEditingController extraDetails;
  final bool busy;
  final VoidCallback onSave;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return ExpressiveCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.lightbulb_rounded, color: Color(0xFFFFB5D0)),
              const SizedBox(width: 10),
              Expanded(child: Text('Savings Suggestion', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Personalize optional purchase ideas. Savings transfers remain internal and do not count as income or expense.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          TextField(controller: hobby, decoration: const InputDecoration(labelText: 'Hobby', hintText: 'Gaming, anime, reading, travel...')),
          const SizedBox(height: 10),
          TextField(controller: occupation, decoration: const InputDecoration(labelText: 'Occupation', hintText: 'Student, worker, creator...')),
          const SizedBox(height: 10),
          TextField(
            controller: age,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
            decoration: const InputDecoration(labelText: 'Age'),
          ),
          const SizedBox(height: 10),
          TextField(controller: goal, decoration: const InputDecoration(labelText: 'Savings goal', hintText: 'Emergency fund, phone, PC, trip...')),
          const SizedBox(height: 10),
          TextField(controller: spendingPreference, decoration: const InputDecoration(labelText: 'Spending preference', hintText: 'Careful, balanced, hobby-first...')),
          const SizedBox(height: 10),
          TextField(controller: extraDetails, minLines: 2, maxLines: 3, decoration: const InputDecoration(labelText: 'Other details optional')),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : onReset,
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Reset'),
              ),
              FilledButton.icon(
                onPressed: busy ? null : onSave,
                icon: const Icon(Icons.save_rounded),
                label: const Text('Save preferences'),
              ),
            ],
          ),
        ],
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
    this.borderRadius = 0,
  });

  final String path;
  final ProfileMediaKind? kind;
  final String displayName;
  final BoxFit fit;
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
      child = _ProfileVideoView(key: ValueKey(path), path: path, fit: fit);
    } else {
      child = Image.file(
        File(path),
        fit: fit,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => _fallback(context),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: SizedBox.expand(child: child),
      ),
    );
  }
}

class _ProfileVideoView extends StatefulWidget {
  const _ProfileVideoView({super.key, required this.path, required this.fit});

  final String path;
  final BoxFit fit;

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
      return const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)));
    }
    final size = current.value.size;
    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: widget.fit,
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
