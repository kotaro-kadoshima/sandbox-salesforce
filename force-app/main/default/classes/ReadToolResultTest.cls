@IsTest
public class ReadToolResultTest {
    @IsTest
    static void shouldIncludeNotice_WhenCreated() {
        // When
        Test.startTest();
        ReadToolResult result = new ReadToolResult();
        Test.stopTest();

        // Then
        assertNotice(result);
        Assert.isFalse(result.succeeded, '生成直後は成功扱いにしない');
        Assert.areEqual(0, result.recordCount, '生成直後の件数は 0');
        Assert.isFalse(result.truncated, '生成直後は打ち切りなし');
        Assert.areEqual('[]', result.resultJson, '生成直後の結果は空の配列');
    }

    @IsTest
    static void shouldIncludeNotice_WhenSuccess() {
        // When
        Test.startTest();
        ReadToolResult result = ReadToolResult.success('[{"Id":"001"}]', 1, true);
        Test.stopTest();

        // Then
        assertNotice(result);
        Assert.isTrue(result.succeeded, '成功の応答');
        Assert.areEqual('[{"Id":"001"}]', result.resultJson, '渡した JSON がそのまま入る');
        Assert.areEqual(1, result.recordCount, '渡した件数がそのまま入る');
        Assert.isTrue(result.truncated, '渡した打ち切りの有無がそのまま入る');
        Assert.isNull(result.errorMessage, '成功時はエラーメッセージなし');
    }

    @IsTest
    static void shouldIncludeNotice_WhenFailure() {
        // When
        Test.startTest();
        ReadToolResult result = ReadToolResult.failure('クエリが不正です');
        Test.stopTest();

        // Then
        assertNotice(result);
        Assert.isFalse(result.succeeded, '失敗の応答');
        Assert.areEqual('クエリが不正です', result.errorMessage, '渡した理由がそのまま入る');
        Assert.areEqual(0, result.recordCount, '失敗時の件数は 0');
    }

    @IsTest
    static void shouldIncludeNotice_WhenSkippedOverInputLimit() {
        // When
        Test.startTest();
        ReadToolResult result = ReadToolResult.skippedOverInputLimit();
        Test.stopTest();

        // Then
        assertNotice(result);
        Assert.isFalse(result.succeeded, '処理しなかった入力は失敗扱い');
        Assert.isTrue(
            result.errorMessage.contains(String.valueOf(ReadToolResult.MAX_INPUTS_PER_CALL)),
            '上限の件数を理由に含める'
        );
    }

    /**
     * 注意喚起の 4 項目が、カスタム表示ラベルと同じ値で入っていることを確かめる。
     * 他のテストクラスからも使う。
     */
    public static void assertNotice(ReadToolResult result) {
        Assert.areEqual(System.Label.DataNotice_Title, result.noticeTitle, '見出しはラベルの値');
        Assert.areEqual(System.Label.DataNotice_Confidential, result.noticeConfidential, '機密情報の注意はラベルの値');
        Assert.areEqual(System.Label.DataNotice_ShareCheck, result.noticeShareCheck, '共有前の確認はラベルの値');
        Assert.areEqual(System.Label.DataNotice_Responsibility, result.noticeResponsibility, '責任の所在はラベルの値');
        Assert.isFalse(String.isBlank(result.noticeTitle), '見出しが空でない');
    }
}
