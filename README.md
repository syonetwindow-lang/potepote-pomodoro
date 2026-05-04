# ぽてぽてポモドーロ

ぽてぽてと一緒に集中できるポモドーロタイマーアプリ（macOS用）

<img src="assets/work_normal.png" width="200"> <img src="assets/break_relax.png" width="200">

## 機能

- **50分作業 / 10分休憩**（設定で変更可能）
- ターン1はメガネなし、ターン2はメガネありのぽてぽてが応援
- 終了5秒前に足音、終了時にアラームでお知らせ
- 常に最前面に表示
- セッション回数カウント

## ダウンロード

[Releases](../../releases) から最新の `.zip` をダウンロードして、解凍したアプリをダブルクリックで起動できます。

> 初回起動時に「開発元が未確認」と表示されたら、右クリック → 「開く」で起動してください。

## 自分でビルドする場合

```bash
swiftc -O -o pomodoro pomodoro.swift -framework Cocoa -framework AVFoundation
```

## ライセンス

MIT License
