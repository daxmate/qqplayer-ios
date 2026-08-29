//
//  MockURLProtocol.swift
//  QQPlayerTests
//
//  URLProtocol mock 测试基建（P2-F）：
//  - 拦截 URLSession 请求，按测试预设返回 (HTTPURLResponse, Data)，不发真实网络请求
//  - 记录收到的全部请求，供断言请求次数 / URL / Header
//  - 通过 URLSessionConfiguration.protocolClasses 注入：只影响测试创建的会话，
//    不影响 URLSession.shared 与其他测试
//
//  注意：handler / receivedRequests 是进程级静态状态，测试必须串行使用
//  （API 测试套件已 .serialized），每个测试开头调用 reset()。
//

import Foundation

final class MockURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)

    /// 预设响应处理器：测试按请求 URL 返回对应响应；抛错视为网络失败。
    nonisolated(unsafe) static var handler: Handler?

    /// 本测试收到的全部请求（按发起顺序）。
    nonisolated(unsafe) static var receivedRequests: [URLRequest] = []

    /// 每个测试开始前调用，清空上一个测试的残留状态。
    static func reset() {
        handler = nil
        receivedRequests = []
    }

    /// 构造注入 MockURLProtocol 的 URLSession（ephemeral，不共享缓存）。
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    /// 便捷方法：构造 JSON 响应。
    static func jsonResponse(_ body: String, status: Int = 200, for request: URLRequest) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(body.utf8))
    }

    // MARK: - URLProtocol

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        MockURLProtocol.receivedRequests.append(request)

        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
