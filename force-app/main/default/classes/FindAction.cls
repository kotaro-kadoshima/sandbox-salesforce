/**
 * sobject-reads の find を再現する Invocable アクション。
 * SOSL の FIND 文を実行ユーザーの権限（USER_MODE）で実行し、オブジェクトごとのグループで、注意喚起付きの応答で返す。
 * カスタム MCP サーバーのツールとして公開するため、クラスとメソッドは global にする。
 */
global with sharing class FindAction {
    @InvocableMethod(
        label='Find'
        description='Executes a text search across multiple Salesforce objects simultaneously. Use this instead of `soqlQuery` when searching for a term that could exist in multiple object types, or when you don\'t know which object contains the data.'
        category='Read Only Records'
    )
    global static List<ReadToolResult> findRecords(List<Input> inputs) {
        List<ReadToolResult> results = new List<ReadToolResult>();
        for (Integer index = 0; index < inputs.size(); index++) {
            // 入力ごとに検索が違うのでまとめて実行できない。実行回数は入力件数の上限で抑える
            results.add(index < ReadToolResult.MAX_INPUTS_PER_CALL ? run(inputs[index]) : ReadToolResult.skippedOverInputLimit());
        }
        return results;
    }

    private static ReadToolResult run(Input input) {
        try {
            String prepared = ReadQueryGuard.prepareSosl(input?.search);
            return toResult(Search.query(prepared, AccessLevel.USER_MODE));
        } catch (Exception e) {
            // 拒否・権限エラー・検索エラーのどれでも、注意喚起付きの失敗の応答にする
            return ReadToolResult.failure(e.getMessage());
        }
    }

    /**
     * 検索結果を、レコードのあるオブジェクトごとのグループにする。合計が上限を超えた分は切り捨てる。
     */
    private static ReadToolResult toResult(List<List<SObject>> resultGroups) {
        List<SearchGroup> groups = new List<SearchGroup>();
        Integer recordCount = 0;
        Boolean truncated = false;
        for (List<SObject> records : resultGroups) {
            SearchGroup searchGroup = new SearchGroup();
            for (SObject record : records) {
                if (recordCount == ReadQueryGuard.MAX_RECORDS) {
                    truncated = true;
                    break;
                }
                searchGroup.records.add(record);
                recordCount++;
            }
            if (!searchGroup.records.isEmpty()) {
                searchGroup.sobjectType = String.valueOf(searchGroup.records[0].getSObjectType());
                groups.add(searchGroup);
            }
            if (truncated) {
                break;
            }
        }
        return ReadToolResult.success(JSON.serialize(groups), recordCount, truncated);
    }

    /** resultJson の 1 グループ（sobject-reads の「オブジェクトごとのグループ」） */
    private class SearchGroup {
        public String sobjectType;
        public List<SObject> records = new List<SObject>();
    }

    global class Input {
        @InvocableVariable(label='Search' description='A valid SOSL search string' required=true)
        public String search;
    }
}
