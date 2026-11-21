@IsTest
private class ReadQueryGuardTest {
    private static final String APPENDED_LIMIT = ' LIMIT ' + ReadQueryGuard.FETCH_LIMIT;

    // ─── SOQL: 拒否 ────────────────────────────────────────────────

    @IsTest
    static void shouldRejectSoql_WhenBlank() {
        assertSoqlRejected('  ', 'SELECT 文を query に');
    }

    @IsTest
    static void shouldRejectSoql_WhenNotSelect() {
        assertSoqlRejected('DELETE FROM Account', 'SELECT 文だけ');
    }

    @IsTest
    static void shouldRejectSoql_WhenForView() {
        assertSoqlRejected('SELECT Id FROM Account FOR VIEW', 'FOR VIEW');
    }

    @IsTest
    static void shouldRejectSoql_WhenForReference() {
        assertSoqlRejected('SELECT Id FROM Account FOR REFERENCE', 'FOR REFERENCE');
    }

    @IsTest
    static void shouldRejectSoql_WhenForUpdate() {
        assertSoqlRejected('SELECT Id FROM Account LIMIT 1 for update', 'for update');
    }

    @IsTest
    static void shouldRejectSoql_WhenUpdateTracking() {
        assertSoqlRejected('SELECT Id FROM KnowledgeArticleVersion UPDATE TRACKING', 'UPDATE TRACKING');
    }

    @IsTest
    static void shouldRejectSoql_WhenUpdateViewstat() {
        assertSoqlRejected('SELECT Id FROM KnowledgeArticleVersion UPDATE VIEWSTAT', 'UPDATE VIEWSTAT');
    }

    @IsTest
    static void shouldRejectSoql_WhenAllRows() {
        assertSoqlRejected('SELECT Id FROM Account ALL ROWS', 'ALL ROWS');
    }

    @IsTest
    static void shouldRejectSoql_WhenSystemMode() {
        assertSoqlRejected('SELECT Id FROM Account WITH SYSTEM_MODE', 'WITH SYSTEM_MODE');
    }

    @IsTest
    static void shouldRejectSoql_WhenMultipleStatements() {
        assertSoqlRejected('SELECT Id FROM Account; SELECT Id FROM Contact', '「;」');
    }

    @IsTest
    static void shouldRejectSoql_WhenBindVariable() {
        assertSoqlRejected('SELECT Id FROM Account WHERE Id = :recordId', 'バインド変数');
    }

    // ─── SOQL: 許可 ────────────────────────────────────────────────

    @IsTest
    static void shouldAcceptSoql_WhenKeywordsAndDateLiteral() {
        String query = 'SELECT Id FROM Account WHERE Name = \'FOR UPDATE 株式会社; :x\' AND CreatedDate = LAST_N_DAYS:30 LIMIT 10';

        ReadQueryGuard.SoqlQuery prepared = ReadQueryGuard.prepareSoql(query);

        Assert.areEqual(query, prepared.query, 'リテラル内の語句と日付リテラルでは拒否せず、LIMIT 10 はそのまま');
    }

    @IsTest
    static void shouldAcceptSoql_WhenUserMode() {
        String query = 'SELECT Id FROM Account WITH USER_MODE LIMIT 5';

        ReadQueryGuard.SoqlQuery prepared = ReadQueryGuard.prepareSoql(query);

        Assert.areEqual(query, prepared.query, 'WITH USER_MODE は Salesforce の判定にまかせる');
    }

    @IsTest
    static void shouldMarkCountOnly_WhenSelectCount() {
        String query = 'SELECT COUNT() FROM Account WHERE Name LIKE \'A%\'';

        ReadQueryGuard.SoqlQuery prepared = ReadQueryGuard.prepareSoql(query);

        Assert.isTrue(prepared.isCountOnly, 'SELECT COUNT() は件数を数えるクエリ');
        Assert.areEqual(query, prepared.query, 'SELECT COUNT() には LIMIT を足さない');
    }

    @IsTest
    static void shouldRejectSoql_WhenAggregateWithoutGroupByHasLimit() {
        assertSoqlRejected('SELECT COUNT(Id) FROM Account LIMIT 5', 'GROUP BY のない集計');
    }

    @IsTest
    static void shouldNotAppendLimit_WhenAggregateWithoutGroupBy() {
        String query = 'SELECT FORMAT(SUM(AnnualRevenue)) total FROM Account WHERE Name LIKE \'A%\'';

        Assert.areEqual(query, ReadQueryGuard.prepareSoql(query).query, 'GROUP BY のない集計には LIMIT を足さない（入れ子の関数も見分ける）');
    }

    @IsTest
    static void shouldAppendLimit_WhenAggregateWithGroupBy() {
        String query = 'SELECT Industry, COUNT(Id) FROM Account GROUP BY Industry';

        Assert.areEqual(query + APPENDED_LIMIT, ReadQueryGuard.prepareSoql(query).query, 'GROUP BY のある集計は行数が増えるので LIMIT を足す');
    }

    // ─── SOQL: 件数上限 ─────────────────────────────────────────────

    @IsTest
    static void shouldAppendLimit_WhenSoqlHasNoLimit() {
        ReadQueryGuard.SoqlQuery prepared = ReadQueryGuard.prepareSoql('SELECT Id FROM Account ORDER BY Name  ');

        Assert.areEqual('SELECT Id FROM Account ORDER BY Name' + APPENDED_LIMIT, prepared.query, '末尾に上限 + 1 件の LIMIT を足す');
        Assert.isFalse(prepared.isCountOnly, '通常のクエリ');
    }

    @IsTest
    static void shouldKeepLimit_WhenSoqlLimitIsWithinMax() {
        String query = 'SELECT Id FROM Account LIMIT ' + ReadQueryGuard.MAX_RECORDS;

        Assert.areEqual(query, ReadQueryGuard.prepareSoql(query).query, '上限以下の LIMIT はそのまま');
    }

    @IsTest
    static void shouldReplaceLimit_WhenSoqlLimitExceedsMax() {
        ReadQueryGuard.SoqlQuery prepared = ReadQueryGuard.prepareSoql('SELECT Id FROM Account LIMIT 500 OFFSET 10');

        Assert.areEqual(
            'SELECT Id FROM Account LIMIT ' + ReadQueryGuard.FETCH_LIMIT + ' OFFSET 10',
            prepared.query,
            '上限を超える LIMIT は上限 + 1 件に置き換える'
        );
    }

    @IsTest
    static void shouldInsertLimitBeforeOffset_WhenSoqlHasOnlyOffset() {
        ReadQueryGuard.SoqlQuery prepared = ReadQueryGuard.prepareSoql('SELECT Id FROM Account ORDER BY Name OFFSET 10');

        Assert.areEqual(
            'SELECT Id FROM Account ORDER BY Name LIMIT ' + ReadQueryGuard.FETCH_LIMIT + ' OFFSET 10',
            prepared.query,
            'LIMIT は OFFSET の前に入れる'
        );
    }

    @IsTest
    static void shouldIgnoreSubqueryLimit_WhenSoqlHasNoOuterLimit() {
        String query = 'SELECT Id, (SELECT Id FROM Contacts WHERE Id IN (SELECT WhoId FROM Task) LIMIT 5) FROM Account';

        Assert.areEqual(query + APPENDED_LIMIT, ReadQueryGuard.prepareSoql(query).query, 'サブクエリの LIMIT は外側の LIMIT とみなさない');
    }

    @IsTest
    static void shouldIgnoreLiteralLimit_WhenLiteralHasParenthesesAndQuotes() {
        String query = 'SELECT Id FROM Account WHERE Name = \'a(b \\\' LIMIT 5\' LIMIT 999';

        Assert.areEqual(
            'SELECT Id FROM Account WHERE Name = \'a(b \\\' LIMIT 5\' LIMIT ' + ReadQueryGuard.FETCH_LIMIT,
            ReadQueryGuard.prepareSoql(query).query,
            'リテラル内の括弧・引用符・LIMIT は数えず、外側の LIMIT だけを置き換える'
        );
    }

    // ─── SOSL: 拒否 ────────────────────────────────────────────────

    @IsTest
    static void shouldRejectSosl_WhenBlank() {
        assertSoslRejected('', 'FIND 文を search に');
    }

    @IsTest
    static void shouldRejectSosl_WhenNotFind() {
        assertSoslRejected('SELECT Id FROM Account', 'FIND 文だけ');
    }

    @IsTest
    static void shouldRejectSosl_WhenUpdateTracking() {
        assertSoslRejected('FIND {Acme} RETURNING KnowledgeArticleVersion(Id) UPDATE TRACKING', 'UPDATE TRACKING');
    }

    @IsTest
    static void shouldRejectSosl_WhenUpdateViewstat() {
        assertSoslRejected('FIND {Acme} RETURNING KnowledgeArticleVersion(Id) UPDATE VIEWSTAT', 'UPDATE VIEWSTAT');
    }

    @IsTest
    static void shouldRejectSosl_WhenSystemMode() {
        assertSoslRejected('FIND {Acme} RETURNING Account(Id) WITH SYSTEM_MODE', 'WITH SYSTEM_MODE');
    }

    @IsTest
    static void shouldRejectSosl_WhenMultipleStatements() {
        assertSoslRejected('FIND {Acme} RETURNING Account(Id); FIND {Beta}', '「;」');
    }

    @IsTest
    static void shouldRejectSosl_WhenBindVariable() {
        assertSoslRejected('FIND :term RETURNING Account(Id)', 'バインド変数');
    }

    // ─── SOSL: 許可と件数上限 ───────────────────────────────────────

    @IsTest
    static void shouldAcceptSosl_WhenSearchTermHasKeywords() {
        String search = 'FIND {UPDATE TRACKING \\} ; :x} RETURNING Account(Id, Name WHERE CreatedDate = LAST_N_DAYS:30)';

        Assert.areEqual(search + APPENDED_LIMIT, ReadQueryGuard.prepareSosl(search), '検索語の中の語句・記号では拒否しない');
    }

    @IsTest
    static void shouldIgnoreReturningLimit_WhenSoslHasNoOuterLimit() {
        String search = 'FIND {Acme} IN NAME FIELDS RETURNING Account(Id, Name LIMIT 500), Contact(Id, Name, Email)';

        Assert.areEqual(search + APPENDED_LIMIT, ReadQueryGuard.prepareSosl(search), 'RETURNING 句のオブジェクトごとの LIMIT は外側の LIMIT とみなさない');
    }

    @IsTest
    static void shouldKeepLimit_WhenSoslLimitIsWithinMax() {
        String search = 'FIND {Acme} RETURNING Account(Id) LIMIT 20';

        Assert.areEqual(search, ReadQueryGuard.prepareSosl(search), '上限以下の LIMIT はそのまま');
    }

    @IsTest
    static void shouldReplaceLimit_WhenSoslLimitExceedsMax() {
        Assert.areEqual(
            'FIND {Acme} RETURNING Account(Id) LIMIT ' + ReadQueryGuard.FETCH_LIMIT,
            ReadQueryGuard.prepareSosl('FIND {Acme} RETURNING Account(Id) LIMIT 2000'),
            '上限を超える LIMIT は上限 + 1 件に置き換える'
        );
    }

    // ─── 結果の切り詰め ─────────────────────────────────────────────

    @IsTest
    static void shouldKeepRecords_WhenWithinMax() {
        List<SObject> fetched = TestDataFactory.createAccounts(ReadQueryGuard.MAX_RECORDS, false);

        Assert.areEqual(ReadQueryGuard.MAX_RECORDS, ReadQueryGuard.keepWithinLimit(fetched).size(), '上限以下ならそのまま');
    }

    @IsTest
    static void shouldCutRecords_WhenOverMax() {
        List<SObject> fetched = TestDataFactory.createAccounts(ReadQueryGuard.FETCH_LIMIT, false);

        List<SObject> kept = ReadQueryGuard.keepWithinLimit(fetched);

        Assert.areEqual(ReadQueryGuard.MAX_RECORDS, kept.size(), '上限の件数に切り詰める');
        Assert.areEqual(fetched[0].get('Name'), kept[0].get('Name'), '先頭から残す');
    }

    // ─── Helpers ─────────────────────────────────────────────────

    private static void assertSoqlRejected(String query, String expectedReason) {
        try {
            ReadQueryGuard.prepareSoql(query);
            Assert.fail('拒否されるはずのクエリが通った: ' + query);
        } catch (ReadToolException e) {
            Assert.isTrue(e.getMessage().contains(expectedReason), '拒否の理由に「' + expectedReason + '」を含む: ' + e.getMessage());
        }
    }

    private static void assertSoslRejected(String search, String expectedReason) {
        try {
            ReadQueryGuard.prepareSosl(search);
            Assert.fail('拒否されるはずのクエリが通った: ' + search);
        } catch (ReadToolException e) {
            Assert.isTrue(e.getMessage().contains(expectedReason), '拒否の理由に「' + expectedReason + '」を含む: ' + e.getMessage());
        }
    }
}
