//
//  WebUserAgent.swift
//  QueenRight
//
//  User-Agent браузерного движка — БЕЗ `import WebKit`.
//
//  ЗАЧЕМ ТАК. Импорт WebKit тянет фреймворк в бинарник и заявляет его в
//  зависимостях приложения, хотя ни одного веб-экрана здесь нет. Обращение
//  через ObjC-runtime даёт ту же строку, не добавляя зависимости: класс
//  ищется по имени, метод вызывается по селектору.
//
//  ПОЧЕМУ НЕ СОБРАТЬ СТРОКУ ВРУЧНУЮ. Внешняя аналитика сверяет UA с тем, что
//  видит на своей стороне при переходе по ссылке. Собранная вручную строка
//  разойдётся с настоящей на первой же смене версии iOS, и сверка перестанет
//  сходиться.
//

import Foundation
import UIKit

enum WebUserAgent {

    /// Кэш на время запуска: создание веб-вью недёшево, а строка не меняется.
    private static var cached: String?

    /// Получить UA. Возвращает nil, если движок недоступен или не ответил.
    ///
    /// Работает только на главном потоке: веб-вью — UI-объект, и создание его
    /// в фоне приводит к падению внутри WebKit.
    @MainActor
    static func resolve(timeout: TimeInterval = 3) async -> String? {
        if let cached { return cached }

        guard let webViewClass = NSClassFromString("WKWebView") as? NSObject.Type else {
            return nil
        }
        let webView = webViewClass.init()

        let selector = NSSelectorFromString("evaluateJavaScript:completionHandler:")
        guard webView.responds(to: selector) else { return nil }

        // Сигнатура метода WKWebView: (id, SEL, NSString*, void(^)(id, NSError*)).
        typealias Evaluate = @convention(c) (
            AnyObject, Selector, NSString, @escaping (Any?, Error?) -> Void
        ) -> Void

        guard let method = webView.method(for: selector) else { return nil }
        let evaluate = unsafeBitCast(method, to: Evaluate.self)

        let value: String? = await withCheckedContinuation { continuation in
            var finished = false
            let finish: (String?) -> Void = { result in
                guard !finished else { return }
                finished = true
                continuation.resume(returning: result)
            }

            // Срок на ответ: если движок молчит, старт приложения ждать не должен.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                finish(nil)
            }

            evaluate(webView, selector, "navigator.userAgent" as NSString) { result, _ in
                // `webView` захвачен замыканием намеренно: без сильной ссылки он
                // освободится раньше, чем движок успеет вызвать обработчик.
                _ = webView
                finish(result as? String)
            }
        }

        if let value, !value.isEmpty {
            cached = value
            return value
        }
        return nil
    }

    /// Уже полученное значение, без ожидания. Для запросов, которые не могут ждать.
    static var cachedValue: String? { cached }
}
