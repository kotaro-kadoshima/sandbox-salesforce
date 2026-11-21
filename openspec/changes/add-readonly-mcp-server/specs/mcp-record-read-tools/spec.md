# Spec Delta

## Purpose

カスタム MCP サーバーから、実行ユーザーが見てよい範囲の Salesforce レコードだけを読み取れるようにする。sobject-reads の `soqlQuery`・`find`・`listRecentSobjectRecords` を、同じツール名・入力のまま、書き込みの手段を持たない形で提供する。

## ADDED Requirements

### Requirement: 読み取り専用のツールだけを提供する

カスタム MCP サーバーは、`soqlQuery`（SOQL 検索）・`find`（SOSL 横断検索）・`listRecentSobjectRecords`（最近使ったレコード取得）の 3 つのツールだけを提供する（SHALL）。どのツールもレコードの作成・更新・削除を行ってはならず（MUST NOT）、MCP クライアントには読み取り専用かつ破壊的でないツールとして公開する（SHALL）。

#### Scenario: ツール一覧が 3 つの読み取りツールだけである

- **WHEN** MCP クライアントがサーバーのツール一覧を取得する
- **THEN** `soqlQuery`・`find`・`listRecentSobjectRecords` の 3 つだけが返る
- **AND** 3 つとも読み取り専用で、破壊的でないことが示されている

#### Scenario: ツールを使ってもレコードが変わらない

- **WHEN** 3 つのツールをそれぞれ実行する
- **THEN** 組織のどのレコードも作成・更新・削除されていない

### Requirement: sobject-reads と同じ入力を受け取る

3 つのツールは、sobject-reads の同名のツールと同じ入力だけを受け取る（SHALL）。`soqlQuery` は `query`（SOQL 文、必須）、`find` は `search`（SOSL 文、必須）、`listRecentSobjectRecords` は `sobjectName`（オブジェクトの API 名、必須。sobject-reads の `sobject-name` に当たる）を受け取る。件数などの独自の入力を足してはならない（MUST NOT）。

#### Scenario: 入力の形が sobject-reads と同じである

- **WHEN** MCP クライアントがツール一覧で 3 つのツールの入力を確認する
- **THEN** `soqlQuery` は `query`、`find` は `search`、`listRecentSobjectRecords` は `sobjectName` だけを、必須の文字列として受け取る

#### Scenario: 必須の入力がないと失敗する

- **WHEN** `listRecentSobjectRecords` を `sobjectName` なしで実行する
- **THEN** レコードは返らず、理由を示す失敗の応答が返る

### Requirement: 実行ユーザーの権限で取得する

3 つのツールは、MCP クライアントで認証したユーザーの権限で取得する（SHALL）。共有設定・項目レベルセキュリティ・オブジェクト権限を必ず適用し、そのユーザーが Salesforce の画面や API で見られないレコードと項目を返してはならない（MUST NOT）。

#### Scenario: 共有されていないレコードは返らない

- **GIVEN** ユーザー A に共有されていないレコードがある
- **WHEN** ユーザー A がそのレコードに一致する条件で `soqlQuery`・`find` を実行する
- **THEN** そのレコードは結果に含まれない

#### Scenario: 参照権限のない項目は返らない

- **GIVEN** ユーザー A に項目 X の参照権限がない
- **WHEN** ユーザー A が項目 X を含む SOQL を `soqlQuery` で実行する
- **THEN** 項目 X の値は返らず、失敗の応答になる

#### Scenario: 参照権限のないオブジェクトは返らない

- **GIVEN** ユーザー A にオブジェクト Y の参照権限がない
- **WHEN** ユーザー A がオブジェクト Y を対象に `soqlQuery` または `find` を実行する
- **THEN** オブジェクト Y のレコードは返らない

### Requirement: SOQL でレコードを検索する

`soqlQuery` は SOQL の SELECT 文を 1 つ受け取り、実行ユーザーの権限で実行して、一致したレコードを SELECT 句の項目付きの配列で返す（SHALL）。あわせて、返した件数と、件数上限で打ち切ったかどうかを返す（SHALL）。`SELECT COUNT() FROM ...` の形のクエリでは、一致した件数を返す（SHALL）。

#### Scenario: SELECT 文の結果が返る

- **WHEN** `SELECT Id, Name, StageName, Amount FROM Opportunity WHERE StageName != 'Closed Lost' ORDER BY Amount DESC LIMIT 10` を渡す
- **THEN** 条件に一致し、ユーザーが参照できる商談が、指定した項目付きで最大 10 件返る
- **AND** 返した件数が示される

#### Scenario: 一致するレコードがない

- **WHEN** どのレコードにも一致しない SELECT 文を渡す
- **THEN** 0 件の成功の応答が返る

#### Scenario: 件数だけを数える

- **WHEN** `SELECT COUNT() FROM Account` を渡す
- **THEN** ユーザーが参照できる取引先の件数が返る

### Requirement: SOQL は読み取りクエリ以外を拒否する

`soqlQuery` は、SELECT で始まらない文、副作用のある句（`FOR VIEW`・`FOR REFERENCE`・`UPDATE TRACKING`・`UPDATE VIEWSTAT`）、Apex 専用の句（`FOR UPDATE`・`ALL ROWS`）、`WITH SYSTEM_MODE`、複数の文、バインド変数を含むクエリを、実行せずに拒否する（SHALL）。文字列リテラルの中の語句と、日付リテラル（`LAST_N_DAYS:30` など）は拒否の理由にしない。

#### Scenario: SELECT 以外の文を拒否する

- **WHEN** `DELETE FROM Account` や空文字を渡す
- **THEN** クエリは実行されず、理由を示す失敗の応答が返る

#### Scenario: 副作用のある句を拒否する

- **WHEN** `SELECT Id FROM Account FOR VIEW` や `SELECT Id FROM Account FOR UPDATE` を渡す
- **THEN** クエリは実行されず、失敗の応答が返る

#### Scenario: システムモードの指定を拒否する

- **WHEN** `SELECT Id FROM Account WITH SYSTEM_MODE` を渡す
- **THEN** クエリは実行されず、失敗の応答が返る

#### Scenario: バインド変数を拒否する

- **WHEN** `SELECT Id FROM Account WHERE Id = :recordId` を渡す
- **THEN** サーバー側の変数は参照されず、失敗の応答が返る

#### Scenario: リテラル内の語句と日付リテラルは拒否の理由にしない

- **WHEN** `SELECT Id FROM Account WHERE Name = 'FOR UPDATE 株式会社' AND CreatedDate = LAST_N_DAYS:30` を渡す
- **THEN** 読み取りクエリとして実行され、成功の応答が返る

### Requirement: SOSL で複数オブジェクトを横断検索する

`find` は SOSL の FIND 文を 1 つ受け取り、実行ユーザーの権限で実行して、一致したレコードをオブジェクトごとのグループで、RETURNING 句に指定した項目付きで返す（SHALL）。あわせて、返した件数の合計と、件数上限で打ち切ったかどうかを返す（SHALL）。

#### Scenario: 複数オブジェクトを横断して検索する

- **WHEN** `FIND {Acme} IN NAME FIELDS RETURNING Account(Id, Name), Contact(Id, Name, Email)` を渡す
- **THEN** ユーザーが参照できる、一致した取引先と取引先責任者が、オブジェクトごとのグループで、指定した項目付きで返る

#### Scenario: 一致するレコードがない

- **WHEN** どのレコードにも一致しない FIND 文を渡す
- **THEN** 0 件の成功の応答が返る

### Requirement: SOSL は読み取りクエリ以外を拒否する

`find` は、FIND で始まらない文、副作用のある句（`UPDATE TRACKING`・`UPDATE VIEWSTAT`）、`WITH SYSTEM_MODE`、複数の文、バインド変数を含むクエリを、実行せずに拒否する（SHALL）。検索語と文字列リテラルの中の語句は拒否の理由にしない。

#### Scenario: FIND 以外の文を拒否する

- **WHEN** `SELECT Id FROM Account` や空文字を渡す
- **THEN** 検索は実行されず、理由を示す失敗の応答が返る

#### Scenario: 副作用のある句を拒否する

- **WHEN** `FIND {Acme} RETURNING KnowledgeArticleVersion(Id) UPDATE VIEWSTAT` を渡す
- **THEN** 検索は実行されず、失敗の応答が返る

#### Scenario: バインド変数を拒否する

- **WHEN** `FIND :term RETURNING Account(Id)` を渡す
- **THEN** サーバー側の変数は参照されず、失敗の応答が返る

#### Scenario: 検索語の中の語句は拒否の理由にしない

- **WHEN** `FIND {UPDATE TRACKING} RETURNING Account(Id, Name)` を渡す
- **THEN** 読み取りの検索として実行され、成功の応答が返る

### Requirement: 最近使ったレコードを取得する

`listRecentSobjectRecords` は、`sobjectName` で指定した種類のレコードのうち、実行ユーザーが最近表示または参照したものを、最後に表示した日時の新しい順に返す（SHALL）。現時点でユーザーが参照できないレコードは、履歴に残っていても返してはならない（MUST NOT）。

#### Scenario: 指定した種類の最近使ったレコードが新しい順に返る

- **WHEN** `sobjectName` に `Account` を指定して実行する
- **THEN** ユーザーが最近使った取引先だけが、ID・名前・最終表示日時付きで新しい順に返る

#### Scenario: 参照できなくなったレコードは返らない

- **GIVEN** ユーザーが以前表示したレコードの共有が外れている
- **WHEN** そのレコードの種類を指定して実行する
- **THEN** そのレコードは結果に含まれない

#### Scenario: 不正なオブジェクト名を拒否する

- **WHEN** 存在しない、またはユーザーが参照できないオブジェクトの名前を指定する
- **THEN** レコードは返らず、理由を示す失敗の応答が返る

### Requirement: 取得件数に上限を設ける

3 つのツールは、1 回の実行で 200 件を超えるレコードを返してはならない（MUST NOT）。一致が 200 件を超えるときは 200 件で打ち切り、打ち切ったことを示す（SHALL）。クエリに LIMIT や OFFSET があるかどうかにかかわらず、上限を理由にクエリを拒否してはならない（MUST NOT）。

#### Scenario: LIMIT がないと 200 件で打ち切る

- **GIVEN** 条件に一致するレコードが 250 件ある
- **WHEN** LIMIT のない SELECT 文を `soqlQuery` に渡す
- **THEN** 200 件が返り、打ち切ったことが示される

#### Scenario: 上限を超える LIMIT でも 200 件で打ち切る

- **GIVEN** 条件に一致するレコードが 250 件ある
- **WHEN** `LIMIT 500` を付けた SELECT 文を `soqlQuery` に渡す
- **THEN** 200 件が返り、打ち切ったことが示される

#### Scenario: 上限以下の LIMIT はそのまま使う

- **WHEN** `LIMIT 10` を付けた SELECT 文を `soqlQuery` に渡す
- **THEN** 最大 10 件が返り、打ち切りは示されない

#### Scenario: LIMIT なしの OFFSET も受け付ける

- **WHEN** 外側に LIMIT がなく `OFFSET 10` だけを付けた SELECT 文を `soqlQuery` に渡す
- **THEN** クエリは拒否されず、11 件目以降のレコードが最大 200 件返る

#### Scenario: サブクエリの LIMIT は外側の LIMIT とみなさない

- **WHEN** 外側に LIMIT がなく、サブクエリにだけ LIMIT がある SELECT 文を `soqlQuery` に渡す
- **THEN** 外側の結果に 200 件の上限が適用される

#### Scenario: SOSL の合計が上限を超えると打ち切る

- **GIVEN** FIND 文に一致するレコードが全オブジェクトの合計で 250 件ある
- **WHEN** その FIND 文を `find` に渡す
- **THEN** 合計 200 件が返り、打ち切ったことが示される

### Requirement: 失敗をツールの応答として返す

3 つのツールは、入力の拒否・権限エラー・クエリエラーを、MCP のツール呼び出しの失敗ではなく、失敗であることと理由を示す通常の応答として返す（SHALL）。

#### Scenario: クエリエラーでも応答が返る

- **WHEN** 存在しない項目を含む SOQL を `soqlQuery` に渡す
- **THEN** ツール呼び出しは完了し、失敗であることとエラー内容を含む応答が返る

### Requirement: 1 回の呼び出しで受け付ける入力を制限する

3 つのツールは、1 回の呼び出しで最大 10 件の入力を処理する（SHALL）。11 件目以降の入力には、処理しなかったことを示す失敗の応答を返す（SHALL）。

#### Scenario: 上限を超えた入力は処理しない

- **WHEN** 1 回の呼び出しで 12 件の入力を渡す
- **THEN** 最初の 10 件は処理され、残りの 2 件には失敗の応答が返る
