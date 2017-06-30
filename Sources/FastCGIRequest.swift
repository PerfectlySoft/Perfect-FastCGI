//
//  FastCGIRequest.swift
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

final class FastCGIRequest: HTTPRequest {
    
    var requestId: UInt16 = 0
    var lastRecordType: UInt8 = 0
    
    var method = HTTPMethod.get
    var path = ""
	var pathComponents = [String]()
    var queryString = ""
    var protocolVersion = (1, 0)
    var remoteAddress = (host: "", port: 0 as UInt16)
    var serverAddress = (host: "", port: 0 as UInt16)
    var serverName = ""
    var documentRoot = "./webroot"
    let connection: NetTCP
	var urlVariables = [String:String]()
	var scratchPad = [String:Any]()
    var mimes: MimeReader?
    var workingBuffer = [UInt8]()
    
    private var headerStore = Dictionary<HTTPRequestHeader.Name, String>()
    
    lazy var queryParams: [(String, String)] = {
        return self.deFormURLEncoded(string: self.queryString)
    }()
    
    var headers: AnyIterator<(HTTPRequestHeader.Name, String)> {
        var g = self.headerStore.makeIterator()
        return AnyIterator<(HTTPRequestHeader.Name, String)> {
            guard let n = g.next() else {
                return nil
            }
            return (n.key, n.value)
        }
    }
    
    lazy var postParams: [(String, String)] = {
        
        if let mime = self.mimes {
            return mime.bodySpecs.filter { $0.file == nil }.map { ($0.fieldName, $0.fieldValue) }
        } else if let bodyString = self.postBodyString {
            return self.deFormURLEncoded(string: bodyString)
        }
        return [(String, String)]()
    }()
    
    var postBodyBytes: [UInt8]? {
        get {
            if let _ = mimes {
                return nil
            }
            return workingBuffer
        }
        set {
            if let nv = newValue {
                workingBuffer = nv
            } else {
                workingBuffer.removeAll()
            }
        }
    }
    
    var postBodyString: String? {
        guard let bytes = postBodyBytes else {
            return nil
        }
        if bytes.isEmpty {
            return ""
        }
        return UTF8Encoding.encode(bytes: bytes)
    }
    var postFileUploads: [MimeReader.BodySpec]? {
        guard let mimes = self.mimes else {
            return nil
        }
        return mimes.bodySpecs
    }
    
    var contentType: String? {
        return self.headerStore[.contentType]
    }
    
    typealias StatusCallback = (HTTPResponseStatus) -> ()
    
    init(connection: NetTCP) {
        self.connection = connection
    }
    
    func header(_ named: HTTPRequestHeader.Name) -> String? {
        return headerStore[named]
    }
    
    func addHeader(_ named: HTTPRequestHeader.Name, value: String) {
        guard let existing = headerStore[named] else {
            self.headerStore[named] = value
            return
        }
        if named == .cookie {
            self.headerStore[named] = existing + "; " + value
        } else {
            self.headerStore[named] = existing + ", " + value
        }
    }
    
    func setHeader(_ named: HTTPRequestHeader.Name, value: String) {
        headerStore[named] = value
    }
    
    func setHeader(named: String, value: String) {
        let lowered = named.lowercased()
        setHeader(HTTPRequestHeader.Name.fromStandard(name: lowered), value: value)
    }
    
    private func addParam(name: String, value: String) {
        let httpChars = "HTTP_".characters
        switch name {
        case "REQUEST_METHOD":
            method = HTTPMethod.from(string: value)
        case "SERVER_PROTOCOL":
            if value == "HTTP/1.1" {
                protocolVersion = (1, 1)
            }
        case "DOCUMENT_ROOT":
            documentRoot = value
        case "SERVER_NAME":
            serverName = value
        case "SERVER_ADDR":
            serverAddress.host = value
        case "SERVER_PORT":
            serverAddress.port = UInt16(value) ?? 0
        case "REMOTE_ADDR":
            remoteAddress.host = value
        case "REMOTE_PORT":
            remoteAddress.port = UInt16(value) ?? 0
        case "QUERY_STRING":
            queryString = value
        case "REQUEST_URI":
            path = value
        default:
            let nameChars = name.characters
            if nameChars.starts(with: httpChars) {
                let newName = String(nameChars[nameChars.index(nameChars.startIndex, offsetBy: httpChars.count)..<nameChars.endIndex]).lowercased().stringByReplacing(string: "_", withString: "-")
                addHeader(HTTPRequestHeader.Name.fromStandard(name: newName), value: value)
            } // else unknown or unwanted header - ignored
        }
    }
    
    func readRequest(callback: @escaping StatusCallback) {
        self.readRecord(continuation: {
            record in
            guard let record = record else {
                return callback(.requestTimeout)
            }
            self.handleRecord(record, callback: callback)
        }, callback: callback)
    }

    func readRecord(continuation: @escaping (FastCGIRecord?) -> (), callback: @escaping StatusCallback) {
        self.connection.readBytesFully(count: fcgiBaseRecordSize, timeoutSeconds: fcgiTimeoutSeconds) {
            [weak self]
            b in
            guard let recBytes = b else {
                return continuation(nil)
            }
            let record = FastCGIRecord()
            record.version = recBytes[0]
            record.recType = recBytes[1]
            record.requestId = ((UInt16(recBytes[3]) << 8) | UInt16(recBytes[2])).netToHost
            record.contentLength = ((UInt16(recBytes[5]) << 8) | UInt16(recBytes[4])).netToHost
            record.paddingLength = recBytes[6];
            record.reserved = recBytes[7]
            self?.readRecordContent(record: record, continuation: continuation, callback: callback)
        }
    }
    
    func readRecordContent(record rec: FastCGIRecord, continuation: @escaping (FastCGIRecord?) -> (), callback: @escaping StatusCallback) {
        guard rec.contentLength > 0 else {
            return self.readRecordPadding(record: rec, continuation: continuation, callback: callback)
        }
        self.connection.readBytesFully(count: Int(rec.contentLength), timeoutSeconds: fcgiTimeoutSeconds) {
            [weak self]
            b in
            if let contentBytes = b {
                rec.content = contentBytes
                self?.readRecordPadding(record: rec, continuation: continuation, callback: callback)
            } else {
                continuation(nil)
            }
        }
    }
    
    func readRecordPadding(record rec: FastCGIRecord, continuation: @escaping (FastCGIRecord?) -> (), callback: StatusCallback) {
        guard rec.paddingLength > 0 else {
            return continuation(rec)
        }
        self.connection.readBytesFully(count: Int(rec.paddingLength), timeoutSeconds: fcgiTimeoutSeconds) {
            b in
            if let paddingBytes = b {
                rec.padding = paddingBytes
                continuation(rec)
            } else {
                continuation(nil)
            }
        }
    }
    
    func handleRecord(_ fcgiRecord: FastCGIRecord, callback: @escaping StatusCallback) {
        switch fcgiRecord.recType {
        case fcgiBeginRequest:
            guard let content = fcgiRecord.content else {
                return callback(.badRequest)
            }
            // FastCGIBeginRequestBody UInt16 role, UInt8 flags
            let role: UInt16 = ((UInt16(content[1]) << 8) | UInt16(content[0])).netToHost
            let flags: UInt8 = content[2]
            addHeader(.custom(name: "x-fcgi-role"), value: String(role))
            addHeader(.custom(name: "x-fcgi-flags"), value: String(flags))
            requestId = fcgiRecord.requestId
        case fcgiParams:
            if let bytes = fcgiRecord.content , fcgiRecord.contentLength > 0 {
                var idx = 0
                repeat {
                    // sizes are either one byte or 4
                    var sz = Int32(bytes[idx])
                    idx += 1
                    if (sz & 0x80) != 0 { // name length
                        sz = (sz & 0x7f) << 24
                        sz += (Int32(bytes[idx]) << 16)
                        idx += 1
                        sz += (Int32(bytes[idx]) << 8)
                        idx += 1
                        sz += Int32(bytes[idx])
                        idx += 1
                    }
                    var vsz = Int32(bytes[idx])
                    idx += 1
                    if (vsz & 0x80) != 0 { // value length
                        vsz = (vsz & 0x7f) << 24
                        vsz += (Int32(bytes[idx]) << 16)
                        idx += 1
                        vsz += (Int32(bytes[idx]) << 8)
                        idx += 1
                        vsz += Int32(bytes[idx])
                        idx += 1
                    }
                    if sz > 0 {
                        let idx2 = Int(idx + sz)
                        let name = UTF8Encoding.encode(bytes: bytes[idx..<idx2])
                        let idx3 = idx2 + Int(vsz)
                        let value = UTF8Encoding.encode(bytes: bytes[idx2..<idx3])
                        addParam(name: name, value: value)
                        idx = idx3
                    }
                } while idx < bytes.count
            }
        case fcgiStdin:
            if let content = fcgiRecord.content , fcgiRecord.contentLength > 0 {
                putPostData(content)
            } else { // done initiating the request. run with it
                return callback(.ok)
            }
        case fcgiData:
            if let content = fcgiRecord.content , fcgiRecord.contentLength > 0 {
                addHeader(.custom(name: "x-fcgi-data"), value: UTF8Encoding.encode(bytes: content))
            }
        case fcgiXStdin:
            if let content = fcgiRecord.content , Int(fcgiRecord.contentLength) == MemoryLayout<UInt32>.size {
                let one = UInt32(content[0])
                let two = UInt32(content[1])
                let three = UInt32(content[2])
                let four = UInt32(content[3])
                let size = ((four << 24) + (three << 16) + (two << 8) + one).netToHost
                readXStdin(size: Int(size), callback: callback)
                return
            }
        default:
            print("Unhandled FastCGI record type \(fcgiRecord.recType)")
        }
        lastRecordType = fcgiRecord.recType
        readRequest(callback: callback)
    }
    
    func readXStdin(size: Int, callback: @escaping StatusCallback) {
        connection.readSomeBytes(count: size) {
            [weak self]
            b in
            guard let bytes = b else {
                self?.connection.close()
                return callback(.requestTimeout) // died. timed out. errorered
            }
            self?.putPostData(bytes)
            let remaining = size - bytes.count
            if  remaining == 0 {
                self?.lastRecordType = fcgiStdin
                self?.readRequest(callback: callback)
            } else {
                self?.readXStdin(size: remaining, callback: callback)
            }
        }
    }
    
    func putPostData(_ b: [UInt8]) {
        if self.workingBuffer.count == 0 && self.mimes == nil {
            if let contentType = self.contentType , contentType.characters.starts(with: "multipart/form-data".characters) {
                self.mimes = MimeReader(contentType)
            }
        }
        if let mimes = self.mimes {
            return mimes.addToBuffer(bytes: b)
        } else {
            self.workingBuffer.append(contentsOf: b)
        }
    }
    
    private func deFormURLEncoded(string: String) -> [(String, String)] {
        return string.characters.split(separator: "&").map(String.init).flatMap {
            let d = $0.characters.split(separator: "=").flatMap { String($0).stringByDecodingURL }
            if d.count == 2 { return (d[0], d[1]) }
            if d.count == 1 { return (d[0], "") }
            return nil
        }
    }
}
