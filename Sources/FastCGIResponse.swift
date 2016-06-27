//
//  FastCGIResponse.swift
//  PerfectFastCGI
//
//  Created by Kyle Jessup on 2016-06-27.
//	Copyright (C) 2016 PerfectlySoft, Inc.
//
//===----------------------------------------------------------------------===//
//
// This source file is part of the Perfect.org open source project
//
// Copyright (c) 2015 - 2016 PerfectlySoft Inc. and the Perfect project authors
// Licensed under Apache License v2.0
//
// See http://perfect.org/licensing.html for license information
//
//===----------------------------------------------------------------------===//
//

import PerfectLib
import PerfectNet

class FastCGIResponse: HTTPResponse {
    let request: HTTPRequest
    var status: HTTPResponseStatus = .ok
    var isStreaming = false
    var bodyBytes = [UInt8]()
    var completedCallback: (() -> ())?
    var cookies = [HTTPCookie]()
    var headerStore = Array<(HTTPResponseHeader.Name, String)>()
    var headers: AnyIterator<(HTTPResponseHeader.Name, String)> {
        var g = self.headerStore.makeIterator()
        return AnyIterator<(HTTPResponseHeader.Name, String)> {
            g.next()
        }
    }
    var connection: NetTCP {
        return request.connection
    }
    
    init(request: FastCGIRequest) {
        self.request = request
        let net = request.connection
        self.completedCallback = {
            let finalBytes = self.makeEndRequestBody(requestId: Int(request.requestId), appStatus: self.status.code, protocolStatus: fcgiRequestComplete)
            net.write(bytes: finalBytes) {
                _ in
                net.close()
            }
        }
    }
    
    func completed() {
        if let cb = self.completedCallback {
            cb()
        }
    }
    
    func addCookie(_ cookie: HTTPCookie) {
        cookies.append(cookie)
    }
    
    func header(_ named: HTTPResponseHeader.Name) -> String? {
        for (n, v) in headerStore where n == named {
            return v
        }
        return nil
    }
    
    func addHeader(_ name: HTTPResponseHeader.Name, value: String) {
        headerStore.append((name, value))
    }
    
    func setHeader(_ name: HTTPResponseHeader.Name, value: String) {
        var fi = [Int]()
        for i in 0..<headerStore.count {
            let (n, _) = headerStore[i]
            if n == name {
                fi.append(i)
            }
        }
        fi = fi.reversed()
        for i in fi {
            headerStore.remove(at: i)
        }
        addHeader(name, value: value)
    }
    
    func appendBody(bytes: [UInt8]) {
        bodyBytes.append(contentsOf: bytes)
    }
    
    func appendBody(string: String) {
        bodyBytes.append(contentsOf: [UInt8](string.utf8))
    }
    
    func setBody(json: [String:Any]) throws {
        let string = try json.jsonEncodedString()
        bodyBytes = [UInt8](string.utf8)
    }
    
    func push(callback: (Bool) -> ()) {
        
    }
    
    func addCookies() {
        for cookie in self.cookies {
            var cookieLine = ""
            cookieLine.append(cookie.name!.stringByEncodingURL)
            cookieLine.append("=")
            cookieLine.append(cookie.value!.stringByEncodingURL)
            
            if let expires = cookie.expires {
                switch expires {
                case .session: ()
                case .absoluteDate(let date):
                    cookieLine.append(";expires=" + date)
                case .absoluteSeconds(let seconds):
                    let formattedDate = try! formatDate(secondsToICUDate(seconds*60),
                                                        format: "%a, %d-%b-%Y %T GMT",
                                                        timezone: "GMT")
                    cookieLine.append(";expires=" + formattedDate)
                case .relativeSeconds(let seconds):
                    let formattedDate = try! formatDate(getNow() + secondsToICUDate(seconds*60),
                                                        format: "%a, %d-%b-%Y %T GMT",
                                                        timezone: "GMT")
                    cookieLine.append(";expires=" + formattedDate)
                }
            }
            if let path = cookie.path {
                cookieLine.append("; path=" + path)
            }
            if let domain = cookie.domain {
                cookieLine.append("; domain=" + domain)
            }
            if let secure = cookie.secure {
                if secure == true {
                    cookieLine.append("; secure")
                }
            }
            if let httpOnly = cookie.httpOnly {
                if httpOnly == true {
                    cookieLine.append("; HttpOnly")
                }
            }
            addHeader(.setCookie, value: cookieLine)
        }
        self.cookies.removeAll()
    }

    func makeEndRequestBody(requestId rid: Int, appStatus: Int, protocolStatus: Int) -> [UInt8] {
        
        let b = Bytes()
        b.import8Bits(from: fcgiVersion1)
            .import8Bits(from: fcgiEndRequest)
            .import16Bits(from: UInt16(rid).hostToNet)
            .import16Bits(from: UInt16(8).hostToNet)
            .import8Bits(from: 0)
            .import8Bits(from: 0)
            .import32Bits(from: UInt32(appStatus).hostToNet)
            .import8Bits(from: UInt8(protocolStatus))
            .import8Bits(from: 0)
            .import8Bits(from: 0)
            .import8Bits(from: 0)
        
        return b.data
    }
}
