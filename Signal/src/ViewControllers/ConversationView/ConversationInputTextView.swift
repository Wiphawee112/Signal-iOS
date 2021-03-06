//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc protocol ConversationInputTextViewDelegate {
    func didPasteAttachment(_ attachment: SignalAttachment?)
    func inputTextViewSendMessagePressed()
    func textViewDidChange(_ textView: UITextView)
}

@objc protocol ConversationTextViewToolbarDelegate {
    func textViewDidChange(_ textView: UITextView)
    func textViewDidChangeSelection(_ textView: UITextView)
    func textViewDidBecomeFirstResponder(_ textView: UITextView)
}

@objcMembers
class ConversationInputTextView: MentionTextView {

    private lazy var placeholderView = UILabel()
    private var placeholderConstraints: [NSLayoutConstraint]?

    weak var inputTextViewDelegate: ConversationInputTextViewDelegate?
    weak var textViewToolbarDelegate: ConversationTextViewToolbarDelegate?

    var trimmedText: String { text.ows_stripped() }
    var untrimmedText: String { text }

    required init() {
        super.init()

        backgroundColor = nil
        scrollIndicatorInsets = UIEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)

        isScrollEnabled = true
        scrollsToTop = false
        isUserInteractionEnabled = true

        contentMode = .redraw
        dataDetectorTypes = []

        placeholderView.text = NSLocalizedString("new_message", comment: "")
        placeholderView.textColor = Theme.placeholderColor
        placeholderView.isUserInteractionEnabled = false
        addSubview(placeholderView)

        // We need to do these steps _after_ placeholderView is configured.
        font = .ows_dynamicTypeBody
        textColor = Theme.primaryTextColor
        textAlignment = .natural
        textContainer.lineFragmentPadding = 0
        contentInset = .zero
        text = nil

        updateTextContainerInset()

        ensurePlaceholderConstraints()
        updatePlaceholderVisibility()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: -

    private func updateTextContainerInset() {
        let stickerButtonOffset: CGFloat = 30
        var leftInset: CGFloat = 12
        var rightInset: CGFloat = leftInset

        // If the placeholder view is visible, we need to offset
        // the input container to accomodate for the sticker button.
        if !placeholderView.isHidden {
            if CurrentAppContext().isRTL {
                leftInset += stickerButtonOffset
            } else {
                rightInset += stickerButtonOffset
            }
        }

        textContainerInset = UIEdgeInsets(top: 7, left: leftInset, bottom: 7, right: rightInset)
    }

    private func ensurePlaceholderConstraints() {
        if let placeholderConstraints = placeholderConstraints {
            NSLayoutConstraint.deactivate(placeholderConstraints)
        }

        let topInset = textContainerInset.top
        let leftInset = textContainerInset.left
        let rightInset = textContainerInset.right

        placeholderConstraints = [
            placeholderView.autoMatch(.width, to: .width, of: self, withOffset: -(leftInset + rightInset)),
            placeholderView.autoPinEdge(toSuperviewEdge: .left, withInset: leftInset),
            placeholderView.autoPinEdge(toSuperviewEdge: .top, withInset: topInset)
        ]
    }

    private func updatePlaceholderVisibility() {
        placeholderView.isHidden = !text.isEmpty
    }

    override var font: UIFont? {
        didSet { placeholderView.font = font }
    }

    override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        // When creating new lines, contentOffset is animated, but because because
        // we are simultaneously resizing the text view, this can cause the
        // text in the textview to be "too high" in the text view.
        // Solution is to disable animation for setting content offset.
        super.setContentOffset(contentOffset, animated: false)
    }

    override var contentInset: UIEdgeInsets {
        didSet { ensurePlaceholderConstraints() }
    }

    override var textContainerInset: UIEdgeInsets {
        didSet { ensurePlaceholderConstraints() }
    }

    override var text: String! {
        didSet {
            updatePlaceholderVisibility()
            updateTextContainerInset()
        }
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { textViewToolbarDelegate?.textViewDidBecomeFirstResponder(self) }
        return result
    }

    var pasteboardHasPossibleAttachment: Bool {
        // We don't want to load/convert images more than once so we
        // only do a cursory validation pass at this time.
        SignalAttachment.pasteboardHasPossibleAttachment() && !SignalAttachment.pasteboardHasText()
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) {
            if pasteboardHasPossibleAttachment {
                return true
            }
        }
        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
        if pasteboardHasPossibleAttachment {
            // Note: attachment might be nil or have an error at this point; that's fine.
            let attachment = SignalAttachment.attachmentFromPasteboard()
            inputTextViewDelegate?.didPasteAttachment(attachment)
            return
        }

        super.paste(sender)
    }

    // MARK: - UITextViewDelegate

    override func textViewDidChange(_ textView: UITextView) {
        super.textViewDidChange(textView)

        updatePlaceholderVisibility()
        updateTextContainerInset()

        inputTextViewDelegate?.textViewDidChange(self)
        textViewToolbarDelegate?.textViewDidChange(self)

        // If the user typed a mention, clear the mentions experience upgrade.
        if messageBody?.ranges.hasMentions == true {
            ExperienceUpgradeManager.clearExperienceUpgradeWithSneakyTransaction(.mentions)
        }
    }

    override func textViewDidChangeSelection(_ textView: UITextView) {
        super.textViewDidChangeSelection(textView)

        textViewToolbarDelegate?.textViewDidChangeSelection(self)
    }

    // MARK: - Key Commands

    override var keyCommands: [UIKeyCommand]? {
        let keyCommands = super.keyCommands ?? []

        // We don't define discoverability title for these key commands as they're
        // considered "default" functionality and shouldn't clutter the shortcut
        // list that is rendered when you hold down the command key.
        return keyCommands + [
            // An unmodified return can only be sent by a hardware keyboard,
            // return on the software keyboard will not trigger this command.
            // Return, send message
            UIKeyCommand(input: "\r", modifierFlags: [], action: #selector(unmodifiedReturnPressed(_:))),
            // Alt + Return, inserts a new line
            UIKeyCommand(input: "\r", modifierFlags: .alternate, action: #selector(modifiedReturnPressed(_:))),
            // Shift + Return, inserts a new line
            UIKeyCommand(input: "\r", modifierFlags: .shift, action: #selector(modifiedReturnPressed(_:)))
        ]
    }

    func unmodifiedReturnPressed(_ sender: UIKeyCommand) {
        Logger.info("unmodifedReturnPressed: \(String(describing: sender.input))")
        inputTextViewDelegate?.inputTextViewSendMessagePressed()
    }

    func modifiedReturnPressed(_ sender: UIKeyCommand) {
        Logger.info("modifedReturnPressed: \(String(describing: sender.input))")

        replace(selectedTextRange ?? UITextRange(), withText: "\n")

        inputTextViewDelegate?.textViewDidChange(self)
        textViewToolbarDelegate?.textViewDidChange(self)
    }
}
