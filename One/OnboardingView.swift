//
//  OnboardingView.swift
//  One
//

import SwiftUI

private struct OnboardingPage {
    let title: String
    let imageName: String
}

private enum OnboardingLayout {
    static let topBarArea: CGFloat = 60
    static let titleArea: CGFloat = 64
    static let mockupArea: CGFloat = 378
    static let dotsArea: CGFloat = 19
    static let buttonGap: CGFloat = 16
    static let buttonArea: CGFloat = 64

    static var sheetHeight: CGFloat {
        topBarArea + titleArea + mockupArea + dotsArea + buttonGap + buttonArea
    }
}

struct OnboardingView: View {
    static var preferredSheetHeight: CGFloat { OnboardingLayout.sheetHeight }

    var onComplete: () -> Void

    @State private var currentPage = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(title: "Create and view events/reminders", imageName: "onboardingMockup1L"),
        OnboardingPage(title: "Organize tasks into folders", imageName: "onboardingMockup2L"),
        OnboardingPage(title: "View upcomings in a separate tab", imageName: "onboardingMockup3L"),
        OnboardingPage(title: "Add widgets to your home screen", imageName: "onboardingMockup4L")
    ]

    private var isLastPage: Bool {
        currentPage == pages.count - 1
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.top, 20)

            Text(LocalizedStringKey(pages[currentPage].title))
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(Color.primaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.9)
                .padding(.top, 20)
                .padding(.horizontal, 8)
                .animation(.easeInOut(duration: 0.25), value: currentPage)

            mockupCarousel
                .padding(.top, 28)

            pageIndicator
                .padding(.top, 12)

            primaryButton
                .padding(.top, 16)
                .padding(.bottom, 16)
        }
        .padding(.horizontal, 24)
        .background(Color.sheetSurface)
    }

    private var topBar: some View {
        HStack {
            if currentPage > 0 {
                Button {
                    Haptics.light()
                    withAnimation(.easeInOut(duration: 0.25)) {
                        currentPage -= 1
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color.primaryText)
                        .frame(width: 40, height: 40)
                        .glassCircleClose()
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            } else {
                Color.clear
                    .frame(width: 40, height: 40)
            }

            Spacer()

            Button {
                Haptics.light()
                onComplete()
            } label: {
                Text("Skip")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            .buttonStyle(.plain)
        }
    }

    private var mockupCarousel: some View {
        TabView(selection: $currentPage) {
            ForEach(pages.indices, id: \.self) { index in
                Image(pages[index].imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxWidth: .infinity)
        .frame(height: 350)
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(pages.indices, id: \.self) { index in
                Circle()
                    .fill(index == currentPage ? Color.primaryText : Color.gray.opacity(0.35))
                    .frame(width: 7, height: 7)
                    .animation(.easeInOut(duration: 0.2), value: currentPage)
            }
        }
    }

    private var primaryButton: some View {
        Button {
            Haptics.light()
            if isLastPage {
                onComplete()
            } else {
                withAnimation(.easeInOut(duration: 0.25)) {
                    currentPage += 1
                }
            }
        } label: {
            Text(isLastPage ? "Get started" : "Next")
                .font(.body)
                .fontWeight(.semibold)
                .foregroundColor(Color.screenBackground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.primaryText)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.25), value: currentPage)
    }
}

#Preview {
    OnboardingView(onComplete: {})
}
