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
        let licenseCopy: [String: [String: String]] = [
            "license": ["zh-Hans":"许可证", "zh-Hant":"授權條款", "ja":"ライセンス", "ko":"라이선스",
                        "es":"Licencia", "fr":"Licence", "de":"Lizenz", "pt":"Licença", "it":"Licenza",
                        "ru":"Лицензия", "uk":"Ліцензія", "ar":"الترخيص", "hi":"लाइसेंस", "bn":"লাইসেন্স",
                        "ur":"لائسنس", "pa":"ਲਾਇਸੈਂਸ", "fa":"مجوز", "tr":"Lisans", "id":"Lisensi", "ms":"Lesen",
                        "vi":"Giấy phép", "th":"ใบอนุญาต", "fil":"Lisensya", "nl":"Licentie", "pl":"Licencja",
                        "sv":"Licens", "el":"Άδεια χρήσης", "he":"רישיון", "sw":"Leseni", "en":"License"],
            "licenseDescription": ["zh-Hans":"禁止商业用途，可自用、修改，并在非商业范围内再分发。",
                                   "zh-Hant":"禁止商業用途，可自行使用、修改，並在非商業範圍內再散布。",
                                   "ja":"非営利目的に限り、使用、改変、再配布できます。",
                                   "ko":"비상업적 목적으로만 사용, 수정 및 재배포할 수 있습니다.",
                                   "es":"Solo para fines no comerciales; se permite usar, modificar y redistribuir.",
                                   "fr":"Usage non commercial uniquement ; utilisation, modification et redistribution autorisées.",
                                   "de":"Nur für nichtkommerzielle Zwecke; Nutzung, Änderung und Weitergabe sind erlaubt.",
                                   "pt":"Somente para fins não comerciais; é permitido usar, modificar e redistribuir.",
                                   "it":"Solo per scopi non commerciali; è possibile usare, modificare e ridistribuire.",
                                   "ru":"Только в некоммерческих целях; разрешены использование, изменение и распространение.",
                                   "uk":"Лише з некомерційною метою; дозволено використовувати, змінювати й поширювати.",
                                   "ar":"للاستخدام غير التجاري فقط؛ يُسمح بالاستخدام والتعديل وإعادة التوزيع.",
                                   "hi":"केवल गैर-व्यावसायिक उपयोग; उपयोग, संशोधन और पुनर्वितरण की अनुमति है।",
                                   "bn":"শুধু অবাণিজ্যিক ব্যবহারের জন্য; ব্যবহার, পরিবর্তন ও পুনর্বিতরণ করা যাবে।",
                                   "ur":"صرف غیر تجارتی استعمال؛ استعمال، ترمیم اور دوبارہ تقسیم کی اجازت ہے۔",
                                   "pa":"ਸਿਰਫ਼ ਗੈਰ-ਵਪਾਰਕ ਵਰਤੋਂ ਲਈ; ਵਰਤਣ, ਸੋਧਣ ਅਤੇ ਮੁੜ ਵੰਡਣ ਦੀ ਇਜਾਜ਼ਤ ਹੈ।",
                                   "fa":"فقط برای استفاده غیرتجاری؛ استفاده، تغییر و بازتوزیع مجاز است.",
                                   "tr":"Yalnızca ticari olmayan kullanım içindir; kullanma, değiştirme ve yeniden dağıtma serbesttir.",
                                   "id":"Hanya untuk penggunaan nonkomersial; boleh digunakan, diubah, dan didistribusikan ulang.",
                                   "ms":"Untuk kegunaan bukan komersial sahaja; boleh digunakan, diubah suai dan diedarkan semula.",
                                   "vi":"Chỉ dành cho mục đích phi thương mại; được phép sử dụng, sửa đổi và phân phối lại.",
                                   "th":"สำหรับการใช้งานที่ไม่ใช่เชิงพาณิชย์เท่านั้น อนุญาตให้ใช้ แก้ไข และเผยแพร่ต่อ",
                                   "fil":"Para lamang sa di-komersyal na paggamit; maaaring gamitin, baguhin, at muling ipamahagi.",
                                   "nl":"Alleen voor niet-commercieel gebruik; gebruik, wijziging en herdistributie zijn toegestaan.",
                                   "pl":"Wyłącznie do celów niekomercyjnych; można używać, modyfikować i rozpowszechniać.",
                                   "sv":"Endast för icke-kommersiellt bruk; användning, ändring och vidare distribution tillåts.",
                                   "el":"Μόνο για μη εμπορική χρήση· επιτρέπονται η χρήση, η τροποποίηση και η αναδιανομή.",
                                   "he":"לשימוש לא מסחרי בלבד; מותר להשתמש, לשנות ולהפיץ מחדש.",
                                   "sw":"Kwa matumizi yasiyo ya kibiashara pekee; matumizi, marekebisho na usambazaji upya unaruhusiwa.",
                                   "en":"Noncommercial use only; you may use, modify, and redistribute it for noncommercial purposes."],
            "viewLicense": ["zh-Hans":"查看许可证", "zh-Hant":"檢視授權條款", "ja":"ライセンスを表示", "ko":"라이선스 보기",
                            "es":"Ver licencia", "fr":"Voir la licence", "de":"Lizenz anzeigen", "pt":"Ver licença",
                            "it":"Visualizza licenza", "ru":"Открыть лицензию", "uk":"Переглянути ліцензію",
                            "ar":"عرض الترخيص", "hi":"लाइसेंस देखें", "bn":"লাইসেন্স দেখুন", "ur":"لائسنس دیکھیں",
                            "pa":"ਲਾਇਸੈਂਸ ਵੇਖੋ", "fa":"مشاهده مجوز", "tr":"Lisansı görüntüle", "id":"Lihat lisensi",
                            "ms":"Lihat lesen", "vi":"Xem giấy phép", "th":"ดูใบอนุญาต", "fil":"Tingnan ang lisensya",
                            "nl":"Licentie bekijken", "pl":"Wyświetl licencję", "sv":"Visa licens",
                            "el":"Προβολή άδειας", "he":"הצגת הרישיון", "sw":"Tazama leseni", "en":"View license"]
        ]
        if let values = licenseCopy[key] { return values[language.id] ?? values["en"] }
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
