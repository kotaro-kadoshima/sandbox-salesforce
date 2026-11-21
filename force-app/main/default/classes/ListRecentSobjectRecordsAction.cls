/**
 * sobject-reads の listRecentSobjectRecords を再現する Invocable アクション。
 * 指定した種類のレコードのうち、実行ユーザーが最近表示または参照したもの（RecentlyViewed）を新しい順に返す。
 * 履歴に残っていても現時点で参照できないレコードは、UserRecordAccess で確認し直して除く。
 * カスタム MCP サーバーのツールとして公開するため、クラスとメソッドは global にする。
 */
global with sharing class ListRecentSobjectRecordsAction {
    @InvocableMethod(
        label='List Recent SObject Records'
        description='Returns records of a specific type that the user recently viewed or modified. Use this as a starting point when the user refers to "my accounts," "recent cases," or "that opportunity I was looking at" without providing specific IDs or names.'
        category='Read Only Records'
    )
    global static List<ReadToolResult> listRecentSobjectRecords(List<Input> inputs) {
        List<ReadToolResult> results = new List<ReadToolResult>();
        for (Integer index = 0; index < inputs.size(); index++) {
            // 入力ごとにオブジェクトが違うのでまとめて取得しない。実行回数は入力件数の上限で抑える
            results.add(index < ReadToolResult.MAX_INPUTS_PER_CALL ? run(inputs[index]) : ReadToolResult.skippedOverInputLimit());
        }
        return results;
    }

    private static ReadToolResult run(Input input) {
        try {
            String sobjectName = resolveReadableObject(input?.sobjectName);
            Integer fetchLimit = ReadQueryGuard.FETCH_LIMIT;
            List<RecentlyViewed> fetched = [
                SELECT Id, Name, Type, LastViewedDate
                FROM RecentlyViewed
                WHERE Type = :sobjectName
                WITH USER_MODE
                ORDER BY LastViewedDate DESC NULLS LAST
                LIMIT :fetchLimit
            ];
            List<SObject> recentRecords = ReadQueryGuard.keepWithinLimit(fetched);
            List<SObject> readableRecords = keepReadable(recentRecords);
            return ReadToolResult.success(JSON.serialize(readableRecords), readableRecords.size(), fetched.size() > recentRecords.size());
        } catch (Exception e) {
            // 拒否・権限エラー・クエリエラーのどれでも、注意喚起付きの失敗の応答にする
            return ReadToolResult.failure(e.getMessage());
        }
    }

    /**
     * オブジェクトの API 名を確かめ、正式な表記で返す。
     * 存在しないオブジェクトと参照できないオブジェクトは、同じメッセージで拒否する。
     */
    private static String resolveReadableObject(String sobjectName) {
        if (String.isBlank(sobjectName)) {
            throw new ReadToolException('sobjectName にオブジェクトの API 名を指定してください（例: Account）。');
        }
        String notReadableMessage = 'オブジェクト「' + sobjectName + '」は存在しないか、参照する権限がありません。';
        Schema.DescribeSObjectResult describe;
        try {
            // 項目の情報は使わないので、遅延読み込みにする
            describe = Schema.describeSObjects(new List<String>{ sobjectName.trim() }, SObjectDescribeOptions.DEFERRED)[0];
        } catch (InvalidParameterValueException e) {
            throw new ReadToolException(notReadableMessage, e);
        }
        if (!describe.isAccessible()) {
            throw new ReadToolException(notReadableMessage);
        }
        return describe.getName();
    }

    /**
     * 現時点で実行ユーザーが参照できるレコードだけを、並び順を保ったまま残す。
     */
    private static List<SObject> keepReadable(List<SObject> recentRecords) {
        if (recentRecords.isEmpty()) {
            return recentRecords;
        }
        Id userId = UserInfo.getUserId();
        Set<Id> recordIds = new Map<Id, SObject>(recentRecords).keySet();
        Set<Id> readableIds = new Set<Id>();
        // UserRecordAccess は RecordId を 1 回 200 件まで指定できる。件数上限（200 件）の範囲に収まる
        for (UserRecordAccess access : [
            SELECT RecordId, HasReadAccess
            FROM UserRecordAccess
            WHERE UserId = :userId AND RecordId IN :recordIds
            WITH USER_MODE
        ]) {
            if (access.HasReadAccess) {
                readableIds.add(access.RecordId);
            }
        }
        List<SObject> readableRecords = new List<SObject>();
        for (SObject record : recentRecords) {
            if (readableIds.contains(record.Id)) {
                readableRecords.add(record);
            }
        }
        return readableRecords;
    }

    global class Input {
        @InvocableVariable(label='SObject Name' description='API name of the object (e.g., Account, Case, Opportunity)' required=true)
        public String sobjectName;
    }
}
