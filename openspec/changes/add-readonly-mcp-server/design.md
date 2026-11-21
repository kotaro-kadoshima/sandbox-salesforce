# Design

## Context

- 動機は proposal.md の Why、振る舞いは `specs/mcp-record-read-tools` と `specs/mcp-data-handling-notice` を参照。
- 再現する sobject-reads の仕様は、公式リファレンスの写し [docs/references/sobject-reads.md](../../../docs/references/sobject-reads.md) を基準にする。
- 既存の構成（参考にする実装）
  - `GetAccountPipelineAction`（`global with sharing`、`@InvocableMethod`）を `HandsonPipelineServer` に登録し、`accountPipelineCard` の CLT とウィジェットで表示している。
  - ウィジェットは直近のコミット（d0935df）で、注意喚起だけの表示に変えてある。ただし文言はウィジェットの JSON に直接書かれている。
  - McpServerDefinition の `<tools>` は `apiDefinition`・`toolName`・`toolTitle`・`uiResource`・`descriptionOverride` と注釈（`readOnly` など）を持ち、`<resources>` は `resourceName`・`resourceUri`（`ui://widget/lightningType/c__<CLT名>`）を持つ。MCP クライアントに見えるツール名は `<toolName>` の値（既存のツールは Setup が生成した `GetAccountPipelineActionapex_GetAccountPipelineAction`）。
- 制約
  - HXL のリソース（`<resources>`・`<uiResource>`）は Setup では設定できない。Setup で作ったサーバーを retrieve して XML を編集し、デプロイする。
  - apply で使う `platform-mcp-tool-widget-coordinate` は、ツールごとに CLT を 2 つ（結果の外枠＝エンベロープと、`outputValues` の中身＝レスポンス）作る。CLT 名は Apex のクラス名から決まる（先頭を小文字にし、末尾の `Action` を除く）。応答にネストしたオブジェクトやリストの項目があると、それをウィジェットに表示することを必須のチェック（`nested-list-coverage`）として扱う。
  - ウィジェットは、入力 1 件の呼び出しだけで表示される（ベータの制約。結果の `content[]` の先頭だけを描画する）。
  - `@InvocableVariable` の名前は Apex の識別子なので、ハイフンを使えない。
  - sourceApiVersion は 68.0。Code Analyzer（`@salesforce/plugin-code-analyzer`）は導入済み。

## Goals / Non-Goals

**Goals:**

- sobject-reads の `soqlQuery`・`find`・`listRecentSobjectRecords` と、ツール名・入力・出力の意味を変えない。違いは、元の要件による追加と、Apex やプラットフォームの制約で合わせられない点だけにする（一覧は D12）。
- 注意喚起を、どのコード経路でも必ず応答に入る構造にする（設定や条件で外れる余地を作らない）。
- 権限の判定は Salesforce の権限モデル（USER_MODE）にまかせ、Apex 側に第 2 の権限ルールを持たない。
- ウィジェットとテキストが同じ文言の出どころを使う。

**Non-Goals:**

- sobject-reads の `getObjectSchema`・`getUserInfo`・`getRelatedRecords` の再現。
- 項目値のマスクや、オブジェクト・項目の除外リスト。
- MCP クライアント側の設定（接続アプリのポリシーなど）の自動化。

## Decisions

### D1. 新しい MCP サーバーを作り、ツール名を sobject-reads に合わせる

- McpServerDefinition `ReadOnlyRecordsServer`（表示ラベル「Read Only Records Server」）を新しく作る。既存の `HandsonPipelineServer` は変えない。
- 手順は「Setup でサーバーを作ってツールを追加 → retrieve → XML を編集 → デプロイ」。`apiIdentifier` と `operation` は Setup が生成した値をそのまま使う。
- 編集で `<toolName>` と `<toolTitle>` を `soqlQuery`・`find`・`listRecentSobjectRecords` に書き換える。Setup が生成する名前はクラス名をもとにした長い名前になり、sobject-reads と一致しないため。
- 3 つのツールの注釈は `readOnly=true`・`destructive=false`・`idempotent=true`・`openWorld=false`・`returnDirect=false` とする。
- 代替案: XML を一から書いてデプロイする。`apiIdentifier` などの生成規則を推測することになるため採らない。

### D2. Apex のクラス構成

| クラス | 役割 |
|---|---|
| `SoqlQueryAction` | `soqlQuery` ツール（`@InvocableMethod`） |
| `FindAction` | `find` ツール（`@InvocableMethod`） |
| `ListRecentSobjectRecordsAction` | `listRecentSobjectRecords` ツール（`@InvocableMethod`） |
| `ReadToolResult` | 3 つのツールで共通の応答クラス（`@InvocableVariable`） |
| `DataHandlingNotice` | カスタム表示ラベルから注意喚起を応答に入れる |
| `ReadQueryGuard` | SOQL と SOSL の読み取り専用チェックと件数上限の適用 |

- クラス名は、coordinate スキルが決める CLT 名が sobject-reads のツール名（`soqlQuery`・`find`・`listRecentSobjectRecords`）になるように付ける。
- 既存の実装にならい、MCP に公開するクラスとメソッドは `global with sharing` にする。各クラスにテストクラスを作る。
- `@InvocableMethod` の `description` と `@InvocableVariable` の `description` には、sobject-reads のツールと入力の説明文をそのまま使う。
- 応答クラスを 3 つのツールで共通にする。各アクションの内部クラスにすると、注意喚起の項目が 3 か所に重複してずれるおそれがあるため。
- `ReadToolResult` は、生成時（コンストラクタ）に必ず `DataHandlingNotice` で注意喚起を入れる。成功・0 件・拒否・例外・入力件数の超過のどの経路でも同じコンストラクタを通るので、注意喚起を入れる処理に分岐がない。

### D3. 応答の項目と、結果を JSON 文字列で返す理由

| 項目 | 型 | 内容 |
|---|---|---|
| `noticeTitle` | String | 注意喚起の見出し |
| `noticeConfidential` | String | 機密情報が含まれる可能性 |
| `noticeShareCheck` | String | 共有・転記前の確認 |
| `noticeResponsibility` | String | 利用者本人の責任 |
| `succeeded` | Boolean | 成功したか |
| `errorMessage` | String | 失敗の理由（成功時は空） |
| `recordCount` | Integer | 返したレコード数。`SELECT COUNT()` では一致した件数 |
| `truncated` | Boolean | 件数上限で打ち切ったか |
| `resultJson` | String | 結果の JSON 文字列（形はツールごとに下表） |

| ツール | `resultJson` の形（sobject-reads の出力に合わせる） |
|---|---|
| `soqlQuery` | レコードの配列（`JSON.serialize` の結果。SELECT 句の項目と `attributes`）。`SELECT COUNT()` では空の配列 |
| `find` | オブジェクトごとのグループの配列 `[{"sobjectType": "Account", "records": [...]}]`。レコードのないグループは含めない |
| `listRecentSobjectRecords` | レコードの配列（`Id`・`Name`・`Type`・`LastViewedDate`）。最終表示日時の新しい順 |

- 結果を型付きのリストではなく JSON 文字列にする。
  - SOQL と SOSL の結果は項目がクエリごとに変わり、CLT に静的な型を付けられない。
  - リストやネストした項目があると、coordinate スキルの `nested-list-coverage` チェックがウィジェットでの表示を求め、注意喚起だけのウィジェット（D5）と両立しない。項目をすべてプリミティブにすれば、ウィジェットに出さない項目は `field-trace` の警告（参考扱い）で済む。
  - MCP クライアントのモデルは JSON 文字列をそのまま読める。
- 代替案: `List<SObject>` を出力にする（型が決まらない）、最近使ったレコードだけ型付きの内部クラスのリストにする（3 つのツールで形がそろわず、上記のチェックにかかる）。どちらも採らない。

### D4. 注意喚起の文言はカスタム表示ラベルで管理する

| ラベル名 | 初期の文言 |
|---|---|
| `DataNotice_Title` | 機密情報の取り扱いに注意してください |
| `DataNotice_Confidential` | Salesforce のデータには、機密情報が含まれている可能性があります。 |
| `DataNotice_ShareCheck` | 内容を共有・転記するときは、共有先と内容を必ず確認してください。 |
| `DataNotice_Responsibility` | 情報の取り扱いの責任は、利用者ご本人にあります。 |

- カテゴリは `McpDataNotice`。Apex から `System.Label.DataNotice_*` で参照する。
- 理由
  - Apex から参照しているラベルは削除できないため、「文言がない」状態が起きない。文言のフォールバックをコードに書く必要がない。
  - Setup の画面で文言を変えられ、次の呼び出しから反映される。
  - 翻訳ワークベンチで翻訳を足せば、ユーザーの言語で返る（今回は日本語のみ）。
  - SOQL を使わないので、ガバナ制限を消費しない。
- 代替案
  - カスタムメタデータ: 見出し・本文などを構造で持てるが、レコードの削除や空欄で文言が消えうるため、結局コードにフォールバック文言が要る。条件で出し分けない今回の要件には過剰。
  - ウィジェットの JSON に直接書く（現在の `accountPipelineCard` の方式）: 要件に反し、テキスト側と文言がずれる。

### D5. ウィジェットは注意喚起だけを表示し、3 つのツールで共有する

- 表示するのは警告アイコン・見出し・3 つの文言だけ。結果の一覧は表示しない（design で確認したいこと 2 への回答）。
  - SOQL と SOSL の結果は形が決まらず、汎用的な一覧を HXL で組めない。
  - 結果をウィジェットに出すと、画面のスクリーンショットなどで内容が広がる経路が増える。結果はモデルの回答テキストで示せば足りる。
  - 既存の `accountPipelineCard` も注意喚起だけに変えた経緯がある。
- 構成要素は既存ウィジェットと同じ `tile/widget`・`tile/row`・`tile/icon`・`tile/text` を使う。ウィジェットの属性は `noticeTitle`・`noticeConfidential`・`noticeShareCheck`・`noticeResponsibility` の 4 つ。
- CLT はスキルの規約どおりツールごとに 2 つ作り、ウィジェットは 1 つを共有する。

| ツール（toolApiName） | エンベロープ CLT | レスポンス CLT | リソース名 / URI |
|---|---|---|---|
| `soqlQuery` | `soqlQuery` | `soqlQueryResponse` | `soqlQuery` / `ui://widget/lightningType/c__soqlQuery` |
| `find` | `find` | `findResponse` | `find` / `ui://widget/lightningType/c__find` |
| `listRecentSobjectRecords` | `listRecentSobjectRecords` | `listRecentSobjectRecordsResponse` | `listRecentSobjectRecords` / `ui://widget/lightningType/c__listRecentSobjectRecords` |

- 共有ウィジェットの名前は `dataHandlingNotice`。各エンベロープ CLT の `renderer.json` が `@widget/c/dataHandlingNotice` を指し、`{!$attrs.outputValues.noticeTitle}` などで 4 つの属性を渡す。
- CLT 名とリソース名は MCP クライアントのツール名には出ない。デプロイで名前が使えないとわかった場合は、この表の名前を変えてよい。
- 代替案
  - ツールごとにウィジェットを作る（スキルの命名規約どおり）: 同じレイアウトが 3 つになり、見た目の変更が 3 か所になる。
  - エンベロープとレスポンスの CLT も 1 組にして 3 つのツールで共有する: ファイルは最少だが、スキルの「エンベロープはツールごと」という前提から外れ、動作の確認がとれていない。

### D6. テキストでも注意喚起を届ける

- 注意喚起の 4 項目は `outputValues` に入るので、ツールの出力テキスト（結果の JSON）にそのまま含まれる。ウィジェット用の文言と出どころが同じになる。
- 各ツールの `descriptionOverride` は、sobject-reads の説明文（[docs/references/sobject-reads.md](../../../docs/references/sobject-reads.md)）をそのまま使い、末尾に次の 2 点を英語で書き足す。
  - 入力は 1 件だけ送ること（ウィジェットが表示されるのは入力 1 件のときだけのため）。
  - 応答の注意喚起を、0 件や失敗のときも含めて、データより先にそのまま利用者に伝えること。

### D7. 権限は USER_MODE にまかせ、Apex 側でマスクや除外はしない

design で確認したいこと 1 への回答。

- SOQL は `Database.queryWithBinds`（`SELECT COUNT()` は `Database.countQueryWithBinds`）を空の Map と `AccessLevel.USER_MODE` で、SOSL は `Search.query(sosl, AccessLevel.USER_MODE)` で、固定のクエリは `WITH USER_MODE` で実行する。共有設定・項目レベルセキュリティ・オブジェクト権限が適用され、参照できない項目やオブジェクトを指定すると例外になる（黙って取り除かないので、モデルにも理由が伝わる）。
- SOQL と SOSL の結果について、Apex 側でのマスクや除外はしない。
  - 権限の判定を Salesforce の設定 1 か所にまとめる。Apex に除外リストを持つと、組織の設定とずれたり、守られているという誤解を生んだりする。
  - 画面で見られる範囲と MCP で見られる範囲を一致させる。
- 例外として、最近使ったレコードは取得後に `UserRecordAccess`（`HasReadAccess`）で確認し直す（D10）。RecentlyViewed は閲覧履歴の一覧で、取得時点のレコードへのアクセス権が反映される保証を文書で確認できていないため。
- 運用で確認すること（実装の範囲外）
  - 「すべてのデータの参照」「すべて表示」などの権限を持つユーザーには広い範囲が返る。MCP サーバーを使えるユーザーは、外部クライアントアプリケーションのポリシーや権限セットで絞る。
  - ページレイアウトで隠しているだけの項目は、項目レベルセキュリティで制御されていないので返る。機密の項目は項目レベルセキュリティで保護されているか確認する。
- 代替案: `Security.stripInaccessible` で項目を取り除く。共有設定には効かず、取り除いたことがモデルに伝わらないため、主な手段にはしない。

### D8. SOQL のチェックは「副作用と件数」に絞り、クエリはそのまま受け付ける

- 入力: `query`（必須、SOQL 文 1 つ）。sobject-reads の `soqlQuery` と同じ。
- `ReadQueryGuard` は、元のクエリと同じ長さの「マスク済みの文字列」を 2 つ作って判定する。位置がずれないので、判定で見つけた位置を元のクエリにそのまま使える。
  - リテラルのマスク: 文字列リテラル（`'...'`、`\'` のエスケープを含む）の中身を埋め文字に置き換える。リテラル内の語句で誤って拒否しないため。
  - 括弧のマスク: さらに括弧の中（サブクエリ・関数）を埋め文字に置き換える。外側の LIMIT と OFFSET を見つけるため。
- 拒否する条件（リテラルのマスク済みの文字列で判定）
  1. 空、または `SELECT` で始まらない。
  2. `;` を含む。
  3. `FOR VIEW`・`FOR REFERENCE`・`UPDATE TRACKING`・`UPDATE VIEWSTAT` を含む（閲覧日時や閲覧数を更新する副作用があり、読み取り専用の要件に反する）。
  4. `FOR UPDATE`・`ALL ROWS` を含む（Apex 専用の構文で、sobject-reads の土台の REST の query でも使えない）。
  5. `WITH SYSTEM_MODE` を含む（実行ユーザーの権限で動かす要件に反する）。`WITH USER_MODE` と `WITH SECURITY_ENFORCED` は拒否せず、Salesforce の判定にまかせる。
  6. コロンの直後（空白を挟んでもよい）に英字か `_` が続く（バインド変数）。日付リテラルは `LAST_N_DAYS:30` のようにコロンの直後が数字なので対象にならない。念のため、実行も空の Map の `queryWithBinds` で行い、Apex のローカル変数が参照されないようにする。
- 件数上限（括弧のマスク済みの文字列で外側の LIMIT と OFFSET を探す）
  - `SELECT COUNT() FROM ...` の形なら、そのまま `countQueryWithBinds` で件数を数える。
  - 外側の `LIMIT n` が 200 以下なら、そのまま実行する。
  - 外側の `LIMIT n` が 200 を超えるなら、数値を 201 に置き換える。
  - 外側に LIMIT がなく OFFSET があれば、OFFSET の直前に `LIMIT 201` を入れる。LIMIT も OFFSET もなければ末尾に ` LIMIT 201` を足す（`FOR` や `UPDATE` の句は拒否済みなので、末尾が LIMIT の正しい位置になる）。
  - 201 件目があれば、200 件だけ返して `truncated=true` にする。
- 書き換えるのは LIMIT の整数だけで、それ以外の文字列を利用者のクエリに連結しない。
- このチェックは SOQL を完全に構文解析するものではない。構文の誤りは Salesforce 側のエラーとして返し、権限の境界は USER_MODE が担う。

### D9. SOSL は FIND 文をそのまま受け取り、SOQL と同じ方法でチェックする

- 入力: `search`（必須、SOSL の FIND 文 1 つ）。sobject-reads の `find` と同じ。
- `ReadQueryGuard` で、SOQL と同じくマスク済みの文字列を作って判定する。リテラルのマスクでは、文字列リテラルに加えて検索語の `{...}`（`\}` のエスケープを含む）もマスクする。
- 拒否する条件: 空、または `FIND` で始まらない。`;` を含む。`UPDATE TRACKING`・`UPDATE VIEWSTAT` を含む。`WITH SYSTEM_MODE` を含む。バインド変数を含む（SOQL と同じ判定）。
- 件数上限: 括弧のマスク済みの文字列で外側の `LIMIT n` を探し（RETURNING 句のオブジェクトごとの LIMIT は括弧の中なので対象にならない）、200 を超えるなら 201 に置き換え、なければ末尾に ` LIMIT 201` を足す。合計が 201 件なら、最後のグループの最後のレコードを除いて 200 件にし、`truncated=true` にする。
- sobject-reads の例は検索語を `{...}` で囲む形。Apex の `Search.query` がこの形を受け付けるかをテストで確かめ、受け付けない場合だけ、検索語を `'...'` の形に変換する（D13・Risks）。
- 代替案: 検索語とオブジェクト名を受け取り、サーバー側でクエリを組み立てる。検証は簡単になるが、sobject-reads の入力と出力が変わるため採らない。

### D10. 最近使ったレコードは固定のクエリで取得し、アクセス権を確認し直す

- 入力: `sobjectName`（必須、オブジェクトの API 名）。sobject-reads の `sobject-name` に当たる。ハイフンは Apex の変数名に使えないため、名前だけが変わる。
- `sobjectName` は `Schema.describeSObjects` で確認し、存在しない・参照できないオブジェクトなら拒否する。
- 動的 SOQL は使わず、次の固定のクエリで取得する。
  - `SELECT Id, Name, Type, LastViewedDate FROM RecentlyViewed WHERE Type = :sobjectName WITH USER_MODE ORDER BY LastViewedDate DESC NULLS LAST LIMIT 201`
- 201 件目があれば 200 件にして `truncated=true` にする。そのあと `UserRecordAccess` で `HasReadAccess` が true のものだけを残す。取り除いた分だけ件数は少なくなる。
- 取得元は元の要件どおり RecentlyViewed（最近表示または参照したレコード）。sobject-reads の説明は「recently viewed or modified」で、取得元は公開されていない。

### D11. 失敗は応答として返し、入力は 1 回 10 件までにする

- 入力ごとに `try/catch (Exception)` で包み、失敗は `succeeded=false` と `errorMessage` で返す。`@InvocableMethod` から例外を投げると `isSuccess=false` になって `outputValues` が空になり、注意喚起が出せないため。
- `errorMessage` には Salesforce の例外メッセージをそのまま入れる（モデルがクエリを直せるようにするため）。チェックで拒否したときのメッセージは日本語で Apex に書く（差し替え対象は注意喚起だけ）。
- 1 回の呼び出しで処理する入力は 10 件まで。11 件目以降は処理せず、失敗の応答を返す。Invocable は入力を配列で受け取るため、SOSL の 1 トランザクション 20 回の制限や、SOQL の回数の制限に余裕を持たせる。

### D12. sobject-reads との違い

design で確認したいこと 3 への回答。再現するのは `soqlQuery`・`find`・`listRecentSobjectRecords` の 3 つで、ツール名と入力は次のとおり合わせる。

| ツール名 | sobject-reads の入力 | 今回の入力 |
|---|---|---|
| `soqlQuery` | `query`（SOQL 文、必須） | `query`（同じ） |
| `find` | `search`（SOSL 文、必須） | `search`（同じ） |
| `listRecentSobjectRecords` | `sobject-name`（必須） | `sobjectName`（名前だけ違う） |

残る違いと、その理由。

| 違い | 理由 |
|---|---|
| 出力が Invocable の結果の外枠に入り、注意喚起・成否・件数・打ち切りの項目が付く。結果は `resultJson` の JSON 文字列（D3） | 注意喚起の要件と、Invocable の出力の形（プラットフォームの制約） |
| エラーを MCP のエラーではなく、失敗を示す通常の応答で返す（D11） | 注意喚起をエラーのときも表示する要件 |
| 結果を最大 200 件で打ち切る（D8〜D10） | 取得件数の上限の要件。クエリは拒否せず受け付ける |
| `FOR VIEW` などの副作用のある句、`WITH SYSTEM_MODE`、バインド変数を拒否する（D8・D9） | 読み取り以外の拒否、実行ユーザーの権限、インジェクション対策の要件。`FOR UPDATE` と `ALL ROWS` は REST の query でも使えない |
| `sobject-name` が `sobjectName` になる | Apex の変数名にハイフンを使えない |
| 1 回の呼び出しで処理する入力は 10 件まで（D11） | Invocable は入力を配列で受け取る（プラットフォームの制約）ため、ガバナ制限に余裕を持たせる |
| 最近使ったレコードから、参照できなくなったレコードを除く（D10） | 権限外のレコードを返さない要件 |

- `getObjectSchema`・`getUserInfo`・`getRelatedRecords` は元の要件の対象外なので作らない。`getObjectSchema` がない分、モデルが項目名を推測する場面が増える（Risks）。

### D13. テストと静的解析

- `ReadQueryGuard` は文字列だけのテストで確かめる。
  - SOQL と SOSL の拒否と許可のシナリオ（spec の全シナリオ。リテラル・検索語・日付リテラルを含む）。
  - LIMIT の書き換え（LIMIT なし、200 以下、200 超、OFFSET だけ、サブクエリだけ、RETURNING 句のオブジェクトごとの LIMIT だけ）。
- 各アクションのテストで、成功・0 件・拒否・例外・入力件数の超過のすべてに注意喚起の 4 項目が入ることを確かめる。
- `SoqlQueryAction` は、取引先を 250 件作って、LIMIT なしと `LIMIT 500` で 200 件に打ち切られることと、`SELECT COUNT()` で件数が返ることを確かめる。
- 権限のテストは `System.runAs` で行う。テスト内で権限セットと `ObjectPermissions`・`FieldPermissions` を作り、取引先の参照権限はあるが `Account.Priority__c` の参照権限はないユーザーで、項目エラーになることを確かめる。取引先の参照権限がないユーザーでは、オブジェクトのエラーになることを確かめる。
- `FindAction` は `Test.setFixedSearchResults` で結果を固定し、オブジェクトごとのグループの形と、`FIND {...}` の形のクエリが `Search.query` で実行できることを確かめる。
- `ListRecentSobjectRecordsAction` は、テストで作ったレコードを `FOR VIEW` 付きで参照して履歴を作る。テストで履歴が作れない場合は、取得の流れと注意喚起の確認にとどめ、組織で確かめる。
- 共有設定のシナリオは組織の共有設定（OWD）に依存するため、Apex のテストではなく、組織で権限の少ないユーザーを使って受け入れ確認で確かめる。
- Code Analyzer はセキュリティのルールで 0 件にする。

## Risks / Trade-offs

- [`<toolName>` を書き換えたデプロイが受け付けられず、ツール名を sobject-reads に合わせられない] → デプロイで確かめる。だめなら Setup の画面でツール名を設定できるか確かめ、それでも無理なら spec の修正をユーザーと相談する。
- [Apex の `Search.query` が `FIND {...}` の形を受け付けない] → テストで確かめ、受け付けない場合は検索語を `'...'` の形に変換する。
- [マスクの誤りで、LIMIT の位置を間違えたり、正しいクエリを拒否したりする] → spec のシナリオに加え、リテラル内の括弧や引用符、入れ子のサブクエリをテストで確かめる。
- [集計関数だけのクエリ（`SELECT COUNT(Id) FROM Account` など）に LIMIT を足すと、Salesforce がエラーにする] → テストで確かめる。エラーになる場合は、GROUP BY のない集計クエリには LIMIT を足さない（結果は 1 行なので上限を超えない）。
- [ウィジェット非対応のクライアントで、モデルが注意喚起を伝えない] → 出力テキストに全文を入れ、ツールの説明で伝えるよう指示する。モデルの振る舞いまでは保証できないため、Slackbot などで受け入れ確認する。
- [入力が 2 件以上だとウィジェットが表示されない] → ツールの説明で入力 1 件を求める。テキストの注意喚起はすべての応答に入る。
- [捕捉できない LimitException では注意喚起も返らない] → 件数上限と入力件数の上限で、制限に届かないようにする。
- [Code Analyzer の `ApexSOQLInjection` が、利用者のクエリを渡す箇所を指摘する] → 書き換えは LIMIT の整数だけにする。それでも指摘が出たら、抑止（`@SuppressWarnings`）で 0 件にはせず、対応方法を相談する。
- [正規表現によるチェックは SOQL と SOSL を完全には解析できない] → チェックの役割は副作用のある句・バインド変数・件数に限る。権限の境界は USER_MODE が担う。
- [広い権限を持つユーザーには広い範囲が返る] → 利用できるユーザーを外部クライアントアプリケーションや権限セットで絞る運用を、受け入れ時に確認する。
- [ページレイアウトで隠しているだけの項目が返る] → 公開前に、機密の項目が項目レベルセキュリティで保護されているか確認する。
- [スキーマ取得のツールがないため、モデルが項目名を推測して失敗しやすい] → エラーメッセージで直せるようにする。必要なら後でツールを追加する。
- [RecentlyViewed や UserRecordAccess で USER_MODE が使えない] → テストで確かめる。使えない場合は `with sharing` と UserRecordAccess の確認で代える。
- [CLT が 6 つあり、内容が重複する] → スキルで生成し、ウィジェットは 1 つにまとめる。
- [ツールを呼ぶたびに API 呼び出し数を消費する] → 件数上限で応答を小さく保つ。

## Migration Plan

1. カスタム表示ラベルと Apex をデプロイし、テストを実行する。
2. Setup で `ReadOnlyRecordsServer` を作り、3 つの Apex アクションをツールとして追加する。
3. McpServerDefinition を retrieve する。
4. coordinate スキルで CLT とウィジェットを作り、デプロイする（レスポンス CLT → ウィジェット → エンベロープ CLT の順）。
5. McpServerDefinition の `<toolName>`・`<toolTitle>`・`<resources>`・`<uiResource>`・`descriptionOverride`・注釈を編集してデプロイし、サーバーを有効にする。
6. MCP クライアントに新しいサーバーを接続し、受け入れ確認をする。

ロールバック: Setup でサーバーを無効にすれば、クライアントからは使えなくなる。メタデータを消す場合は、McpServerDefinition → CLT・ウィジェット → Apex → ラベルの順で破壊的デプロイする。既存の `HandsonPipelineServer` には影響しない。

## Open Questions

- 組織でクラシック暗号化の項目を使っているか（未確認）。使っている場合は、Apex での値の扱いを公開前に確認する。
- 新しいサーバーのエンドポイント URL と、既存の外部クライアントアプリケーションをそのまま使えるか。サーバー作成後に Setup で確認する。
