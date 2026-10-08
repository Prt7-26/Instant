import AppKit
import Combine
import InstantCore

final class SettingsStore: ObservableObject {
    static let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Instant", isDirectory: true)
    static let file = directory.appendingPathComponent("settings.json")
    static let defaultArchiveDirectory = directory.appendingPathComponent("Conversations", isDirectory: true)

    @Published var value: AppConfiguration { didSet { save(); onChange?() } }
    @Published var apiKey: String = "" { didSet { scheduleKeySave() } }
    @Published var error: String?
    @Published var shortcutError = false
    var onChange: (() -> Void)?
    private var keySave: DispatchWorkItem?
    private var ready = false
    private var keyDirty = false
    private var credentialError: String?
    private let configurationFile: URL
    private let keychainEnabled: Bool
    private let keyWriter: (String) throws -> Void
    private(set) var keychainReadFailed = false
    var language: Language { Language.resolve(value.language) }
    var l10n: L10n { L10n(language: language) }
    var connection: ConnectionConfiguration {
        ConnectionConfiguration(baseURL: value.baseURL, key: apiKey, model: value.model)
    }
    var connectionIssue: ConnectionIssue? {
        if keychainReadFailed && connection.key.isEmpty { return .keychainUnavailable }
        return connection.issue
    }
    var archiveDirectory: URL {
        value.archiveFolderPath.isEmpty ? Self.defaultArchiveDirectory
            : URL(fileURLWithPath: (value.archiveFolderPath as NSString).expandingTildeInPath, isDirectory: true)
    }

    func chooseArchiveFolder() {
        let picker = NSOpenPanel()
        picker.canChooseFiles = false
        picker.canChooseDirectories = true
        picker.allowsMultipleSelection = false
        picker.canCreateDirectories = true
        picker.directoryURL = archiveDirectory
        picker.prompt = l10n["chooseFolder"]
        if picker.runModal() == .OK, let url = picker.url { value.archiveFolderPath = url.path }
    }
    func openArchiveFolder() {
        do {
            _ = try ConversationStore(directory: archiveDirectory)
            NSWorkspace.shared.open(archiveDirectory)
        } catch { self.error = error.localizedDescription }
    }

    init(readKeychain: Bool = true, configurationFile: URL = SettingsStore.file,
         keyReader: () throws -> String = Keychain.read, keyWriter: @escaping (String) throws -> Void = Keychain.save) {
        self.configurationFile = configurationFile
        self.keyWriter = keyWriter
        keychainEnabled = readKeychain
        value = (try? Data(contentsOf: configurationFile)).flatMap { try? JSONDecoder().decode(AppConfiguration.self, from: $0) } ?? AppConfiguration()
        if readKeychain {
            do { apiKey = try keyReader() }
            catch {
                keychainReadFailed = true
                credentialError = l10n.connectionCopy[.keychain]
                self.error = credentialError
            }
        }
        ready = true
    }
    func save() {
        do {
            try FileManager.default.createDirectory(at: configurationFile.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                   attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(value)
            try data.write(to: configurationFile, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configurationFile.path)
        } catch { self.error = error.localizedDescription }
    }
    private func scheduleKeySave() {
        guard ready else { return }
        // An empty field after a denied read is not permission to erase an
        // existing credential that this process never managed to load.
        guard !(keychainReadFailed && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) else { return }
        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { keychainReadFailed = false }
        guard keychainEnabled else { return }
        keyDirty = true
        keySave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flushKey() }
        keySave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
    func flushKey() {
        keySave?.cancel()
        guard keychainEnabled, keyDirty else { return }
        do {
            try keyWriter(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
            keyDirty = false
            if error == credentialError { error = nil }
            credentialError = nil
        } catch {
            credentialError = l10n.connectionCopy[.keychainSave]
            self.error = credentialError
        }
    }
}

struct L10n {
    let language: Language
    private static let keys = ["settings", "archive", "minutes", "shortcut", "translationShortcut", "doubleSpace", "custom", "language", "system", "model", "record", "conflict", "translation", "input", "connection", "retry"]
    private var values: [String] {
        let row: String
        switch language.id {
        case "zh-Hans": row = "设置|自动归档|分钟|唤起快捷键|翻译快捷键|双击空格|自定义|语言|跟随系统|模型|按下快捷键|快捷键已被占用|翻译|输入|连接失败|按 Enter 重试"
        case "zh-Hant": row = "設定|自動封存|分鐘|喚起快捷鍵|翻譯快捷鍵|連按兩次空白鍵|自訂|語言|跟隨系統|模型|按下快捷鍵|快捷鍵已被佔用|翻譯|輸入|連線失敗|按 Enter 重試"
        case "es": row = "Ajustes|Archivar automáticamente|minutos|Atajo global|Atajo de traducción|Doble espacio|Personalizado|Idioma|Del sistema|Modelo|Pulsa un atajo|Atajo no disponible|Traducir|Entrada|Error de conexión|Enter para reintentar"
        case "fr": row = "Réglages|Archivage automatique|minutes|Raccourci global|Raccourci de traduction|Double espace|Personnalisé|Langue|Du système|Modèle|Saisir un raccourci|Raccourci indisponible|Traduire|Saisie|Échec de connexion|Entrée pour réessayer"
        case "de": row = "Einstellungen|Automatisch archivieren|Minuten|Globaler Kurzbefehl|Übersetzungskurzbefehl|Zweimal Leertaste|Eigener Kurzbefehl|Sprache|Systemsprache|Modell|Kurzbefehl drücken|Kurzbefehl nicht verfügbar|Übersetzen|Eingabe|Verbindungsfehler|Mit Enter wiederholen"
        case "pt": row = "Ajustes|Arquivar automaticamente|minutos|Atalho global|Atalho de tradução|Espaço duplo|Personalizado|Idioma|Do sistema|Modelo|Pressione um atalho|Atalho indisponível|Traduzir|Entrada|Falha de conexão|Enter para tentar novamente"
        case "it": row = "Impostazioni|Archivia automaticamente|minuti|Scorciatoia globale|Scorciatoia traduzione|Doppio spazio|Personalizzata|Lingua|Di sistema|Modello|Premi una scorciatoia|Scorciatoia non disponibile|Traduci|Testo|Connessione non riuscita|Invio per riprovare"
        case "ru": row = "Настройки|Автоархивация|минут|Глобальная клавиша|Клавиша перевода|Двойной пробел|Своя комбинация|Язык|Системный|Модель|Нажмите сочетание|Сочетание недоступно|Перевод|Ввод|Ошибка подключения|Enter — повторить"
        case "uk": row = "Параметри|Автоархівація|хвилин|Глобальна клавіша|Клавіша перекладу|Подвійний пробіл|Власна комбінація|Мова|Системна|Модель|Натисніть комбінацію|Комбінація недоступна|Переклад|Введення|Помилка з’єднання|Enter — повторити"
        case "ja": row = "設定|自動アーカイブ|分|呼び出しショートカット|翻訳ショートカット|スペースを2回|カスタム|言語|システムに従う|モデル|キーを押す|使用できないショートカット|翻訳|入力|接続できません|Enterで再試行"
        case "ko": row = "설정|자동 보관|분|호출 단축키|번역 단축키|스페이스 두 번|사용자 지정|언어|시스템 설정|모델|단축키 입력|사용할 수 없는 단축키|번역|입력|연결 실패|Enter로 다시 시도"
        case "ar": row = "الإعدادات|أرشفة تلقائية|دقائق|اختصار عام|اختصار الترجمة|مسافة مرتين|مخصص|اللغة|لغة النظام|النموذج|اضغط الاختصار|الاختصار غير متاح|ترجمة|إدخال|فشل الاتصال|Enter للمحاولة مجددًا"
        case "hi": row = "सेटिंग्स|अपने आप संग्रह करें|मिनट|वैश्विक शॉर्टकट|अनुवाद शॉर्टकट|दो बार स्पेस|कस्टम|भाषा|सिस्टम की भाषा|मॉडल|शॉर्टकट दबाएँ|शॉर्टकट उपलब्ध नहीं|अनुवाद|इनपुट|कनेक्शन विफल|फिर कोशिश के लिए Enter"
        case "bn": row = "সেটিংস|স্বয়ংক্রিয় সংরক্ষণ|মিনিট|সাধারণ শর্টকাট|অনুবাদ শর্টকাট|দুইবার স্পেস|কাস্টম|ভাষা|সিস্টেমের ভাষা|মডেল|শর্টকাট চাপুন|শর্টকাট উপলব্ধ নয়|অনুবাদ|ইনপুট|সংযোগ ব্যর্থ|আবার চেষ্টা করতে Enter"
        case "ur": row = "ترتیبات|خودکار محفوظ کریں|منٹ|عمومی شارٹ کٹ|ترجمہ شارٹ کٹ|دو بار اسپیس|حسب ضرورت|زبان|سسٹم کی زبان|ماڈل|شارٹ کٹ دبائیں|شارٹ کٹ دستیاب نہیں|ترجمہ|اندراج|رابطہ ناکام|دوبارہ کوشش کے لیے Enter"
        case "pa": row = "ਸੈਟਿੰਗਾਂ|ਆਪਣੇ ਆਪ ਸੰਭਾਲੋ|ਮਿੰਟ|ਗਲੋਬਲ ਸ਼ਾਰਟਕੱਟ|ਅਨੁਵਾਦ ਸ਼ਾਰਟਕੱਟ|ਦੋ ਵਾਰ ਸਪੇਸ|ਕਸਟਮ|ਭਾਸ਼ਾ|ਸਿਸਟਮ ਦੀ ਭਾਸ਼ਾ|ਮਾਡਲ|ਸ਼ਾਰਟਕੱਟ ਦਬਾਓ|ਸ਼ਾਰਟਕੱਟ ਉਪਲਬਧ ਨਹੀਂ|ਅਨੁਵਾਦ|ਇਨਪੁੱਟ|ਕਨੈਕਸ਼ਨ ਅਸਫਲ|ਦੁਬਾਰਾ ਕੋਸ਼ਿਸ਼ ਲਈ Enter"
        case "fa": row = "تنظیمات|بایگانی خودکار|دقیقه|میانبر عمومی|میانبر ترجمه|دو بار فاصله|سفارشی|زبان|زبان سیستم|مدل|میانبر را فشار دهید|میانبر در دسترس نیست|ترجمه|ورودی|اتصال ناموفق|Enter برای تلاش دوباره"
        case "tr": row = "Ayarlar|Otomatik arşivle|dakika|Genel kısayol|Çeviri kısayolu|Çift boşluk|Özel|Dil|Sistem dili|Model|Kısayola basın|Kısayol kullanılamıyor|Çeviri|Girdi|Bağlantı başarısız|Tekrar denemek için Enter"
        case "id": row = "Pengaturan|Arsip otomatis|menit|Pintasan global|Pintasan terjemahan|Spasi dua kali|Khusus|Bahasa|Bahasa sistem|Model|Tekan pintasan|Pintasan tidak tersedia|Terjemahan|Masukan|Koneksi gagal|Enter untuk mencoba lagi"
        case "ms": row = "Tetapan|Arkib automatik|minit|Pintasan global|Pintasan terjemahan|Ruang dua kali|Tersuai|Bahasa|Bahasa sistem|Model|Tekan pintasan|Pintasan tidak tersedia|Terjemahan|Input|Sambungan gagal|Enter untuk cuba lagi"
        case "vi": row = "Cài đặt|Tự động lưu trữ|phút|Phím tắt chung|Phím tắt dịch|Hai lần dấu cách|Tùy chỉnh|Ngôn ngữ|Theo hệ thống|Mô hình|Nhấn phím tắt|Phím tắt không khả dụng|Dịch|Nhập|Kết nối thất bại|Enter để thử lại"
        case "th": row = "การตั้งค่า|เก็บถาวรอัตโนมัติ|นาที|ปุ่มลัดเรียกใช้|ปุ่มลัดแปลภาษา|เว้นวรรคสองครั้ง|กำหนดเอง|ภาษา|ตามระบบ|โมเดล|กดปุ่มลัด|ปุ่มลัดไม่พร้อมใช้งาน|แปลภาษา|ป้อนข้อความ|เชื่อมต่อไม่สำเร็จ|Enter เพื่อลองอีกครั้ง"
        case "fil": row = "Mga Setting|Awtomatikong i-archive|minuto|Pangkalahatang shortcut|Shortcut sa pagsasalin|Dobleng space|Pasadya|Wika|Wika ng system|Modelo|Pindutin ang shortcut|Hindi magamit ang shortcut|Isalin|Input|Nabigo ang koneksyon|Enter para subukang muli"
        case "nl": row = "Instellingen|Automatisch archiveren|minuten|Algemene sneltoets|Vertaalsneltoets|Dubbele spatie|Aangepast|Taal|Systeemtaal|Model|Druk op een sneltoets|Sneltoets niet beschikbaar|Vertalen|Invoer|Verbinding mislukt|Enter om opnieuw te proberen"
        case "pl": row = "Ustawienia|Archiwizuj automatycznie|minuty|Skrót globalny|Skrót tłumaczenia|Podwójna spacja|Własny|Język|Systemowy|Model|Naciśnij skrót|Skrót niedostępny|Tłumacz|Tekst|Błąd połączenia|Enter, aby ponowić"
        case "sv": row = "Inställningar|Arkivera automatiskt|minuter|Globalt kortkommando|Kortkommando för översättning|Dubbelt blanksteg|Anpassat|Språk|Systemspråk|Modell|Tryck kortkommandot|Kortkommandot är upptaget|Översätt|Inmatning|Anslutningen misslyckades|Enter för att försöka igen"
        case "el": row = "Ρυθμίσεις|Αυτόματη αρχειοθέτηση|λεπτά|Γενική συντόμευση|Συντόμευση μετάφρασης|Διπλό διάστημα|Προσαρμοσμένη|Γλώσσα|Γλώσσα συστήματος|Μοντέλο|Πατήστε συντόμευση|Μη διαθέσιμη συντόμευση|Μετάφραση|Είσοδος|Αποτυχία σύνδεσης|Enter για επανάληψη"
        case "he": row = "הגדרות|ארכיון אוטומטי|דקות|קיצור כללי|קיצור תרגום|רווח כפול|מותאם אישית|שפה|שפת המערכת|מודל|הקש קיצור|הקיצור אינו זמין|תרגום|קלט|החיבור נכשל|Enter לניסיון נוסף"
        case "sw": row = "Mipangilio|Hifadhi kiotomatiki|dakika|Njia ya mkato ya jumla|Njia ya mkato ya tafsiri|Nafasi mara mbili|Maalum|Lugha|Lugha ya mfumo|Modeli|Bonyeza njia ya mkato|Njia ya mkato haipatikani|Tafsiri|Ingizo|Muunganisho umeshindwa|Enter kujaribu tena"
        default: row = "Settings|Auto-archive|minutes|Global shortcut|Translation shortcut|Double Space|Custom|Language|Follow System|Model|Press shortcut|Shortcut unavailable|Translate|Input|Connection failed|Press Enter to retry"
        }
        return row.components(separatedBy: "|")
    }
    subscript(_ key: String) -> String {
        if let value = additional(key) { return value }
        guard let index = Self.keys.firstIndex(of: key) else { return key }
        return values[index]
    }
    func error(_ error: Error) -> String {
        modelFailureGuidance(error, hasPartialAnswer: false)
    }
}
