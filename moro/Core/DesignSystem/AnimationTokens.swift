//
//  AnimationTokens.swift
//  Moro
//
//  Animation Design System v1.0
//  Light. Simple. Friendly.
//
//  全局动画配置，用于确保整个 App 动画风格统一、轻量、克制。
//  适用于 SwiftUI、Timeline、Detail、Profile、Compose、Onboarding 等所有页面。
//  使用方式：AnimationTokens.duration.md, AnimationTokens.spring.soft, AnimationTokens.motion.md
//

import SwiftUI

public enum AnimationTokens {

    // MARK: - Duration Tokens
    public enum duration {
        /// 极快交互动画（按钮点击、轻反馈）
        public static let xs: Double = 0.10

        /// 微交互（按钮、Tab 切换）
        public static let sm: Double = 0.16

        /// 功能动画（列表插入、回复加载）
        public static let md: Double = 0.22

        /// 模态/底部弹窗、结构动画
        public static let lg: Double = 0.28

        /// 情感动画（Lottie 轻动效）
        public static let xl: Double = 0.50

        /// Onboarding 较大幅动画
        public static let xxl: Double = 0.60
    }

    // MARK: - Easing Tokens
    public enum easing {
        /// 标准 easeOut（用于列表、淡入淡出）
        public static let easeOutMD: Animation =
            .easeOut(duration: AnimationTokens.duration.md)

        /// 较柔的 easeOut（弹窗、浮层）
        public static let easeOutLG: Animation =
            .easeOut(duration: AnimationTokens.duration.lg)

        /// 标准 easeInOut（切换、进度变化）
        public static let easeInOut: Animation =
            .easeInOut(duration: AnimationTokens.duration.lg)

        /// 轻柔 Spring（Tap、按钮弹跳）
        public static let springSoft: Animation =
            .spring(response: 0.30, dampingFraction: 0.80)

        /// 中等 Spring（结构性变化）
        public static let springMedium: Animation =
            .spring(response: 0.35, dampingFraction: 0.70)

        /// 偏硬 Spring（稳定、最小回弹）
        public static let springFirm: Animation =
            .spring(response: 0.25, dampingFraction: 0.85)
    }

    // MARK: - Motion Tokens (Translation)
    public enum motion {
        /// 微移动（2pt）用于细微 UI 元素变化
        public static let xs: CGFloat = 2

        /// 小幅过渡（4pt）用于轻量插入动效
        public static let sm: CGFloat = 4

        /// 中幅过渡（8pt）用于列表、卡片
        public static let md: CGFloat = 8

        /// 较大（12pt）用于弹窗、Page 转场
        public static let lg: CGFloat = 12
    }

    // MARK: - Scale Tokens
    public enum scale {
        /// 按下轻缩放（Tap Down）
        public static let tapDown: CGFloat = 0.94

        /// 点赞弹跳最大缩放（上限避免太夸张）
        public static let likeBounce: CGFloat = 1.12

        /// 通用轻跃动（用于图标吸引注意）
        public static let gentleBounce: CGFloat = 1.06
    }

    // MARK: - Opacity Tokens
    public enum opacity {
        /// 列表插入初始透明度
        public static let listStart: Double = 0.0

        /// 弹窗背景蒙层
        public static let modalBackground: Double = 0.38
    }
}