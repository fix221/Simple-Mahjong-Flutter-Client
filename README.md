# Flutter 麻将客户端

对接 `../server`（Go WebSocket）。

## 运行

```bash
# 确保 PATH 里有 flutter，或用完整路径：
# & "D:\Flutter SDK\bin\flutter.bat"

cd flutter_client
flutter pub get
flutter run -d windows    # 桌面
flutter run -d chrome     # 网页
flutter run               # 手机/模拟器
```

## 功能

- 创建/加入房间（推倒胡、川麻换三张）
- 出牌、碰、胡、过、自摸
- 川麻换三张（点选 3 张同花色）

## 打包

```bash
flutter build apk
flutter build windows
flutter build web
```
