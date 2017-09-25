{.emit: """
#define STBTT_STATIC
#define STBRP_STATIC
#define STB_TRUETYPE_IMPLEMENTATION
#define STB_RECT_PACK_IMPLEMENTATION
""".}
include "stb_truetype/stb_rect_pack.h.nim"
include "stb_truetype/stb_truetype.h.nim"

import sequtils, math

type
    stbtt_pack_context = object
        user_allocator_context, pack_info: pointer
        width, height, stride_in_bytes, padding: cint
        h_oversample, v_oversample: cuint
        pixels: ptr cuchar
        nodes: pointer
    stbtt_packed_char {.pure.} = object
        x0, y0, x1, y1: cushort
        xoff, yoff, xadvance: cfloat
        xoff2, yoff2: cfloat
    stbtt_pack_range {.pure.} = object
        font_size: cfloat
        first_unicode_char_in_range: cint
        array_of_unicode_codepoints: ptr cint
        num_chars: cint
        char_data_for_range: ptr stbtt_packed_char
        h_oversample, v_oversample: cuchar
        
    PackedChar* = stbtt_packed_char
    PackContext* = stbtt_pack_context

    PackRangeType* = enum
        packRangeRange, packRangeSeq
    PackRange* = object
        case typ*: PackRangeType
        of packRangeRange:
            first_unicode_char_in_range*: int
            num_chars*: int            
        of packRangeSeq:
            array_of_unicode_codepoints*: seq[int]
        font_size*: float32
    AlignedQuad* = object
        x0*, y0*, s0*, t0*: float32
        x1*, y1*, s1*, t1*: float32

proc stbtt_PackBegin(spc: ptr stbtt_pack_context, pixels: ptr cuchar, 
    width, height, stride_in_bytes, padding: cint, alloc_context: pointer): cint
        {.importc: "stbtt_PackBegin", noDecl.}
proc stbtt_PackEnd(spc: ptr stbtt_pack_context) {.importc: "stbtt_PackEnd", noDecl.}

proc stbtt_PackFontRange(spc: ptr stbtt_pack_context, font_data: ptr cuchar, font_index: cint, 
    font_size: cfloat, first_unicode_char_in_range, num_chars_in_range: cint, 
        char_data_for_range: ptr stbtt_packed_char): cint {.importc: "stbtt_PackFontRange", noDecl.}
proc stbtt_PackFontRanges(spc: ptr stbtt_pack_context, font_data: ptr cuchar, font_index: cint, 
    ranges: ptr stbtt_pack_range, num_ranges: cint): cint {.importc: "stbtt_PackFontRanges", noDecl.}

proc stbtt_PackSetOversampling(spc: ptr stbtt_pack_context, h_oversample, v_overample: cuint)
    {.importc: "stbtt_PackSetOversampling", noDecl.}

proc packBegin*(spc: var PackContext, pixels: string, width, height, stride_in_bytes, padding: int): int =
    int stbtt_PackBegin(addr spc, cast[ptr cuchar](unsafeAddr pixels[0]), 
        cint width, cint height, cint stride_in_bytes, cint padding, nil)
proc packEnd*(spc: var PackContext) =
    stbtt_PackEnd(addr spc)

proc packFontRange*(spc: var PackContext, font_data: string, font_index: int, font_size: float32,
    first_unicode_char_in_range, num_chars_in_range: int, char_data_for_range: var seq[PackedChar]): int =
    char_data_for_range.setLen(num_chars_in_range)
    stbtt_PackFontRange(addr spc, cast[ptr cuchar](unsafeAddr font_data[0]), cint font_index,
        cfloat font_size, cint first_unicode_char_in_range, cint num_chars_in_range, 
            addr char_data_for_range[0])

proc packFontRanges*(spc: var PackContext, font_data: string, font_index: int, ranges: openArray[PackRange]): (int, seq[seq[PackedChar]]) =
    var 
        cRanges = newSeqOfCap[stbtt_pack_range](ranges.len)
        unicode_codepoint_ranges = newSeq[seq[cint]]()
    result[1] = @[]
    for p in pairs(ranges):
        let 
            r = p[1]
            i = p[0]
        if r.typ == packRangeRange:
            result[1].add(newSeq[PackedChar](r.num_chars))            
            cRanges.add(stbtt_pack_range(font_size: cfloat r.font_size, first_unicode_char_in_range: 
                cint r.first_unicode_char_in_range, num_chars: cint r.num_chars,
                ))
        else:
            result[1].add(newSeq[PackedChar](r.array_of_unicode_codepoints.len))
            unicode_codepoint_ranges.add r.array_of_unicode_codepoints.map(proc(x: int): cint = cint x)
            cRanges.add(stbtt_pack_range(font_size: cfloat r.font_size, 
                num_chars: cint ranges[i].array_of_unicode_codepoints.len, 
                    array_of_unicode_codepoints: unsafeAddr unicode_codepoint_ranges[high(unicode_codepoint_ranges)][0]))
        cRanges[high(cRanges)].char_data_for_range = cast[ptr stbtt_packed_char](addr result[1][high(result[1])][0])                    
    result[0] = int stbtt_PackFontRanges(addr spc, unsafeAddr font_data[0], cint font_index, addr cRanges[0], cint cRanges.len)

proc packSetOverampling*(spc: var PackContext, h_oversample, v_overample: range[0..8]) =
    stbtt_PackSetOversampling(addr spc, cuint h_oversample, cuint v_overample)

proc getPackedQuad*(b: PackedChar, pw, ph: int, xpos, ypos: var float32, align_to_integer: bool): AlignedQuad =
    let
        ipw = 1f / float32 pw
        iph = 1f / float32 ph
    
    if align_to_integer:
        let
            x = round(xpos + b.xoff)
            y = round(ypos + b.yoff)
        result.x0 = x
        result.y0 = y
        result.x1 = x + b.xoff2 - b.xoff
        result.y1 = y + b.yoff2 - b.yoff
    else:
        result.x0 = xpos + b.xoff
        result.y0 = ypos + b.yoff
        result.x1 = xpos + b.xoff2
        result.y1 = ypos + b.yoff2
    
    result.s0 = float32(b.x0) * ipw
    result.t0 = float32(b.y0) * iph
    result.s1 = float32(b.x1) * ipw
    result.t1 = float32(b.y1) * iph

    xpos += b.xadvance