import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game_client.dart';
import 'models.dart';
import 'widgets/table_3d.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 允许横屏 + 竖屏
  SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const MahjongApp());
}

class MahjongApp extends StatelessWidget {
  const MahjongApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '麻将',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B5E20),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final client = GameClient();
  final urlCtrl = TextEditingController(text: 'ws://example.com/ws');
  final nameCtrl = TextEditingController();
  final userCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  final roomCtrl = TextEditingController();
  bool _registerMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    nameCtrl.text = '玩家${DateTime.now().millisecond % 1000}';
    client.addListener(_onUpdate);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 回前台续连；切后台不主动断开，尽量保活
    if (state == AppLifecycleState.resumed) {
      client.onAppResumed();
    }
  }

  void _onUpdate() {
    if (!mounted) return;
    setState(() {});
    if (client.notice.isNotEmpty) {
      final n = client.notice;
      client.notice = '';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(n), duration: const Duration(seconds: 3)),
        );
      });
    }
    if (client.status.contains('对局结束') && client.settleText.isNotEmpty) {
      final text = client.settleText;
      client.settleText = '';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(client.lastHuang ? '流局结算' : '胡牌结算'),
            content: SingleChildScrollView(child: Text(text)),
            actions: [
              TextButton(
                onPressed: () {
                  client.lastError = '';
                  Navigator.pop(context);
                },
                child: const Text('确定'),
              ),
            ],
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    client.removeListener(_onUpdate);
    client.disconnect();
    urlCtrl.dispose();
    nameCtrl.dispose();
    userCtrl.dispose();
    passCtrl.dispose();
    roomCtrl.dispose();
    super.dispose();
  }

  bool get _landscape {
    final s = MediaQuery.sizeOf(context);
    return s.width > s.height;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(client.connected
            ? '${client.loggedIn ? client.username : (client.playerName.isEmpty ? '游客' : client.playerName)} · ${client.gold}币 · ${client.playerId}'
            : (_landscape ? '麻将' : '麻将 · 推倒胡/川麻')),
        actions: [
          if (client.connected)
            IconButton(
              tooltip: '断开',
              onPressed: () => client.disconnect().then((_) => setState(() {})),
              icon: const Icon(Icons.link_off),
            ),
        ],
      ),
      body: SafeArea(
        child: !client.connected
            ? Padding(
                padding: EdgeInsets.all(_landscape ? 8 : 12),
                child: _connectPage(),
              )
            : client.inGame
                ? _gameTable()
                : Padding(
                    padding: EdgeInsets.all(_landscape ? 8 : 12),
                    child: client.room != null
                        ? _room()
                        : (client.loggedIn || client.status.startsWith('游客')
                            ? _lobby()
                            : _authPage()),
                  ),
      ),
    );
  }

  Widget _connectPage() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ListView(
          shrinkWrap: true,
          children: [
            Text('麻将',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('连接服务器',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            TextField(
              controller: urlCtrl,
              decoration: const InputDecoration(
                labelText: 'WebSocket 地址',
                hintText: 'ws://IP:8081/ws',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => client.connect(urlCtrl.text, nameCtrl.text),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('连接', style: TextStyle(fontSize: 18)),
              ),
            ),
            const SizedBox(height: 12),
            Text(client.status, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _authPage() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(_registerMode ? '注册账号' : '登录',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(client.status, textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.amber)),
            const SizedBox(height: 16),
            TextField(
              controller: userCtrl,
              decoration: const InputDecoration(
                labelText: '用户名',
                hintText: '3-24位字母数字_',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '密码',
                hintText: '至少4位',
                border: OutlineInputBorder(),
              ),
            ),
            if (_registerMode) ...[
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: '昵称（可选）',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                if (_registerMode) {
                  client.register(userCtrl.text, passCtrl.text,
                      nickname: nameCtrl.text);
                } else {
                  client.login(userCtrl.text, passCtrl.text);
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(_registerMode ? '注册并登录' : '登录',
                    style: const TextStyle(fontSize: 18)),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() => _registerMode = !_registerMode),
              child: Text(_registerMode ? '已有账号？去登录' : '没有账号？注册'),
            ),
            const Divider(height: 32),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: '游客昵称',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => client.enterAsGuest(nameCtrl.text),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('游客进入（金币不持久）'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lobby() {
    final list = Expanded(
      child: client.roomList.isEmpty
          ? const Center(child: Text('暂无房间'))
          : ListView.builder(
              itemCount: client.roomList.length,
              itemBuilder: (_, i) {
                final r = client.roomList[i];
                return Card(
                  child: ListTile(
                    dense: _landscape,
                    title: Text('[${r.id}] ${r.rule}'),
                    subtitle:
                        Text('${r.count}/4 ${r.inGame ? "对局中" : "等待"}'),
                    trailing: r.inGame || r.count >= 4
                        ? null
                        : FilledButton(
                            onPressed: () => client.joinRoom(r.id),
                            child: const Text('加入'),
                          ),
                  ),
                );
              },
            ),
    );

    final controls = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(client.status, style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(onPressed: client.listRooms, child: const Text('刷新房间')),
            FilledButton.tonal(
              onPressed: () => client.createRoom('tuidaohu'),
              child: const Text('创建推倒胡'),
            ),
            FilledButton.tonal(
              onPressed: () => client.createRoom('sichuan'),
              child: const Text('创建川麻换三张'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: roomCtrl,
                decoration: const InputDecoration(
                  labelText: '房间号',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                textCapitalization: TextCapitalization.characters,
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => client.joinRoom(roomCtrl.text),
              child: const Text('加入'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text('房间列表',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );

    if (_landscape) {
      return Row(
        children: [
          SizedBox(width: 320, child: controls),
          const SizedBox(width: 12),
          list,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [controls, Expanded(child: list)],
    );
  }

  Widget _room() {
    final r = client.room!;
    final isOwner = r.owner == client.playerId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('房间 ${r.id} · ${r.rule}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(client.status),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            children: r.players.map((p) {
              final mark = p['id'] == r.owner ? ' (房主)' : '';
              return ListTile(
                leading: const Icon(Icons.person),
                title: Text('${p['name']}$mark'),
              );
            }).toList(),
          ),
        ),
        if (isOwner && !r.inGame)
          FilledButton(
            onPressed: client.startGame,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('开始游戏', style: TextStyle(fontSize: 18)),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () {
            client.leaveRoom();
            client.listRooms();
          },
          child: const Text('离开房间'),
        ),
      ],
    );
  }

  Widget _gameTable() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Table3D(
            client: client,
            onHandTap: (tile, index) {
              if (client.inExchange) {
                client.toggleSelectAt(index);
              } else if (!client.inDingQue) {
                client.discard(tile);
              }
            },
          ),
        ),
        if (client.inDingQue) _dingQueBar(),
        if (client.inExchange)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: FilledButton(
              onPressed:
                  client.selectedCount == 3 ? client.confirmExchange : null,
              child: Text('确认换三张 (${client.selectedCount}/3)'),
            ),
          ),
        if (client.showActions) _actionBar(),
      ],
    );
  }


  Widget _dingQueBar() {
    Widget btn(String label, int suit) {
      final chosen = client.myQue == suit;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: chosen ? Colors.orange : null,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed:
                client.myQue >= 0 ? null : () => client.chooseDingQue(suit),
            child: Text('缺$label', style: const TextStyle(fontSize: 16)),
          ),
        ),
      );
    }

    return Column(
      children: [
        const Text('定缺：选一门不要的花色', style: TextStyle(fontSize: 15)),
        const SizedBox(height: 6),
        Row(children: [btn('万', 0), btn('筒', 1), btn('条', 2)]),
        const SizedBox(height: 6),
      ],
    );
  }


  Widget _actionBar() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          if (client.canPung && !client.actionSelf)
            FilledButton(
              onPressed: () => client.action('pung'),
              child: const Text('碰'),
            ),
          if (client.canMingKong && !client.actionSelf)
            FilledButton(
              onPressed: () => client.mingKong(),
              child: const Text('直杠'),
            ),
          if (client.actionSelf && client.anKongOptions.isNotEmpty)
            FilledButton(
              onPressed: () => _confirmAnKong(client.anKongOptions.first),
              child: Text('暗杠${client.anKongOptions.first.label}'),
            ),
          if (client.actionSelf && client.jiaKongOptions.isNotEmpty)
            FilledButton(
              onPressed: () => client.jiaKong(client.jiaKongOptions.first),
              child: Text('补杠${client.jiaKongOptions.first.label}'),
            ),
          if (client.canWin)
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
              onPressed: () => client.action('win'),
              child: Text(client.robKong
                  ? '抢杠胡'
                  : (client.actionSelf ? '自摸' : '胡')),
            ),
          OutlinedButton(
            onPressed: () {
              if (client.actionSelf) {
                client.dismissActions();
              } else {
                client.passAction();
              }
            },
            child: const Text('过'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAnKong(Tile t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('暗杠确认'),
        content: Text('确认暗杠 ${t.label}？\n对外亮出 2 张，另外 2 张隐藏。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认暗杠')),
        ],
      ),
    );
    if (ok == true) {
      client.anKong(t);
    }
  }
}