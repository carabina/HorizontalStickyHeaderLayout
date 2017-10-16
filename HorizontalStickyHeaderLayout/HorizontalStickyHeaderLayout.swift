//
//  CustomLayout.swift
//  Example
//
//  Created by Toshihiro Suzuki on 2017/10/06.
//  Copyright © 2017 toshi0383. All rights reserved.
//

import UIKit

private struct Layout {
    let indexPath: IndexPath
    let frame: CGRect
    var attributes: UICollectionViewLayoutAttributes {
        let attr = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        attr.frame = frame
        return attr
    }
}

public protocol HorizontalStickyHeaderLayoutDelegate: class {
    func collectionView(_ collectionView: UICollectionView, hshlSizeForItemAtIndexPath indexPath: IndexPath) -> CGSize
    func collectionView(_ collectionView: UICollectionView, hshlSectionInsetsAtSection section: Int) -> UIEdgeInsets
    func collectionView(_ collectionView: UICollectionView, hshlMinSpacingForCellsAtSection section: Int) -> CGFloat
    func collectionView(_ collectionView: UICollectionView, hshlSizeForHeaderAtSection section: Int) -> CGSize
    func collectionView(_ collectionView: UICollectionView, hshlHeaderInsetsAtSection section: Int) -> UIEdgeInsets
}

public final class HorizontalStickyHeaderLayout: UICollectionViewLayout {
    private var cacheForItems = [Layout]()
    public weak var delegate: HorizontalStickyHeaderLayoutDelegate?
    public var contentInset = UIEdgeInsets.zero
    lazy var animator: UIDynamicAnimator = {
        return UIDynamicAnimator(collectionViewLayout: self)
    }()

    // MARK: UICollectionViewLayout overrides
    public override func prepare() {
        super.prepare()

        // delegate
        if delegate == nil {
            if let d = collectionView?.delegate as? HorizontalStickyHeaderLayoutDelegate {
                delegate = d
            }
        }
        guard let delegate = delegate else {
            fatalError("Delegate is not set.")
        }
        guard let cv = collectionView else {
            fatalError("collectionView is not set.")
        }

        // prepare layout for cells
        var x: CGFloat = contentInset.left
        for section in 0..<cv.numberOfSections {
            let headerHeight = delegate.collectionView(cv, hshlSizeForHeaderAtSection: section).height
            let headerInsets = delegate.collectionView(cv, hshlHeaderInsetsAtSection: section)
            let sectionInsets: UIEdgeInsets = delegate.collectionView(cv, hshlSectionInsetsAtSection: section)
            x += sectionInsets.left
            let y = headerInsets.top
                + headerHeight
                + headerInsets.bottom
            let minSpacingForCells: CGFloat = delegate.collectionView(cv, hshlMinSpacingForCellsAtSection: section)
            let numberOfItems = cv.numberOfItems(inSection: section)
            for i in 0..<numberOfItems {
                let ip = IndexPath(item: i, section: section)
                let itemSize: CGSize = delegate.collectionView(cv, hshlSizeForItemAtIndexPath: ip)
                let frame = CGRect(x: x, y: y, width: itemSize.width, height: itemSize.height)
                cacheForItems.append(Layout(indexPath: ip, frame: frame))
                x += itemSize.width
                if i != numberOfItems - 1 {
                    x += minSpacingForCells
                }
            }
            x += sectionInsets.right
        }

        // setup UIDynamicAnimator
        let visibleRect = cv.bounds.insetBy(dx: 0, dy: 0)
        let visiblePaths = indexPaths(rect: visibleRect)
        do { // Items
            var currentlyVisible: [IndexPath] = []
            for behavior in animator.behaviors {
                if let behavior = behavior as? UIAttachmentBehavior,
                    let item = behavior.items
                        .flatMap({ $0 as? UICollectionViewLayoutAttributes })
                        .first(where: { $0.representedElementCategory == .cell }) {
                    if !visiblePaths.contains(item.indexPath) {
                        animator.removeBehavior(behavior)
                    } else {
                        currentlyVisible.append(item.indexPath)
                    }
                }
            }

            let newlyVisible = visiblePaths.filter { path in
                return !currentlyVisible.contains(path)
            }

            let staticAttributes = cacheForItems
                .filter { newlyVisible.contains($0.indexPath) }
                .map { $0.attributes }

            for attributes in staticAttributes {
                let spring = UIAttachmentBehavior(item: attributes, attachedToAnchor: attributes.center)
                animator.addBehavior(spring)
            }
        }
        do { // headers
            let visibleSections = Set(visiblePaths.map { $0.section })
            var currentlyVisible: [Int] = []
            for behavior in animator.behaviors {
                if let behavior = behavior as? UIAttachmentBehavior,
                    let item = behavior.items
                        .flatMap({ $0 as? UICollectionViewLayoutAttributes })
                        .first(where: { $0.representedElementCategory == .supplementaryView }) {
                    if !visibleSections.contains(item.indexPath.section) {
                        animator.removeBehavior(behavior)
                    } else {
                        currentlyVisible.append(item.indexPath.section)
                    }
                }
            }
            let newlyVisible = visibleSections.filter { section in
                return !currentlyVisible.contains(section)
            }

            let staticAttributes = getAttributesForHeaders()
                .filter { newlyVisible.contains($0.indexPath.section) }
            for attributes in staticAttributes {
                let spacing = UIAttachmentBehavior(item: attributes, attachedToAnchor: attributes.center)
                animator.addBehavior(spacing)
            }
        }
    }
    public override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        return animator.items(in: rect).map { $0 as! UICollectionViewLayoutAttributes }
    }
    public override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        return animator.layoutAttributesForCell(at: indexPath)
    }
    public override func layoutAttributesForSupplementaryView(ofKind elementKind: String, at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        return animator.layoutAttributesForSupplementaryView(ofKind: elementKind, at: indexPath)
    }
    public override var collectionViewContentSize: CGSize {
        guard let cv = collectionView, let delegate = delegate else {
            fatalError()
        }
        let maxX = cacheForItems.last?.frame.maxX ?? 0
        let lastSection = cv.numberOfSections - 1
        let sectionInsets: UIEdgeInsets = delegate.collectionView(cv, hshlSectionInsetsAtSection: lastSection)
        let contentWidth = maxX + sectionInsets.right
        let contentHeight = cv.bounds.height - contentInset.top - contentInset.bottom
        return CGSize(width: contentWidth, height: contentHeight)
    }

    /////////////////////////////////////////////////
    // Note: Needed for sticky headers while scroling

    override open func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        let attributesForHeaders = getAttributesForHeaders()
        for behavior in animator.behaviors {
            if let behavior = behavior as? UIAttachmentBehavior,
                let attributes = behavior.items
                    .flatMap({ $0 as? UICollectionViewLayoutAttributes })
                    .first(where: { $0.representedElementCategory == .supplementaryView }) {
                if let calculated = attributesForHeaders.first(where: { $0.indexPath == attributes.indexPath }) {
                    if attributes.center != calculated.center {
                        attributes.center = calculated.center
                        animator.updateItem(usingCurrentState: attributes)
                    }
                }
            }
        }
        return false
    }

    // MARK: Utilities

    /// Calculates sticky frame for header
    /// - returns: UICollectionViewLayoutAttributes for each sections
    private func getAttributesForHeaders() -> [UICollectionViewLayoutAttributes] {
        guard let delegate = delegate, let cv = collectionView else {
            fatalError()
        }
        var attributes = [UICollectionViewLayoutAttributes]()
        for section in 0..<cv.numberOfSections {
            var x: CGFloat = 0
            let headerSize = delegate.collectionView(cv, hshlSizeForHeaderAtSection: section)
            let headerInsets = delegate.collectionView(cv, hshlHeaderInsetsAtSection: section)
            let itemsInsets = delegate.collectionView(cv, hshlSectionInsetsAtSection: section)
            do {
                let numberOfItems = cv.numberOfItems(inSection: section)
                if let firstItemAttributes = animator.layoutAttributesForCell(at: IndexPath(item: 0, section: section) ),
                    let lastItemAttributes = animator.layoutAttributesForCell(at: IndexPath(row: numberOfItems - 1, section: section)) {

                    let edgeX = cv.contentOffset.x + contentInset.left + headerInsets.left
                    let xByLeftBoundary = max(edgeX, firstItemAttributes.frame.minX - itemsInsets.left + headerInsets.left)

                    let xByRightBoundary = (lastItemAttributes.frame.maxX + itemsInsets.right) - headerSize.width - headerInsets.right
                    x += min(xByLeftBoundary, xByRightBoundary)
                }
            }

            func shouldPopHeader() -> Bool {
                #if os(tvOS)
                    let cv = collectionView!
                    if let focusedItemFrame = cv.visibleCells.first(where: { $0.isFocused }).map({ $0.frame }) {
                        let shouldPop = !(focusedItemFrame.maxX < x ||
                            x + headerSize.width
                            + headerInsets.right // in case item next to is focused and enlarged
                            < focusedItemFrame.minX)
                        return shouldPop
                    } else {
                        return false
                    }
                #elseif os(iOS)
                    return false
                #endif
            }

            let deltaY: CGFloat = shouldPopHeader() ? -20 : 0
            let frame = CGRect(x: x + headerInsets.left,
                               y: headerInsets.top + deltaY,
                               width: headerSize.width,
                               height: headerSize.height)
            let attr = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: UICollectionElementKindSectionHeader,
                                                        with: IndexPath(item: 0, section: section))
            attr.frame = frame
            attributes.append(attr)
            x += headerInsets.right
        }
        return attributes
    }
    func firstIndexPath(_ rect: CGRect) -> IndexPath {
//        for layout in cacheForItems {
//            if layout.frame.origin.x >= rect.minX {
//                return layout.indexPath
//            }
//        }
//
//        return IndexPath(item: 0, section: 0)
        return cacheForItems.first!.indexPath
    }

    func lastIndexPath(_ rect: CGRect) -> IndexPath {
//        for layout in cacheForItems {
//            if layout.frame.origin.x >= rect.maxX {
//                return layout.indexPath
//            }
//        }
//        return IndexPath(item: 0, section: 0)
        return cacheForItems.last!.indexPath
    }

    func indexPaths(rect: CGRect) -> [IndexPath] {
        let min = firstIndexPath(rect)
        let max = lastIndexPath(rect)
        var indexPaths = [IndexPath]()
        for section in (min.section...max.section) {
            let numberOfItems = collectionView!.numberOfItems(inSection: section)
            indexPaths.append(contentsOf: (min.item..<numberOfItems).map { IndexPath(item: $0, section: section) })
        }
        return indexPaths
    }
}
