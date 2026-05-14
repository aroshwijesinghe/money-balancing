import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BoardingMoneyApp());
}

class BoardingMoneyApp extends StatefulWidget {
  const BoardingMoneyApp({super.key});

  @override
  State<BoardingMoneyApp> createState() => _BoardingMoneyAppState();
}

class _BoardingMoneyAppState extends State<BoardingMoneyApp> {
  bool _unlocked = false;
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final isDark = await AppPrefsService.getDarkMode();
    if (!mounted) {
      return;
    }
    setState(() {
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    });
  }

  Future<void> _setDarkMode(bool enabled) async {
    await AppPrefsService.setDarkMode(enabled);
    if (!mounted) {
      return;
    }
    setState(() {
      _themeMode = enabled ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Boarding House Ledger',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00695C)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00695C),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: _themeMode,
      home: _unlocked
          ? HomeScreen(
              onLock: () {
                setState(() {
                  _unlocked = false;
                });
              },
              onThemeChanged: _setDarkMode,
              themeMode: _themeMode,
            )
          : PinGate(
              onUnlocked: () {
                setState(() {
                  _unlocked = true;
                });
              },
            ),
    );
  }
}

class PinGate extends StatefulWidget {
  const PinGate({super.key, required this.onUnlocked});

  final VoidCallback onUnlocked;

  @override
  State<PinGate> createState() => _PinGateState();
}

class _PinGateState extends State<PinGate> {
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = true;
  bool _hasPin = false;
  String? _error;

  Future<bool> _ensureOwnerProfile() async {
    final profile = await AppPrefsService.getOwnerProfile();
    if (profile.name.trim().isNotEmpty && profile.name != 'Owner') {
      return true;
    }
    if (!mounted) {
      return false;
    }
    final result = await showDialog<MemberFormResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const MemberDialog(),
    );
    if (result == null) {
      return false;
    }
    await AppPrefsService.setOwnerProfile(
      name: result.name.trim(),
      photoPath: result.photoPath,
    );
    return true;
  }

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final hasPin = await AuthService.hasPin();
    if (!mounted) {
      return;
    }
    setState(() {
      _hasPin = hasPin;
      _loading = false;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final pin = _pinController.text.trim();
    if (_hasPin) {
      final ok = await AuthService.verifyPin(pin);
      if (!mounted) {
        return;
      }
      if (!ok) {
        setState(() {
          _error = 'Wrong PIN. Try again.';
        });
        return;
      }
      widget.onUnlocked();
      return;
    }

    final ready = await _ensureOwnerProfile();
    if (!ready) {
      return;
    }
    await AuthService.setPin(pin);
    if (!mounted) {
      return;
    }
    widget.onUnlocked();
  }

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.home_work_rounded,
                        size: 44,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _hasPin ? 'Enter PIN' : 'Create PIN',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _pinController,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'PIN (4-8 digits)',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'PIN is required';
                          }
                          if (!RegExp(r'^\d{4,8}$').hasMatch(value.trim())) {
                            return 'Use 4 to 8 digits';
                          }
                          return null;
                        },
                      ),
                      if (!_hasPin) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _confirmController,
                          keyboardType: TextInputType.number,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Confirm PIN',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please confirm PIN';
                            }
                            if (value.trim() != _pinController.text.trim()) {
                              return 'PIN does not match';
                            }
                            return null;
                          },
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed: _submit,
                        child: Text(_hasPin ? 'Unlock' : 'Create & Continue'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.onLock,
    required this.onThemeChanged,
    required this.themeMode,
  });

  final VoidCallback onLock;
  final ValueChanged<bool> onThemeChanged;
  final ThemeMode themeMode;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  void _refreshAll() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      MembersPage(onChanged: _refreshAll),
      TransactionsPage(onChanged: _refreshAll),
      DashboardPage(refreshToken: DateTime.now().millisecondsSinceEpoch),
      SettingsPage(
        onLock: widget.onLock,
        onThemeChanged: widget.onThemeChanged,
        isDarkMode: widget.themeMode == ThemeMode.dark,
      ),
    ];

    final titles = ['Members', 'Transactions', 'Dashboard', 'Settings'];

    return Scaffold(
      appBar: AppBar(title: Text(titles[_index])),
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) {
          setState(() {
            _index = value;
          });
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.people_alt), label: 'Members'),
          NavigationDestination(
            icon: Icon(Icons.receipt_long),
            label: 'Transactions',
          ),
          NavigationDestination(icon: Icon(Icons.analytics), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

class MembersPage extends StatefulWidget {
  const MembersPage({super.key, required this.onChanged});

  final VoidCallback onChanged;

  @override
  State<MembersPage> createState() => _MembersPageState();
}

class _MembersPageState extends State<MembersPage> {
  late Future<List<Member>> _futureMembers;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _futureMembers = DbService.instance.getMembers();
    setState(() {});
  }

  Future<void> _upsertMember([Member? existing]) async {
    final result = await showDialog<MemberFormResult>(
      context: context,
      builder: (_) => MemberDialog(existing: existing),
    );
    if (result == null) {
      return;
    }

    if (existing == null) {
      await DbService.instance.insertMember(
        name: result.name,
        photoPath: result.photoPath,
      );
    } else {
      await DbService.instance.updateMember(
        id: existing.id,
        name: result.name,
        photoPath: result.photoPath,
      );
    }

    widget.onChanged();
    _reload();
  }

  Future<void> _deleteMember(Member member) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete member?'),
        content: const Text(
          'This will remove the member and all related transactions.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) {
      return;
    }

    await DbService.instance.deleteMember(member.id);
    widget.onChanged();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Member>>(
      future: _futureMembers,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final members = snapshot.data!;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _upsertMember,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Add Member'),
                ),
              ),
            ),
            Expanded(
              child: members.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No members yet. Tap "Add Member" to get started.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: members.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final member = members[index];
                        return Card(
                          child: ListTile(
                            leading: MemberAvatar(path: member.photoPath),
                            title: Text(member.name),
                            subtitle: Text(
                              'Added: ${DateFormat('yyyy-MM-dd HH:mm').format(member.createdAt)}',
                            ),
                            onTap: () => _upsertMember(member),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _deleteMember(member),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({super.key, required this.onChanged});

  final VoidCallback onChanged;

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  late Future<List<Member>> _futureMembers;
  late Future<List<TransactionRecord>> _futureTransactions;
  final _money = NumberFormat.currency(symbol: 'LKR ', decimalDigits: 2);
  String _ownerName = 'Owner';

  @override
  void initState() {
    super.initState();
    _loadOwnerName();
    _reload();
  }

  Future<void> _loadOwnerName() async {
    final profile = await AppPrefsService.getOwnerProfile();
    if (!mounted) {
      return;
    }
    setState(() {
      _ownerName = profile.name;
    });
  }

  void _reload() {
    _futureMembers = DbService.instance.getMembers();
    _futureTransactions = DbService.instance.getTransactions();
    setState(() {});
  }

  Future<void> _upsertTransaction(
    List<Member> members, {
    TransactionRecord? tx,
    TransactionDirection? direction,
  }) async {
    if (members.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one member first.')),
      );
      return;
    }

    final result = await showDialog<TransactionFormResult>(
      context: context,
      builder: (_) => TransactionDialog(
        members: members,
        existing: tx,
        initialDirection: direction,
      ),
    );
    if (result == null) {
      return;
    }

    if (tx == null) {
      await DbService.instance.insertTransaction(result);
    } else {
      await DbService.instance.updateTransaction(tx.id, result);
    }

    widget.onChanged();
    _reload();
  }

  Future<void> _deleteTransaction(int id) async {
    await DbService.instance.deleteTransaction(id);
    widget.onChanged();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Member>>(
      future: _futureMembers,
      builder: (context, memberSnap) {
        if (!memberSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final members = memberSnap.data!;

        return FutureBuilder<List<TransactionRecord>>(
          future: _futureTransactions,
          builder: (context, txSnap) {
            if (!txSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final txs = txSnap.data!;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red.shade600,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => _upsertTransaction(
                            members,
                            direction: TransactionDirection.memberPaysOwner,
                          ),
                          icon: const Icon(Icons.call_made_rounded),
                          label: const Text('Should Pay'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => _upsertTransaction(
                            members,
                            direction: TransactionDirection.ownerPaysMember,
                          ),
                          icon: const Icon(Icons.call_received_rounded),
                          label: const Text('Should Receive'),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: txs.isEmpty
                      ? const Center(
                          child: Text('No transactions yet. Add your first one.'),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          itemCount: txs.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final tx = txs[index];
                            final directionText = tx.ownerToMember
                                ? '$_ownerName -> ${tx.receiverMemberName ?? 'Member'}'
                                : '${tx.giverName} -> $_ownerName';
                            return Card(
                              child: InkWell(
                                onTap: () => _upsertTransaction(members, tx: tx),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(child: Text(directionText)),
                                          Text(
                                            _money.format(tx.amount),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        tx.reason,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Text(
                                            DateFormat('yyyy-MM-dd HH:mm').format(tx.dealAt),
                                            style: Theme.of(context).textTheme.bodySmall,
                                          ),
                                          const Spacer(),
                                          GestureDetector(
                                            onTap: () => _deleteTransaction(tx.id),
                                            child: const Text('Delete'),
                                          ),
                                        ],
                                      ),
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
          },
        );
      },
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.refreshToken});

  final int refreshToken;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late Future<DashboardData> _future;
  final _money = NumberFormat.currency(symbol: 'LKR ', decimalDigits: 2);
  String _ownerName = 'Owner';

  @override
  void initState() {
    super.initState();
    _loadOwnerName();
    _load();
  }

  Future<void> _loadOwnerName() async {
    final profile = await AppPrefsService.getOwnerProfile();
    if (!mounted) {
      return;
    }
    setState(() {
      _ownerName = profile.name;
    });
  }

  @override
  void didUpdateWidget(covariant DashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _load();
    }
  }

  void _load() {
    _future = DbService.instance.getDashboardData();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DashboardData>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.account_balance_wallet),
                title: Text('Total Came To $_ownerName'),
                subtitle: Text(_money.format(data.totalPaidToOwner)),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.pending_actions),
                title: Text('$_ownerName Should Pay (Pending)'),
                subtitle: Text(_money.format(data.totalOwnerShouldPay)),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: const Text('Total Transactions'),
                subtitle: Text('${data.transactionCount} deals'),
              ),
            ),
            const SizedBox(height: 12),
            Text('Reports', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.calendar_view_week),
                title: const Text('Weekly'),
                subtitle: Text(
                  'In: ${_money.format(data.weeklyIncoming)} | Out: ${_money.format(data.weeklyOutgoing)}',
                ),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.calendar_month),
                title: const Text('Monthly'),
                subtitle: Text(
                  'In: ${_money.format(data.monthlyIncoming)} | Out: ${_money.format(data.monthlyOutgoing)}',
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('Member Summary', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (data.members.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No members yet.'),
                ),
              )
            else
              ...data.members.map((member) {
                final net = member.givenTotal - member.receivedTotal;
                final statusColor = net > 0
                    ? Colors.red.shade700
                    : net < 0
                        ? Colors.green.shade700
                        : Colors.amber.shade700;
                final statusText = net > 0
                    ? 'Needs to pay'
                    : net < 0
                        ? 'Will receive'
                        : 'Balanced';
                return Card(
                  child: ListTile(
                    leading: MemberAvatar(path: member.photoPath),
                    title: Text(member.name),
                    subtitle: Text(
                      'Given: ${_money.format(member.givenTotal)} | Received: ${_money.format(member.receivedTotal)}',
                    ),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MemberProfilePage(
                            member: member,
                            ownerName: _ownerName,
                          ),
                        ),
                      );
                      _load();
                    },
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              radius: 9,
                              backgroundColor: statusColor.withValues(alpha: 0.18),
                              child: Icon(
                                Icons.attach_money_rounded,
                                color: statusColor,
                                size: 13,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              statusText,
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Net: ${_money.format(net)}',
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.onLock,
    required this.onThemeChanged,
    required this.isDarkMode,
  });

  final VoidCallback onLock;
  final ValueChanged<bool> onThemeChanged;
  final bool isDarkMode;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _oldPin = TextEditingController();
  final _newPin = TextEditingController();
  final _confirmPin = TextEditingController();
  final _form = GlobalKey<FormState>();
  String _ownerName = 'Owner';
  String? _ownerPhotoPath;

  @override
  void initState() {
    super.initState();
    _loadOwnerProfile();
  }

  Future<void> _loadOwnerProfile() async {
    final profile = await AppPrefsService.getOwnerProfile();
    if (!mounted) {
      return;
    }
    setState(() {
      _ownerName = profile.name;
      _ownerPhotoPath = profile.photoPath;
    });
  }

  Future<void> _editOwnerProfile() async {
    final result = await showDialog<MemberFormResult>(
      context: context,
      builder: (_) => MemberDialog(
        existing: Member(
          id: -1,
          name: _ownerName,
          photoPath: _ownerPhotoPath,
          createdAt: DateTime.now(),
        ),
      ),
    );
    if (result == null) {
      return;
    }
    await AppPrefsService.setOwnerProfile(
      name: result.name,
      photoPath: result.photoPath,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _ownerName = result.name;
      _ownerPhotoPath = result.photoPath;
    });
  }

  Future<void> _changePin() async {
    if (!_form.currentState!.validate()) {
      return;
    }
    final ok = await AuthService.verifyPin(_oldPin.text.trim());
    if (!ok) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Old PIN is incorrect.')),
      );
      return;
    }

    await AuthService.setPin(_newPin.text.trim());
    if (!mounted) {
      return;
    }
    _oldPin.clear();
    _newPin.clear();
    _confirmPin.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('PIN updated.')),
    );
  }

  @override
  void dispose() {
    _oldPin.dispose();
    _newPin.dispose();
    _confirmPin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: SwitchListTile(
            secondary: const Icon(Icons.dark_mode),
            title: const Text('Dark Mode'),
            value: widget.isDarkMode,
            onChanged: widget.onThemeChanged,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: MemberAvatar(path: _ownerPhotoPath),
            title: Text(_ownerName),
            subtitle: const Text('Owner profile'),
            trailing: const Icon(Icons.edit),
            onTap: _editOwnerProfile,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Change PIN', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _oldPin,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Old PIN',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _newPin,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'New PIN',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || !RegExp(r'^\d{4,8}$').hasMatch(value.trim())) {
                        return 'Use 4 to 8 digits';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirmPin,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirm New PIN',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim() != _newPin.text.trim()) {
                        return 'PIN mismatch';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _changePin, child: const Text('Save PIN')),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.lock),
            title: const Text('Lock App Now'),
            subtitle: const Text('Go back to PIN screen'),
            onTap: widget.onLock,
          ),
        ),
      ],
    );
  }
}

class MemberDialog extends StatefulWidget {
  const MemberDialog({super.key, this.existing});

  final Member? existing;

  @override
  State<MemberDialog> createState() => _MemberDialogState();
}

class _MemberDialogState extends State<MemberDialog> {
  final _name = TextEditingController();
  final _form = GlobalKey<FormState>();
  String? _photoPath;

  @override
  void initState() {
    super.initState();
    _name.text = widget.existing?.name ?? '';
    _photoPath = widget.existing?.photoPath;
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: source, imageQuality: 80);
    if (file == null) {
      return;
    }

    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'member_photos'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final extension = p.extension(file.path);
    final newPath = p.join(
      dir.path,
      '${DateTime.now().millisecondsSinceEpoch}$extension',
    );
    await File(file.path).copy(newPath);
    if (!mounted) {
      return;
    }
    setState(() {
      _photoPath = newPath;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add Member' : 'Edit Member'),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MemberAvatar(path: _photoPath, radius: 34),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _pickPhoto(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera),
                    label: const Text('Camera'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _pickPhoto(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Member name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Name is required';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) {
              return;
            }
            Navigator.of(context).pop(
              MemberFormResult(name: _name.text.trim(), photoPath: _photoPath),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class TransactionDialog extends StatefulWidget {
  const TransactionDialog({
    super.key,
    required this.members,
    this.existing,
    this.initialDirection,
  });

  final List<Member> members;
  final TransactionRecord? existing;
  final TransactionDirection? initialDirection;

  @override
  State<TransactionDialog> createState() => _TransactionDialogState();
}

class _TransactionDialogState extends State<TransactionDialog> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  final _amount = TextEditingController();

  late int _giverId;
  ReceiverType _receiverType = ReceiverType.owner;
  int? _receiverMemberId;
  late DateTime _dealAt;
  TransactionDirection _direction = TransactionDirection.memberPaysOwner;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _giverId = existing?.giverId ?? widget.members.first.id;
    _receiverType = existing?.receiverType ?? ReceiverType.owner;
    _receiverMemberId = existing?.receiverMemberId;
    _direction = widget.initialDirection ??
        ((existing?.ownerToMember ?? false)
        ? TransactionDirection.ownerPaysMember
        : TransactionDirection.memberPaysOwner);
    _dealAt = existing?.dealAt ?? DateTime.now();
    _reason.text = existing?.reason ?? '';
    _amount.text = existing == null ? '' : existing.amount.toStringAsFixed(2);
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: _dealAt,
    );
    if (date == null || !mounted) {
      return;
    }

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dealAt),
    );
    if (time == null || !mounted) {
      return;
    }

    setState(() {
      _dealAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  @override
  void dispose() {
    _reason.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add Transaction' : 'Edit Transaction'),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: _direction == TransactionDirection.memberPaysOwner
                    ? _giverId
                    : _receiverMemberId,
                decoration: const InputDecoration(
                  labelText: 'Member',
                  border: OutlineInputBorder(),
                ),
                items: widget.members
                    .map(
                      (member) => DropdownMenuItem(
                        value: member.id,
                        child: Text(member.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      if (_direction == TransactionDirection.memberPaysOwner) {
                        _giverId = value;
                      } else {
                        _receiverMemberId = value;
                      }
                    });
                  }
                },
              ),
              const SizedBox(height: 10),
              SegmentedButton<TransactionDirection>(
                segments: const [
                  ButtonSegment(
                    value: TransactionDirection.memberPaysOwner,
                    label: Text('Member -> Owner'),
                    icon: Icon(Icons.home),
                  ),
                  ButtonSegment(
                    value: TransactionDirection.ownerPaysMember,
                    label: Text('Owner -> Member'),
                    icon: Icon(Icons.person),
                  ),
                ],
                selected: {_direction},
                onSelectionChanged: (selection) {
                  setState(() {
                    _direction = selection.first;
                    if (_direction == TransactionDirection.memberPaysOwner) {
                      _receiverType = ReceiverType.owner;
                      _receiverMemberId = null;
                    } else {
                      _receiverType = ReceiverType.member;
                      _receiverMemberId ??= widget.members.first.id;
                    }
                  });
                },
              ),
              if (_direction == TransactionDirection.ownerPaysMember) ...[
                const SizedBox(height: 10),
                const ListTile(
                  leading: Icon(Icons.account_circle),
                  title: Text('Payer'),
                  subtitle: Text('Owner'),
                ),
              ],
              const SizedBox(height: 10),
              TextFormField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount (LKR)',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final amount = double.tryParse(value ?? '');
                  if (amount == null || amount <= 0) {
                    return 'Enter valid amount';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _reason,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Reason is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: _pickDateTime,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Deal date & time',
                    border: OutlineInputBorder(),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(DateFormat('yyyy-MM-dd HH:mm').format(_dealAt)),
                      const Icon(Icons.schedule),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) {
              return;
            }
            final giverId = _direction == TransactionDirection.ownerPaysMember
                ? -1
                : _giverId;
            final receiverMemberId =
                _direction == TransactionDirection.ownerPaysMember
                    ? _receiverMemberId
                    : null;
            Navigator.of(context).pop(
              TransactionFormResult(
                direction: _direction,
                giverId: giverId,
                receiverType: _direction == TransactionDirection.ownerPaysMember
                    ? ReceiverType.member
                    : ReceiverType.owner,
                receiverMemberId: receiverMemberId,
                amount: double.parse(_amount.text.trim()),
                reason: _reason.text.trim(),
                dealAt: _dealAt,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class MemberAvatar extends StatelessWidget {
  const MemberAvatar({super.key, required this.path, this.radius = 22});

  final String? path;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final hasImage = path != null && path!.isNotEmpty && File(path!).existsSync();
    return CircleAvatar(
      radius: radius,
      backgroundImage: hasImage ? FileImage(File(path!)) : null,
      child: hasImage ? null : const Icon(Icons.person),
    );
  }
}

class MemberFormResult {
  MemberFormResult({required this.name, required this.photoPath});

  final String name;
  final String? photoPath;
}

class TransactionFormResult {
  TransactionFormResult({
    required this.direction,
    required this.giverId,
    required this.receiverType,
    required this.receiverMemberId,
    required this.amount,
    required this.reason,
    required this.dealAt,
  });

  final TransactionDirection direction;
  final int giverId;
  final ReceiverType receiverType;
  final int? receiverMemberId;
  final double amount;
  final String reason;
  final DateTime dealAt;
}

enum ReceiverType { owner, member }
enum TransactionDirection { memberPaysOwner, ownerPaysMember }

class Member {
  Member({
    required this.id,
    required this.name,
    required this.photoPath,
    required this.createdAt,
  });

  final int id;
  final String name;
  final String? photoPath;
  final DateTime createdAt;

  factory Member.fromMap(Map<String, Object?> map) {
    return Member(
      id: map['id'] as int,
      name: map['name'] as String,
      photoPath: map['photoPath'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int),
    );
  }
}

class TransactionRecord {
  TransactionRecord({
    required this.id,
    required this.giverId,
    required this.giverName,
    required this.receiverType,
    required this.receiverMemberId,
    required this.receiverMemberName,
    required this.giverType,
    required this.amount,
    required this.reason,
    required this.dealAt,
    required this.isCompleted,
    required this.completedAt,
  });

  final int id;
  final int giverId;
  final String giverName;
  final ReceiverType receiverType;
  final int? receiverMemberId;
  final String? receiverMemberName;
  final String giverType;
  final double amount;
  final String reason;
  final DateTime dealAt;
  final bool isCompleted;
  final DateTime? completedAt;

  bool get ownerToMember =>
      giverType == 'owner' && receiverType == ReceiverType.member;

  factory TransactionRecord.fromMap(Map<String, Object?> map) {
    return TransactionRecord(
      id: map['id'] as int,
      giverId: map['giverId'] as int,
      giverName: map['giverName'] as String,
      receiverType: (map['receiverType'] as String) == 'owner'
          ? ReceiverType.owner
          : ReceiverType.member,
      receiverMemberId: map['receiverMemberId'] as int?,
      receiverMemberName: map['receiverName'] as String?,
      giverType: (map['giverType'] as String?) ?? 'member',
      amount: (map['amount'] as num).toDouble(),
      reason: map['reason'] as String,
      dealAt: DateTime.fromMillisecondsSinceEpoch(map['dealAt'] as int),
      isCompleted: ((map['isCompleted'] as int?) ?? 0) == 1,
      completedAt: map['completedAt'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(map['completedAt'] as int),
    );
  }
}

class MemberSummary {
  MemberSummary({
    required this.id,
    required this.name,
    required this.photoPath,
    required this.givenTotal,
    required this.receivedTotal,
  });

  final int id;
  final String name;
  final String? photoPath;
  final double givenTotal;
  final double receivedTotal;

  factory MemberSummary.fromMap(Map<String, Object?> map) {
    return MemberSummary(
      id: map['id'] as int,
      name: map['name'] as String,
      photoPath: map['photoPath'] as String?,
      givenTotal: (map['givenTotal'] as num).toDouble(),
      receivedTotal: (map['receivedTotal'] as num).toDouble(),
    );
  }
}

class DashboardData {
  DashboardData({
    required this.totalPaidToOwner,
    required this.totalOwnerShouldPay,
    required this.transactionCount,
    required this.weeklyIncoming,
    required this.weeklyOutgoing,
    required this.monthlyIncoming,
    required this.monthlyOutgoing,
    required this.members,
  });

  final double totalPaidToOwner;
  final double totalOwnerShouldPay;
  final int transactionCount;
  final double weeklyIncoming;
  final double weeklyOutgoing;
  final double monthlyIncoming;
  final double monthlyOutgoing;
  final List<MemberSummary> members;
}

class MemberProfilePage extends StatefulWidget {
  const MemberProfilePage({
    super.key,
    required this.member,
    required this.ownerName,
  });

  final MemberSummary member;
  final String ownerName;

  @override
  State<MemberProfilePage> createState() => _MemberProfilePageState();
}

class _MemberProfilePageState extends State<MemberProfilePage> {
  final _money = NumberFormat.currency(symbol: 'LKR ', decimalDigits: 2);
  late MemberSummary _member;

  @override
  void initState() {
    super.initState();
    _member = widget.member;
  }

  Future<void> _completeBalance() async {
    final net = _member.givenTotal - _member.receivedTotal;
    if (net == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Already balanced.')),
      );
      return;
    }
    await DbService.instance.completeMemberBalance(memberId: _member.id, net: net);
    final latest = await DbService.instance.getMemberSummaryById(_member.id);
    if (!mounted || latest == null) {
      return;
    }
    setState(() {
      _member = latest;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Balance completed and set to zero.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final net = _member.givenTotal - _member.receivedTotal;
    final statusText = net > 0
        ? 'Needs to pay'
        : net < 0
            ? 'Will receive'
            : 'Balanced';
    return Scaffold(
      appBar: AppBar(title: Text(_member.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  MemberAvatar(path: _member.photoPath, radius: 42),
                  const SizedBox(height: 10),
                  Text(
                    _member.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text('Status: $statusText'),
                  const SizedBox(height: 12),
                  Text('Given: ${_money.format(_member.givenTotal)}'),
                  Text('Received: ${_money.format(_member.receivedTotal)}'),
                  const SizedBox(height: 8),
                  Text(
                    'Net: ${_money.format(net)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _completeBalance,
            icon: const Icon(Icons.handshake_rounded),
            label: Text('Complete Balance with ${widget.ownerName}'),
          ),
        ],
      ),
    );
  }
}

class AuthService {
  static const _pinKey = 'app_pin';

  static Future<bool> hasPin() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_pinKey) ?? '').isNotEmpty;
  }

  static Future<void> setPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pinKey, pin);
  }

  static Future<bool> verifyPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pinKey) == pin;
  }
}

class OwnerProfile {
  OwnerProfile({required this.name, required this.photoPath});

  final String name;
  final String? photoPath;
}

class AppPrefsService {
  static const _darkModeKey = 'dark_mode';
  static const _ownerNameKey = 'owner_name';
  static const _ownerPhotoKey = 'owner_photo';

  static Future<bool> getDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_darkModeKey) ?? false;
  }

  static Future<void> setDarkMode(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkModeKey, enabled);
  }

  static Future<OwnerProfile> getOwnerProfile() async {
    final prefs = await SharedPreferences.getInstance();
    return OwnerProfile(
      name: prefs.getString(_ownerNameKey) ?? 'Owner',
      photoPath: prefs.getString(_ownerPhotoKey),
    );
  }

  static Future<void> setOwnerProfile({
    required String name,
    required String? photoPath,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ownerNameKey, name);
    if (photoPath == null || photoPath.isEmpty) {
      await prefs.remove(_ownerPhotoKey);
    } else {
      await prefs.setString(_ownerPhotoKey, photoPath);
    }
  }
}

class DbService {
  DbService._();

  static final DbService instance = DbService._();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) {
      return _db!;
    }
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final basePath = await getDatabasesPath();
    final path = p.join(basePath, 'boarding_money.db');
    return openDatabase(
      path,
      version: 2,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE members(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            photoPath TEXT,
            createdAt INTEGER NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE transactions(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            giverId INTEGER NOT NULL,
            giverType TEXT NOT NULL DEFAULT 'member',
            receiverType TEXT NOT NULL,
            receiverMemberId INTEGER,
            amount REAL NOT NULL,
            reason TEXT NOT NULL,
            dealAt INTEGER NOT NULL,
            createdAt INTEGER NOT NULL,
            isCompleted INTEGER NOT NULL DEFAULT 0,
            completedAt INTEGER
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE transactions ADD COLUMN giverType TEXT NOT NULL DEFAULT 'member'",
          );
          await db.execute(
            "ALTER TABLE transactions ADD COLUMN isCompleted INTEGER NOT NULL DEFAULT 0",
          );
          await db.execute(
            'ALTER TABLE transactions ADD COLUMN completedAt INTEGER',
          );
        }
      },
    );
  }

  Future<List<Member>> getMembers() async {
    final db = await database;
    final rows = await db.query('members', orderBy: 'name COLLATE NOCASE ASC');
    return rows.map(Member.fromMap).toList();
  }

  Future<void> insertMember({required String name, String? photoPath}) async {
    final db = await database;
    await db.insert('members', {
      'name': name,
      'photoPath': photoPath,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> updateMember({
    required int id,
    required String name,
    String? photoPath,
  }) async {
    final db = await database;
    await db.update(
      'members',
      {
        'name': name,
        'photoPath': photoPath,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteMember(int id) async {
    final db = await database;
    await db.delete('transactions', where: 'giverId = ?', whereArgs: [id]);
    await db.delete(
      'transactions',
      where: 'receiverType = ? AND receiverMemberId = ?',
      whereArgs: ['member', id],
    );
    await db.delete('members', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<TransactionRecord>> getTransactions() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT
        t.id,
        t.giverId,
        CASE WHEN t.giverType = 'owner' THEN 'Owner' ELSE g.name END AS giverName,
        t.giverType,
        t.receiverType,
        t.receiverMemberId,
        r.name AS receiverName,
        t.amount,
        t.reason,
        t.dealAt,
        t.isCompleted,
        t.completedAt
      FROM transactions t
      LEFT JOIN members g ON g.id = t.giverId
      LEFT JOIN members r ON r.id = t.receiverMemberId
      ORDER BY t.dealAt DESC, t.id DESC
    ''');
    return rows.map(TransactionRecord.fromMap).toList();
  }

  Future<void> insertTransaction(TransactionFormResult data) async {
    final db = await database;
    await db.insert('transactions', {
      'giverId': data.giverId,
      'giverType': data.direction == TransactionDirection.ownerPaysMember
          ? 'owner'
          : 'member',
      'receiverType': data.receiverType == ReceiverType.owner ? 'owner' : 'member',
      'receiverMemberId':
          data.receiverType == ReceiverType.owner ? null : data.receiverMemberId,
      'amount': data.amount,
      'reason': data.reason,
      'dealAt': data.dealAt.millisecondsSinceEpoch,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'isCompleted': 0,
      'completedAt': null,
    });
  }

  Future<void> updateTransaction(int id, TransactionFormResult data) async {
    final db = await database;
    await db.update(
      'transactions',
      {
        'giverId': data.giverId,
        'giverType': data.direction == TransactionDirection.ownerPaysMember
            ? 'owner'
            : 'member',
        'receiverType': data.receiverType == ReceiverType.owner ? 'owner' : 'member',
        'receiverMemberId':
            data.receiverType == ReceiverType.owner ? null : data.receiverMemberId,
        'amount': data.amount,
        'reason': data.reason,
        'dealAt': data.dealAt.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteTransaction(int id) async {
    final db = await database;
    await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> setTransactionCompleted(int id, bool isCompleted) async {
    final db = await database;
    await db.update(
      'transactions',
      {
        'isCompleted': isCompleted ? 1 : 0,
        'completedAt':
            isCompleted ? DateTime.now().millisecondsSinceEpoch : null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<MemberSummary?> getMemberSummaryById(int memberId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT
        m.id,
        m.name,
        m.photoPath,
        IFNULL((SELECT SUM(t1.amount) FROM transactions t1 WHERE t1.giverId = m.id), 0) AS givenTotal,
        IFNULL((SELECT SUM(t2.amount) FROM transactions t2 WHERE t2.receiverType = 'member' AND t2.receiverMemberId = m.id), 0) AS receivedTotal
      FROM members m
      WHERE m.id = ?
      LIMIT 1
    ''', [memberId]);
    if (rows.isEmpty) {
      return null;
    }
    return MemberSummary.fromMap(rows.first);
  }

  Future<void> completeMemberBalance({
    required int memberId,
    required double net,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (net > 0) {
      await db.insert('transactions', {
        'giverId': -1,
        'giverType': 'owner',
        'receiverType': 'member',
        'receiverMemberId': memberId,
        'amount': net,
        'reason': 'Balance completed',
        'dealAt': now,
        'createdAt': now,
        'isCompleted': 1,
        'completedAt': now,
      });
    } else if (net < 0) {
      await db.insert('transactions', {
        'giverId': memberId,
        'giverType': 'member',
        'receiverType': 'owner',
        'receiverMemberId': null,
        'amount': net.abs(),
        'reason': 'Balance completed',
        'dealAt': now,
        'createdAt': now,
        'isCompleted': 1,
        'completedAt': now,
      });
    }
  }

  Future<DashboardData> getDashboardData() async {
    final db = await database;
    final ownerRows = await db.rawQuery(
      'SELECT IFNULL(SUM(amount), 0) AS total FROM transactions WHERE receiverType = ?',
      ['owner'],
    );
    final ownerPendingRows = await db.rawQuery('''
      SELECT IFNULL(SUM(amount), 0) AS total
      FROM transactions
      WHERE giverType = 'owner' AND receiverType = 'member' AND isCompleted = 0
    ''');
    final countRows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM transactions',
    );
    final now = DateTime.now();
    final weekStart = now.subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    final monthStart = now.subtract(const Duration(days: 30)).millisecondsSinceEpoch;
    final weeklyRows = await db.rawQuery('''
      SELECT
        IFNULL(SUM(CASE WHEN receiverType = 'owner' THEN amount ELSE 0 END), 0) AS incoming,
        IFNULL(SUM(CASE WHEN giverType = 'owner' AND receiverType = 'member' THEN amount ELSE 0 END), 0) AS outgoing
      FROM transactions
      WHERE dealAt >= ?
    ''', [weekStart]);
    final monthlyRows = await db.rawQuery('''
      SELECT
        IFNULL(SUM(CASE WHEN receiverType = 'owner' THEN amount ELSE 0 END), 0) AS incoming,
        IFNULL(SUM(CASE WHEN giverType = 'owner' AND receiverType = 'member' THEN amount ELSE 0 END), 0) AS outgoing
      FROM transactions
      WHERE dealAt >= ?
    ''', [monthStart]);
    final memberRows = await db.rawQuery('''
      SELECT
        m.id,
        m.name,
        m.photoPath,
        IFNULL((SELECT SUM(t1.amount) FROM transactions t1 WHERE t1.giverId = m.id), 0) AS givenTotal,
        IFNULL((SELECT SUM(t2.amount) FROM transactions t2 WHERE t2.receiverType = 'member' AND t2.receiverMemberId = m.id), 0) AS receivedTotal
      FROM members m
      ORDER BY m.name COLLATE NOCASE ASC
    ''');

    return DashboardData(
      totalPaidToOwner: (ownerRows.first['total'] as num).toDouble(),
      totalOwnerShouldPay: (ownerPendingRows.first['total'] as num).toDouble(),
      transactionCount: (countRows.first['count'] as num).toInt(),
      weeklyIncoming: (weeklyRows.first['incoming'] as num).toDouble(),
      weeklyOutgoing: (weeklyRows.first['outgoing'] as num).toDouble(),
      monthlyIncoming: (monthlyRows.first['incoming'] as num).toDouble(),
      monthlyOutgoing: (monthlyRows.first['outgoing'] as num).toDouble(),
      members: memberRows.map(MemberSummary.fromMap).toList(),
    );
  }
}
