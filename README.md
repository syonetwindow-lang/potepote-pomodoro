# ぽてぽてのポモドーロ

かわいいキャラと足跡プログレスバーで集中・休憩のリズムを整える、macOS向けのシンプルなポモドーロタイマー。

## 特徴

- 作業 50 分 / 休憩 10 分（5分刻みで調整可能）
- キャラの呼吸アニメと、3〜5秒間隔のランダムな瞬き
- 足跡が伸びていく進捗バー
- 残り5秒で「ぽてぽて」とカウントダウン
- ターン1/2でメガネ姿と通常姿が切り替わる
- ウィンドウは右上にフロート表示

## 動作環境

- macOS 12.0 以降
- Xcode コマンドラインツール（`swiftc` 利用のため）

## ビルド

```sh
./build.sh
```

`build/ぽてぽてポモドーロ.app` が生成されます。

```sh
open "build/ぽてぽてポモドーロ.app"
```

## ボタン

- **はじめ**（みどり）: タイマー開始
- **つづける**（オレンジ／みどり）: 一時停止／再開
- **もどる**（赤）: 初期状態へ戻す
- **じかん**（紫）: 作業・休憩の長さを設定

## 構成

```
.
├── Sources/
│   └── pomodoro.swift     # アプリ本体（Cocoa）
├── Resources/
│   ├── AppIcon.icns
│   ├── work_normal.png
│   ├── work_glasses.png
│   └── break_relax.png
├── Info.plist
├── build.sh
└── README.md
```

## カスタマイズ

`Sources/pomodoro.swift` 冒頭の `EYE_WORK_NORMAL` `EYE_WORK_GLASSES` `EYE_BREAK` 定数で、瞬きまぶたの位置・サイズ・色を画像に合わせて調整できます。座標は左上原点で 0〜1 に正規化。

## クレジット

- イラスト（`Resources/work_normal.png` `work_glasses.png` `break_relax.png` `AppIcon.icns`）: tuyosi（友人）提供・許諾済み
- コード: syonetwindow-lang

## ライセンス

ソースコード: [MIT](LICENSE)

イラストは MIT の対象外です。再配布・改変を行う場合は作者（友人）に個別の許諾を取得してください。
