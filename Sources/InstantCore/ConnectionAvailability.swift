import Foundation

public enum ConnectionField: String, CaseIterable, Equatable {
    case baseURL, apiKey, model
}

public enum ConnectionIssue: Equatable {
    case missing([ConnectionField])
    case invalidURL, invalidKey, invalidModel, keychainUnavailable
}

public struct ConnectionConfiguration {
    public let baseURL: String
    public let key: String
    public let model: String

    public init(baseURL: String, key: String, model: String) {
        self.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public var issue: ConnectionIssue? {
        let missing = ConnectionField.allCases.filter {
            switch $0 {
            case .baseURL: return baseURL.isEmpty
            case .apiKey: return key.isEmpty
            case .model: return model.isEmpty
            }
        }
        if !missing.isEmpty { return .missing(missing) }
        if (try? ChatService.endpoint(for: baseURL)) == nil { return .invalidURL }
        let invalid = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
        if key.rangeOfCharacter(from: invalid) != nil { return .invalidKey }
        if model.rangeOfCharacter(from: invalid) != nil { return .invalidModel }
        return nil
    }
}

/// Only fixed categories cross into the UI. Provider messages may contain the
/// request, credentials, HTML or untrusted instructions and are never displayed.
public enum ModelFailureReason: String, CaseIterable, Equatable {
    case authentication, permission, model, endpoint, quota, rateLimited, unavailable
    case contextLimit, rejected, offline, network, timeout, certificate
    case empty, format, interrupted, filtered, outputLimit, unknown

    public static func http(_ status: Int) -> Self {
        switch status {
        case 401: return .authentication
        case 402: return .quota
        case 403: return .permission
        case 404, 405, 301...399: return .endpoint
        case 408, 504: return .timeout
        case 413: return .contextLimit
        case 429: return .rateLimited
        case 400, 409, 415, 422: return .rejected
        case 500...599: return .unavailable
        default: return .unknown
        }
    }
    public static func classify(_ error: Error) -> Self {
        if let error = error as? ChatError {
            switch error {
            case .failure(let reason): return reason
            case .status(let code): return http(code)
            case .emptyResponse: return .empty
            case .invalidResponse: return .format
            case .serverError: return .unavailable
            case .invalidURL: return .endpoint
            case .missingKey: return .authentication
            case .configuration: return .rejected
            }
        }
        if error is CancellationError { return .interrupted }
        let error = error as NSError
        if error.domain == NSURLErrorDomain {
            switch error.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorDataNotAllowed: return .offline
            case NSURLErrorTimedOut: return .timeout
            case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateHasBadDate,
                 NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasUnknownRoot,
                 NSURLErrorServerCertificateNotYetValid, NSURLErrorClientCertificateRejected,
                 NSURLErrorClientCertificateRequired: return .certificate
            case NSURLErrorCancelled, NSURLErrorNetworkConnectionLost: return .interrupted
            case NSURLErrorBadURL, NSURLErrorUnsupportedURL: return .endpoint
            case NSURLErrorBadServerResponse, NSURLErrorCannotParseResponse,
                 NSURLErrorCannotDecodeContentData, NSURLErrorCannotDecodeRawData: return .format
            case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed, NSURLErrorCannotConnectToHost: return .network
            default: return .network
            }
        }
        return .unknown
    }

    public static func providerError(in object: [String: Any]) -> Self? {
        let nested = object["error"] as? [String: Any]
        let hasError = object["error"].map { !($0 is NSNull) } ?? false
        let code = (nested?["code"] as? String) ?? (object["code"] as? String)
        let type = nested?["type"] as? String
        let values = [code, type].compactMap { $0 }.map {
            String($0.prefix(128)).lowercased().filter { $0.isLetter || $0.isNumber }
        }
        let successful = ["0", "200", "ok", "success"]
        guard hasError || (code != nil && !successful.contains(values.first ?? "")) else { return nil }
        for value in values {
            if ["invalidapikey", "incorrectapikey", "invalidaccesstoken", "authenticationerror"].contains(value) || value.hasPrefix("invalidapikey") { return .authentication }
            if ["arrearage", "insufficientquota", "billinghardlimitreached", "quotaexhausted", "allocationquotafreetieronly"].contains(value) { return .quota }
            // Aliyun's Throttling.AllocationQuota is throughput limiting, not a
            // reliable signal that the account has no balance.
            if value.hasPrefix("throttling") || ["ratelimitexceeded", "ratelimiterror", "limitrequests", "limitburst"].contains(value) { return .rateLimited }
            if ["modelnotfound", "invalidmodel", "modelnotsupported", "deploymentnotfound"].contains(value) { return .model }
            if value.hasPrefix("accessdenied") || ["permissiondenied", "permissionerror", "forbidden"].contains(value) { return .permission }
            if ["contextlengthexceeded", "maxcontextlengthexceeded", "inputtoolong", "requesttoolarge"].contains(value) { return .contextLimit }
            if ["datainspectionfailed", "contentfilter", "contentpolicyviolation", "inappropriatecontent"].contains(value) { return .filtered }
            if ["invalidparameter", "invalidrequesterror", "invalidparametererror", "badrequest", "unsupportedparameter"].contains(value) { return .rejected }
            if value.hasPrefix("internalerror") || ["serviceunavailable", "internalservererror", "servererror", "overloadederror"].contains(value) { return .unavailable }
        }
        return .unknown
    }
}
