@IsTest
private class GetAccountPipelineActionTest {
    @IsTest
    static void returnsOnlyOpenOpportunities() {
        Account acc = new Account(Name = 'テスト工業株式会社');
        insert acc;
        insert new List<Opportunity>{
            new Opportunity(Name = 'A', AccountId = acc.Id, StageName = 'Prospecting', CloseDate = Date.today().addDays(30), Amount = 100),
            new Opportunity(Name = 'B', AccountId = acc.Id, StageName = 'Prospecting', CloseDate = Date.today().addDays(60), Amount = 250),
            new Opportunity(Name = 'C', AccountId = acc.Id, StageName = 'Closed Won', CloseDate = Date.today(), Amount = 1000)
        };

        GetAccountPipelineAction.Input input = new GetAccountPipelineAction.Input();
        input.accountName = 'テスト工業';

        Test.startTest();
        List<GetAccountPipelineAction.Output> outputs =
            GetAccountPipelineAction.getPipeline(new List<GetAccountPipelineAction.Input>{ input });
        Test.stopTest();

        GetAccountPipelineAction.AccountPipeline pipeline = outputs[0].pipeline;
        Assert.areEqual(acc.Id, pipeline.id);
        Assert.areEqual(2, pipeline.openCount, 'クローズ済みの商談は含めない');
        Assert.areEqual(350, pipeline.openAmount);
    }

    @IsTest
    static void returnsEmptyWhenNoAccountMatches() {
        GetAccountPipelineAction.Input input = new GetAccountPipelineAction.Input();
        input.accountName = '存在しない会社';

        List<GetAccountPipelineAction.Output> outputs =
            GetAccountPipelineAction.getPipeline(new List<GetAccountPipelineAction.Input>{ input });

        Assert.isNull(outputs[0].pipeline);
    }
}