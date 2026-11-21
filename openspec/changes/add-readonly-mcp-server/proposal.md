# Proposal

## Why

Salesforce には機密情報を含むレコードがあり、Claude Desktop・ChatGPT・Slackbot などの MCP クライアントで取り出した内容が、意図せず社外や関係者以外に共有されるおそれがある。標準の sobject-reads サーバーは結果を返すだけで、利用者に取り扱いの注意を促す手段がない。そこで、必要な読み取り機能だけを Apex で持つカスタム MCP サーバーを用意し、すべての応答で注意喚起を表示して、共有時の確認と自己責任を利用者に明示する。

## What Changes

- 読み取り専用のカスタム MCP サーバー（McpServerDefinition）を新しく作る。既存の `HandsonPipelineServer` には手を入れない。
- Apex の `@InvocableMethod` で、sobject-reads の次の 3 つのツールを再現し、MCP サーバーに登録する。ツール名・入力・出力の意味は sobject-reads から変えない。
  - `soqlQuery`: SOQL でレコードを検索する
  - `find`: SOSL で複数オブジェクトを横断検索する
  - `listRecentSobjectRecords`: 最近使ったレコード（RecentlyViewed）を取得する
- sobject-reads と違うのは、下記の要件による追加と、Apex やプラットフォームの制約で合わせられない点だけにする。
- 3 つのツールはすべて実行ユーザーの権限で動かす（`USER_MODE`。共有設定・項目レベルセキュリティ・オブジェクト権限を適用する）。
- SOQL と SOSL は読み取り以外を拒否し、副作用のある句とバインド変数を受け付けない。結果は最大 200 件で打ち切る。
- 3 つのツールのすべての応答（0 件・エラーを含む）に、条件分岐なしで注意喚起を含める。
  - MCP Apps に対応したクライアントでは、HXL ウィジェットで注意喚起を表示する。
  - ウィジェットを表示できないクライアントへの伝達は考慮しない。ツールの説明は sobject-reads と同じにし、モデルにテキストで伝えるよう指示しない（ウィジェットとの二重表示を避ける）。
- 注意喚起の文言はカスタム表示ラベルに置き、コードを変えずに差し替えられるようにする。
- 書き込み・更新・削除の機能は一切持たない。

## Capabilities

### New Capabilities

- `mcp-record-read-tools`: カスタム MCP サーバーが提供する読み取り専用ツール（sobject-reads と同じ `soqlQuery`・`find`・`listRecentSobjectRecords`）の入出力、実行ユーザー権限の適用、クエリの検証と件数上限。
- `mcp-data-handling-notice`: MCP ツールの応答に付ける、機密情報の取り扱いに関する注意喚起。ウィジェットで表示すること、モデルに伝達を指示しないこと、差し替え可能な文言管理を含む。

### Modified Capabilities

なし。

## Impact

- **追加する Apex**: 3 つの Invocable アクション、共通の応答クラス、注意喚起の組み立て、クエリ検証のクラスと、それぞれのテストクラス（`force-app/main/default/classes/`）。
- **追加するメタデータ**: カスタム表示ラベル、ツールごとの Custom Lightning Type（2 つずつ）、注意喚起の HXL ウィジェット、新しい McpServerDefinition。
- **組織の設定**: Setup で MCP サーバーを作ってツールを追加し、retrieve したうえで `<resources>` と `<uiResource>` を編集してデプロイする。MCP クライアント（Claude Desktop など）から新しいサーバーへの接続設定が必要になる。
- **利用上の影響**: ツール呼び出しは組織の API 呼び出し数を消費する。結果は実行ユーザーが見られる範囲に限られるため、管理者など広い権限を持つユーザーが使うと広い範囲が返る。
- **対象外**: 作成・更新・削除のツール、条件によって注意喚起を出し分ける仕組み、Agentforce アクション用のウィジェット、ウィジェットを表示できないクライアント（MCP Apps 非対応のクライアント、Slackbot など）への注意喚起の伝達。
