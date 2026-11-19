public with sharing class OpportunitySummary {
    // 取引先ごとに「未クローズ商談」の金額合計を返す
    public static Map<Id, Decimal> openAmountByAccount(Set<Id> accountIds) {
        Map<Id, Decimal> result = new Map<Id, Decimal>();
        for (AggregateResult ar : [
            SELECT AccountId accId, SUM(Amount) total
            FROM Opportunity
            WHERE AccountId IN :accountIds AND IsClosed = false
            GROUP BY AccountId
        ]) {
            result.put((Id) ar.get('accId'), (Decimal) ar.get('total'));
        }
        return result;
    }
}