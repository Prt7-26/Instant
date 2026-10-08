import Foundation

extension L10n {
    func additional(_ key: String) -> String? {
        if key == "copyAnswer" {
            return ["zh-Hans":"复制回答", "zh-Hant":"複製回答", "ja":"回答をコピー", "ko":"답변 복사",
                    "es":"Copiar respuesta", "fr":"Copier la réponse", "de":"Antwort kopieren", "pt":"Copiar resposta",
                    "it":"Copia risposta", "ru":"Копировать ответ", "uk":"Копіювати відповідь", "ar":"نسخ الإجابة",
                    "hi":"उत्तर कॉपी करें", "bn":"উত্তর কপি করুন", "ur":"جواب کاپی کریں", "pa":"ਜਵਾਬ ਕਾਪੀ ਕਰੋ",
                    "fa":"کپی پاسخ", "tr":"Yanıtı kopyala", "id":"Salin jawaban", "ms":"Salin jawapan",
                    "vi":"Sao chép câu trả lời", "th":"คัดลอกคำตอบ", "fil":"Kopyahin ang sagot", "nl":"Antwoord kopiëren",
                    "pl":"Kopiuj odpowiedź", "sv":"Kopiera svar", "el":"Αντιγραφή απάντησης", "he":"העתקת תשובה",
                    "sw":"Nakili jibu"][language.id] ?? "Copy answer"
        }
        if key == "sources" {
            return ["zh-Hans":"来源", "zh-Hant":"來源", "ja":"出典", "ko":"출처", "es":"Fuentes", "fr":"Sources",
                    "de":"Quellen", "pt":"Fontes", "it":"Fonti", "ru":"Источники", "uk":"Джерела", "ar":"المصادر",
                    "hi":"स्रोत", "bn":"উৎস", "ur":"ذرائع", "pa":"ਸਰੋਤ", "fa":"منابع", "tr":"Kaynaklar",
                    "id":"Sumber", "ms":"Sumber", "vi":"Nguồn", "th":"แหล่งข้อมูล", "fil":"Mga sanggunian",
                    "nl":"Bronnen", "pl":"Źródła", "sv":"Källor", "el":"Πηγές", "he":"מקורות", "sw":"Vyanzo"][language.id] ?? "Sources"
        }
        let keys = ["archiveNow", "manualArchiveShortcut", "archiveFolder", "chooseFolder", "defaultFolder", "openFolder", "restart", "quit"]
        guard let index = keys.firstIndex(of: key) else { return nil }
        let row: String
        switch language.id {
        case "zh-Hans": row = "归档对话|手动归档快捷键|归档文件夹|选择文件夹…|默认文件夹|打开归档文件夹|重启应用|退出"
        case "zh-Hant": row = "封存對話|手動封存快捷鍵|封存資料夾|選擇資料夾…|預設資料夾|開啟封存資料夾|重新啟動|結束"
        case "ja": row = "会話をアーカイブ|アーカイブのショートカット|保存フォルダ|フォルダを選択…|既定のフォルダ|保存フォルダを開く|再起動|終了"
        case "ko": row = "대화 보관|수동 보관 단축키|보관 폴더|폴더 선택…|기본 폴더|보관 폴더 열기|다시 시작|종료"
        case "es": row = "Archivar conversación|Atajo de archivo manual|Carpeta de archivo|Elegir carpeta…|Carpeta predeterminada|Abrir carpeta de archivo|Reiniciar|Salir"
        case "fr": row = "Archiver la conversation|Raccourci d’archivage|Dossier d’archives|Choisir un dossier…|Dossier par défaut|Ouvrir les archives|Redémarrer|Quitter"
        case "de": row = "Gespräch archivieren|Archivierungskurzbefehl|Archivordner|Ordner auswählen…|Standardordner|Archivordner öffnen|Neu starten|Beenden"
        case "pt": row = "Arquivar conversa|Atalho de arquivamento|Pasta de arquivo|Escolher pasta…|Pasta padrão|Abrir pasta de arquivo|Reiniciar|Sair"
        case "it": row = "Archivia conversazione|Scorciatoia archivio|Cartella archivio|Scegli cartella…|Cartella predefinita|Apri cartella archivio|Riavvia|Esci"
        case "ru": row = "Архивировать разговор|Клавиша архивации|Папка архива|Выбрать папку…|Папка по умолчанию|Открыть папку архива|Перезапустить|Выйти"
        case "uk": row = "Архівувати розмову|Клавіша архівації|Папка архіву|Вибрати папку…|Типова папка|Відкрити папку архіву|Перезапустити|Вийти"
        case "ar": row = "أرشفة المحادثة|اختصار الأرشفة اليدوية|مجلد الأرشيف|اختيار مجلد…|المجلد الافتراضي|فتح مجلد الأرشيف|إعادة التشغيل|إنهاء"
        case "hi": row = "बातचीत संग्रह करें|संग्रह करने का शॉर्टकट|संग्रह फ़ोल्डर|फ़ोल्डर चुनें…|डिफ़ॉल्ट फ़ोल्डर|संग्रह फ़ोल्डर खोलें|फिर शुरू करें|बंद करें"
        case "bn": row = "কথোপকথন সংরক্ষণ|সংরক্ষণের শর্টকাট|সংরক্ষণ ফোল্ডার|ফোল্ডার বেছে নিন…|ডিফল্ট ফোল্ডার|সংরক্ষণ ফোল্ডার খুলুন|পুনরায় চালু|বন্ধ করুন"
        case "ur": row = "گفتگو محفوظ کریں|محفوظ کرنے کا شارٹ کٹ|محفوظات کا فولڈر|فولڈر منتخب کریں…|پہلے سے طے شدہ فولڈر|محفوظات کا فولڈر کھولیں|دوبارہ شروع کریں|بند کریں"
        case "pa": row = "ਗੱਲਬਾਤ ਸੰਭਾਲੋ|ਸੰਭਾਲਣ ਦਾ ਸ਼ਾਰਟਕੱਟ|ਸੰਭਾਲ ਫੋਲਡਰ|ਫੋਲਡਰ ਚੁਣੋ…|ਮੂਲ ਫੋਲਡਰ|ਸੰਭਾਲ ਫੋਲਡਰ ਖੋਲ੍ਹੋ|ਮੁੜ ਚਾਲੂ ਕਰੋ|ਬੰਦ ਕਰੋ"
        case "fa": row = "بایگانی گفتگو|میانبر بایگانی دستی|پوشه بایگانی|انتخاب پوشه…|پوشه پیش‌فرض|باز کردن پوشه بایگانی|راه‌اندازی مجدد|خروج"
        case "tr": row = "Sohbeti arşivle|Arşivleme kısayolu|Arşiv klasörü|Klasör seç…|Varsayılan klasör|Arşiv klasörünü aç|Yeniden başlat|Çıkış"
        case "id": row = "Arsipkan percakapan|Pintasan arsip manual|Folder arsip|Pilih folder…|Folder bawaan|Buka folder arsip|Mulai ulang|Keluar"
        case "ms": row = "Arkibkan perbualan|Pintasan arkib manual|Folder arkib|Pilih folder…|Folder lalai|Buka folder arkib|Mulakan semula|Keluar"
        case "vi": row = "Lưu trữ hội thoại|Phím tắt lưu trữ|Thư mục lưu trữ|Chọn thư mục…|Thư mục mặc định|Mở thư mục lưu trữ|Khởi động lại|Thoát"
        case "th": row = "เก็บบทสนทนา|ปุ่มลัดเก็บถาวร|โฟลเดอร์เก็บถาวร|เลือกโฟลเดอร์…|โฟลเดอร์เริ่มต้น|เปิดโฟลเดอร์เก็บถาวร|เริ่มใหม่|ออก"
        case "fil": row = "I-archive ang usapan|Shortcut sa pag-archive|Folder ng archive|Pumili ng folder…|Default na folder|Buksan ang archive|I-restart|Lumabas"
        case "nl": row = "Gesprek archiveren|Archiveringssneltoets|Archiefmap|Map kiezen…|Standaardmap|Archiefmap openen|Herstarten|Stoppen"
        case "pl": row = "Archiwizuj rozmowę|Skrót archiwizacji|Folder archiwum|Wybierz folder…|Folder domyślny|Otwórz folder archiwum|Uruchom ponownie|Zakończ"
        case "sv": row = "Arkivera samtal|Kortkommando för arkivering|Arkivmapp|Välj mapp…|Standardmapp|Öppna arkivmapp|Starta om|Avsluta"
        case "el": row = "Αρχειοθέτηση συνομιλίας|Συντόμευση αρχειοθέτησης|Φάκελος αρχείου|Επιλογή φακέλου…|Προεπιλεγμένος φάκελος|Άνοιγμα φακέλου αρχείου|Επανεκκίνηση|Έξοδος"
        case "he": row = "ארכוב שיחה|קיצור לארכוב ידני|תיקיית ארכיון|בחירת תיקייה…|תיקיית ברירת מחדל|פתיחת תיקיית ארכיון|הפעלה מחדש|יציאה"
        case "sw": row = "Hifadhi mazungumzo|Njia ya mkato ya kuhifadhi|Folda ya kumbukumbu|Chagua folda…|Folda chaguomsingi|Fungua folda ya kumbukumbu|Anzisha upya|Ondoka"
        default: row = "Archive conversation|Manual archive shortcut|Archive folder|Choose folder…|Default folder|Open archive folder|Restart|Quit"
        }
        return row.components(separatedBy: "|")[index]
    }
}
