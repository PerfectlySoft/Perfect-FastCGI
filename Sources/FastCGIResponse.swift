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
import PerfectHTTP

final class FastCGIResponse: HTTPResponse {
    let request: HTTPRequest
    let requestId: UInt16
    var status: HTTPResponseStatus = .ok
    var isStreaming = false
    var bodyBytes = [UInt8]()
    var completedCallback: (() -> ())?
    var wroteHeaders = false
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
        self.requestId = request.requestId
        let net = request.connection
        self.completedCallback = {
            self.completedCallback = nil
            self.push {
                ok in
                guard ok else {
                    net.close()
                    return
                }
                let finalBytes = self.makeEndRequestBody(requestId: Int(request.requestId), appStatus: self.status.code, protocolStatus: fcgiRequestComplete)
                net.write(bytes: finalBytes) {
                    _ in
                    net.close()
                }
            }
        }
    }
    
    func completed() {
        if let cb = self.completedCallback {
            cb()
        }
    }
    
    func header(_ named: HTTPResponseHeader.Name) -> String? {
        for (n, v) in headerStore where n == named {
            return v
        }
        return nil
    }
    
    func addHeader(_ name: HTTPResponseHeader.Name, value: String) -> Self {
        headerStore.append((name, value))
		return self
    }
    
    func setHeader(_ name: HTTPResponseHeader.Name, value: String) -> Self {
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
        return addHeader(name, value: value)
    }
    
    func pushHeaders(callback: @escaping (Bool) -> ()) {
        wroteHeaders = true
        var responseString = "Status: \(status)\r\n"
        for (n, v) in headers {
            responseString.append("\(n.standardName): \(v)\r\n")
        }
        responseString.append("\r\n")
        let bytes = makeStdoutBody(requestId: Int(requestId), data: [UInt8](responseString.utf8))
        connection.write(bytes: bytes) {
            _ in
            self.pushBody(callback: callback)
        }
    }
    
    func pushBody(callback: @escaping (Bool) -> ()) {
        guard !bodyBytes.isEmpty else {
            return callback(true)
        }
        let bytes = makeStdoutBody(requestId: Int(requestId), data: bodyBytes)
        connection.write(bytes: bytes) {
            wrote in
            self.bodyBytes.removeAll()
            callback(wrote == bytes.count)
        }
    }
    
    func push(callback: @escaping (Bool) -> ()) {
        if !wroteHeaders {
            pushHeaders(callback: callback)
        } else {
            pushBody(callback: callback)
        }
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
    
    func makeStdoutBody(requestId rid: Int, data: [UInt8], firstPos: Int, count: Int) -> [UInt8] {
        let b = Bytes()
        if count > fcgiBodyChunkSize {
            b.importBytes(from: makeStdoutBody(requestId: rid, data: data, firstPos: firstPos, count: fcgiBodyChunkSize))
                .importBytes(from: makeStdoutBody(requestId: rid, data: data, firstPos: fcgiBodyChunkSize + firstPos, count: count - fcgiBodyChunkSize))
        } else {
            let padBytes = count % 8
            b.import8Bits(from: fcgiVersion1)
                .import8Bits(from: fcgiStdout)
                .import16Bits(from: UInt16(rid).hostToNet)
                .import16Bits(from: UInt16(count).hostToNet)
                .import8Bits(from: UInt8(padBytes))
                .import8Bits(from: 0)
            if firstPos == 0 && count == data.count {
                b.importBytes(from: data)
            } else {
                b.importBytes(from: data[firstPos..<(firstPos+count)])
            }
            if padBytes > 0 {
                for _ in 1...padBytes {
                    b.import8Bits(from: 0)
                }
            }
        }
        return b.data
    }
    
    func makeStdoutBody(requestId rid: Int, data: [UInt8]) -> [UInt8] {
        return makeStdoutBody(requestId: rid, data: data, firstPos: 0, count: data.count)
    }
}
