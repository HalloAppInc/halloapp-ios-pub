//
//  SlideshowViewController2.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 8/24/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import UIKit

class SlideshowViewController: UIPageViewController {

    private let media: [FeedMedia]

    init(media: [FeedMedia]) {
        self.media = media
        super.init(transitionStyle: .scroll, navigationOrientation: .horizontal, options: [.interPageSpacing: 4])
        dataSource = self
        delegate = self

        if let mediaItem = media.first {
            let slideViewController = SlideshowSlideViewController()
            slideViewController.mediaItem = mediaItem
            setViewControllers([slideViewController], direction: .forward, animated: false)
        }
    }

    var timer: Timer?

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let closeButton = UIButton(type: .close)
        closeButton.addTarget(self, action: #selector(dismissAnimated), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
        ])

        view.backgroundColor = .black
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTap(_:))))
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard let slideViewController = viewControllers?.first as? SlideshowSlideViewController else {
            return
        }
        slideViewController.startAnimation()
        scheduleNextPageTransition()
    }

    @objc private func dismissAnimated() {
        dismiss(animated: true)
    }

    @objc private func didTap(_ tapGestureRecognizer: UITapGestureRecognizer) {
        guard let slideViewController = viewControllers?.first as? SlideshowSlideViewController,
              let mediaItem = slideViewController.mediaItem,
              let mediaIndex = media.firstIndex(of: mediaItem) else {
            return
        }

        let tapLocation = tapGestureRecognizer.location(in: view)

        switch tapLocation.x {
        case view.bounds.minX..<view.bounds.minX + view.bounds.width * 0.2:
            // page back
            transition(to: mediaIndex - 1)
        case view.bounds.maxX - view.bounds.width * 0.2..<view.bounds.maxX:
            // page forward
            transition(to: mediaIndex + 1)
        default:
            break
        }
    }

    private func transition(to index: Int) {
        guard index >= media.startIndex, index < media.endIndex else {
            return
        }
        let slideViewController = SlideshowSlideViewController()
        slideViewController.mediaItem = media[index]

        UIView.transition(with: view, duration: 0.8, options: [.transitionCrossDissolve, .beginFromCurrentState]) {
            self.setViewControllers([slideViewController], direction: .forward, animated: false)
        } completion: { _ in
            slideViewController.startAnimation()
            self.scheduleNextPageTransition()
        }
    }

    func scheduleNextPageTransition() {
        self.timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            guard let self,
                  let slideViewController = self.viewControllers?.first as? SlideshowSlideViewController,
                  let mediaItem = slideViewController.mediaItem,
                  let mediaIndex = self.media.firstIndex(of: mediaItem) else {
                return
            }
            self.transition(to: mediaIndex + 1)
        }
    }
}

extension SlideshowViewController: UIPageViewControllerDataSource {

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let slideViewController = viewController as? SlideshowSlideViewController,
              let mediaItem = slideViewController.mediaItem,
              let mediaIndex = media.firstIndex(of: mediaItem) else {
            return nil
        }

        let nextIndex = media.index(before: mediaIndex)
        guard nextIndex >= media.startIndex else {
            return nil
        }

        let vc = SlideshowSlideViewController()
        vc.mediaItem = media[nextIndex]
        return vc
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let slideViewController = viewController as? SlideshowSlideViewController,
              let mediaItem = slideViewController.mediaItem,
              let mediaIndex = media.firstIndex(of: mediaItem) else {
            return nil
        }

        let previousIndex = media.index(after: mediaIndex)
        guard previousIndex < media.endIndex else {
            return nil
        }

        let vc = SlideshowSlideViewController()
        vc.mediaItem = media[previousIndex]
        return vc
    }
}

extension SlideshowViewController: UIPageViewControllerDelegate {

    func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {

    }

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard let slideViewController = viewControllers?.first as? SlideshowSlideViewController else {
            return
        }
        previousViewControllers.forEach { ($0 as? SlideshowSlideViewController)?.reset() }
        slideViewController.startAnimation()
        scheduleNextPageTransition()
    }
}
