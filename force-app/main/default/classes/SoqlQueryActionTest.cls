@IsTest
private class SoqlQueryActionTest {
    // 上限（200 件）を超える件数を用意して、打ち切りを確かめる
    private static final Integer ACCOUNT_COUNT = 250;

    @TestSetup
    static void setupTestData() {
        TestDataFactory.createAccounts(ACCOUNT_COUNT, true);
    }

    // ─── 成功 ─────────────────────────────────────────────────────

    @IsTest
    static void shouldReturnRecords_WhenSelectWithLimit() {
        // When
        ReadToolResult result = runOne(
            'SELECT Id, Name FROM Account WHERE Name LIKE \'' + TestDataFactory.ACCOUNT_NAME_PREFIX + '%\' ORDER BY Name LIMIT 10'
        );

        // Then
        assertSucceeded(result, 10, false);
        List<Object> records = (List<Object>) JSON.deserializeUntyped(result.resultJson);
        Map<String, Object> first = (Map<String, Object>) records[0];
        Assert.areEqual(TestDataFactory.ACCOUNT_NAME_PREFIX + '000', first.get('Name'), 'SELECT 句の項目が並び順どおりに返る');
    }

    @IsTest
    static void shouldReturnEmpty_WhenNoRecordMatches() {
        ReadToolResult result = runOne('SELECT Id FROM Account WHERE Name = \'存在しない取引先\'');

        assertSucceeded(result, 0, false);
        Assert.areEqual('[]', result.resultJson, '0 件は空の配列');
    }

    @IsTest
    static void shouldReturnCount_WhenSelectCount() {
        ReadToolResult result = runOne('SELECT COUNT() FROM Account');

        assertSucceeded(result, ACCOUNT_COUNT, false);
        Assert.areEqual('[]', result.resultJson, 'SELECT COUNT() ではレコードを返さない');
    }

    @IsTest
    static void shouldReturnAggregate_WhenAggregateWithoutGroupBy() {
        ReadToolResult result = runOne('SELECT COUNT(Id) total FROM Account');

        assertSucceeded(result, 1, false);
        Map<String, Object> row = (Map<String, Object>) ((List<Object>) JSON.deserializeUntyped(result.resultJson))[0];
        Assert.areEqual(ACCOUNT_COUNT, row.get('total'), 'GROUP BY のない集計は 1 行で、LIMIT を足しても実行できる');
    }

    // ─── 件数上限 ──────────────────────────────────────────────────

    @IsTest
    static void shouldTruncate_WhenNoLimitAndOverMax() {
        ReadToolResult result = runOne('SELECT Id FROM Account');

        assertSucceeded(result, ReadQueryGuard.MAX_RECORDS, true);
    }

    @IsTest
    static void shouldTruncate_WhenLimitExceedsMax() {
        ReadToolResult result = runOne('SELECT Id FROM Account LIMIT 500');

        assertSucceeded(result, ReadQueryGuard.MAX_RECORDS, true);
    }

    @IsTest
    static void shouldTruncate_WhenOnlyOffset() {
        // 250 件のうち 11 件目以降は 240 件あり、上限で打ち切られる
        ReadToolResult result = runOne('SELECT Id FROM Account ORDER BY Name OFFSET 10');

        assertSucceeded(result, ReadQueryGuard.MAX_RECORDS, true);
    }

    // ─── 失敗 ─────────────────────────────────────────────────────

    @IsTest
    static void shouldFail_WhenNotSelect() {
        ReadToolResult result = runOne('DELETE FROM Account');

        assertFailed(result);
        Assert.areEqual(ACCOUNT_COUNT, [SELECT COUNT() FROM Account], 'レコードは変わらない');
    }

    @IsTest
    static void shouldFail_WhenFieldDoesNotExist() {
        ReadToolResult result = runOne('SELECT Id, NoSuchField__c FROM Account LIMIT 1');

        assertFailed(result);
        Assert.isTrue(result.errorMessage.contains('NoSuchField__c'), 'Salesforce のエラー内容をそのまま返す: ' + result.errorMessage);
    }

    @IsTest
    static void shouldFail_WhenBindVariable() {
        ReadToolResult result = runOne('SELECT Id FROM Account WHERE Name = :accountName');

        assertFailed(result);
    }

    @IsTest
    static void shouldSkipInputs_WhenOverInputLimit() {
        // Given
        Integer inputCount = ReadToolResult.MAX_INPUTS_PER_CALL + 2;
        List<SoqlQueryAction.Input> inputs = new List<SoqlQueryAction.Input>();
        for (Integer index = 0; index < inputCount; index++) {
            inputs.add(newInput('SELECT Id FROM Account LIMIT 1'));
        }

        // When
        Test.startTest();
        List<ReadToolResult> results = SoqlQueryAction.soqlQuery(inputs);
        Test.stopTest();

        // Then
        Assert.areEqual(inputCount, results.size(), '入力と同じ数の応答を返す');
        for (Integer index = 0; index < inputCount; index++) {
            ReadToolResultTest.assertNotice(results[index]);
            Assert.areEqual(index < ReadToolResult.MAX_INPUTS_PER_CALL, results[index].succeeded, '上限までは処理し、超えた分は処理しない: ' + index);
        }
    }

    // ─── 実行ユーザーの権限 ─────────────────────────────────────────

    @IsTest
    static void shouldFail_WhenUserCannotReadField() {
        // Given: 取引先は参照できるが、一部の項目は参照できないユーザー
        User restrictedUser = createRestrictedUser(true);
        String hiddenField = TestDataFactory.findAccountFieldHiddenFrom(restrictedUser.ProfileId);
        String queryWithField = 'SELECT Id, ' + hiddenField + ' FROM Account LIMIT 1';
        Assert.isTrue(execute(queryWithField).succeeded, '前提: テストを実行する管理者はこの項目を参照できる');

        // When
        ReadToolResult nameOnly;
        ReadToolResult withField;
        Test.startTest();
        System.runAs(restrictedUser) {
            nameOnly = execute('SELECT Id, Name FROM Account LIMIT 1');
            withField = execute(queryWithField);
        }
        Test.stopTest();

        // Then
        assertSucceeded(nameOnly, 1, false);
        assertFailed(withField);
    }

    @IsTest
    static void shouldFail_WhenUserCannotReadObject() {
        // Given: 取引先を参照できないユーザー
        User restrictedUser = createRestrictedUser(false);

        // When
        ReadToolResult result;
        Test.startTest();
        System.runAs(restrictedUser) {
            result = execute('SELECT Id, Name FROM Account LIMIT 1');
        }
        Test.stopTest();

        // Then
        assertFailed(result);
    }

    // ─── Helpers ─────────────────────────────────────────────────

    private static ReadToolResult runOne(String query) {
        Test.startTest();
        ReadToolResult result = execute(query);
        Test.stopTest();
        return result;
    }

    private static ReadToolResult execute(String query) {
        List<ReadToolResult> results = SoqlQueryAction.soqlQuery(new List<SoqlQueryAction.Input>{ newInput(query) });
        Assert.areEqual(1, results.size(), '入力 1 件に応答 1 件');
        return results[0];
    }

    private static User createRestrictedUser(Boolean canReadAccount) {
        User restrictedUser;
        // 設定オブジェクトの DML を、取引先の DML と分ける
        System.runAs(new User(Id = UserInfo.getUserId())) {
            restrictedUser = TestDataFactory.createUserWithoutAccountRead();
            if (canReadAccount) {
                TestDataFactory.grantAccountReadOnly(restrictedUser);
            }
        }
        return restrictedUser;
    }

    private static SoqlQueryAction.Input newInput(String query) {
        SoqlQueryAction.Input input = new SoqlQueryAction.Input();
        input.query = query;
        return input;
    }

    private static void assertSucceeded(ReadToolResult result, Integer expectedCount, Boolean expectedTruncated) {
        ReadToolResultTest.assertNotice(result);
        Assert.isTrue(result.succeeded, '成功の応答: ' + result.errorMessage);
        Assert.areEqual(expectedCount, result.recordCount, '返した件数');
        Assert.areEqual(expectedTruncated, result.truncated, '打ち切りの有無');
    }

    private static void assertFailed(ReadToolResult result) {
        ReadToolResultTest.assertNotice(result);
        Assert.isFalse(result.succeeded, '失敗の応答');
        Assert.isFalse(String.isBlank(result.errorMessage), '失敗の理由を返す');
    }
}
