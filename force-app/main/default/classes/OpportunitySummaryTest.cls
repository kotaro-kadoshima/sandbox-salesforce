@IsTest
private class OpportunitySummaryTest {
    @IsTest
    static void sumsOnlyOpenOpportunities() {
        Account acc = new Account(Name = 'Test Co');
        insert acc;
        insert new List<Opportunity>{
            new Opportunity(Name = 'A', AccountId = acc.Id, StageName = 'Prospecting', CloseDate = Date.today().addDays(30), Amount = 100),
            new Opportunity(Name = 'B', AccountId = acc.Id, StageName = 'Prospecting', CloseDate = Date.today().addDays(30), Amount = 250),
            new Opportunity(Name = 'C', AccountId = acc.Id, StageName = 'Closed Won', CloseDate = Date.today(), Amount = 1000)
        };

        Test.startTest();
        Map<Id, Decimal> totals = OpportunitySummary.openAmountByAccount(new Set<Id>{ acc.Id });
        Test.stopTest();

        Assert.areEqual(350, totals.get(acc.Id), 'クローズ済みの商談は合計に含めない');
    }
}