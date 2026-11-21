/**
 * テストデータを作る共通のファクトリ。
 */
@IsTest
public class TestDataFactory {
    /** createAccounts で作る取引先の名前の先頭 */
    public static final String ACCOUNT_NAME_PREFIX = 'Read Tool Account ';

    /**
     * 取引先を作る。名前は ACCOUNT_NAME_PREFIX + 3 桁の連番（000 から）。
     * @param count 作る件数
     * @param doInsert true なら登録する（重複ルールの警告では止めない）
     * @return 作った取引先
     */
    public static List<Account> createAccounts(Integer count, Boolean doInsert) {
        List<Account> accounts = new List<Account>();
        for (Integer index = 0; index < count; index++) {
            accounts.add(new Account(Name = ACCOUNT_NAME_PREFIX + String.valueOf(index).leftPad(3, '0')));
        }
        if (doInsert) {
            Database.DMLOptions options = new Database.DMLOptions();
            options.DuplicateRuleHeader.allowSave = true;
            Database.insert(accounts, options);
        }
        return accounts;
    }

    /**
     * 取引先責任者を作る。姓は ACCOUNT_NAME_PREFIX + 3 桁の連番（000 から）。
     * @param count 作る件数
     * @param doInsert true なら登録する（重複ルールの警告では止めない）
     * @return 作った取引先責任者
     */
    public static List<Contact> createContacts(Integer count, Boolean doInsert) {
        List<Contact> contacts = new List<Contact>();
        for (Integer index = 0; index < count; index++) {
            contacts.add(new Contact(LastName = ACCOUNT_NAME_PREFIX + String.valueOf(index).leftPad(3, '0')));
        }
        if (doInsert) {
            Database.DMLOptions options = new Database.DMLOptions();
            options.DuplicateRuleHeader.allowSave = true;
            Database.insert(contacts, options);
        }
        return contacts;
    }

    /**
     * 取引先の参照権限を持たないプロファイルのユーザーを作って登録する。
     * プロファイルの名前は組織の言語で変わるため、ライセンスと権限の条件で選ぶ。
     * 設定オブジェクトの DML なので、取引先などとは別の System.runAs の中で呼ぶ。
     * @return 登録したユーザー
     */
    public static User createUserWithoutAccountRead() {
        Set<Id> excludedProfileIds = new Set<Id>();
        for (ObjectPermissions permission : [
            SELECT Parent.ProfileId
            FROM ObjectPermissions
            WHERE Parent.IsOwnedByProfile = true AND SobjectType = 'Account' AND PermissionsRead = true
        ]) {
            excludedProfileIds.add(permission.Parent.ProfileId);
        }
        Profile profile = [
            SELECT Id
            FROM Profile
            WHERE UserLicense.LicenseDefinitionKey = 'SFDC' AND PermissionsViewAllData = false AND Id NOT IN :excludedProfileIds
            ORDER BY CreatedDate
            LIMIT 1
        ];
        String uniqueKey = String.valueOf(Crypto.getRandomInteger()).remove('-');
        User user = new User(
            ProfileId = profile.Id,
            LastName = 'Read Tool User',
            Alias = 'rtuser',
            Email = 'readtool' + uniqueKey + '@example.com',
            Username = 'readtool' + uniqueKey + '@example.com.test',
            TimeZoneSidKey = 'Asia/Tokyo',
            LocaleSidKey = 'ja_JP',
            LanguageLocaleKey = 'en_US',
            EmailEncodingKey = 'UTF-8'
        );
        insert user;
        return user;
    }

    /**
     * 指定したプロファイルでは参照できず、テストを実行するユーザーは参照できる取引先の項目を 1 つ返す。
     * どの項目が該当するかは組織の項目レベルセキュリティで変わるため、項目名を決め打ちしない。
     * @param profileId 参照できないことを確かめるプロファイル
     * @return 項目の API 名（名前順で最初のもの）
     */
    public static String findAccountFieldHiddenFrom(Id profileId) {
        Set<String> readableFields = new Set<String>();
        for (FieldPermissions permission : [
            SELECT Field
            FROM FieldPermissions
            WHERE Parent.ProfileId = :profileId AND SobjectType = 'Account' AND PermissionsRead = true
        ]) {
            readableFields.add(permission.Field);
        }
        List<String> candidates = new List<String>();
        for (Schema.SObjectField field : Schema.SObjectType.Account.fields.getMap().values()) {
            Schema.DescribeFieldResult describe = field.getDescribe();
            if (describe.isPermissionable() && describe.isAccessible() && !readableFields.contains('Account.' + describe.getName())) {
                candidates.add(describe.getName());
            }
        }
        Assert.isFalse(candidates.isEmpty(), '前提: プロファイルが参照できない取引先の項目がある');
        candidates.sort();
        return candidates[0];
    }

    /**
     * 取引先の参照権限だけを持つ権限セットを作り、ユーザーに割り当てる（項目の参照権限は付けない）。
     * 設定オブジェクトの DML なので、取引先などとは別の System.runAs の中で呼ぶ。
     * @param user 割り当てるユーザー
     */
    public static void grantAccountReadOnly(User user) {
        PermissionSet permissionSet = new PermissionSet(Name = 'ReadToolAccountRead', Label = 'Read Tool Account Read');
        insert permissionSet;
        insert new ObjectPermissions(ParentId = permissionSet.Id, SobjectType = 'Account', PermissionsRead = true);
        insert new PermissionSetAssignment(AssigneeId = user.Id, PermissionSetId = permissionSet.Id);
    }
}
