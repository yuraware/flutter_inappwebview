//
//  ViewportInsetsValidation.swift
//  flutter_inappwebview
//
//  Pure validation for WKWebView.setMinimumViewportInset(_:maximumViewportInset:).
//
//  That setter raises an *uncatchable* NSInvalidArgumentException (the app is
//  terminated) whenever WebKit considers the input invalid. It validates
//  against the web view's CURRENT frame, so the very same call is fine once
//  the view is laid out and fatal while it is still 0x0 — which is exactly the
//  state Flutter creates every platform view in (`CGRectZero`, sized later).
//
//  Shipped WebKit behaviour (Source/WebKit/UIProcess/API/Cocoa/WKWebView.mm):
//    * always: any negative inset, or minimum larger than maximum  -> throws
//    * iOS 15.5–15.x (WebKit 613): `frame - inset` empty             -> throws,
//      EVEN for `.zero` insets on an empty frame (no zero-inset guard)
//    * iOS 16+ (WebKit 7614+): same, but only when the inset size itself
//      is non-empty, i.e. zero/top-only insets never throw
//  We follow the strictest rule so the decision is safe on every iOS version.
//

import Foundation
import CoreGraphics
#if canImport(UIKit)
import UIKit
typealias ViewportEdgeInsets = UIEdgeInsets
#else
import AppKit
typealias ViewportEdgeInsets = NSEdgeInsets
#endif

enum ViewportInsetsDecision: Equatable {
    /// Safe to call `setMinimumViewportInset(_:maximumViewportInset:)` right now.
    case apply
    /// The frame cannot fit the insets yet; retry after the next layout pass.
    case deferUntilLayout
    /// Invalid regardless of frame — WebKit would always throw. Drop the request.
    case reject(reason: String)
}

enum ViewportInsetsValidation {
    static func decide(frameSize: CGSize,
                       minimum: ViewportEdgeInsets,
                       maximum: ViewportEdgeInsets) -> ViewportInsetsDecision {
        if hasNegativeComponent(minimum) {
            return .reject(reason: "minimumViewportInset cannot be negative")
        }
        if hasNegativeComponent(maximum) {
            return .reject(reason: "maximumViewportInset cannot be negative")
        }
        if minimum.top + minimum.bottom > maximum.top + maximum.bottom ||
            minimum.left + minimum.right > maximum.left + maximum.right {
            return .reject(reason: "minimumViewportInset cannot be larger than maximumViewportInset")
        }
        // WebKit: `(frame - inset).isEmpty()` where isEmpty is `width <= 0 || height <= 0`.
        if isEmpty(frameSize, minus: maximum) || isEmpty(frameSize, minus: minimum) {
            return .deferUntilLayout
        }
        return .apply
    }

    private static func hasNegativeComponent(_ insets: ViewportEdgeInsets) -> Bool {
        return insets.top < 0 || insets.left < 0 || insets.bottom < 0 || insets.right < 0
    }

    private static func isEmpty(_ size: CGSize, minus insets: ViewportEdgeInsets) -> Bool {
        let width = size.width - (insets.left + insets.right)
        let height = size.height - (insets.top + insets.bottom)
        return width <= 0 || height <= 0
    }
}
