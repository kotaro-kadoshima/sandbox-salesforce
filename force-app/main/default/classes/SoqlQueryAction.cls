/**
 * sobject-reads の soqlQuery を再現する Invocable アクション。
 * SOQL の SELECT 文を実行ユーザーの権限（USER_MODE）で実行し、注意喚起付きの応答で返す。
 * カスタム MCP サーバーのツールとして公開するため、クラスとメソッドは global にする。
 */
global with sharing class SoqlQueryAction {
    @InvocableMethod(
        label='SOQL Query'
        description='Executes a SOQL query to retrieve Salesforce records. This is the primary way to read data when you know which object and fields you need. SOQL syntax: `SELECT fields FROM Object WHERE conditions ORDER BY field LIMIT n`. Supports relationship queries to traverse lookups and subqueries for child records. Always include a WHERE clause and a LIMIT clause. For large objects, filter on indexed fields to avoid timeout errors.'
        category='Read Only Records'
    )
    global static List<ReadToolResult> soqlQuery(List<Input> inputs) {
        List<ReadToolResult> results = new List<ReadToolResult>();
        for (Integer index = 0; index < inputs.size(); index++) {
            // 入力ごとにクエリが違うのでまとめて実行できない。実行回数は入力件数の上限で抑える
            results.add(index < ReadToolResult.MAX_INPUTS_PER_CALL ? run(inputs[index]) : ReadToolResult.skippedOverInputLimit());
        }
        return results;
    }

    private static ReadToolResult run(Input input) {
        try {
            ReadQueryGuard.SoqlQuery prepared = ReadQueryGuard.prepareSoql(input?.query);
            // バインド変数は空の Map でしか解決させず、Apex の変数を参照させない
            if (prepared.isCountOnly) {
                Integer matched = Database.countQueryWithBinds(prepared.query, new Map<String, Object>(), AccessLevel.USER_MODE);
                return ReadToolResult.success('[]', matched, false);
            }
            List<SObject> fetched = Database.queryWithBinds(prepared.query, new Map<String, Object>(), AccessLevel.USER_MODE);
            List<SObject> records = ReadQueryGuard.keepWithinLimit(fetched);
            return ReadToolResult.success(JSON.serialize(records), records.size(), fetched.size() > records.size());
        } catch (Exception e) {
            // 拒否・権限エラー・クエリエラーのどれでも、注意喚起付きの失敗の応答にする
            return ReadToolResult.failure(e.getMessage());
        }
    }

    global class Input {
        @InvocableVariable(label='Query' description='A valid SOQL query string' required=true)
        public String query;
    }
}
