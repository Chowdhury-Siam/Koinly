part of 'main.dart';

/// Presentation order is independent of the original persisted tab indexes.
class _SideRailNavigation extends StatelessWidget {
  const _SideRailNavigation({required this.selectedIndex, required this.extended, required this.onSelected});
  final int selectedIndex;
  final bool extended;
  final ValueChanged<int> onSelected;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = context.watch<AppController>();
    return Container(width: extended ? 248 : 88,
      decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(right: BorderSide(color: scheme.outlineVariant))),
      child: SafeArea(right: false, child: Column(children: [
        Padding(padding: EdgeInsets.symmetric(horizontal: extended ? 24 : 20, vertical: 28),
          child: Row(children: [const KoinlyAppIcon(size: 40, borderRadius: 20),
            if (extended) ...[const SizedBox(width: 12), Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(appTitle, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text('PRIVATE FINANCE', style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 2)),
              ]))],
          ])),
        Expanded(child: ListView(padding: const EdgeInsets.symmetric(horizontal: 12), children: [
          for (final index in const [0, 3, 1, 2, 4])
            _RailItem(destination: _FloatingDockNavigation.destinations[index],
              selected: selectedIndex == index, extended: extended, onTap: () => onSelected(index)),
          _RailItem(destination: const _DockDestination(label: 'Settings', icon: Icons.settings_outlined, activeIcon: Icons.settings_outlined),
            selected: selectedIndex == -1, extended: extended,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
        ])),
        if (extended) Padding(padding: const EdgeInsets.all(12), child: ExpressiveCard(
          padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(state.cloudSyncEnabled ? Icons.cloud_outlined : Icons.lock_outline_rounded,
              color: scheme.secondary, size: 14), const SizedBox(width: 8),
              Text(state.cloudSyncEnabled ? 'CLOUD SYNC' : 'LOCAL-ONLY MODE', style: Theme.of(context).textTheme.labelSmall)]),
            const SizedBox(height: 8),
            Text(state.cloudSyncEnabled ? state.syncStatus : 'Your finance data stays on this device. Cloud sync is off.',
              style: Theme.of(context).textTheme.bodySmall),
          ]))),
        const SizedBox(height: 12),
      ])),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({required this.destination, required this.selected, required this.extended, required this.onTap});
  final _DockDestination destination;
  final bool selected;
  final bool extended;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(padding: const EdgeInsets.only(bottom: 4), child: Semantics(
      selected: selected, button: true, child: Tooltip(message: destination.label,
        child: Material(color: Colors.transparent, child: InkWell(
          onTap: onTap, borderRadius: BorderRadius.circular(22),
          child: AnimatedContainer(
            duration: MediaQuery.of(context).disableAnimations ? Duration.zero : AppMotion.medium,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(color: selected ? scheme.primaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: selected ? kSleekAccent.withOpacity(.18) : Colors.transparent)),
            child: Row(mainAxisAlignment: extended ? MainAxisAlignment.start : MainAxisAlignment.center, children: [
              Container(width: 32, height: 32,
                decoration: BoxDecoration(shape: BoxShape.circle, color: selected ? kSleekAccent : Colors.transparent),
                child: Icon(selected ? destination.activeIcon : destination.icon,
                  size: 19, color: selected ? Colors.white : scheme.onSurfaceVariant)),
              if (extended) ...[const SizedBox(width: 12), Expanded(child: Text(destination.label,
                style: TextStyle(fontSize: 14, fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? scheme.onSurface : scheme.onSurfaceVariant)))],
            ]),
          ),
        )),
      ),
    ));
  }
}

class _FloatingDockNavigation extends StatelessWidget {
  const _FloatingDockNavigation({required this.selectedIndex, required this.onSelected});
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  static List<_DockDestination> get destinations => const [
    _DockDestination(label: 'Home', icon: Icons.grid_view_outlined, activeIcon: Icons.grid_view_rounded),
    _DockDestination(label: 'Insights', icon: Icons.bar_chart_outlined, activeIcon: Icons.bar_chart_rounded),
    _DockDestination(label: 'Loans', icon: Icons.handshake_outlined, activeIcon: Icons.handshake_rounded),
    _DockDestination(label: 'Activity', icon: Icons.receipt_long_outlined, activeIcon: Icons.receipt_long_rounded),
    _DockDestination(label: 'Categories', icon: Icons.category_outlined, activeIcon: Icons.category_rounded),
  ];
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(color: scheme.surface, child: Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: scheme.outlineVariant))),
      child: SafeArea(top: false, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(children: [
          for (final index in const [0, 3, -1, 1, 2, 4])
            if (index == -1) Expanded(child: Center(child: Tooltip(message: 'Add transaction',
              child: KoinlyPrimaryAction(onPressed: () => showTransactionEditor(context)))))
            else Expanded(child: Semantics(selected: selectedIndex == index, button: true,
              child: InkWell(onTap: () => onSelected(index), borderRadius: BorderRadius.circular(12),
                child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(selectedIndex == index ? destinations[index].activeIcon : destinations[index].icon,
                    size: 21, color: selectedIndex == index ? kSleekAccent : scheme.onSurfaceVariant),
                  const SizedBox(height: 5),
                  FittedBox(fit: BoxFit.scaleDown, child: Text(destinations[index].label, maxLines: 1,
                    style: TextStyle(fontSize: 10, fontWeight: selectedIndex == index ? FontWeight.w600 : FontWeight.w400,
                      color: selectedIndex == index ? scheme.onSurface : scheme.onSurfaceVariant))),
                ])),
              ),
            )),
        ]))),
    ));
  }
}

class PageScaffold extends StatelessWidget {
  const PageScaffold({super.key, required this.title, this.actions = const [], required this.child, this.subtitle});
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final desktop = AppBreakpoints.isExpanded(context);
    final back = Navigator.canPop(context);
    return Scaffold(backgroundColor: theme.scaffoldBackgroundColor,
      body: Row(children: [
        if (desktop && back) _SideRailNavigation(
          selectedIndex: title == 'Settings' ? -1 : context.read<AppController>().tabIndex,
          extended: MediaQuery.sizeOf(context).width >= AppBreakpoints.large,
          onSelected: (index) {
            context.read<AppController>().selectTabIndex(index);
            Navigator.of(context).popUntil((route) => route.isFirst);
          }),
        Expanded(child: SafeArea(bottom: false, child: Column(children: [
        Container(
          margin: EdgeInsets.fromLTRB(desktop ? 32 : 16, desktop ? 24 : 12, desktop ? 32 : 16, 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: theme.colorScheme.surface,
            border: Border.all(color: theme.colorScheme.outlineVariant), borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            if (back) const BackButton() else if (!desktop) ...[
              const KoinlyAppIcon(size: 32, borderRadius: 16), const SizedBox(width: 10)],
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
              if (subtitle != null) ...[const SizedBox(height: 3), Text(subtitle!, maxLines: 1,
                overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall)],
            ])),
            ...actions.map((action) => Padding(padding: const EdgeInsets.only(left: 4), child: action)),
            if (desktop && !back) ...[
              const SizedBox(width: 8),
              Tooltip(message: 'Theme', child: IconButton(onPressed: () => showThemeDialog(context),
                icon: Icon(theme.brightness == Brightness.dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined))),
              const SizedBox(width: 8),
              KoinlyPrimaryAction(label: 'Add', onPressed: () => showTransactionEditor(context)),
              if (!actions.any((action) => action is ProfileAvatarButton)) ...[
                const SizedBox(width: 10), const ProfileAvatarButton()],
            ],
          ]),
        ),
        Expanded(child: KoinlyAtmosphere(child: child)),
      ]))),
      ]),
    );
  }
}
