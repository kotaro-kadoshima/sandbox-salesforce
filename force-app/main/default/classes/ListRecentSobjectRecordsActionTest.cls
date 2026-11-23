@IsTest
private class ListRecentSobjectRecordsActionTest {
    // ─── 成功 ─────────────────────────────────────────────────────

    @IsTest
    static void shouldReturnRecentRecordsOfType_WhenViewed() {
        // Given: 取引先 3 件と取引先責任者 1 件を表示した履歴
        List<Account> accounts = TestDataFactory.createAccounts(3, true);
        List<Contact> contacts = TestDataFactory.createContacts(1, true);
        markAsViewed(accounts, contacts);

        // When
        ReadToolResult result = runOne('Account');

        // Then
        assertSucceeded(result, accounts.size(), false);
        Set<Id> returnedIds = new Set<Id>();
        for (Object record : (List<Object>) JSON.deserializeUntyped(result.resultJson)) {
            Map<String, Object> fields = (Map<String, Object>) record;
            Assert.areEqual('Account', fields.get('Type'), '指定した種類のレコードだけが返る');
            Assert.isNotNull(fields.get('LastViewedDate'), '最終表示日時を返す');
            returnedIds.add((Id) fields.get('Id'));
        }
        Assert.areEqual(new Map<Id, Account>(accounts).keySet(), returnedIds, '表示した取引先が返る');
    }

    @IsTest
    static void shouldAcceptLowerCaseName_WhenObjectExists() {
        // Given
        List<Account> accounts = TestDataFactory.createAccounts(1, true);
        markAsViewed(accounts, new List<Contact>());

        // When
        ReadToolResult result = runOne(' account ');

        // Then
        assertSucceeded(result, 1, false);
    }

    @IsTest
    static void shouldReturnEmpty_WhenNothingViewed() {
        ReadToolResult result = runOne('Account');

        assertSucceeded(result, 0, false);
        Assert.areEqual('[]', result.resultJson, '0 件は空の配列');
    }

    // ─── 失敗 ─────────────────────────────────────────────────────

    @IsTest
    static void shouldFail_WhenSobjectNameBlank() {
        ReadToolResult result = runOne(null);

        assertFailed(result);
        Assert.isTrue(result.errorMessage.contains('sobjectName'), '指定が必要な入力を示す');
    }

    @IsTest
    static void shouldFail_WhenObjectDoesNotExist() {
        ReadToolResult result = runOne('NoSuchObject__c');

        assertFailed(result);
        Assert.isTrue(result.errorMessage.contains('NoSuchObject__c'), '指定したオブジェクト名を示す');
    }

    @IsTest
    static void shouldSkipInputs_WhenOverInputLimit() {
        // Given
        Integer inputCount = ReadToolResult.MAX_INPUTS_PER_CALL + 2;
        List<ListRecentSobjectRecordsAction.Input> inputs = new List<ListRecentSobjectRecordsAction.Input>();
        for (Integer index = 0; index < inputCount; index++) {
            inputs.add(newInput('Account'));
        }

        // When
        Test.startTest();
        List<ReadToolResult> results = ListRecentSobjectRecordsAction.listRecentSobjectRecords(inputs);
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
    static void shouldFail_WhenUserCannotReadObject() {
        // Given: 取引先を参照できないユーザー
        User restrictedUser;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            restrictedUser = TestDataFactory.createUserWithoutAccountRead();
        }

        // When
        ReadToolResult result;
        Test.startTest();
        System.runAs(restrictedUser) {
            result = execute('Account');
        }
        Test.stopTest();

        // Then
        assertFailed(result);
    }

    @IsTest
    static void shouldExcludeRecord_WhenAccessRevokedAfterViewing() {
        // Given: 共有設定が非公開のオブジェクトで、ユーザーが自分のレコード 2 件を表示した履歴
        User restrictedUser;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            restrictedUser = TestDataFactory.createUserWithoutAccountRead();
            TestDataFactory.grantPrivateObjectReadCreate(restrictedUser);
        }
        CustomObject1__c revoked = new CustomObject1__c(Name = 'Revoked');
        CustomObject1__c kept = new CustomObject1__c(Name = 'Kept');
        System.runAs(restrictedUser) {
            insert new List<CustomObject1__c>{ revoked, kept };
            List<CustomObject1__c> viewed = [SELECT Id FROM CustomObject1__c WHERE Id IN (:revoked.Id, :kept.Id) WITH USER_MODE FOR VIEW];
            Assert.areEqual(2, viewed.size(), '前提: 履歴を作るレコードを参照できる');
        }

        // 所有者を変えて、1 件だけ参照できなくする
        update new CustomObject1__c(Id = revoked.Id, OwnerId = UserInfo.getUserId());
        System.runAs(restrictedUser) {
            Integer visible = [SELECT COUNT() FROM CustomObject1__c WHERE Id = :revoked.Id WITH USER_MODE];
            Assert.areEqual(0, visible, '前提: CustomObject1__c の共有設定が非公開で、所有者を変えたレコードは参照できない');
        }

        // When
        ReadToolResult result;
        Test.startTest();
        System.runAs(restrictedUser) {
            result = execute('CustomObject1__c');
        }
        Test.stopTest();

        // Then
        assertSucceeded(result, 1, false);
        List<Object> records = (List<Object>) JSON.deserializeUntyped(result.resultJson);
        Assert.areEqual(kept.Id, (Id) ((Map<String, Object>) records[0]).get('Id'), '参照できるレコードだけが返る');
    }

    // ─── Helpers ─────────────────────────────────────────────────

    /**
     * FOR VIEW で参照して、実行ユーザーの「最近使ったレコード」の履歴を作る。
     */
    private static void markAsViewed(List<Account> accounts, List<Contact> contacts) {
        Set<Id> accountIds = new Map<Id, Account>(accounts).keySet();
        Set<Id> contactIds = new Map<Id, Contact>(contacts).keySet();
        List<Account> viewedAccounts = [SELECT Id FROM Account WHERE Id IN :accountIds WITH USER_MODE FOR VIEW];
        List<Contact> viewedContacts = [SELECT Id FROM Contact WHERE Id IN :contactIds WITH USER_MODE FOR VIEW];
        Assert.areEqual(accounts.size() + contacts.size(), viewedAccounts.size() + viewedContacts.size(), '前提: 履歴を作るレコードを参照できる');
    }

    private static ReadToolResult runOne(String sobjectName) {
        Test.startTest();
        ReadToolResult result = execute(sobjectName);
        Test.stopTest();
        return result;
    }

    private static ReadToolResult execute(String sobjectName) {
        List<ReadToolResult> results = ListRecentSobjectRecordsAction.listRecentSobjectRecords(
            new List<ListRecentSobjectRecordsAction.Input>{ newInput(sobjectName) }
        );
        Assert.areEqual(1, results.size(), '入力 1 件に応答 1 件');
        return results[0];
    }

    private static ListRecentSobjectRecordsAction.Input newInput(String sobjectName) {
        ListRecentSobjectRecordsAction.Input input = new ListRecentSobjectRecordsAction.Input();
        input.sobjectName = sobjectName;
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
