
import UIKit

class TalkPageTopicCell: CollectionViewCell {
    
    private let titleLabel = UILabel()
    private let unreadView = UIView()
    private let dividerView = UIView(frame: .zero)
    private let chevronImageView = UIImageView(frame: .zero)
    
    private var isDeviceRTL: Bool {
        return effectiveUserInterfaceLayoutDirection == .rightToLeft
    }
    
    var semanticContentAttributeOverride: UISemanticContentAttribute = .unspecified {
        didSet {
            textAlignmentOverride = semanticContentAttributeOverride == .forceRightToLeft ? NSTextAlignment.right : NSTextAlignment.left
            titleLabel.semanticContentAttribute = semanticContentAttributeOverride
        }
    }
    
    private var textAlignmentOverride: NSTextAlignment = .left {
        didSet {
            titleLabel.textAlignment = textAlignmentOverride
        }
    }

    override func sizeThatFits(_ size: CGSize, apply: Bool) -> CGSize {
        
        let adjustedMargins = UIEdgeInsets(top: layoutMargins.top + 5, left: layoutMargins.left + 5, bottom: layoutMargins.bottom + 5, right: layoutMargins.right + 5)
        
        let unreadIndicatorSideLength = CGFloat(11)
        let unreadIndicatorX = !isDeviceRTL ? adjustedMargins.left : size.width - adjustedMargins.right - unreadIndicatorSideLength
       
        let chevronSize = CGSize(width: 8, height: 14)
        let chevronX = !isDeviceRTL ? size.width - adjustedMargins.right - chevronSize.width : adjustedMargins.left
        
        let titleX = !isDeviceRTL ? unreadIndicatorX + unreadIndicatorSideLength + 15 : chevronX + chevronSize.width + 28
        let titleMaxX = !isDeviceRTL ? size.width - adjustedMargins.right - chevronSize.width - 28 : size.width - adjustedMargins.right - unreadIndicatorSideLength - 15
        
        let titleMaximumWidth = titleMaxX - titleX
        let titleOrigin = CGPoint(x: titleX, y: adjustedMargins.top)
        
        let titleLabelFrame = titleLabel.wmf_preferredFrame(at: titleOrigin, maximumWidth: titleMaximumWidth, alignedBy: semanticContentAttributeOverride, apply: apply)
        
        let finalHeight = adjustedMargins.top + titleLabelFrame.size.height + adjustedMargins.bottom
        
        if apply {
            
            dividerView.frame = CGRect(x: 0, y: finalHeight - 1, width: size.width, height: 1)
            unreadView.frame = CGRect(x: unreadIndicatorX, y: (finalHeight / 2) - (unreadIndicatorSideLength / 2), width: unreadIndicatorSideLength, height: unreadIndicatorSideLength)
            chevronImageView.frame = CGRect(x: chevronX, y: (finalHeight / 2) - (chevronSize.height / 2), width: chevronSize.width, height: chevronSize.height)
            titleLabel.textAlignment = textAlignmentOverride
        }
        
        return CGSize(width: size.width, height: finalHeight)
    }
    
    func configure(title: String, isRead: Bool = true) {
        unreadView.isHidden = isRead
        configureTitleLabel(title: title)
    }
    
    private func configureTitleLabel(title: String) {
        
        let font = UIFont.wmf_font(.body, compatibleWithTraitCollection: traitCollection)
        let boldFont = UIFont.wmf_font(.semiboldBody, compatibleWithTraitCollection: traitCollection)
        let italicfont = UIFont.wmf_font(.italicBody, compatibleWithTraitCollection: traitCollection)
        let attributedString = title.wmf_attributedStringFromHTML(with: font, boldFont: boldFont, italicFont: italicfont, boldItalicFont: boldFont, color: titleLabel.textColor, linkColor:nil, handlingLists: false, handlingSuperSubscripts: true, withAdditionalBoldingForMatchingSubstring:nil, tagMapping: ["a": "b"], additionalTagAttributes: nil)
        titleLabel.attributedText = attributedString
    }
    
    override func setup() {
        chevronImageView.image = UIImage.wmf_imageFlipped(forRTLLayoutDirectionNamed: "chevron-right")
        unreadView.layer.cornerRadius = 5.5
        contentView.addSubview(titleLabel)
        contentView.addSubview(dividerView)
        contentView.addSubview(unreadView)
        contentView.addSubview(chevronImageView)
        super.setup()
    }
}

extension TalkPageTopicCell: Themeable {
    func apply(theme: Theme) {
        titleLabel.textColor = theme.colors.primaryText
        setBackgroundColors(theme.colors.paperBackground, selected: theme.colors.baseBackground)
        dividerView.backgroundColor = theme.colors.border
        unreadView.backgroundColor = theme.colors.unreadIndicator
        chevronImageView.tintColor = theme.colors.secondaryText
    }
}
