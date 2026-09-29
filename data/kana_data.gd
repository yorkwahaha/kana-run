extends RefCounted
class_name KanaDB

## 五十音資料庫 — 靜態資料與查詢工具。
## 全部內容為 const，編譯期即載入，不佔執行期記憶體。

enum Kind {
	SEION,   ## 清音 46
	DAKUON,  ## 濁音・半濁音 25
	YOON,    ## 拗音 33
	KATA,    ## 片假名 104（由前三個單元自動轉換而來）
}

const UNIT_NAMES := {
	Kind.SEION: "清音篇",
	Kind.DAKUON: "濁音・半濁音篇",
	Kind.YOON: "拗音篇",
	Kind.KATA: "片假名篇",
}

const UNIT_SUBTITLES := {
	Kind.SEION: "46 音 · 一切的起點",
	Kind.DAKUON: "25 音 · 點與圈的世界",
	Kind.YOON: "33 音 · 組合的韻律",
	Kind.KATA: "104 音 · 同一套音，另一套字",
}

## [假名, 羅馬字, _kind]
const SEION: Array = [
	["あ", "a"], ["い", "i"], ["う", "u"], ["え", "e"], ["お", "o"],
	["か", "ka"], ["き", "ki"], ["く", "ku"], ["け", "ke"], ["こ", "ko"],
	["さ", "sa"], ["し", "shi"], ["す", "su"], ["せ", "se"], ["そ", "so"],
	["た", "ta"], ["ち", "chi"], ["つ", "tsu"], ["て", "te"], ["と", "to"],
	["な", "na"], ["に", "ni"], ["ぬ", "nu"], ["ね", "ne"], ["の", "no"],
	["は", "ha"], ["ひ", "hi"], ["ふ", "fu"], ["へ", "he"], ["ほ", "ho"],
	["ま", "ma"], ["み", "mi"], ["む", "mu"], ["め", "me"], ["も", "mo"],
	["や", "ya"], ["ゆ", "yu"], ["よ", "yo"],
	["ら", "ra"], ["り", "ri"], ["る", "ru"], ["れ", "re"], ["ろ", "ro"],
	["わ", "wa"], ["を", "o"], ["ん", "n"],
]

const DAKUON: Array = [
	["が", "ga"], ["ぎ", "gi"], ["ぐ", "gu"], ["げ", "ge"], ["ご", "go"],
	["ざ", "za"], ["じ", "ji"], ["ず", "zu"], ["ぜ", "ze"], ["ぞ", "zo"],
	["だ", "da"], ["ぢ", "ji"], ["づ", "zu"], ["で", "de"], ["ど", "do"],
	["ば", "ba"], ["び", "bi"], ["ぶ", "bu"], ["べ", "be"], ["ぼ", "bo"],
	["ぱ", "pa"], ["ぴ", "pi"], ["ぷ", "pu"], ["ぺ", "pe"], ["ぽ", "po"],
]

## 拗音：第三個字元是 small ya / yu / yo
const YOON: Array = [
	["きゃ", "kya"], ["きゅ", "kyu"], ["きょ", "kyo"],
	["ぎゃ", "gya"], ["ぎゅ", "gyu"], ["ぎょ", "gyo"],
	["しゃ", "sha"], ["しゅ", "shu"], ["しょ", "sho"],
	["じゃ", "ja"], ["じゅ", "ju"], ["じょ", "jo"],
	["ちゃ", "cha"], ["ちゅ", "chu"], ["ちょ", "cho"],
	["にゃ", "nya"], ["にゅ", "nyu"], ["にょ", "nyo"],
	["ひゃ", "hya"], ["ひゅ", "hyu"], ["ひょ", "hyo"],
	["びゃ", "bya"], ["びゅ", "byu"], ["びょ", "byo"],
	["ぴゃ", "pya"], ["ぴゅ", "pyu"], ["ぴょ", "pyo"],
	["みゃ", "mya"], ["みゅ", "myu"], ["みょ", "myo"],
	["りゃ", "rya"], ["りゅ", "ryu"], ["りょ", "ryo"],
]

## 範例詞庫：假名 -> [漢字, 假名讀音, 羅馬字, 中文釋義]
## reading 必須「包含」該假名，挖空題會依此定位。
const WORDS: Dictionary = {
	# ── 清音 ──
	"あ": ["雨", "あめ", "ame", "雨"],
	"い": ["井", "い", "ii", "井"],
	"う": ["宇宙", "うちゅう", "uchuu", "宇宙"],
	"え": ["繪", "え", "e", "圖畫"],
	"お": ["音", "おと", "oto", "聲音"],
	"か": ["傘", "かさ", "kasa", "傘"],
	"き": ["樹", "き", "ki", "樹木"],
	"く": ["鞋", "くつ", "kutsu", "鞋子"],
	"け": ["毛", "け", "ke", "毛（計量詞）"],
	"こ": ["聲", "こえ", "koe", "聲音"],
	"さ": ["差", "さ", "sa", "差異"],
	"し": ["詩", "し", "shi", "詩"],
	"す": ["醋", "す", "su", "醋"],
	"せ": ["瀨戶", "せと", "seto", "瀨戶"],
	"そ": ["組織", "そしき", "soshiki", "組織"],
	"た": ["棚", "だな", "dana", "架子"],
	"ち": ["血", "ち", "chi", "血液"],
	"つ": ["粒", "つぶ", "tsubu", "一顆"],
	"て": ["手", "て", "te", "手"],
	"と": ["鳥", "とり", "tori", "鳥"],
	"な": ["苗", "なえ", "nae", "幼苗"],
	"に": ["荷", "に", "ni", "行李"],
	"ぬ": ["布", "ぬの", "nuno", "布"],
	"ね": ["貓", "ねこ", "neko", "貓"],
	"の": ["草原", "のはら", "nohara", "草原"],
	"は": ["花", "はな", "hana", "花朵"],
	"ひ": ["火", "ひ", "hi", "火焰"],
	"ふ": ["船", "ふね", "fune", "船"],
	"へ": ["平凡", "へいき", "heiki", "平凡"],
	"ほ": ["星", "ほし", "hoshi", "星星"],
	"ま": ["松", "まつ", "matsu", "松樹"],
	"み": ["水", "みず", "mizu", "水"],
	"む": ["蟲", "むし", "mushi", "昆蟲"],
	"め": ["目", "め", "me", "眼睛"],
	"も": ["桃", "もも", "momo", "桃子"],
	"や": ["山", "やま", "yama", "山"],
	"ゆ": ["雪", "ゆき", "yuki", "雪"],
	"よ": ["夜", "よる", "yoru", "夜晚"],
	"ら": ["寺", "てら", "tera", "寺院"],
	"り": ["理由", "りゆう", "riyuu", "理由"],
	"る": ["煮", "にる", "niru", "烹煮"],
	"れ": ["例子", "れい", "rei", "例子"],
	"ろ": ["爐", "ろ", "ro", "爐灶"],
	"わ": ["棉", "わた", "wata", "棉絮"],
	"を": [],
	"ん": ["書", "ほん", "hon", "書本"],
	# ── 濁音・半濁音 ──
	"が": ["鏡", "かがみ", "kagami", "鏡子"],
	"ぎ": ["形式", "けいしき", "keishiki", "形式"],
	"ぐ": ["道具", "どうぐ", "dougu", "工具"],
	"げ": ["現金", "げんきん", "genkin", "現金"],
	"ご": ["午後", "ごご", "gogo", "下午"],
	"ざ": ["座", "ざ", "za", "座位"],
	"じ": ["地圖", "ちず", "chizu", "地圖"],
	"ず": ["數", "かず", "kazu", "數量"],
	"ぜ": ["全部", "ぜんぶ", "zenbu", "全部"],
	"ぞ": ["象", "ぞう", "zou", "大象"],
	"だ": ["段落", "だんらく", "danraku", "段落"],
	"ぢ": ["自治", "じち", "jichi", "自治"],
	"づ": ["繼續", "つづく", "tsuduku", "持續"],
	"で": ["相遇", "であい", "deai", "相遇"],
	"ど": ["堂", "どう", "dou", "堂"],
	"ば": ["場所", "ばしょ", "basho", "場所"],
	"び": ["美人", "びじん", "bijin", "美人"],
	"ぶ": ["部", "ぶ", "bu", "部分"],
	"べ": ["蛇", "へび", "hebi", "毒蛇"],
	"ぼ": ["僕", "ぼく", "boku", "我（僕）"],
	"ぱ": ["麵包", "ぱん", "pan", "麵包"],
	"ぴ": ["啤酒", "びーる", "biiru", "啤酒"],
	"ぷ": ["泳池", "ぷーる", "puuru", "游泳池"],
	"ぺ": ["頁", "ぺーじ", "peiji", "頁面"],
	"ぽ": ["郵筒", "ぽすと", "posuto", "郵筒"],
	# ── 拗音 ──
	"きゃ": ["客", "きゃく", "kyaku", "客人"],
	"きゅ": ["教育", "きょうう", "kiyouu", "教育"],
	"きょ": ["教室", "きょうしつ", "kyoushitsu", "教室"],
	"ぎゃ": [],
	"ぎゅ": ["牛", "ぎゅう", "gyuu", "牛"],
	"ぎょ": ["行", "ぎょう", "gyouu", "行動"],
	"しゃ": ["會社", "しゃ", "sha", "公司"],
	"しゅ": ["種類", "しゅ", "shu", "種類"],
	"しょ": ["書", "しょ", "sho", "書信"],
	"じゃ": ["蛇", "じゃ", "ja", "毒蛇"],
	"じゅ": ["樹", "じゅ", "ju", "樹木"],
	"じょ": ["女性", "じょせい", "josei", "女性"],
	"ちゃ": ["茶", "ちゃ", "cha", "茶葉"],
	"ちゅ": ["注射", "ちゅうしゃ", "chuusha", "注射"],
	"ちょ": ["著作", "ちょさく", "chosaku", "著作"],
	"にゃ": [],
	"にゅ": [],
	"にょ": [],
	"ひゃ": ["百", "ひゃく", "hyaku", "一百"],
	"ひゅ": [],
	"ひょ": ["表", "ひょう", "hyouu", "表面"],
	"びゃ": [],
	"びゅ": ["眉", "びゅ", "byu", "眉毛"],
	"びょ": [],
	"ぴゃ": [],
	"ぴゅ": [],
	"ぴょ": [],
	"みゃ": ["妙", "みょう", "myou", "奇妙"],
	"みゅ": [],
	"みょ": ["妙", "みょう", "myou", "奇妙"],
	"りゃ": [],
	"りゅ": ["留學", "りゅうがく", "ryuugaku", "留學"],
	"りょ": ["旅行", "りょこう", "ryokou", "旅行"],
}

## 易混淆群組：同群任取 1–2 個作為干擾項，比亂猜有效得多。
const CONFUSION_GROUPS: Array = [
	["あ", "お", "う", "ら", "わ"],
	["い", "り", "う", "に"],
	["う", "ふ", "つ", "ら", "す"],
	["え", "さ", "け", "せ"],
	["お", "こ", "さ", "を", "ほ"],
	["か", "が", "さ", "は", "き"],
	["き", "さ", "し", "ち", "ぎ"],
	["く", "ち", "ら", "す", "つ"],
	["け", "せ", "こ", "て"],
	["こ", "と", "そ", "さ"],
	["さ", "き", "せ", "は", "ざ"],
	["し", "ち", "つ", "じ", "き"],
	["す", "つ", "ず", "ち", "ふ"],
	["せ", "け", "そ", "さ", "ぜ"],
	["そ", "こ", "と", "さ", "ぞ"],
	["た", "な", "は", "ら", "だ"],
	["ち", "し", "つ", "り", "ぢ"],
	["つ", "す", "っ", "ち", "ふ", "づ"],
	["て", "と", "ね", "け", "で"],
	["と", "そ", "こ", "ね", "ど"],
	["な", "は", "た", "ら", "ま"],
	["に", "い", "り", "ち", "ひ"],
	["ぬ", "ね", "の", "み", "ぶ"],
	["ね", "の", "は", "て", "れ"],
	["の", "ほ", "を", "も", "の"],
	["は", "ほ", "ま", "へ", "ば", "ぱ"],
	["ひ", "に", "ふ", "り", "び", "ぴ"],
	["ふ", "う", "つ", "ほ", "ひ", "ぶ", "ぷ"],
	["へ", "は", "け", "べ", "ぺ"],
	["ほ", "は", "ま", "も", "ぼ", "ぽ"],
	["ま", "は", "み", "む", "ね"],
	["み", "も", "ぬ", "ま", "り", "び"],
	["む", "め", "も", "み", "ぶ"],
	["め", "も", "ぬ", "み", "べ"],
	["も", "ほ", "の", "ま", "ぼ"],
	["や", "ら", "な", "ま", "や"],
	["ゆ", "み", "る", "ゆ"],
	["よ", "ら", "ろ", "も", "ぞ"],
	["ら", "わ", "あ", "る", "や", "り"],
	["り", "い", "み", "ち", "ひ", "じ"],
	["る", "ら", "ろ", "す", "む", "ゆ"],
	["れ", "ね", "け", "わ", "る"],
	["ろ", "る", "お", "よ", "う"],
	["わ", "を", "れ", "ね", "ほ"],
	["を", "お", "ほ", "の", "ろ"],
	["ん", "あ", "な", "ん", "ん"],
	["が", "か", "ぎ", "ぐ", "げ", "ご"],
	["ざ", "さ", "じ", "ず", "ぜ", "ぞ"],
	["だ", "た", "で", "ど", "ち", "つ"],
	["ば", "は", "び", "ぶ", "べ", "ぼ"],
	["ぱ", "は", "ぴ", "ぷ", "ぺ", "ぽ"],
	["きゃ", "しゃ", "ちゃ", "にゃ", "ひゃ", "みゃ", "ぎゃ", "じゃ", "びゃ", "ぴゃ"],
	["きゅ", "しゅ", "ちゅ", "にゅ", "ひゅ", "びゅ", "ぴゅ", "りゅ", "みゅ", "ぎゅ"],
	["きょ", "しょ", "ちょ", "にょ", "ひょ", "びょ", "ぴょ", "りょ", "みょ", "ぎょ"],
	["ぎゃ", "じゃ", "ちゃ", "びゃ", "ぴゃ", "しゃ"],
	["じゅ", "りゅ", "ぎゅ", "しゅ", "ちゅ", "ひゅ"],
	["じょ", "りょ", "ぎょ", "しょ", "ちょ", "ひょ"],
]

## 濁音／半濁音的清音原型。用來在錯題卡上解釋「點與圈從哪來」。
const DAKUEN_BASE := {
	"が": "か", "ぎ": "き", "ぐ": "く", "げ": "け", "ご": "こ",
	"ざ": "さ", "じ": "し", "ず": "す", "ぜ": "せ", "ぞ": "そ",
	"だ": "た", "ぢ": "ち", "づ": "つ", "で": "て", "ど": "と",
	"ば": "は", "び": "ひ", "ぶ": "ふ", "べ": "へ", "ぼ": "ほ",
	"ぱ": "は", "ぴ": "ひ", "ぷ": "ふ", "ぺ": "へ", "ぽ": "ほ",
}

## 假名構成拆解：教學用。回傳 0~2 行說明。
static func decompose(kana: String) -> Array:
	var out: Array = []
	if kana.length() == 2:
		var base := kana.substr(0, 1)
		var small := kana.substr(1, 1)
		if base == "し":
			out.append("由「し」加上小寫的「%s」拼成，只算一個音節" % small)
		else:
			out.append("由「%s」加上小寫的「%s」拼成，只算一個音節" % [base, small])
		return out
	if DAKUEN_BASE.has(kana):
		var b: String = DAKUEN_BASE[kana]
		if kana.begins_with("は") or kna_at(kana, 1) == "は":
			out.append("「%s」加上半濁點（°）變成「%s」，讀音不變、語感更輕" % [b, kana])
		elif kana == "ぢ" or kana == "づ":
			out.append("「%s」加濁點的歷史假名，現代多寫成「%s／%s」" % [b, b + "じ", b + "ず"])
		else:
			out.append("「%s」加上濁點（゛）變成「%s」" % [b, kana])
	return out


static func kna_at(s: String, i: int) -> String:
	if i < 0 or i >= s.length():
		return ""
	return s.substr(i, 1)


## 把一串假名切成一個一個「音」。
##
## 不能直接逐字切：拗音是兩個字元（き + ゃ），
## 逐字切會變成 `き` 與 `ゃ`，後者查不到音檔，整個詞就沒聲音了。
## 規則：一個基本假名，若下一個字是 small ya/yu/yo 或 small 母音，就合成兩字。
const SMALL := "ゃゅょぁぃぅぇぉゎャュョァィゥェォヮ"
## 長音符（ー, U+30FC）落在假名碼位範圍內，但不是一個可發音的假名，
## 必須單獨排除，否則 びーる 會被切成 び / ー / る。
const SKIP_CHARS := "ーｰ・"

static func split_kana(s: String) -> Array:
	var out: Array = []
	var i := 0
	var n := s.length()
	while i < n:
		var c := s.unicode_at(i)
		# 長音符與拉丁字母不是假名（例如 ビール），直接跳過
		if not (c >= 0x3041 and c <= 0x30FF) or SKIP_CHARS.contains(s.substr(i, 1)):
			i += 1
			continue
		if i + 1 < n:
			var nxt := s.substr(i + 1, 1)
			if SMALL.contains(nxt):
				out.append(s.substr(i, 2))
				i += 2
				continue
		out.append(s.substr(i, 1))
		i += 1
	return out


## 取得該假名在五十音圖中的左右鄰居（教學提示用）
static func neighbours(kana: String) -> Array:
	var for_kind := SEION
	if kind_of(kana) == Kind.DAKUON:
		for_kind = DAKUON
	elif kind_of(kana) == Kind.YOON:
		for_kind = YOON
	var idx := -1
	for i in for_kind.size():
		if for_kind[i][0] == kana:
			idx = i
			break
	if idx < 0 or for_kind.size() < 2:
		return []
	return [for_kind[(idx - 1 + for_kind.size()) % for_kind.size()][0],
		for_kind[(idx + 1) % for_kind.size()][0]]


## 靜態索引（_init 時建立一次）
static var _romaji_index: Dictionary = {}
static var _confusion_index: Dictionary = {}
static var _units: Dictionary = {}
static var _order: Array = []
static var _ready_done := false


static func _ensure() -> void:
	if _ready_done:
		return
	_ready_done = true

	_units = {
		Kind.SEION: SEION,
		Kind.DAKUON: DAKUON,
		Kind.YOON: YOON,
	}
	_order = []
	for kind in [Kind.SEION, Kind.DAKUON, Kind.YOON]:
		for entry in _units[kind]:
			var kana: String = entry[0]
			_romaji_index[kana] = entry[1]
			_order.append(kana)

	# 片假名單元由前三個平假名單元轉換而來。
	# 不另外手寫 104 筆：手寫的話兩邊迟早會對不起來，
	# 而且清音／濁音／拗音增減時要同步改兩個地方。
	var kata: Array = []
	for kind in [Kind.SEION, Kind.DAKUON, Kind.YOON]:
		for entry in _units[kind]:
			var k: String = to_script(str(entry[0]), true)
			kata.append([k, str(entry[1])])
			_romaji_index[k] = str(entry[1])
	_units[Kind.KATA] = kata
	for entry in kata:
		_order.append(str(entry[0]))

	for group in CONFUSION_GROUPS:
		for kana in group:
			if not _confusion_index.has(kana):
				_confusion_index[kana] = group
			# 片假名版本掛到同一組，答錯時提示才會一致
			var k: String = to_script(str(kana), true)
			if k != str(kana) and not _confusion_index.has(k):
				_confusion_index[k] = group


## 取得單元假名陣列（每項為 [kana, romaji]）
static func unit(kind: int) -> Array:
	_ensure()
	return _units.get(kind, [])


static func kind_of(kana: String) -> int:
	_ensure()
	if _units[Kind.SEION].any(func(e): return e[0] == kana):
		return Kind.SEION
	if _units[Kind.DAKUON].any(func(e): return e[0] == kana):
		return Kind.DAKUON
	if _units[Kind.YOON].any(func(e): return e[0] == kana):
		return Kind.YOON
	return Kind.KATA


static func romaji(kana: String) -> String:
	_ensure()
	return _romaji_index.get(kana, "")


static func all_kana() -> Array:
	_ensure()
	return _order.duplicate()


static func count_for(kind: int) -> int:
	return unit(kind).size()


## 依假名取得與其易混淆的同群假名（不含自己）
static func confusion(kana: String) -> Array:
	_ensure()
	var group: Array = _confusion_index.get(kana, [])
	var want_kata := is_katakana(kana)
	var out: Array = []
	for k in group:
		if k == kana:
			continue
		out.append(to_script(str(k), want_kata))
	return out


static func is_katakana(kana: String) -> bool:
	if kana.is_empty():
		return false
	var c := kana.unicode_at(0)
	return c >= 0x30A1 and c <= 0x30FF


## 詞彙庫以平假名為 key。片假名的挖空題要能用到同一份詞庫，
## 所以查詢時先轉回平假名，再把讀音轉回片假名。
static func word_for(kana: String) -> Array:
	var w: Array = _lookup_word(kana)
	if w.size() < 4 or not is_katakana(kana):
		return w
	var out := w.duplicate()
	out[1] = to_script(str(w[1]), true)
	return out


static func has_word(kana: String) -> bool:
	return _lookup_word(kana).size() >= 4


static func _lookup_word(kana: String) -> Array:
	if WORDS.has(kana):
		return WORDS[kana]
	if is_katakana(kana):
		return WORDS.get(to_script(kana, false), [])
	return []


## 假名平／片假名互轉。`katakana` 為 true 時輸出片假名。
static func to_script(kana: String, katakana: bool) -> String:
	if not katakana:
		return kana
	var out := ""
	for i in kana.length():
		var code := kana.unicode_at(i)
		if code >= 0x3041 and code <= 0x3096:
			out += String.chr(code + 0x60)
		else:
			out += String.chr(code)
	return out


## 依 0=平假名 / 1=片假名 把整串文本中的假名轉換
static func convert_text(text: String, katakana: bool) -> String:
	if not katakana:
		return text
	return to_script(text, true)


## 辨識可作答的題目（需要詞彙的挖空題）
static func kana_with_word() -> Array:
	_ensure()
	var out: Array = []
	for kana in _order:
		if has_word(kana):
			out.append(kana)
	return out
