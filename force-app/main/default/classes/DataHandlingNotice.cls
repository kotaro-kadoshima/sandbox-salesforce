/**
 * MCP ツールの応答に付ける、機密情報の取り扱いに関する注意喚起。
 * 文言はカスタム表示ラベル（カテゴリ McpDataNotice）で管理し、コードには書かない。
 */
public with sharing class DataHandlingNotice {
    /**
     * 応答に注意喚起の 4 項目を入れる。結果や利用者によって出し分けないため、条件分岐は持たない。
     * @param result 注意喚起を入れる応答
     */
    public static void applyTo(ReadToolResult result) {
        result.noticeTitle = System.Label.DataNotice_Title;
        result.noticeConfidential = System.Label.DataNotice_Confidential;
        result.noticeShareCheck = System.Label.DataNotice_ShareCheck;
        result.noticeResponsibility = System.Label.DataNotice_Responsibility;
    }
}
