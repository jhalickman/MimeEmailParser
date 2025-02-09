//
//  WordDecoder.swift
//  MimeEmailParser
//
//  Created by Igor Rendulic on 4/2/20.
//
//  Copyright (c) 2020 Igor Rendulic. All rights reserved.
/*
 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

import Foundation

public enum WordError: Error {
    case invalidWord
    case notEncoded
}

// WordDecoder decodes an RFC 2047 encoded-word (q, b words)
public class WordDecoder {
    
    public init(){}

    public func decodeRFC2047Word(word:String) throws -> String {
        var input = word
        // See https://tools.ietf.org/html/rfc2047#section-2 for details.
        // Our decoder is permissive, we accept empty encoded-text.
        if input.count < 8 || !input.hasPrefix("=?") || !input.hasSuffix("?=") || input.countInstances(of: "?") != 4 {
            throw WordError.notEncoded
        }
        // split delimits the first 2 fields
        
        input = String(input[2 ..< input.count-2])
        // split delimits the first 2 fields
        let splitIndex = input.indexDistance(of: "?")!
        // split word "UTF-8?q?ascii" into "UTF-8", 'q', and "ascii"
        let charset = input[..<splitIndex]
        if charset.isEmpty {
            throw WordError.invalidWord
        }
        if input.count < splitIndex + 3 {
            throw WordError.invalidWord
        }
        let encoding = input[splitIndex + 1]
        // the field after split must only be one byte
        if input[splitIndex+2] != "?" {
            throw WordError.invalidWord
        }
        let text = String(input[(splitIndex+3)...])
        
        let content = try decode(encoding: encoding, text: text, charset: String(charset))
        let output = try convert(charset: String(charset), content: content)
        return output
    }
    
    fileprivate func decode(encoding:Character, text:String, charset:String) throws -> String {
        switch encoding {
        case "B", "b":
            let d = Data(base64Encoded: text)!
            let encoding = charsetToSwiftEncoding(charset: charset)
            return String(data: d, encoding: encoding)!
        case "Q", "q":
            return try qDecode(s: text,  charset: charset)
        default:
            return ""
        }
    }
    
    fileprivate func qDecode(s:String, charset:String) throws -> String {
        var dec = [UInt8]()
        var i = 0
        while true {
            if i >= s.count {
                break
            }
            let char = s[i]
            if char == "_" {
                let space = String(" ").utf8.map{UInt8($0)}
                dec.append(contentsOf: space)
            } else if char == "=" {
                if i+2 >= s.count {
                    throw WordError.invalidWord
                }
                let b = try readHexByte(a: s[i+1], b: s[i+2])
                dec.append(b)
                i += 2
            } else if (char <= "~" && char >= " ") || char == "\n" || char == "\r" || char == "\t" {
                let charBytes = String(char).utf8.map{UInt8($0)}
                dec.append(contentsOf: charBytes)
            } else {
                throw WordError.invalidWord
            }
            i += 1
        }
        let data = Data(dec)
        
        let encoding = charsetToSwiftEncoding(charset: charset)
        
        return String(data: data, encoding: encoding)!
    }
    
    fileprivate func charsetToSwiftEncoding(charset:String) -> String.Encoding {
        switch charset.lowercased() {
            case "us-ascii":
                return String.Encoding.ascii
            //case "":
            //    return String.Encoding.iso2022JP
            case "iso-8859-1":
                return String.Encoding.isoLatin1
            case "iso-8859-2":
                return String.Encoding.isoLatin2
            case "iso-8859-15":
                /* TODO This is the right way to do it but calls functions that do no compile on Linux
                 let cfEnc = CFStringEncodings.isoLatin9
                let nsEnc = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cfEnc.rawValue))
                return String.Encoding(rawValue: nsEnc)*/
                return String.Encoding.isoLatin2
            case "gb2312":
                return String.Encoding.japaneseEUC
            case "macintosh":
                return String.Encoding.macOSRoman
            //case "":
            //    return String.Encoding.nextstep
            //case "":
            //    return String.Encoding.nonLossyASCII
            //case "":
            //    return String.Encoding.shiftJIS
            //case "":
            //    return String.Encoding.symbol
            case "utf-16":
                return String.Encoding.utf16
            case "utf-16be":
                return String.Encoding.utf16BigEndian
            case "utf-16le":
                return String.Encoding.utf16LittleEndian
            case "utf-32":
                return String.Encoding.utf32
            case "utf-32be":
                return String.Encoding.utf32BigEndian
            case "utf-32le":
                return String.Encoding.utf32LittleEndian
            case "utf-8":
                return String.Encoding.utf8
            case "windows-1250":
                return String.Encoding.windowsCP1250
            case "windows-1251":
                return String.Encoding.windowsCP1251
            case "windows-1252":
                return String.Encoding.windowsCP1252
            case "windows-1253":
                return String.Encoding.windowsCP1253
            case "windows-1254":
                return String.Encoding.windowsCP1254
            default:
                return String.Encoding.unicode
        }
   
    }
    
    fileprivate func convert(charset:String, content:String) throws -> String {
        if "utf-8".caseInsensitiveCompare(charset) == .orderedSame {
            return content
        }
        if "us-ascii".caseInsensitiveCompare(charset) == .orderedSame {
            var out = String()
            for char in content {
                if char.unicodeScalarCodePoint() >= 128 {
                    out.append("\u{FFFD}") // unicode replacement char
                } else {
                    out.append(char)
                }
            }
            return out
        } else {
            // convert to utf-8
            let newStr = String(utf8String: content.cString(using: .utf8)!)!
            return newStr
        }
    }
    
    fileprivate func readHexByte(a:Character, b:Character) throws -> UInt8 {
        let ab = String(a).utf8.map{UInt8($0)}[0]
        let bb = String(b).utf8.map{UInt8($0)}[0]
        let hb = try fromHex(c: ab)
        let lb = try fromHex(c: bb)
        let x = hb << 4 | lb
        return x
    }
    
    fileprivate func fromHex(c:UInt8) throws -> UInt8 {
        let c0 = String("0").utf8.map{UInt8($0)}[0]
        let c9 = String("9").utf8.map{UInt8($0)}[0]
        let cA = String("A").utf8.map{UInt8($0)}[0]
        let cF = String("F").utf8.map{UInt8($0)}[0]
        let ca = String("a").utf8.map{UInt8($0)}[0]
        let cf = String("f").utf8.map{UInt8($0)}[0]
        if c >= c0 && c <= c9 {
            return c - c0
        }
        if c >= cA && c <= cF {
            return c - cA + 10
        }
        // Accept badly encoded bytes.
        if c >= ca && c <= cf {
            return c - ca + 10
        }
        throw WordError.invalidWord
    }
}
