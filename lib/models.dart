import 'dart:convert';

class Tile {
  final int suit; // 0万 1筒 2条 3风 4箭
  final int num;

  const Tile({required this.suit, required this.num});

  factory Tile.fromJson(Map<String, dynamic> j) {
    return Tile(
      suit: asInt(j['suit']),
      num: asInt(j['num']),
    );
  }

  Map<String, dynamic> toJson() => {'suit': suit, 'num': num};

  int get id => suit * 10 + num;

  String get label {
    if (suit == 3) {
      const names = ['东', '南', '西', '北'];
      return names[(num - 1).clamp(0, 3)];
    }
    if (suit == 4) {
      const names = ['中', '发', '白'];
      return names[(num - 1).clamp(0, 2)];
    }
    const suits = ['万', '筒', '条'];
    return '$num${suits[suit.clamp(0, 2)]}';
  }

  /// Mahjong Unicode (U+1F000 block). Example: 🀀 East, 🀇 1-wan, 🀫 back.
  ///
  /// Mapping:
  ///   feng 1-4  -> 1F000..1F003  东南西北
  ///   jian 1-3  -> 1F004..1F006  中发白
  ///   wan  1-9  -> 1F007..1F00F
  ///   tiao 1-9  -> 1F010..1F018
  ///   tong 1-9  -> 1F019..1F021
  String get unicode {
    int code;
    switch (suit) {
      case 3: // feng
        code = 0x1F000 + (num - 1).clamp(0, 3);
        break;
      case 4: // jian
        code = 0x1F004 + (num - 1).clamp(0, 2);
        break;
      case 0: // wan / characters
        code = 0x1F007 + (num - 1).clamp(0, 8);
        break;
      case 2: // tiao / bamboos
        code = 0x1F010 + (num - 1).clamp(0, 8);
        break;
      case 1: // tong / circles
        code = 0x1F019 + (num - 1).clamp(0, 8);
        break;
      default:
        code = 0x1F02B;
    }
    return String.fromCharCode(code);
  }

  /// Tile back 🀫
  static const String unicodeBack = '\u{1F02B}';

  static int asInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.round();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  @override
  bool operator ==(Object other) =>
      other is Tile && other.suit == suit && other.num == num;

  @override
  int get hashCode => id;
}

class RoomInfo {
  final String id;
  final String rule;
  final int count;
  final bool inGame;

  RoomInfo({
    required this.id,
    required this.rule,
    required this.count,
    required this.inGame,
  });

  factory RoomInfo.fromJson(Map<String, dynamic> j) => RoomInfo(
        id: '${j['id'] ?? ''}',
        rule: '${j['rule'] ?? ''}',
        count: Tile.asInt(j['count']),
        inGame: j['in_game'] == true,
      );
}

class RoomState {
  final String id;
  final String rule;
  final String owner;
  final bool inGame;
  final List<Map<String, String>> players;

  RoomState({
    required this.id,
    required this.rule,
    required this.owner,
    required this.inGame,
    required this.players,
  });

  factory RoomState.fromJson(Map<String, dynamic> j) {
    final raw = j['players'];
    final players = <Map<String, String>>[];
    if (raw is List) {
      for (final p in raw) {
        if (p is Map) {
          players.add({
            'id': '${p['id'] ?? ''}',
            'name': '${p['name'] ?? ''}',
          });
        }
      }
    }
    return RoomState(
      id: '${j['id'] ?? ''}',
      rule: '${j['rule'] ?? ''}',
      owner: '${j['owner'] ?? ''}',
      inGame: j['in_game'] == true,
      players: players,
    );
  }
}

/// 通用服务端消息
class ServerMsg {
  final String type;
  final dynamic data;

  ServerMsg({required this.type, required this.data});

  factory ServerMsg.fromRaw(String raw) {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return ServerMsg(type: '${map['type'] ?? ''}', data: map['data']);
  }
}

