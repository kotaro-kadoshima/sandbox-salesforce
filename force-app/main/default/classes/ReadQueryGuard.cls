/**
 * 読み取り専用 MCP ツールに渡された SOQL と SOSL を、実行前に確かめて整える。
 * 役割は「副作用のある句・システムモード・バインド変数の拒否」と「件数上限の適用」だけで、
 * 権限の判定は実行時の USER_MODE にまかせる。構文の誤りは Salesforce 側のエラーとして返す。
 */
public with sharing class ReadQueryGuard {
    /** 1 回の実行で返すレコードの上限 */
    public static final Integer MAX_RECORDS = 200;
    /** 打ち切りを判定するため、上限より 1 件多く取得する */
    public static final Integer FETCH_LIMIT = MAX_RECORDS + 1;

    // マスクの埋め文字。英数字ではないので、キーワードの前後の境界（\b）を変えない
    private static final String MASK = '#';
    private static final Integer OPEN_PAREN = '('.charAt(0);
    private static final Integer CLOSE_PAREN = ')'.charAt(0);

    // 文字列リテラル（'...'、\' のエスケープを含む）。閉じていないものは末尾まで
    private static final Pattern SOQL_LITERAL = Pattern.compile('(?s)\'(?:\\\\.|[^\'\\\\])*\'?');
    // SOSL では、文字列リテラルに加えて検索語の {...}（\} のエスケープを含む）もリテラルとして扱う
    private static final Pattern SOSL_LITERAL = Pattern.compile(
        '(?s)\'(?:\\\\.|[^\'\\\\])*\'?|\\{(?:\\\\.|[^}\\\\])*\\}?'
    );

    private static final Pattern SELECT_START = Pattern.compile('(?i)^\\s*SELECT\\b');
    private static final Pattern FIND_START = Pattern.compile('(?i)^\\s*FIND\\b');
    private static final Pattern COUNT_ONLY = Pattern.compile('(?i)^\\s*SELECT\\s+COUNT\\s*\\(\\s*\\)\\s+FROM\\b');
    // FOR VIEW・FOR REFERENCE・UPDATE TRACKING・UPDATE VIEWSTAT は閲覧日時などを更新する。
    // FOR UPDATE・ALL ROWS は Apex 専用の構文で、REST の query（sobject-reads）でも使えない
    private static final Pattern SOQL_FORBIDDEN_CLAUSE = Pattern.compile(
        '(?i)\\b(?:FOR\\s+(?:VIEW|REFERENCE|UPDATE)|UPDATE\\s+(?:TRACKING|VIEWSTAT)|ALL\\s+ROWS)\\b'
    );
    private static final Pattern SOSL_FORBIDDEN_CLAUSE = Pattern.compile('(?i)\\bUPDATE\\s+(?:TRACKING|VIEWSTAT)\\b');
    private static final Pattern SYSTEM_MODE = Pattern.compile('(?i)\\bWITH\\s+SYSTEM_MODE\\b');
    // バインド変数は「:」の直後に英字か _ が続く。日付リテラル（LAST_N_DAYS:30）は直後が数字
    private static final Pattern BIND_VARIABLE = Pattern.compile(':\\s*[A-Za-z_]');
    // 集計関数と GROUP BY はサブクエリに書けないので、外側のクエリだけに現れる
    private static final Pattern AGGREGATE_FUNCTION = Pattern.compile('(?i)\\b(?:COUNT|COUNT_DISTINCT|SUM|AVG|MIN|MAX)\\s*\\(');
    private static final Pattern GROUP_BY = Pattern.compile('(?i)\\bGROUP\\s+BY\\b');
    private static final Pattern OUTER_LIMIT = Pattern.compile('(?i)\\bLIMIT\\s+(\\d+)\\b');
    private static final Pattern OUTER_OFFSET = Pattern.compile('(?i)\\bOFFSET\\b');

    /**
     * SOQL を確かめ、件数上限を適用したクエリを返す。
     * @param query MCP クライアントから渡された SOQL
     * @return 実行するクエリと、SELECT COUNT() かどうか
     * @throws ReadToolException 読み取り以外の句やバインド変数を含むとき
     */
    public static SoqlQuery prepareSoql(String query) {
        if (String.isBlank(query)) {
            throw new ReadToolException('SOQL の SELECT 文を query に指定してください。');
        }
        String literalMasked = maskLiterals(query, SOQL_LITERAL);
        if (!SELECT_START.matcher(literalMasked).find()) {
            throw new ReadToolException('SOQL は SELECT 文だけを実行できます。');
        }
        rejectUnsafeClauses(literalMasked, SOQL_FORBIDDEN_CLAUSE);
        if (COUNT_ONLY.matcher(literalMasked).find()) {
            return new SoqlQuery(query, true);
        }
        String outerMasked = maskParentheses(literalMasked);
        if (AGGREGATE_FUNCTION.matcher(literalMasked).find() && !GROUP_BY.matcher(literalMasked).find()) {
            // GROUP BY のない集計は 1 行だけ返すので上限を超えない。
            // LIMIT を付けると Salesforce が捕捉できない例外（UnexpectedException）を投げ、注意喚起も返せないため、実行前に止める
            if (OUTER_LIMIT.matcher(outerMasked).find()) {
                throw new ReadToolException('GROUP BY のない集計クエリには LIMIT を付けられません。LIMIT を取り除いてください。');
            }
            return new SoqlQuery(query, false);
        }
        return new SoqlQuery(applyRecordLimit(query, outerMasked, true), false);
    }

    /**
     * SOSL を確かめ、件数上限を適用したクエリを返す。
     * @param search MCP クライアントから渡された SOSL
     * @return 実行するクエリ
     * @throws ReadToolException 読み取り以外の句やバインド変数を含むとき
     */
    public static String prepareSosl(String search) {
        if (String.isBlank(search)) {
            throw new ReadToolException('SOSL の FIND 文を search に指定してください。');
        }
        String literalMasked = maskLiterals(search, SOSL_LITERAL);
        if (!FIND_START.matcher(literalMasked).find()) {
            throw new ReadToolException('SOSL は FIND 文だけを実行できます。');
        }
        rejectUnsafeClauses(literalMasked, SOSL_FORBIDDEN_CLAUSE);
        // SOSL の外側には OFFSET がない（オブジェクトごとの OFFSET は RETURNING 句の括弧の中）
        return applyRecordLimit(search, maskParentheses(literalMasked), false);
    }

    /**
     * 上限より 1 件多く取得した結果を、上限の件数までに切り詰める。
     * @param fetched FETCH_LIMIT 件まで取得したレコード
     * @return 先頭から MAX_RECORDS 件まで。上限以下ならそのまま
     */
    public static List<SObject> keepWithinLimit(List<SObject> fetched) {
        if (fetched.size() <= MAX_RECORDS) {
            return fetched;
        }
        List<SObject> kept = new List<SObject>();
        for (Integer index = 0; index < MAX_RECORDS; index++) {
            kept.add(fetched[index]);
        }
        return kept;
    }

    private static void rejectUnsafeClauses(String literalMasked, Pattern forbiddenClause) {
        if (literalMasked.contains(';')) {
            throw new ReadToolException('複数の文は実行できません。「;」を取り除いてください。');
        }
        Matcher forbidden = forbiddenClause.matcher(literalMasked);
        if (forbidden.find()) {
            throw new ReadToolException('読み取り専用のため、「' + forbidden.group(0) + '」を含むクエリは実行できません。');
        }
        if (SYSTEM_MODE.matcher(literalMasked).find()) {
            throw new ReadToolException('実行ユーザーの権限で実行するため、WITH SYSTEM_MODE は指定できません。');
        }
        if (BIND_VARIABLE.matcher(literalMasked).find()) {
            throw new ReadToolException('バインド変数（:名前）は使えません。値をクエリに直接書いてください。');
        }
    }

    /**
     * 外側の LIMIT を上限に合わせる。書き換えるのは LIMIT の数値だけで、利用者のクエリに別の文字列は足さない。
     * 位置は、元のクエリと同じ長さのマスク済みの文字列で探す。
     */
    private static String applyRecordLimit(String original, String outerMasked, Boolean hasOuterOffset) {
        Matcher limitMatcher = OUTER_LIMIT.matcher(outerMasked);
        if (limitMatcher.find()) {
            if (Decimal.valueOf(limitMatcher.group(1)) <= MAX_RECORDS) {
                return original;
            }
            return original.substring(0, limitMatcher.start(1)) + FETCH_LIMIT + original.substring(limitMatcher.end(1));
        }
        if (hasOuterOffset) {
            // LIMIT は OFFSET より前に書く必要がある
            Matcher offsetMatcher = OUTER_OFFSET.matcher(outerMasked);
            if (offsetMatcher.find()) {
                return original.substring(0, offsetMatcher.start()) + 'LIMIT ' + FETCH_LIMIT + ' ' + original.substring(offsetMatcher.start());
            }
        }
        // FOR・UPDATE の句は拒否済みなので、末尾が LIMIT の正しい位置になる
        return original.trim() + ' LIMIT ' + FETCH_LIMIT;
    }

    /**
     * リテラルの中身を埋め文字に置き換える。長さを変えないので、見つけた位置を元のクエリにそのまま使える。
     */
    private static String maskLiterals(String text, Pattern literal) {
        List<String> parts = new List<String>();
        Matcher matcher = literal.matcher(text);
        Integer segmentStart = 0;
        while (matcher.find()) {
            parts.add(text.substring(segmentStart, matcher.start()));
            // 開き記号だけ残す
            parts.add(text.substring(matcher.start(), matcher.start() + 1) + MASK.repeat(matcher.end() - matcher.start() - 1));
            segmentStart = matcher.end();
        }
        parts.add(text.substring(segmentStart));
        return String.join(parts, '');
    }

    /**
     * 括弧の中（サブクエリ・関数・RETURNING 句の項目）を埋め文字に置き換え、外側の句だけを残す。
     * リテラルはマスク済みの文字列を受け取るので、リテラル内の括弧は数えない。
     */
    private static String maskParentheses(String text) {
        List<String> parts = new List<String>();
        Integer depth = 0;
        Integer segmentStart = 0;
        for (Integer index = 0; index < text.length(); index++) {
            Integer character = text.charAt(index);
            if (character == OPEN_PAREN) {
                if (depth == 0) {
                    parts.add(text.substring(segmentStart, index + 1));
                    segmentStart = index + 1;
                }
                depth++;
            } else if (character == CLOSE_PAREN && depth > 0) {
                depth--;
                if (depth == 0) {
                    parts.add(MASK.repeat(index - segmentStart));
                    segmentStart = index;
                }
            }
        }
        // 閉じていない括弧は末尾までマスクする
        parts.add(depth > 0 ? MASK.repeat(text.length() - segmentStart) : text.substring(segmentStart));
        return String.join(parts, '');
    }

    /**
     * 実行する SOQL と、その種類。
     */
    public class SoqlQuery {
        /** 件数上限を適用したクエリ */
        public String query { get; private set; }
        /** SELECT COUNT() の形か（Database.countQueryWithBinds で数える） */
        public Boolean isCountOnly { get; private set; }

        public SoqlQuery(String query, Boolean isCountOnly) {
            this.query = query;
            this.isCountOnly = isCountOnly;
        }
    }
}
