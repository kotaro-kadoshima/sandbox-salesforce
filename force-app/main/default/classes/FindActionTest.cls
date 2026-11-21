@IsTest
private class FindActionTest {
    // sobject-reads の find の例と同じ、検索語を {...} で囲む形
    private static final String SEARCH_ACCOUNTS_AND_CONTACTS =
        'FIND {Read Tool} IN NAME FIELDS RETURNING Account(Id, Name), Contact(Id, Name, Email)';

    // ─── 成功 ─────────────────────────────────────────────────────

    @IsTest
    static void shouldReturnGroups_WhenRecordsMatch() {
        // Given
        List<Account> accounts = TestDataFactory.createAccounts(2, true);
        List<Contact> contacts = TestDataFactory.createContacts(1, true);
        Test.setFixedSearchResults(new List<Id>{ accounts[0].Id, accounts[1].Id, contacts[0].Id });

        // When
        ReadToolResult result = runOne(SEARCH_ACCOUNTS_AND_CONTACTS);

        // Then
        assertSucceeded(result, 3, false);
        List<Object> groups = (List<Object>) JSON.deserializeUntyped(result.resultJson);
        Assert.areEqual(2, groups.size(), 'レコードのあるオブジェクトごとにグループを作る');
        assertGroup((Map<String, Object>) groups[0], 'Account', 2);
        assertGroup((Map<String, Object>) groups[1], 'Contact', 1);
    }

    @IsTest
    static void shouldReturnEmpty_WhenNoRecordMatches() {
        ReadToolResult result = runOne(SEARCH_ACCOUNTS_AND_CONTACTS);

        assertSucceeded(result, 0, false);
        Assert.areEqual('[]', result.resultJson, '0 件は空の配列');
    }

    @IsTest
    static void shouldTruncate_WhenOverMax() {
        // Given: 上限（200 件）を超える一致
        List<Account> accounts = TestDataFactory.createAccounts(ReadQueryGuard.MAX_RECORDS + 50, true);
        Test.setFixedSearchResults(new List<Id>(new Map<Id, Account>(accounts).keySet()));

        // When
        ReadToolResult result = runOne('FIND {Read Tool} RETURNING Account(Id, Name)');

        // Then
        assertSucceeded(result, ReadQueryGuard.MAX_RECORDS, true);
    }

    // ─── 失敗 ─────────────────────────────────────────────────────

    @IsTest
    static void shouldFail_WhenNotFind() {
        ReadToolResult result = runOne('SELECT Id FROM Account');

        assertFailed(result);
    }

    @IsTest
    static void shouldFail_WhenUpdateViewstat() {
        ReadToolResult result = runOne('FIND {Acme} RETURNING KnowledgeArticleVersion(Id) UPDATE VIEWSTAT');

        assertFailed(result);
    }

    @IsTest
    static void shouldFail_WhenObjectDoesNotExist() {
        ReadToolResult result = runOne('FIND {Acme} RETURNING NoSuchObject__c(Id)');

        assertFailed(result);
    }

    @IsTest
    static void shouldSkipInputs_WhenOverInputLimit() {
        // Given
        Integer inputCount = ReadToolResult.MAX_INPUTS_PER_CALL + 2;
        List<FindAction.Input> inputs = new List<FindAction.Input>();
        for (Integer index = 0; index < inputCount; index++) {
            inputs.add(newInput(SEARCH_ACCOUNTS_AND_CONTACTS));
        }

        // When
        Test.startTest();
        List<ReadToolResult> results = FindAction.findRecords(inputs);
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
    static void shouldNotReturnRecords_WhenUserCannotReadObject() {
        // Given: 取引先を参照できないユーザー
        Account account = TestDataFactory.createAccounts(1, true)[0];
        User restrictedUser;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            restrictedUser = TestDataFactory.createUserWithoutAccountRead();
        }
        Test.setFixedSearchResults(new List<Id>{ account.Id });

        // When
        ReadToolResult result;
        Test.startTest();
        System.runAs(restrictedUser) {
            result = execute('FIND {Read Tool} RETURNING Account(Id, Name)');
        }
        Test.stopTest();

        // Then
        ReadToolResultTest.assertNotice(result);
        Assert.areEqual(0, result.recordCount, '参照できないオブジェクトのレコードは返らない');
        Assert.isFalse(result.resultJson.contains(account.Id), '取引先の ID が結果に含まれない');
    }

    // ─── Helpers ─────────────────────────────────────────────────

    private static ReadToolResult runOne(String search) {
        Test.startTest();
        ReadToolResult result = execute(search);
        Test.stopTest();
        return result;
    }

    private static ReadToolResult execute(String search) {
        List<ReadToolResult> results = FindAction.findRecords(new List<FindAction.Input>{ newInput(search) });
        Assert.areEqual(1, results.size(), '入力 1 件に応答 1 件');
        return results[0];
    }

    private static FindAction.Input newInput(String search) {
        FindAction.Input input = new FindAction.Input();
        input.search = search;
        return input;
    }

    private static void assertGroup(Map<String, Object> searchGroup, String expectedType, Integer expectedCount) {
        Assert.areEqual(expectedType, searchGroup.get('sobjectType'), 'グループのオブジェクト');
        Assert.areEqual(expectedCount, ((List<Object>) searchGroup.get('records')).size(), 'グループのレコード数');
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
