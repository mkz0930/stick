import Foundation

/// widget 调起的 URL host 枚举
enum StickWidgetHost: String {
    case chat
}

enum StickWidgetURLRouter {
    /// 异步把 seed 推到下一帧再写 — 让 app 先把主界面渲染出来，sheet/chat 出现时不抖
    static func route(_ url: URL, setChatSeed: @escaping (String) -> Void) {
        guard url.scheme == "stick",
              let host = StickWidgetHost(rawValue: url.host ?? "") else { return }

        switch host {
        case .chat:
            let seed = url.queryValue(for: "seed") ?? ""
            DispatchQueue.main.async { setChatSeed(seed) }
        }
    }
}

private extension URL {
    func queryValue(for name: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
    }
}
