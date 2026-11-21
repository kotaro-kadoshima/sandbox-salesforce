# Tasks

Apex は `platform-apex-generate`、テストは `platform-apex-test-generate` と `platform-apex-test-run`、デプロイと retrieve は `platform-metadata-deploy` と `platform-metadata-retrieve`、静的解析は `dx-code-analyzer-run` を使う。コメントは既存のクラスに合わせて日本語で書く。ツールと入力の説明文は [docs/references/sobject-reads.md](../../../docs/references/sobject-reads.md) から写す。

## 1. 注意喚起の文言と共通の応答

- [x] 1.1 組織の既定の言語（`Organization.LanguageLocaleKey`）を `sf data query` で確認し、カスタム表示ラベルの `language` に使う値を決める。確認した値をこのタスクに書き残したら完了
  - 結果（2026-11-21）: `LanguageLocaleKey` は `en_US`。ラベルの `language` は `en_US` にし、値は日本語の文言をそのまま入れる。参考: OWD は Account・Opportunity が `Edit`、Contact が `ControlledByParent`、Lead・Case が `ReadEditTransfer` で、非公開の標準オブジェクトはない（10.4 で使う）
- [x] 1.2 `force-app/main/default/labels/CustomLabels.labels-meta.xml` に、design D4 の 4 つのラベル（`DataNotice_Title`・`DataNotice_Confidential`・`DataNotice_ShareCheck`・`DataNotice_Responsibility`、カテゴリ `McpDataNotice`）を作る。4 つのラベルがあり、`sf project deploy validate` で構文エラーが出なければ完了
- [x] 1.3 共通の応答クラス `ReadToolResult`（design D3 の 9 項目、`global`、`@InvocableVariable`）と、ラベルから注意喚起を入れる `DataHandlingNotice` を作る。`ReadToolResult` はコンストラクタで必ず注意喚起を入れる。テストで、生成直後の応答に 4 項目がラベルと同じ値で入っていることを確かめ、テストが通れば完了

## 2. クエリのチェック

- [x] 2.1 `ReadQueryGuard` の SOQL のチェックを design D8 のとおり作る（同じ長さのマスク済みの文字列 2 つ、拒否する条件、`SELECT COUNT()` の判定、LIMIT の置き換えと追加）。`ReadQueryGuardTest` で、spec の「SOQL は読み取りクエリ以外を拒否する」の全シナリオと、LIMIT の書き換え（LIMIT なし、200 以下、200 超、OFFSET だけ、サブクエリだけ）、リテラル内の括弧や引用符、入れ子のサブクエリを確かめ、テストが通れば完了
- [x] 2.2 `ReadQueryGuard` の SOSL のチェックを design D9 のとおり作る（検索語の `{...}` もマスクする、拒否する条件、外側の LIMIT の置き換えと追加）。`ReadQueryGuardTest` で、spec の「SOSL は読み取りクエリ以外を拒否する」の全シナリオと、RETURNING 句のオブジェクトごとの LIMIT を外側の LIMIT とみなさないことを確かめ、テストが通れば完了
- [x] 2.3 Code Analyzer をセキュリティのルールで `ReadQueryGuard` に実行し、指摘が 0 件なら完了。指摘が出たら、抑止で消さずに内容をユーザーに報告して対応を相談する（design の Risks）

## 3. soqlQuery ツール

- [x] 3.1 `SoqlQueryAction`（`global with sharing`、`@InvocableMethod`、入力は `query` だけ）を作る。説明文は sobject-reads の `soqlQuery` から写す。`ReadQueryGuard` でチェックし、`Database.queryWithBinds`（`SELECT COUNT()` は `Database.countQueryWithBinds`）を空の Map と `AccessLevel.USER_MODE` で呼ぶ。入力は 10 件まで処理し、例外はすべて失敗の応答にする（design D11）。テストで、成功・0 件・拒否・存在しない項目のエラー・バインド変数のエラー・`SELECT COUNT()` の件数・11 件目以降の入力と、取引先 250 件で LIMIT なしと `LIMIT 500` が 200 件に打ち切られることを確かめる。すべての応答に注意喚起があり、テストが通れば完了。集計関数だけのクエリに LIMIT を足すとエラーになるとわかった場合は、design の Risks のとおり直す
  - 結果（2026-11-21）: GROUP BY のない集計に LIMIT を足すと、捕捉できない `System.UnexpectedException` になった。LIMIT を足さず、利用者が付けた LIMIT は実行前に拒否するよう `ReadQueryGuard` を直し、design D8・Risks に反映した
- [x] 3.2 `SoqlQueryAction` の権限テストを `System.runAs` で書く。テスト内で作る権限セットで「取引先の参照権限はあるが `Account.Priority__c` の参照権限はない」ユーザーと、「取引先の参照権限がない」ユーザーを用意し、どちらも失敗の応答（注意喚起付き）になることを確かめる。テスト用ユーザーのプロファイルは、言語で変わる名前ではない条件で取得する。テストが通れば完了
  - 結果（2026-11-21）: この組織では `Account.Priority__c` の参照権限がすべてのプロファイルに付いており、権限セット（足し算しかできない）では外せなかった。代わりに、選んだプロファイルが参照できず管理者は参照できる取引先の項目を、テストの中で動的に選んで確かめる（`TestDataFactory.findAccountFieldHiddenFrom`）。プロファイル名は日本語と英語が混在していたため、ライセンス（`SFDC`）と権限の条件で選んでいる
- [x] 3.3 Code Analyzer をセキュリティのルールで `SoqlQueryAction` に実行し、指摘が 0 件なら完了（出たら 2.3 と同じ扱い）

## 4. find ツール

- [x] 4.1 `FindAction`（`global with sharing`、`@InvocableMethod`、入力は `search` だけ）を作る。説明文は sobject-reads の `find` から写す。`ReadQueryGuard` でチェックし、`Search.query` を `AccessLevel.USER_MODE` で実行して、design D3 のオブジェクトごとのグループで返す。合計 201 件なら 200 件に打ち切る。入力は 10 件まで処理する。テストは `Test.setFixedSearchResults` を使い、グループの形・0 件・拒否・`FIND {...}` の形のクエリの実行と、すべての応答に注意喚起があることを確かめ、テストが通れば完了。`Search.query` が `FIND {...}` の形を受け付けないとわかった場合は、design D9 のとおり `'...'` の形への変換を足し、その結果をこのタスクに書き残す
  - 結果（2026-11-21）: `Search.query` は `FIND {...}` の形をそのまま実行できたので、変換は足していない。入力名 `search` も `@InvocableVariable` の名前として使えた
- [x] 4.2 Code Analyzer をセキュリティのルールで `FindAction` に実行し、指摘が 0 件なら完了（出たら 2.3 と同じ扱い）

## 5. listRecentSobjectRecords ツール

- [ ] 5.1 `ListRecentSobjectRecordsAction`（`global with sharing`、`@InvocableMethod`、入力は必須の `sobjectName` だけ）を design D10 のとおり作る。説明文は sobject-reads の `listRecentSobjectRecords` から写す。テストでは作ったレコードを `FOR VIEW` 付きで参照して履歴を作り、指定した種類だけが新しい順で返ること・`sobjectName` がないときの失敗・存在しないオブジェクトの拒否・アクセス権のないレコードの除外と、すべての応答に注意喚起があることを確かめ、テストが通れば完了。テストで履歴が作れない、または `WITH USER_MODE` が使えないとわかった場合は、その結果をこのタスクに書き残し、design の Risks の代替案で進めてよいかユーザーに確認する
  - 途中経過（2026-11-21）: 実装とテスト 7 件は完了（カバレッジ 100%）。`FOR VIEW` で履歴を作れ、`RecentlyViewed`・`UserRecordAccess` の `WITH USER_MODE` も使えた。ただし「アクセス権のないレコードの除外」は、組織の OWD がすべて公開で、閲覧後に参照できなくなる状況を作れず、テストで確かめられていない（確認方法をユーザーと相談中）
- [x] 5.2 Code Analyzer をセキュリティのルールで `ListRecentSobjectRecordsAction` に実行し、指摘が 0 件なら完了（出たら 2.3 と同じ扱い）

## 6. ラベルと Apex のデプロイ

- [x] 6.1 ラベルと 1〜5 の Apex（テストクラスを含む）を組織にデプロイし、追加したテストクラスを組織で実行する。デプロイが成功し、すべてのテストが通り、追加したクラスのカバレッジが 75% 以上なら完了
- [x] 6.2 3 つのアクションを Actions REST API で describe する（`sf api request rest /services/data/v68.0/actions/custom/apex/<クラス名>`）。`inputs` が `query`・`search`・`sobjectName` のそれぞれ 1 つだけ（必須の文字列）で、`outputs` が design D3 の 9 項目、すべてプリミティブ型（リストやネストがない）なら完了

## 7. MCP サーバーの作成と retrieve

- [x] 7.1 Setup で MCP サーバー `ReadOnlyRecordsServer`（表示ラベル「Read Only Records Server」）を作り、`SoqlQueryAction`・`FindAction`・`ListRecentSobjectRecordsAction` をツールとして追加する（ユーザーが画面で操作する。ツール名を設定できる画面なら `soqlQuery`・`find`・`listRecentSobjectRecords` にする）。Setup のサーバー詳細に 3 つのツールが表示されれば完了
  - 結果（2026-11-21）: ユーザーの許可を得て画面を操作した。手順は [docs/procedures/readonly-mcp-server-setup.md](../../../docs/procedures/readonly-mcp-server-setup.md)。ツールの編集画面でツール表示ラベル・ツール名・アノテーション（参照のみ・冪等）を設定できたので、9.2 のうち `<toolName>`・`<toolTitle>`・注釈はここで設定した。Setup が生成したツール名は 64 文字で切れていた（`ListRecentSobjectRecordsActionapex_ListRecentSobjectRecordsActi`）。サーバーは無効のまま
- [x] 7.2 McpServerDefinition `ReadOnlyRecordsServer` を retrieve する。`force-app/main/default/mcpServerDefinitions/ReadOnlyRecordsServer.mcpServerDefinition-meta.xml` ができ、3 つの `<tools>` に Setup が生成した `apiIdentifier`・`operation`・`toolName` が入っていることを確認したら完了
  - 結果（2026-11-21）: `apiIdentifier` は `aa:apex-<クラス名>`、`operation` はクラス名、`toolName`・`toolTitle` は 7.1 で設定した `soqlQuery`・`find`・`listRecentSobjectRecords`。注釈は `readOnly`・`idempotent` が `true`、それ以外は `false`

## 8. CLT とウィジェット

- [x] 8.1 `platform-mcp-tool-widget-coordinate` を `SoqlQueryAction`（action ソース）で実行し、`soqlQueryResponse`・`soqlQuery`（`renderer.json` を含む）と共有ウィジェット `dataHandlingNotice` を作る。ウィジェットは design D5 のとおり、警告アイコン・見出し・3 つの文言だけを表示し、属性は注意喚起の 4 項目だけにする。スキルのチェックで `clt-reference-integrity`・`renderer-wires-widget`・`nested-list-coverage` が pass、`field-trace` は注意喚起以外の項目の OMITTED 警告だけなら完了
  - 結果（2026-11-21）: 4 つのチェックは条件どおり（`field-trace` の OMITTED は `errorMessage`・`recordCount`・`resultJson`・`succeeded`・`truncated`）。CLT の `lightning__textType` は最大 255 文字だが、スキルの対応表どおり STRING の項目はすべてこの型にした。`resultJson` などが 255 文字を超えてもウィジェットが表示されるかは 10.2 で確かめる
- [x] 8.2 同じスキルを `FindAction` で実行し、`findResponse`・`find` を作る。ウィジェットは新しく作らず、`renderer.json` から `@widget/c/dataHandlingNotice` を指す。8.1 と同じチェック結果なら完了
- [x] 8.3 同じスキルを `ListRecentSobjectRecordsAction` で実行し、`listRecentSobjectRecordsResponse`・`listRecentSobjectRecords` を作る。ウィジェットは 8.2 と同じく共有する。8.1 と同じチェック結果なら完了
- [x] 8.4 レスポンス CLT 3 つ → ウィジェット → エンベロープ CLT 3 つの順でデプロイし、すべて成功したら完了。CLT 名が使えずにデプロイが失敗した場合は、design D5 のとおり名前を変えて、変えた名前をこのタスクに書き残す
  - 結果（2026-11-21）: 3 回とも dry-run のあとにデプロイし、すべて成功した。CLT 名は design D5 の表のまま使えた

## 9. McpServerDefinition の編集とデプロイ

- [x] 9.1 retrieve した XML に、design D5 の表のとおり `<resources>` を 3 つ（`resourceName`・`resourceUri`・`resourceTitle`・`description`）足す。各 `resourceUri` が `ui://widget/lightningType/c__<エンベロープ CLT 名>` の形で、8 で作った CLT 名と一致していれば完了
- [x] 9.2 3 つの `<tools>` に、`<toolName>` と `<toolTitle>`（`soqlQuery`・`find`・`listRecentSobjectRecords`）、`<uiResource>`、注釈（`readOnly=true`・`destructive=false`・`idempotent=true`・`openWorld=false`・`returnDirect=false`）、design D6 の `descriptionOverride`（sobject-reads の説明文に、入力 1 件だけ送ることと注意喚起をそのまま伝えることを書き足したもの）を設定する。各ツールの `<uiResource>` が、対応する `<resources>` の `resourceName` と完全に一致していれば完了
- [x] 9.3 McpServerDefinition をデプロイし、Setup でサーバーを有効にする。デプロイが成功し、Setup でサーバーが有効、3 つのツールにリソースが関連付いていれば完了。`<toolName>` の書き換えでデプロイが失敗した場合は、design の Risks のとおり、ほかの方法を確かめてからユーザーに相談する
  - 結果（2026-11-21）: dry-run のあとにデプロイが成功し、Setup で有効にした（一覧で「稼働中」）。Setup の画面にはリソースの関連付けが表示されないため、組織から retrieve し直して、3 つの `<uiResource>` と `<resources>` がローカルと同じ値で保存されていることを確かめた。組織が返す XML は要素がアルファベット順（`<uiResource>` が `<toolTitle>` の後ろ）だったので、ローカルのファイルもその並びにした。手順は [docs/procedures/readonly-mcp-server-setup.md](../../../docs/procedures/readonly-mcp-server-setup.md) の 6

## 10. 受け入れ確認

- [ ] 10.1 Claude Desktop（claude.ai のカスタムコネクタ）に新しいサーバーを接続する。ツール一覧に `soqlQuery`・`find`・`listRecentSobjectRecords` の 3 つだけが読み取り専用として表示され、入力がそれぞれ `query`・`search`・`sobjectName` だけなら完了。接続に使ったエンドポイント URL と外部クライアントアプリケーションを書き残す
- [ ] 10.2 Claude Desktop で 3 つのツールをそれぞれ入力 1 件で実行し、結果あり・0 件・エラー（`soqlQuery` に `DELETE FROM Account` を渡すなど）のどれでも注意喚起のウィジェットが表示されれば完了
  - 途中経過（2026-11-21）: `listRecentSobjectRecords`（`Account`、0 件）でウィジェットが表示された。0 件は正しい結果（組織の閲覧履歴に取引先がなく、Contact と Opportunity が 8 件ずつ）。モデルはテキストでも注意喚起を伝えたが、3 つの文言のうち 2 つの順序を入れ替えていた。ツール名の横に「未認証」と表示される
- [ ] 10.3 ウィジェットを表示しないクライアント（Claude Code から claude.ai のコネクタ経由、または Slackbot）で 3 つのツールを実行し、出力テキストに見出しと 3 つの文言が含まれ、モデルが利用者に伝えていれば完了。モデルが伝えなかったクライアントがあれば書き残す
- [ ] 10.4 組織の共有設定（OWD）を確認し、非公開のオブジェクトで、権限の少ないユーザーとして接続して、共有されていないレコードと参照権限のない項目が返らないことを確かめたら完了。非公開のオブジェクトがない場合は、組織の設定を変えずにユーザーと確認方法を相談する
- [ ] 10.5 Setup でラベル `DataNotice_Title` の文言を一時的に変え、次の呼び出しでウィジェットとテキストの両方に新しい文言が出ることを確かめてから、元に戻したら完了
- [ ] 10.6 運用の前提（design D7）として、機密の項目が項目レベルセキュリティで保護されているかと、サーバーを使えるユーザーの範囲をユーザーと確認し、結果を書き残したら完了

## Workflow follow-up

- 受け入れ確認とレビューが済んだら、この change をアーカイブする。
- アーカイブ後、`openspec/specs/` に `mcp-record-read-tools` と `mcp-data-handling-notice` が作られていることを確かめる。
