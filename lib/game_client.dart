import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'models.dart';

/// 连接 Go 麻将服: ws://host:8081/ws
/// 断线后自动重连；session 按进程 PID 分文件，同机多开互不抢座位。
class GameClient extends ChangeNotifier {
  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  Timer? _heartbeat;
  Timer? _reconnectTimer;

  String serverUrl = '';
  String playerId = '';
  /// 持久化会话 ID：杀进程后再开也应恢复
  String sessionId = '';
  String playerName = '';
  int gold = 10000;
  String username = '';
  int userId = 0;
  bool loggedIn = false;
  bool guestMode = true;
  String status = '未连接';
  bool connected = false;
  bool _manualDisconnect = false;
  bool _sessionLoaded = false;

  RoomState? room;
  List<RoomInfo> roomList = [];

  bool inGame = false;
  int mySeat = -1;
  List<String> playerNames = [];
  List<Tile> hand = [];
  List<dynamic> melds = []; // 自己的副露
  List<Tile> anKongOptions = [];
  List<Tile> jiaKongOptions = [];
  bool canAnOrJia = false;
  List<String> discardLog = [];
  int current = -1;
  String phase = '';
  int wall = 0;
  bool inExchange = false;
  bool inDingQue = false;
  List<int> selectedIndices = [];

  int myQue = -1;
  List<int> allQue = [];
  final Map<int, int> highlightIds = {};

  bool showActions = false;
  bool canPung = false;
  bool canWin = false;
  bool actionSelf = false;

  String lastError = '';
  final Set<int> wonSeats = {};
  String rule = '';
  String notice = '';

  // tuidaohu UI state
  int dealer = 0;
  int sealedN = 0;
  bool canMingKong = false;
  bool robKong = false;
  bool lastKongDraw = false;
  String lastWinKind = '';
  String settleText = '';
  List<Tile> horseTiles = [];
  int horseFan = 0;
  int patternMul = 1;
  int totalMul = 0;
  bool lastHuang = false;

  /// Per-seat table data for 3D view
  List<List<Tile>> seatDiscards = [];
  List<List<dynamic>> seatMelds = [];
  List<int> seatHandCounts = [];

  List<dynamic> meldsOf(int seat) {
    if (seat >= 0 && seat < seatMelds.length) return seatMelds[seat];
    return const [];
  }

  /// Per-process session so two clients on one device keep different player IDs.
  File get _sessionFile {
    final dir = Directory.systemTemp;
    return File(
      '${dir.path}${Platform.pathSeparator}mahjong_client_session_$pid.json',
    );
  }

  Future<void> _loadSession() async {
    if (_sessionLoaded) return;
    _sessionLoaded = true;
    try {
      final f = _sessionFile;
      if (await f.exists()) {
        final m = jsonDecode(await f.readAsString());
        if (m is Map) {
          final sid = '${m['session_id'] ?? ''}';
          final name = '${m['name'] ?? ''}';
          final un = '${m['username'] ?? ''}';
          final uid = Tile.asInt(m['user_id']);
          if (sid.isNotEmpty) sessionId = sid;
          if (name.isNotEmpty) playerName = name;
          if (un.isNotEmpty) {
            username = un;
            loggedIn = true;
            guestMode = false;
          }
          if (uid > 0) userId = uid;
          if (m['logged_in'] == true) {
            loggedIn = true;
            guestMode = false;
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _saveSession() async {
    try {
      await _sessionFile.writeAsString(jsonEncode({
        'session_id': sessionId,
        'name': playerName,
        'username': username,
        'user_id': userId,
        'logged_in': loggedIn,
      }));
    } catch (_) {}
  }

  Future<void> connect(String url, String name) async {
    _manualDisconnect = false;
    serverUrl = url.trim();
    await _loadSession();
    // 用户输入的名字优先；若空则用本地缓存名
    final n = name.trim();
    if (n.isNotEmpty) {
      playerName = n;
    } else if (playerName.isEmpty) {
      playerName = '玩家';
    }
    await _saveSession();
    await _openSocket();
  }

  Future<void> _openSocket() async {
    await _cleanupSocket(closeSink: true);
    await _loadSession();
    status = sessionId.isNotEmpty ? '重连中...' : '连接中...';
        notifyListeners();
    try {
      final uri = Uri.parse(serverUrl);
      _ch = WebSocketChannel.connect(uri);
      connected = true;
      status = '已连接，等待服务器...';
      notifyListeners();
      _sub = _ch!.stream.listen(
        _onData,
        onError: (e) {
          status = '连接错误: $e';
          connected = false;
          notifyListeners();
          _scheduleReconnect();
        },
        onDone: () {
          status = '连接已断开';
          connected = false;
          notifyListeners();
          if (!_manualDisconnect) {
            _scheduleReconnect();
          }
        },
      );
      _startHeartbeat();
    } catch (e) {
      status = '连接失败: $e';
      connected = false;
      notifyListeners();
      _scheduleReconnect();
    }
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 20), (_) {
      if (connected) send('ping');
    });
  }

  void _scheduleReconnect() {
    if (_manualDisconnect) return;
    if (serverUrl.isEmpty) return;
        _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 1), () {
      if (_manualDisconnect || connected) return;
      status = sessionId.isNotEmpty ? '自动恢复会话...' : '自动重连...';
      notifyListeners();
      _openSocket();
    });
  }

  Future<void> disconnect() async {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _heartbeat?.cancel();
    // 手动断开：清本地会话，下次是新 ID
    sessionId = '';
    try {
      if (await _sessionFile.exists()) await _sessionFile.delete();
    } catch (_) {}
    await _cleanupSocket(closeSink: true);
    connected = false;
    playerId = '';
    room = null;
    inGame = false;
    status = '已断开';
    notifyListeners();
  }

  Future<void> _cleanupSocket({required bool closeSink}) async {
    _heartbeat?.cancel();
    _heartbeat = null;
    await _sub?.cancel();
    _sub = null;
    if (closeSink) {
      try {
        await _ch?.sink.close();
      } catch (_) {}
    }
    _ch = null;
  }

  void onAppResumed() {
    if (_manualDisconnect) return;
    if (!connected && serverUrl.isNotEmpty) {
      status = '恢复连接...';
      notifyListeners();
      _openSocket();
    } else if (connected) {
      send('ping');
    }
  }

  void send(String type, [Map<String, dynamic>? data]) {
    if (_ch == null || !connected) return;
    final payload = <String, dynamic>{'type': type};
    if (data != null) payload['data'] = data;
    try {
      _ch!.sink.add(jsonEncode(payload));
    } catch (_) {}
  }

  void _trySendResume() {
    if (sessionId.isEmpty) return;
    send('resume', {
      'player_id': sessionId,
      'name': playerName,
    });
    status = '正在恢复 ID $sessionId ...';
    notifyListeners();
  }

  void _onData(dynamic raw) {
    try {
      final msg = ServerMsg.fromRaw(raw as String);
      _handle(msg);
    } catch (e) {
      status = '解析消息失败: $e';
      notifyListeners();
    }
  }

  Map<String, dynamic> _map(dynamic d) {
    if (d is Map<String, dynamic>) return d;
    if (d is Map) return Map<String, dynamic>.from(d);
    return {};
  }

  List<Tile> _tiles(dynamic d) {
    if (d is! List) return [];
    return d
        .whereType<Map>()
        .map((e) => Tile.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  void _setHighlightFromTiles(List<Tile> tiles) {
    highlightIds.clear();
    for (final t in tiles) {
      highlightIds[t.id] = (highlightIds[t.id] ?? 0) + 1;
    }
  }

  void _setHighlightOne(Tile? t) {
    highlightIds.clear();
    if (t != null) highlightIds[t.id] = 1;
  }

  static String queName(int s) {
    if (s == 0) return '万';
    if (s == 1) return '筒';
    if (s == 2) return '条';
    return '?';
  }

  void _bindSession(String id) {
    if (id.isEmpty) return;
    playerId = id;
    sessionId = id;
    _saveSession();
  }

  void _handle(ServerMsg msg) {
    final d = msg.data;
    switch (msg.type) {
      case 'connected':
        final m = _map(d);
        final newId = '${m['id'] ?? ''}';
        playerId = newId;
        if (m['gold'] != null) gold = Tile.asInt(m['gold']);
        // resume first if same machine session
        if (sessionId.isNotEmpty && sessionId != newId) {
          status = '连接成功，自动恢复...';
          notifyListeners();
          Future.microtask(_trySendResume);
        } else {
          _bindSession(newId);
          status = '已连接，请登录或游客进入';
        }
        break;
      case 'auth_ok':
        final m = _map(d);
        loggedIn = true;
        guestMode = false;
        userId = Tile.asInt(m['user_id']);
        username = '${m['username'] ?? username}';
        if (m['name'] != null) playerName = '${m['name']}';
        if (m['gold'] != null) gold = Tile.asInt(m['gold']);
        if (m['id'] != null) _bindSession('${m['id']}');
        status = '登录成功 $username · $gold币';
        notice = '欢迎，$playerName';
        _saveSession();
        listRooms();
        break;
      case 'auth_fail':
        final m = _map(d);
        lastError = '${m['msg'] ?? '登录失败'}';
        status = lastError;
        notice = lastError;
        break;
      case 'resume_ok':
        final m = _map(d);
        final rid = '${m['id'] ?? sessionId}';
        _bindSession(rid);
            if (m['gold'] != null) gold = Tile.asInt(m['gold']);
        if (m['name'] != null) playerName = '${m['name']}';
        if (m['room'] is Map) {
          room = RoomState.fromJson(Map<String, dynamic>.from(m['room'] as Map));
        }
        inGame = m['in_game'] == true;
        mySeat = Tile.asInt(m['seat']);
        rule = '${m['rule'] ?? rule}';
        final names = m['players'];
        if (names is List) {
          playerNames = names.map((e) => '$e').toList();
        }
        if (inGame) {
          hand = _tiles(m['hand']);
          hand.sort((a, b) => a.id.compareTo(b.id));
          melds = m['melds'] is List ? List<dynamic>.from(m['melds'] as List) : [];
          _resetTableSeats();
          _ingestDiscardsMatrix(m['discards']);
          _ingestMeldsMatrix(m['all_melds']);
          if (mySeat >= 0) {
            _ensureSeats(mySeat + 1);
            seatMelds[mySeat] = List<dynamic>.from(melds);
            seatHandCounts[mySeat] = hand.length;
          }
          final hc = m['hand_count'];
          // optional per-seat not provided; keep defaults
          if (hc != null && mySeat >= 0) {
            seatHandCounts[mySeat] = Tile.asInt(hc);
          }
          phase = '${m['phase'] ?? ''}';
          current = Tile.asInt(m['current']);
          wall = Tile.asInt(m['wall']);
          myQue = m.containsKey('que') ? Tile.asInt(m['que']) : myQue;
          final aq = m['all_que'];
          if (aq is List) {
            allQue = aq.map((e) => Tile.asInt(e)).toList();
          }
          final won = m['won'];
          if (won is List) {
            wonSeats.clear();
            for (var i = 0; i < won.length; i++) {
              if (won[i] == true) wonSeats.add(i);
            }
          }
          inExchange = m['need_exchange'] == true;
          inDingQue = m['need_dingque'] == true;
          selectedIndices = [];
          showActions = false;
          status = '重连成功 ID=$playerId 座位$mySeat';
          notice = '已恢复同一用户 ID 并回到牌桌';
        } else {
          status = '重连成功 ID=$playerId';
          notice = '已恢复同一用户 ID';
          listRooms();
        }
        break;
      case 'resume_fail':
        final m = _map(d);
        // 旧会话失效：改用当前新 ID 并保存
        _bindSession(playerId);
            inGame = false;
        room = null;
        notice = '${m['msg'] ?? '会话失效，已使用新 ID'}';
        status = '新 ID=$playerId（${m['msg'] ?? '旧会话失效'}）';
        listRooms();
        break;
      case 'profile':
        final m = _map(d);
        if (m['name'] != null) playerName = '${m['name']}';
        if (m['gold'] != null) gold = Tile.asInt(m['gold']);
        if (m['username'] != null) username = '${m['username']}';
        if (m['user_id'] != null) userId = Tile.asInt(m['user_id']);
        if (m['guest'] == true) {
          guestMode = true;
          loggedIn = false;
        } else if (userId > 0) {
          guestMode = false;
          loggedIn = true;
        }
        status = '$playerName · $gold币 · ID=$playerId';
        _saveSession();
        break;
      case 'pong':
        return;
      case 'tips':
        final m = _map(d);
        notice = '${m['msg'] ?? ''}';
        if (notice.isNotEmpty) status = notice;
        break;
      case 'player_left':
        final m = _map(d);
        final name = '${m['name'] ?? '有人'}';
        final reason = '${m['reason'] ?? ''}';
        final offline = m['offline'] == true;
        if (reason == 'disconnect' || offline) {
          notice = '$name 断线了，等待重连';
        } else {
          notice = '$name 离开了房间';
        }
        status = notice;
        discardLog.add(notice);
        if (discardLog.length > 16) {
          discardLog = discardLog.sublist(discardLog.length - 16);
        }
        break;
      case 'player_reconnected':
        final m = _map(d);
        final name = '${m['name'] ?? '有人'}';
        notice = '$name 已重新连接';
        status = notice;
        discardLog.add(notice);
        break;
      case 'room':
        room = RoomState.fromJson(_map(d));
        if (playerId.isNotEmpty) _bindSession(playerId);
        status = '房间 ${room?.id} · ID=$playerId';
        break;
      case 'room_list':
        roomList = [];
        if (d is List) {
          for (final e in d) {
            if (e is Map) {
              roomList.add(RoomInfo.fromJson(Map<String, dynamic>.from(e)));
            }
          }
        }
        break;
      case 'game_start':
        final m = _map(d);
        inGame = true;
        if (playerId.isNotEmpty) _bindSession(playerId);
        rule = '${m['rule'] ?? ''}';
        mySeat = Tile.asInt(m['seat']);
        hand = _tiles(m['hand']);
        hand.sort((a, b) => a.id.compareTo(b.id));
        inExchange = m['exchange'] == true;
        inDingQue = false;
        phase = inExchange ? 'exchange' : '';
        current = -1;
        discardLog = [];
        selectedIndices = [];
        showActions = false;
        wonSeats.clear();
        myQue = -1;
        allQue = [];
        highlightIds.clear();
        melds = [];
        anKongOptions = [];
        jiaKongOptions = [];
        canAnOrJia = false;
        canMingKong = false;
        robKong = false;
        lastKongDraw = false;
        settleText = '';
        horseTiles = [];
        lastHuang = false;
        dealer = Tile.asInt(m['dealer']);
        sealedN = Tile.asInt(m['sealed']);
        final names = m['players'];
        playerNames = [];
        if (names is List) {
          playerNames = names.map((e) => '$e').toList();
        }
        _resetTableSeats();
        if (mySeat >= 0) {
          _ensureSeats(playerNames.length);
          seatHandCounts[mySeat] = hand.length;
        }
        status = inExchange ? '选 3 张同花色换牌' : '游戏开始（庄P$dealer）';
        break;
      case 'turn':
        final m = _map(d);
        current = Tile.asInt(m['current']);
        phase = '${m['phase'] ?? ''}';
        wall = Tile.asInt(m['wall']);
        if (current == mySeat && phase == 'discard') {
          status = myQue >= 0
              ? '轮到你出牌（定缺：${queName(myQue)}）'
              : '轮到你出牌';
        }
        break;
      case 'discarded':
        final m = _map(d);
        final seat = Tile.asInt(m['seat']);
        final tile = m['tile'] is Map
            ? Tile.fromJson(Map<String, dynamic>.from(m['tile'] as Map))
            : null;
        if (tile != null) {
          _ensureSeats(seat + 1 > playerNames.length ? seat + 1 : (playerNames.isEmpty ? 4 : playerNames.length));
          if (seat >= 0 && seat < seatDiscards.length) {
            seatDiscards[seat] = [...seatDiscards[seat], tile];
          }
          if (seat >= 0 && seat < seatHandCounts.length) {
            // after discard, hand is 13-ish; server doesn't send count
            if (seat == mySeat) {
              seatHandCounts[seat] = hand.length;
            } else if (seatHandCounts[seat] > 0) {
              seatHandCounts[seat] = seatHandCounts[seat] - 1;
            }
          }
          discardLog.add('P$seat 打 ${tile.label}');
          if (discardLog.length > 16) {
            discardLog = discardLog.sublist(discardLog.length - 16);
          }
        }
        if (seat == mySeat) highlightIds.clear();
        showActions = false;
        break;
      case 'draw':
        final m = _map(d);
        hand = _tiles(m['hand']);
        hand.sort((a, b) => a.id.compareTo(b.id));
        if (m['melds'] is List) {
          melds = List<dynamic>.from(m['melds'] as List);
          if (mySeat >= 0) {
            _ensureSeats(mySeat + 1);
            seatMelds[mySeat] = List<dynamic>.from(melds);
          }
        }
        if (mySeat >= 0) {
          _ensureSeats(mySeat + 1);
          seatHandCounts[mySeat] = hand.length;
        }
        // current seat just drew
        if (current >= 0) {
          _ensureSeats(current + 1);
          if (current != mySeat) {
            seatHandCounts[current] = seatHandCounts[current] + 1;
          }
        }
        final t = m['tile'] is Map
            ? Tile.fromJson(Map<String, dynamic>.from(m['tile'] as Map))
            : null;
        _setHighlightOne(t);
        lastKongDraw = m['kong_draw'] == true;
        if (t != null) {
          status = lastKongDraw ? '杠后补牌 ${t.label}' : '摸到 ${t.label}';
        }
        break;
      case 'hand':
        final m = _map(d);
        hand = _tiles(m['hand']);
        hand.sort((a, b) => a.id.compareTo(b.id));
        if (m['melds'] is List) {
          melds = List<dynamic>.from(m['melds'] as List);
          if (mySeat >= 0) {
            _ensureSeats(mySeat + 1);
            seatMelds[mySeat] = List<dynamic>.from(melds);
          }
        }
        if (mySeat >= 0) {
          _ensureSeats(mySeat + 1);
          seatHandCounts[mySeat] = hand.length;
        }
        break;
      case 'action_prompt':
        final m = _map(d);
        canPung = m['can_pung'] == true;
        canWin = m['can_win'] == true;
        actionSelf = m['self'] == true;
        canMingKong = m['can_kong'] == true && !(m['self'] == true);
        robKong = m['rob_kong'] == true;
        // self an/jia come via self_options, not here
        canAnOrJia = false;
        showActions = canPung || canWin || canMingKong;
        if (robKong && canWin) {
          status = '可以抢杠胡！';
        } else if (canWin) {
          status = actionSelf ? '可以自摸！' : '可以胡！';
        } else {
          status = '可以操作';
        }
        break;
      case 'exchange_ok':
        inExchange = false;
        selectedIndices = [];
        status = '已提交换牌，等待其他人...';
        break;
      case 'exchange_done':
        final m = _map(d);
        hand = _tiles(m['hand']);
        hand.sort((a, b) => a.id.compareTo(b.id));
        final received = _tiles(m['received']);
        _setHighlightFromTiles(received);
        inExchange = false;
        selectedIndices = [];
        if (m['need_dingque'] == true) {
          inDingQue = true;
          phase = 'dingque';
          status = '换牌完成，请定缺（缺一门）';
        } else {
          status = '换牌完成';
        }
        break;
      case 'dingque_ok':
        final m = _map(d);
        myQue = Tile.asInt(m['suit']);
        status = '已定缺：${queName(myQue)}，等待其他人...';
        break;
      case 'dingque_update':
        break;
      case 'game_ready':
        final m = _map(d);
        hand = _tiles(m['hand']);
        hand.sort((a, b) => a.id.compareTo(b.id));
        myQue = Tile.asInt(m['que']);
        allQue = [];
        final aq = m['all_que'];
        if (aq is List) {
          allQue = aq.map((e) => Tile.asInt(e)).toList();
        }
        inDingQue = false;
        phase = 'discard';
        final draw = m['draw'] is Map
            ? Tile.fromJson(Map<String, dynamic>.from(m['draw'] as Map))
            : null;
        _setHighlightOne(draw);
        status = '定缺完成（缺${queName(myQue)}），开始出牌';
        break;
      case 'pung':
        final m = _map(d);
        final seat = Tile.asInt(m['seat']);
        final from = Tile.asInt(m['from']);
        status = 'P$seat 碰了';
        showActions = false;
        highlightIds.clear();
        _ensureSeats((seat > from ? seat : from) + 1);
        if (m['melds'] is List) {
          seatMelds[seat] = List<dynamic>.from(m['melds'] as List);
          if (seat == mySeat) melds = seatMelds[seat];
        }
        // remove claimed discard
        if (from >= 0 && from < seatDiscards.length && seatDiscards[from].isNotEmpty) {
          seatDiscards[from] = seatDiscards[from].sublist(0, seatDiscards[from].length - 1);
        }
        if (seat >= 0 && seat < seatHandCounts.length) {
          // pung uses 2 from hand; display count ≈ remaining
          if (seat == mySeat) {
            seatHandCounts[seat] = hand.length;
          } else {
            seatHandCounts[seat] = (seatHandCounts[seat] - 2).clamp(0, 14);
          }
        }
        break;
      case 'kong':
        final mk = _map(d);
        final seat = Tile.asInt(mk['seat']);
        final from = Tile.asInt(mk['from']);
        final kind = '${mk['kind'] ?? ''}';
        final kindCn = kind == 'an'
            ? '暗杠'
            : kind == 'ming'
                ? '直杠'
                : kind == 'jia'
                    ? '补杠'
                    : kind;
        status = 'P$seat $kindCn';
        if (mk['robbable'] == true) status += '（可抢杠）';
        if (kind == 'an' && mk['show_tiles'] != null) {
          status += '（亮2张）';
        }
        showActions = false;
        _ensureSeats((seat > from ? seat : from) + 1);
        if (mk['melds'] is List) {
          seatMelds[seat] = List<dynamic>.from(mk['melds'] as List);
          if (seat == mySeat) melds = seatMelds[seat];
        }
        if (kind == 'ming' && from >= 0 && from < seatDiscards.length && seatDiscards[from].isNotEmpty) {
          seatDiscards[from] = seatDiscards[from].sublist(0, seatDiscards[from].length - 1);
        }
        if (seat >= 0 && seat < seatHandCounts.length) {
          if (seat == mySeat) {
            seatHandCounts[seat] = hand.length;
          } else if (kind == 'an') {
            seatHandCounts[seat] = (seatHandCounts[seat] - 4).clamp(0, 14);
          } else if (kind == 'ming') {
            seatHandCounts[seat] = (seatHandCounts[seat] - 3).clamp(0, 14);
          } else if (kind == 'jia') {
            seatHandCounts[seat] = (seatHandCounts[seat] - 1).clamp(0, 14);
          }
        }
        discardLog.add(status);
        break;
      case 'self_options':
        final so = _map(d);
        canWin = so['can_win'] == true;
        anKongOptions = _tiles(so['an_kong']);
        jiaKongOptions = _tiles(so['jia_kong']);
        canAnOrJia = anKongOptions.isNotEmpty || jiaKongOptions.isNotEmpty;
        canMingKong = false;
        robKong = false;
        if (so['melds'] is List) melds = List<dynamic>.from(so['melds'] as List);
        if (so['hand'] is List) {
          hand = _tiles(so['hand']);
          hand.sort((a, b) => a.id.compareTo(b.id));
        }
        actionSelf = true;
        showActions = canWin || canAnOrJia;
        if (canWin) {
          status = '可以自摸/杠';
        } else if (canAnOrJia) {
          status = '可以暗杠/补杠';
        }
        break;
      case 'won':
        final m = _map(d);
        final seat = Tile.asInt(m['seat']);
        final cont = m['continue'] == true;
        lastWinKind = '${m['win_kind'] ?? ''}';
        wonSeats.add(seat);
        final ws = m['won_seats'];
        if (ws is List) {
          wonSeats
            ..clear()
            ..addAll(ws.map((e) => Tile.asInt(e)));
        }
        final kindHint = lastWinKind == 'rob_jia'
            ? '抢杠胡'
            : lastWinKind == 'ming_flower'
                ? '点杠开花'
                : lastWinKind == 'self'
                    ? '自摸'
                    : '胡';
        if (cont) {
          inGame = true;
          canPung = false;
          canWin = false;
          canMingKong = false;
          canAnOrJia = false;
          robKong = false;
          actionSelf = false;
          highlightIds.clear();
          status = 'P$seat $kindHint！血战继续（已胡 ${wonSeats.length} 人）';
          notice = status;
        } else {
          inGame = false;
          status = 'P$seat $kindHint！';
        }
        showActions = false;
        discardLog.add('P$seat $kindHint');
        break;
      case 'game_over':
        if (rule == 'sichuan' && inGame && wonSeats.isNotEmpty) {
          final m = _map(d);
          if (m['result'] is List) {
            // Keep the live Sichuan table if the server is still advancing rounds.
            break;
          }
        }
        inGame = false;
        inDingQue = false;
        inExchange = false;
        showActions = false;
        status = '对局结束';
        final m = _map(d);
        lastHuang = m['huang'] == true;
        if (m['dealer'] != null) dealer = Tile.asInt(m['dealer']);
        final detail = m['detail'];
        horseTiles = [];
        horseFan = 0;
        patternMul = 1;
        totalMul = 0;
        if (detail is Map) {
          horseTiles = _tiles(detail['horse_tiles']);
          horseFan = Tile.asInt(detail['horse_fan']);
          patternMul = Tile.asInt(detail['pattern_mul']);
          if (patternMul <= 0) patternMul = 1;
          totalMul = Tile.asInt(detail['total_mul']);
          lastWinKind = '${detail['win_kind'] ?? lastWinKind}';
        }
        final lines = <String>[];
        if (lastHuang) {
          lines.add('流局（黄牌）· 仅结算杠费 · 庄家连庄');
        } else {
          lines.add('胡牌结算');
          if (lastWinKind.isNotEmpty) lines.add('方式: $lastWinKind');
          if (horseTiles.isNotEmpty) {
            lines.add(
                '买马: ${horseTiles.map((t) => t.label).join(' ')}  有效番=$horseFan');
          }
          lines.add('牌型倍数=$patternMul  总倍数=$totalMul');
        }
        final result = m['result'];
        if (result is List) {
          for (final r in result) {
            if (r is Map) {
              final name = '${r['name']}';
              final won = r['won'] == true;
              final kd = Tile.asInt(r['kong_delta']);
              final wd = Tile.asInt(r['win_delta']);
              final dlt = Tile.asInt(r['delta']);
              final g = Tile.asInt(r['gold']);
              final sign = dlt >= 0 ? '+$dlt' : '$dlt';
              lines.add(
                  '$name ${won ? "胡" : "未胡"}  杠$kd 胡$wd 合计$sign  金币$g');
              // update local gold if me
              if (name == playerName && r['gold'] != null) {
                gold = g;
              }
            }
          }
        }
        settleText = lines.join('\n');
        lastError = settleText;
        break;
      case 'error':
        final m = _map(d);
        lastError = '${m['msg'] ?? '错误'}';
        status = lastError;
        notice = lastError;
        break;
    }
    notifyListeners();
  }


  void _ensureSeats(int n) {
    if (n <= 0) n = 4;
    while (seatDiscards.length < n) {
      seatDiscards.add([]);
    }
    while (seatMelds.length < n) {
      seatMelds.add([]);
    }
    while (seatHandCounts.length < n) {
      seatHandCounts.add(13);
    }
    if (seatDiscards.length > n) {
      seatDiscards = seatDiscards.sublist(0, n);
      seatMelds = seatMelds.sublist(0, n);
      seatHandCounts = seatHandCounts.sublist(0, n);
    }
  }

  void _resetTableSeats() {
    final n = playerNames.isEmpty ? 4 : playerNames.length;
    seatDiscards = List.generate(n, (_) => <Tile>[]);
    seatMelds = List.generate(n, (_) => <dynamic>[]);
    seatHandCounts = List.generate(n, (_) => 13);
  }

  List<Tile> discardsOf(int seat) {
    if (seat < 0 || seat >= seatDiscards.length) return const [];
    return seatDiscards[seat];
  }

  List<dynamic> meldsOf(int seat) {
    if (seat < 0 || seat >= seatMelds.length) return const [];
    return seatMelds[seat];
  }

  int handCountOf(int seat) {
    if (seat == mySeat) return hand.length;
    if (seat < 0 || seat >= seatHandCounts.length) {
      // default closed hand size before sync
      return 13;
    }
    final c = seatHandCounts[seat];
    return c > 0 ? c : 13;
  }


  void _ingestDiscardsMatrix(dynamic raw) {
    if (raw is! List) return;
    _ensureSeats(raw.length);
    for (var i = 0; i < raw.length; i++) {
      seatDiscards[i] = _tiles(raw[i]);
    }
  }

  void _ingestMeldsMatrix(dynamic raw) {
    if (raw is! List) return;
    _ensureSeats(raw.length);
    for (var i = 0; i < raw.length; i++) {
      final row = raw[i];
      seatMelds[i] = row is List ? List<dynamic>.from(row) : <dynamic>[];
    }
  }
  void register(String username, String password, {String nickname = ''}) {
    send('register', {
      'username': username.trim(),
      'password': password,
      'nickname': nickname.trim().isEmpty ? username.trim() : nickname.trim(),
    });
    status = '注册中...';
    notifyListeners();
  }

  void login(String username, String password) {
    send('login', {
      'username': username.trim(),
      'password': password,
    });
    status = '登录中...';
    notifyListeners();
  }

  void enterAsGuest([String? name]) {
    final n = (name ?? playerName).trim();
    playerName = n.isEmpty ? '游客' : n;
    guestMode = true;
    loggedIn = false;
    userId = 0;
    username = '';
    send('set_name', {'name': playerName});
    status = '游客：$playerName';
    listRooms();
    notifyListeners();
  }

  void listRooms() => send('list_rooms');
  void createRoom(String rule) => send('create_room', {'rule': rule});
  void joinRoom(String id) => send('join_room', {'room_id': id.toUpperCase()});

  void leaveRoom() {
    send('leave_room');
    room = null;
    inGame = false;
    // 离开房间仍保留 sessionId，ID 不变
    notifyListeners();
  }

  void startGame() => send('start_game');

  void discard(Tile t) {
    send('discard', {'tile': t.toJson()});
    status = '出牌 ${t.label}';
    notifyListeners();
  }

  void chooseDingQue(int suit) {
    if (!inDingQue) return;
    send('dingque', {'suit': suit});
    status = '提交定缺...';
    notifyListeners();
  }

  void toggleSelectAt(int index) {
    if (!inExchange) return;
    if (index < 0 || index >= hand.length) return;
    if (selectedIndices.contains(index)) {
      selectedIndices.remove(index);
    } else {
      if (selectedIndices.length >= 3) return;
      final t = hand[index];
      if (selectedIndices.isNotEmpty &&
          hand[selectedIndices.first].suit != t.suit) {
        status = '换三张必须同花色';
        notifyListeners();
        return;
      }
      selectedIndices.add(index);
    }
    notifyListeners();
  }

  void confirmExchange() {
    if (selectedIndices.length != 3) return;
    for (final i in selectedIndices) {
      if (i < 0 || i >= hand.length) return;
    }
    send('exchange', {
      'tiles': selectedIndices.map((i) => hand[i].toJson()).toList(),
    });
    status = '提交换牌...';
    notifyListeners();
  }

  void anKong(Tile t) {
    send('kong', {'kind': 'an', 'tile': t.toJson()});
    showActions = false;
    canAnOrJia = false;
    anKongOptions = [];
    jiaKongOptions = [];
    notifyListeners();
  }

  void jiaKong(Tile t) {
    send('kong', {'kind': 'jia', 'tile': t.toJson()});
    showActions = false;
    canAnOrJia = false;
    anKongOptions = [];
    jiaKongOptions = [];
    notifyListeners();
  }

  void mingKong() {
    send('action', {'action': 'kong'});
    showActions = false;
    canMingKong = false;
    notifyListeners();
  }

  /// 自己回合的「过」：只关 UI，不必通知服务器
  void dismissActions() {
    showActions = false;
    canAnOrJia = false;
    canMingKong = false;
    anKongOptions = [];
    jiaKongOptions = [];
    canPung = false;
    canWin = false;
    robKong = false;
    notifyListeners();
  }

  void action(String a) {
    if (a == 'win' && actionSelf) {
      send('self_win');
    } else if (a == 'win' && robKong) {
      send('rob_kong', {'action': 'win'});
    } else {
      send('action', {'action': a});
    }
    showActions = false;
    canAnOrJia = false;
    canMingKong = false;
    anKongOptions = [];
    jiaKongOptions = [];
    canPung = false;
    canWin = false;
    robKong = false;
    notifyListeners();
  }

  /// 别人打出牌后的过
  void passAction() {
    if (actionSelf) {
      dismissActions();
      return;
    }
    action('pass');
  }

  bool isIndexSelected(int index) => selectedIndices.contains(index);
  int get selectedCount => selectedIndices.length;

  bool isHighlightedAt(int index) {
    if (index < 0 || index >= hand.length) return false;
    final id = hand[index].id;
    var need = highlightIds[id] ?? 0;
    if (need <= 0) return false;
    var seen = 0;
    for (var i = 0; i <= index; i++) {
      if (hand[i].id == id) {
        if (i == index) return seen < need;
        seen++;
      }
    }
    return false;
  }
}
