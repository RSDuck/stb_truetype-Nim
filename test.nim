import stb_truetype, stb_image/write as stbw, sequtils, unicode

var 
    spc = PackContext()
    data = newString(256 * 256)

    fontData = readFile(r"c:\windows\fonts\arial.ttf")

    char_data = newSeq[PackedChar]()

discard packBegin(spc, data, 256, 256, 256, 1)
discard packFontRange(spc, fontData, 0, 16.0, 64, 256 + 128, char_data)
packSetOverampling(spc, 1, 1)
let ranges = packFontRanges(spc, fontData, 0, [
    PackRange(typ: packRangeRange, font_size: 12.0, first_unicode_char_in_range: 256, num_chars: 10),
    PackRange(typ: packRangeSeq, font_size: 22.0, array_of_unicode_codepoints: @[
        ord('$'), ord('^'), ord('{'), int runeAtPos("ß", 0), int runeAtPos("Ω", 0), int runeAtPos("я", 0)])])
packEnd(spc)

proc lerp(s, t, v: float32): float32 = s + (t - s) * v

#scrappy cut out function
var
    x = 0f
    y = 0f
let 
    rect = getPackedQuad(ranges[1][1][4], 256, 256, x, y, true)
    rw = int rect.x1 - rect.x0
    rh = int rect.y1 - rect.y0
var singleChar = newSeq[byte](rw * rh)
for j in 0..rh - 1:
    for i in 0..rw - 1:
        let
            x = int(lerp(rect.s0, rect.s1, float32(i) / float32(rw)) * 256)
            y = int(lerp(rect.t0, rect.t1, float32(j) / float32(rh)) * 256)
        singleChar[i + j * rw] = (byte data[x + y * 256])
writePNG("test2.png", rw, rh, 1, singleChar) # should contain only an Omega

writePng("test.png", 256, 256, 1, cast[seq[uint8]](toSeq(items data))) # should contain every rendered character