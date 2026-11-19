Map<Id, Account> accs = new Map<Id, Account>(
    [SELECT Id, Name FROM Account WHERE Site = 'cli-handson']
);
Map<Id, Decimal> totals = OpportunitySummary.openAmountByAccount(accs.keySet());
for (Id accId : totals.keySet()) {
    System.debug(accs.get(accId).Name + ' : ' + totals.get(accId));
}