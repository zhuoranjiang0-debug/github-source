## 文本编码检查与解码。
##
## 这个类是被一次真实事故逼出来的：有人在编辑器里改完工程文件后保存，
## 编辑器用非 UTF-8 的编码写回，个别汉字悄悄变成了乱码。
## 麻烦的地方在于——JSON 结构依然合法，程序照跑不误，
## 只是游戏里的文字变了样，极难发现。
##
## 所以读取工程文件前先做一次字节级的体检，把问题拦在门口。
class_name TextEncoding
extends RefCounted

## UTF-8 BOM：EF BB BF
const BOM_BYTES := [0xEF, 0xBB, 0xBF]
## 乱码替换字符 U+FFFD：EF BF BD
const REPLACEMENT_BYTES := [0xEF, 0xBF, 0xBD]


## 返回第一个非法 UTF-8 字节的偏移；全部合法则返回 -1。
static func first_invalid_offset(bytes: PackedByteArray) -> int:
	var i := 0
	var n := bytes.size()
	while i < n:
		var b := bytes[i]
		var extra := 0
		if b < 0x80:
			extra = 0
		elif b >= 0xC2 and b <= 0xDF:
			extra = 1
		elif b >= 0xE0 and b <= 0xEF:
			extra = 2
		elif b >= 0xF0 and b <= 0xF4:
			extra = 3
		else:
			return i
		if i + extra >= n:
			return i
		for k in range(1, extra + 1):
			var cont := bytes[i + k]
			if cont < 0x80 or cont > 0xBF:
				return i
		i += extra + 1
	return -1


## 把字节偏移换算成行号，好让报错能指到具体位置。
static func byte_offset_to_line(bytes: PackedByteArray, offset: int) -> int:
	var line := 1
	var limit := mini(offset, bytes.size())
	for i in limit:
		if bytes[i] == 0x0A:
			line += 1
	return line


static func has_bom(bytes: PackedByteArray) -> bool:
	return bytes.size() >= 3 \
		and bytes[0] == BOM_BYTES[0] and bytes[1] == BOM_BYTES[1] and bytes[2] == BOM_BYTES[2]


## 检测乱码替换字符 U+FFFD（EF BF BD）。
## 它是"合法 UTF-8"，单靠合法性检查抓不到，但它一定意味着某处已经坏掉了。
static func contains_replacement_char(bytes: PackedByteArray) -> bool:
	if bytes.size() < 3:
		return false
	for i in bytes.size() - 2:
		if bytes[i] == REPLACEMENT_BYTES[0] \
			and bytes[i + 1] == REPLACEMENT_BYTES[1] \
			and bytes[i + 2] == REPLACEMENT_BYTES[2]:
			return true
	return false


## 解码成文本，自动跳过 UTF-8 BOM。
## 容忍 BOM 是因为有些编辑器保存时会加上它，我们不该因此拒绝整个工程。
static func decode(bytes: PackedByteArray) -> String:
	if has_bom(bytes):
		return bytes.slice(3).get_string_from_utf8()
	return bytes.get_string_from_utf8()
