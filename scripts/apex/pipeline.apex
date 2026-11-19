GetAccountPipelineAction.Input input = new GetAccountPipelineAction.Input();
input.accountName = '青空モビリティ';
List<GetAccountPipelineAction.Output> outputs =
    GetAccountPipelineAction.getPipeline(new List<GetAccountPipelineAction.Input>{ input });
System.debug(JSON.serializePretty(outputs));