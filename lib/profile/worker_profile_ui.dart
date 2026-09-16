part of '../main.dart';

class _WorkerProfileException implements Exception {
  const _WorkerProfileException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  bool get sessionExpired => statusCode == 401;
  @override
  String toString() => message;
}

class _WorkerProfileAccount {
  const _WorkerProfileAccount({
    required this.id,
    required this.username,
    required this.createdAt,
    required this.updatedAt,
    required this.status,
    required this.isAdministrator,
  });

  final String id;
  final String username;
  final int createdAt;
  final int updatedAt;
  final String status;
  final bool isAdministrator;

  factory _WorkerProfileAccount.fromJson(Map<String, dynamic> json) => _WorkerProfileAccount(
        id: json['id']?.toString() ?? '',
        username: json['username']?.toString() ?? '',
        createdAt: (json['createdAt'] as num? ?? 0).toInt(),
        updatedAt: (json['updatedAt'] as num? ?? 0).toInt(),
        status: json['status']?.toString() ?? 'invited',
        isAdministrator: json['isAdministrator'] == true,
      );
}

class _WorkerProfileAccountsPage {
  const _WorkerProfileAccountsPage({required this.total, required this.accounts});
  final int total;
  final List<_WorkerProfileAccount> accounts;
}

class _WorkerProfileApi {
  _WorkerProfileApi(String rawBaseUrl)
      : baseUrl = CloudSyncService.normalizeApiBaseUrl(rawBaseUrl),
        _client = http.Client();

  final String baseUrl;
  final http.Client _client;
  String _cookie = '';

  String get _origin => Uri.parse(baseUrl).origin;
  bool get signedIn => _cookie.isNotEmpty;

  Map<String, String> _headers({bool json = false}) => {
        'Accept': 'application/json',
        'Origin': _origin,
        'X-Profile-Request': '1',
        if (json) 'Content-Type': 'application/json',
        if (_cookie.isNotEmpty) 'Cookie': _cookie,
      };

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<void> login({required String username, required String password}) async {
    final response = await _client
        .post(
          _uri('/profile/api/login'),
          headers: _headers(json: true),
          body: jsonEncode({'username': username, 'password': password}),
        )
        .timeout(const Duration(seconds: 15));
    _throwIfError(response);
    final setCookie = response.headers['set-cookie'] ?? '';
    final match = RegExp(r'__Host-koinly-admin=([^;]+)').firstMatch(setCookie);
    final token = match?.group(1)?.trim() ?? '';
    if (token.isEmpty) {
      throw const _WorkerProfileException('The Worker signed in but did not return an administrator session. Redeploy the latest Worker and try again.');
    }
    _cookie = '__Host-koinly-admin=$token';
  }

  Future<void> logout() async {
    if (_cookie.isEmpty) return;
    try {
      await _client
          .post(_uri('/profile/api/logout'), headers: _headers(json: true), body: '{}')
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // The local session is still cleared even if the network is unavailable.
    }
    _cookie = '';
  }

  Future<_WorkerProfileAccountsPage> accounts() async {
    final response = await _client
        .get(_uri('/profile/api/accounts?page=1'), headers: _headers())
        .timeout(const Duration(seconds: 15));
    final decoded = _decode(response);
    final rawAccounts = decoded['accounts'];
    return _WorkerProfileAccountsPage(
      total: (decoded['total'] as num? ?? 0).toInt(),
      accounts: rawAccounts is List
          ? rawAccounts.whereType<Map>().map((entry) => _WorkerProfileAccount.fromJson(Map<String, dynamic>.from(entry))).toList()
          : const [],
    );
  }

  Future<String> createAccount({required String username, required String password}) => _mutate(
        'POST',
        '/profile/api/accounts',
        {'username': username, 'password': password},
      );

  Future<String> changeUsername({required String userId, required String username}) => _mutate(
        'POST',
        '/profile/api/accounts/$userId/username',
        {'username': username},
      );

  Future<String> changePassword({required String userId, required String password}) => _mutate(
        'POST',
        '/profile/api/accounts/$userId/password',
        {'password': password},
      );

  Future<String> deleteAccount(String userId) => _mutate('DELETE', '/profile/api/accounts/$userId', null);

  Future<String> _mutate(String method, String path, Map<String, dynamic>? body) async {
    final encoded = body == null ? null : jsonEncode(body);
    late final http.Response response;
    if (method == 'POST') {
      response = await _client
          .post(_uri(path), headers: _headers(json: true), body: encoded ?? '{}')
          .timeout(const Duration(seconds: 15));
    } else {
      response = await _client
          .delete(_uri(path), headers: _headers(json: true), body: encoded)
          .timeout(const Duration(seconds: 15));
    }
    final decoded = _decode(response);
    return decoded['message']?.toString().trim().isNotEmpty == true ? decoded['message'].toString().trim() : 'Saved.';
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> decoded = const {};
    try {
      final value = jsonDecode(response.body);
      if (value is Map) decoded = Map<String, dynamic>.from(value);
    } catch (_) {
      if (response.statusCode >= 200 && response.statusCode < 300) return decoded;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded['error']?.toString().trim();
      throw _WorkerProfileException(
        message == null || message.isEmpty ? 'Worker profile request failed (HTTP ${response.statusCode}).' : message,
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }

  void _throwIfError(http.Response response) => _decode(response);

  void dispose() => _client.close();
}

class WorkerProfileScreen extends StatefulWidget {
  const WorkerProfileScreen({
    super.key,
    required this.workerUrl,
    this.suggestedUsername = '',
  });

  final String workerUrl;
  final String suggestedUsername;

  @override
  State<WorkerProfileScreen> createState() => _WorkerProfileScreenState();
}

class _WorkerProfileScreenState extends State<WorkerProfileScreen> {
  late final _WorkerProfileApi _api;
  late final TextEditingController _usernameController;
  final _passwordController = TextEditingController();
  bool _passwordVisible = false;
  bool _busy = false;
  int _total = 0;
  List<_WorkerProfileAccount> _accounts = const [];

  @override
  void initState() {
    super.initState();
    _api = _WorkerProfileApi(widget.workerUrl);
    _usernameController = TextEditingController(text: widget.suggestedUsername.trim().toLowerCase());
  }

  @override
  void dispose() {
    _api.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on TimeoutException {
      if (mounted) showSnack(context, 'Worker profile request timed out.');
    } on SocketException {
      if (mounted) showSnack(context, 'Could not reach the Worker. Check your internet connection.');
    } on _WorkerProfileException catch (error) {
      if (error.sessionExpired && _api.signedIn) {
        await _api.logout();
        if (mounted) setState(() => _accounts = const []);
      }
      if (mounted) showSnack(context, error.message);
    } catch (error) {
      if (mounted) showSnack(context, redactSyncSecrets(error.toString().replaceFirst('Exception: ', '')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _login() async {
    final username = _usernameController.text.trim().toLowerCase();
    final usernameError = _syncUsernameValidationError(username);
    if (usernameError != null) {
      showSnack(context, usernameError);
      return;
    }
    if (_passwordController.text.length < 8) {
      showSnack(context, 'Enter your administrator password.');
      return;
    }
    await _run(() async {
      await _api.login(username: username, password: _passwordController.text);
      _passwordController.clear();
      await _loadAccounts();
    });
  }

  Future<void> _loadAccounts() async {
    final page = await _api.accounts();
    if (!mounted) return;
    setState(() {
      _total = page.total;
      _accounts = page.accounts;
    });
  }

  Future<void> _logout() async {
    await _run(() async {
      await _api.logout();
      if (!mounted) return;
      setState(() {
        _accounts = const [];
        _total = 0;
      });
    });
  }

  Future<Map<String, String>?> _showAccountDialog({
    required String title,
    String username = '',
    bool usernameEditable = true,
    bool requirePassword = true,
  }) async {
    final usernameController = TextEditingController(text: username);
    final passwordController = TextEditingController();
    var passwordVisible = false;
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (usernameEditable)
                TextField(
                  controller: usernameController,
                  contextMenuBuilder: koinlyTextFieldContextMenu,
                  enableInteractiveSelection: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: requirePassword ? TextInputAction.next : TextInputAction.done,
                  decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.person_rounded)),
                ),
              if (usernameEditable && requirePassword) const SizedBox(height: 12),
              if (requirePassword)
                TextField(
                  controller: passwordController,
                  contextMenuBuilder: koinlyTextFieldContextMenu,
                  enableInteractiveSelection: true,
                  obscureText: !passwordVisible,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_rounded),
                    suffixIcon: IconButton(
                      onPressed: () => setDialogState(() => passwordVisible = !passwordVisible),
                      icon: Icon(passwordVisible ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, {
                'username': usernameController.text.trim().toLowerCase(),
                'password': passwordController.text,
              }),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    usernameController.dispose();
    passwordController.dispose();
    return result;
  }

  Future<void> _createAccount() async {
    final values = await _showAccountDialog(title: 'Create account');
    if (values == null || !mounted) return;
    final username = values['username'] ?? '';
    final password = values['password'] ?? '';
    final usernameError = _syncUsernameValidationError(username);
    if (usernameError != null) {
      showSnack(context, usernameError);
      return;
    }
    if (password.length < 8) {
      showSnack(context, 'Password must be at least 8 characters.');
      return;
    }
    await _run(() async {
      final message = await _api.createAccount(username: username, password: password);
      await _loadAccounts();
      if (mounted) showSnack(context, message);
    });
  }

  Future<void> _changeUsername(_WorkerProfileAccount account) async {
    final values = await _showAccountDialog(
      title: 'Change username',
      username: account.username,
      requirePassword: false,
    );
    if (values == null || !mounted) return;
    final username = values['username'] ?? '';
    final usernameError = _syncUsernameValidationError(username);
    if (usernameError != null) {
      showSnack(context, usernameError);
      return;
    }
    if (username == account.username) return;
    await _run(() async {
      final message = await _api.changeUsername(userId: account.id, username: username);
      await context.read<AppController>().applyWorkerProfileUsernameRename(
            previousUsername: account.username,
            nextUsername: username,
          );
      await _loadAccounts();
      if (mounted) showSnack(context, message);
    });
  }

  Future<void> _changePassword(_WorkerProfileAccount account) async {
    final values = await _showAccountDialog(
      title: 'Change password for ${account.username}',
      usernameEditable: false,
    );
    if (values == null || !mounted) return;
    final password = values['password'] ?? '';
    if (password.length < 8) {
      showSnack(context, 'Password must be at least 8 characters.');
      return;
    }
    await _run(() async {
      final message = await _api.changePassword(userId: account.id, password: password);
      final appState = context.read<AppController>();
      if (appState.syncAccountUsername.trim().toLowerCase() == account.username.trim().toLowerCase()) {
        await appState.logoutSyncAccount();
      }
      if (account.isAdministrator) {
        // Changing the administrator password intentionally revokes the portal
        // session. Return to the login view immediately instead of waiting for
        // the next API call to discover the invalidated cookie.
        await _api.logout();
        if (mounted) {
          setState(() {
            _accounts = const [];
            _total = 0;
          });
          showSnack(context, '$message Sign in again with the new password.');
        }
      } else {
        await _loadAccounts();
        if (mounted) showSnack(context, message);
      }
    });
  }

  Future<void> _deleteAccount(_WorkerProfileAccount account) async {
    if (account.isAdministrator) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${account.username}?'),
        content: const Text('This permanently deletes the account and its synchronized Worker data. This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kSleekExpense),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      final message = await _api.deleteAccount(account.id);
      final state = context.read<AppController>();
      if (state.syncAccountUsername.trim().toLowerCase() == account.username.trim().toLowerCase()) {
        await state.logoutSyncAccount();
      }
      await _loadAccounts();
      if (mounted) showSnack(context, message);
    });
  }

  Widget _loginView(BuildContext context) {
    return ResponsiveContent(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExpressiveCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: kSleekAccent.withOpacity(.12),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: kSleekAccent.withOpacity(.28)),
                      ),
                      child: const Icon(Icons.admin_panel_settings_rounded, color: kSleekAccent),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Administrator login', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                          const SizedBox(height: 3),
                          Text('Manage accounts on your validated Worker.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _usernameController,
                  contextMenuBuilder: koinlyTextFieldContextMenu,
                  enableInteractiveSelection: true,
                  enabled: !_busy,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.person_rounded)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  contextMenuBuilder: koinlyTextFieldContextMenu,
                  enableInteractiveSelection: true,
                  enabled: !_busy,
                  obscureText: !_passwordVisible,
                  autocorrect: false,
                  enableSuggestions: false,
                  onSubmitted: (_) => _busy ? null : _login(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_rounded),
                    suffixIcon: IconButton(
                      onPressed: _busy ? null : () => setState(() => _passwordVisible = !_passwordVisible),
                      icon: Icon(_passwordVisible ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : _login,
                  icon: _busy ? const KoinlyInlineLoader(size: 18) : const Icon(Icons.login_rounded),
                  label: const Text('Sign in'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _accountCard(BuildContext context, _WorkerProfileAccount account) {
    final scheme = Theme.of(context).colorScheme;
    final created = account.createdAt > 0
        ? DateFormat.yMMMd().format(DateTime.fromMillisecondsSinceEpoch(account.createdAt))
        : 'Unknown';
    final active = account.status.toLowerCase() == 'active';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ExpressiveCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: kSleekAccent.withOpacity(.12),
                  child: Text(
                    account.username.isEmpty ? '?' : account.username.substring(0, 1).toUpperCase(),
                    style: const TextStyle(color: kSleekAccent, fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(account.username, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 3),
                      Text('Created $created', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                if (account.isAdministrator)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: kSleekAccent.withOpacity(.12),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: kSleekAccent.withOpacity(.28)),
                    ),
                    child: const Text('Administrator', style: TextStyle(color: kSleekAccent, fontWeight: FontWeight.w900, fontSize: 12)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(active ? Icons.check_circle_rounded : Icons.schedule_rounded, size: 18, color: active ? kSleekAccent : scheme.onSurfaceVariant),
                const SizedBox(width: 7),
                Text(active ? 'Active' : 'Invited', style: TextStyle(color: active ? kSleekAccent : scheme.onSurfaceVariant, fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _changeUsername(account),
                  icon: const Icon(Icons.drive_file_rename_outline_rounded),
                  label: const Text('Change username'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _changePassword(account),
                  icon: const Icon(Icons.password_rounded),
                  label: const Text('Change password'),
                ),
                if (!account.isAdministrator)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: kSleekExpense),
                    onPressed: _busy ? null : () => _deleteAccount(account),
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Delete'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _accountsView(BuildContext context) {
    return ResponsiveContent(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExpressiveCard(
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: kSleekAccent.withOpacity(.12),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(Icons.groups_rounded, color: kSleekAccent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Registered accounts', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 2),
                      Text('$_total account${_total == 1 ? '' : 's'} on this Worker', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _createAccount,
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Create account'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _run(_loadAccounts),
            icon: _busy ? const KoinlyInlineLoader(size: 18) : const Icon(Icons.refresh_rounded),
            label: const Text('Refresh'),
          ),
          const SizedBox(height: 18),
          ..._accounts.map((account) => _accountCard(context, account)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = _api.signedIn;
    return PageScaffold(
      title: 'Profile',
      subtitle: signedIn ? 'Worker administration' : null,
      actions: signedIn
          ? [
              IconButton(
                tooltip: 'Sign out',
                onPressed: _busy ? null : _logout,
                icon: const Icon(Icons.logout_rounded),
              ),
            ]
          : const [],
      child: signedIn ? _accountsView(context) : _loginView(context),
    );
  }
}
