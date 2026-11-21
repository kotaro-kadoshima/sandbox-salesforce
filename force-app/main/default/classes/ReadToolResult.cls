/**
 * 読み取り専用 MCP ツール（soqlQuery・find・listRecentSobjectRecords）で共通の応答。
 * どの経路で作っても、コンストラクタで必ず注意喚起が入る。
 * MCP サーバーのツールの出力として公開するため、global にする。
 */
global with sharing class ReadToolResult {
    /** 1 回の呼び出しで処理する入力の上限 */
    public static final Integer MAX_INPUTS_PER_CALL = 10;

    @InvocableVariable(label='Notice Title' description='Title of the data-handling notice.')
    public String noticeTitle;

    @InvocableVariable(label='Notice: Confidential' description='Data-handling notice: the data may contain confidential information.')
    public String noticeConfidential;

    @InvocableVariable(label='Notice: Share Check' description='Data-handling notice: check the recipients and the content before sharing.')
    public String noticeShareCheck;

    @InvocableVariable(label='Notice: Responsibility' description='Data-handling notice: the user is responsible for handling the data.')
    public String noticeResponsibility;

    @InvocableVariable(label='Succeeded' description='True when the query ran. False when the input was rejected or the query failed.')
    public Boolean succeeded;

    @InvocableVariable(label='Error Message' description='Why the call failed. Empty when it succeeded.')
    public String errorMessage;

    @InvocableVariable(label='Record Count' description='Number of records returned. For SELECT COUNT() queries, the number of matching records.')
    public Integer recordCount;

    @InvocableVariable(label='Truncated' description='True when more records matched than the limit of 200 and the result was cut off.')
    public Boolean truncated;

    @InvocableVariable(label='Result JSON' description='The result as a JSON string.')
    public String resultJson;

    /**
     * 注意喚起を入れた、空の失敗の応答を作る。成功・失敗の項目は success / failure で上書きする。
     */
    global ReadToolResult() {
        DataHandlingNotice.applyTo(this);
        this.succeeded = false;
        this.recordCount = 0;
        this.truncated = false;
        this.resultJson = '[]';
    }

    /**
     * 成功の応答を作る。
     * @param resultJson 結果の JSON 文字列
     * @param recordCount 返したレコード数（SELECT COUNT() では一致した件数）
     * @param truncated 件数上限で打ち切ったか
     * @return 注意喚起付きの成功の応答
     */
    public static ReadToolResult success(String resultJson, Integer recordCount, Boolean truncated) {
        ReadToolResult result = new ReadToolResult();
        result.succeeded = true;
        result.resultJson = resultJson;
        result.recordCount = recordCount;
        result.truncated = truncated;
        return result;
    }

    /**
     * 失敗の応答を作る。
     * @param errorMessage 失敗の理由
     * @return 注意喚起付きの失敗の応答
     */
    public static ReadToolResult failure(String errorMessage) {
        ReadToolResult result = new ReadToolResult();
        result.errorMessage = errorMessage;
        return result;
    }

    /**
     * 入力件数の上限を超えたため処理しなかった入力への応答を作る。
     * @return 注意喚起付きの失敗の応答
     */
    public static ReadToolResult skippedOverInputLimit() {
        return failure(
            '1 回の呼び出しで処理できる入力は ' + MAX_INPUTS_PER_CALL + ' 件までです。この入力は処理していません。入力は 1 件ずつ送ってください。'
        );
    }
}
