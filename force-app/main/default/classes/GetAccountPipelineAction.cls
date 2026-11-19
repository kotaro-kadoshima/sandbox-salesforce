/**
 * 取引先1社の「未クローズ商談」と合計金額を返す Invocable アクション。
 * カスタム MCP サーバーのツールとして公開するため、クラスとメソッドは global にする。
 */
global with sharing class GetAccountPipelineAction {
    @InvocableMethod(
        label='Get Account Pipeline'
        description='Returns the open opportunities and their total amount for one account, looked up by (part of) the account name.'
        category='CLI Handson'
    )
    global static List<Output> getPipeline(List<Input> inputs) {
        List<Output> outputs = new List<Output>();
        // MCP からは 1 件ずつ呼ばれる前提なので、入力ごとに検索する
        for (Input input : inputs) {
            String pattern = '%' + input.accountName + '%';
            List<Account> accounts = [
                SELECT Id, Name, Industry, BillingCity,
                    (SELECT Name, StageName, CloseDate, Amount
                     FROM Opportunities
                     WHERE IsClosed = false
                     ORDER BY CloseDate)
                FROM Account
                WHERE Name LIKE :pattern
                ORDER BY Name
                LIMIT 1
            ];
            Output output = new Output();
            if (!accounts.isEmpty()) {
                output.pipeline = toPipeline(accounts[0]);
            }
            outputs.add(output);
        }
        return outputs;
    }

    private static AccountPipeline toPipeline(Account acc) {
        AccountPipeline pipeline = new AccountPipeline();
        pipeline.id = acc.Id;
        pipeline.name = acc.Name;
        pipeline.industry = acc.Industry;
        pipeline.billingCity = acc.BillingCity;
        pipeline.openAmount = 0;
        pipeline.opportunities = new List<OpportunityItem>();
        for (Opportunity opp : acc.Opportunities) {
            OpportunityItem item = new OpportunityItem();
            item.name = opp.Name;
            item.stageName = opp.StageName;
            item.closeDateLabel = opp.CloseDate?.format();
            item.amount = opp.Amount;
            item.amountLabel = toYen(opp.Amount);
            pipeline.opportunities.add(item);
            pipeline.openAmount += (opp.Amount == null ? 0 : opp.Amount);
        }
        pipeline.openCount = pipeline.opportunities.size();
        pipeline.openAmountLabel = toYen(pipeline.openAmount);
        pipeline.accountRecordLink =
            URL.getOrgDomainUrl().toExternalForm() + '/lightning/r/Account/' + acc.Id + '/view';
        return pipeline;
    }

    private static String toYen(Decimal value) {
        return value == null ? '-' : '¥' + value.setScale(0).format();
    }

    global class Input {
        @InvocableVariable(label='Account Name' description='Account name or part of it, for example 北斗電機' required=true)
        public String accountName;
    }

    global class Output {
        @InvocableVariable(label='Pipeline' description='Open opportunities of the account. Empty when no account matches.')
        public AccountPipeline pipeline;
    }

    global class AccountPipeline {
        @InvocableVariable
        public String id;
        @InvocableVariable
        public String name;
        @InvocableVariable
        public String industry;
        @InvocableVariable
        public String billingCity;
        @InvocableVariable
        public Decimal openAmount;
        @InvocableVariable
        public String openAmountLabel;
        @InvocableVariable
        public Integer openCount;
        @InvocableVariable
        public List<OpportunityItem> opportunities;
        @InvocableVariable
        public String accountRecordLink;
    }

    global class OpportunityItem {
        @InvocableVariable
        public String name;
        @InvocableVariable
        public String stageName;
        @InvocableVariable
        public String closeDateLabel;
        @InvocableVariable
        public Decimal amount;
        @InvocableVariable
        public String amountLabel;
    }
}