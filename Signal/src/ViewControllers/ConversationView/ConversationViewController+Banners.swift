//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public extension ConversationViewController {

    static func createBannerWithTitle(title: String,
                                      bannerColor: UIColor,
                                      tapBlock: @escaping () -> Void) -> UIView {
        owsAssertDebug(title.count > 0)

        let bannerView = GestureView()
        bannerView.addTap(block: tapBlock)
        bannerView.backgroundColor = bannerColor
        bannerView.accessibilityIdentifier = "banner_close"

        let label = buildBannerLabel(title: title)
        label.textAlignment = .center

        let closeIcon = UIImage(named: "banner_close")!
        let closeButton = UIImageView(image: closeIcon)
        bannerView.addSubview(closeButton)
        let kBannerCloseButtonPadding: CGFloat = 8
        closeButton.autoPinEdge(toSuperviewEdge: .top, withInset: kBannerCloseButtonPadding)
        closeButton.autoPinTrailingToSuperviewMargin(withInset: kBannerCloseButtonPadding)
        closeButton.autoSetDimensions(to: closeIcon.size)

        bannerView.addSubview(label)
        label.autoPinEdge(toSuperviewEdge: .top, withInset: 5)
        label.autoPinEdge(toSuperviewEdge: .bottom, withInset: 5)
        let kBannerHPadding: CGFloat = 15
        label.autoPinLeadingToSuperviewMargin(withInset: kBannerHPadding)
        let kBannerHSpacing: CGFloat = 10
        closeButton.autoPinTrailing(toEdgeOf: label, offset: kBannerHSpacing)

        return bannerView
    }

    // MARK: - Pending Join Requests Banner

    func createPendingJoinRequestBanner(viewState: CVViewState,
                                        count pendingMemberRequestCount: UInt,
                                        viewMemberRequestsBlock: @escaping () -> Void) -> UIView {
        owsAssertDebug(pendingMemberRequestCount > 0)

        let format = NSLocalizedString("PENDING_GROUP_MEMBERS_REQUEST_BANNER_FORMAT",
                                       comment: "Format for banner indicating that there are pending member requests to join the group. Embeds {{ the number of pending member requests }}.")
        let title = String(format: format, OWSFormat.formatUInt(pendingMemberRequestCount))

        let dismissButton = OWSButton(title: CommonStrings.dismissButton) { [weak self] in
            AssertIsOnMainThread()
            viewState.isPendingMemberRequestsBannerHidden = true
            self?.ensureBannerState()
        }
        dismissButton.titleLabel?.font = UIFont.ows_dynamicTypeSubheadlineClamped.ows_semibold
        let viewRequestsLabel = NSLocalizedString("PENDING_GROUP_MEMBERS_REQUEST_BANNER_VIEW_REQUESTS",
                                                  comment: "Label for the 'view requests' button in the pending member requests banner.")
        let viewRequestsButton = OWSButton(title: viewRequestsLabel, block: viewMemberRequestsBlock)
        viewRequestsButton.titleLabel?.font = UIFont.ows_dynamicTypeSubheadlineClamped.ows_semibold

        return Self.createBanner(title: title,
                                 buttons: [dismissButton, viewRequestsButton],
                                 accessibilityIdentifier: "pending_group_request_banner")
    }

    // MARK: - Manual Migration Banner

    var manualMigrationInfoForGroup: GroupsV2MigrationInfo? {
        guard GroupManager.canManuallyMigrate else {
            return nil
        }
        guard let groupThread = thread as? TSGroupThread,
              groupThread.isGroupV1Thread else {
            return nil
        }
        guard groupThread.isLocalUserFullMember else {
            return nil
        }

        // migrationInfoForManualMigrationWithGroupThread uses
        // a transaction, so we try to avoid calling it.
        return GroupsV2Migration.migrationInfoForManualMigration(groupThread: groupThread)
    }

    func createMigrateGroupBanner(viewState: CVViewState,
                                  migrationInfo: GroupsV2MigrationInfo) -> UIView {

        let title = NSLocalizedString("GROUPS_LEGACY_GROUP_MIGRATE_GROUP_OFFER_BANNER",
                                      comment: "Title for the the 'migrate group' banner.")

        let notNowButton = OWSButton(title: CommonStrings.notNowButton) { [weak self] in
            AssertIsOnMainThread()
            viewState.isMigrateGroupBannerHidden = true
            self?.ensureBannerState()
        }
        notNowButton.titleLabel?.font = UIFont.ows_dynamicTypeSubheadlineClamped.ows_semibold

        let migrateButtonText = NSLocalizedString("GROUPS_LEGACY_GROUP_MIGRATE_GROUP_MIGRATE_BUTTON",
                                                  comment: "Label for the 'migrate' button in the 'migrate group' banner.")
        let migrateButton = OWSButton(title: migrateButtonText) { [weak self] in
            self?.migrateGroupPressed(migrationInfo: migrationInfo)
        }
        migrateButton.titleLabel?.font = UIFont.ows_dynamicTypeSubheadlineClamped.ows_semibold

        return Self.createBanner(title: title,
                                 buttons: [notNowButton, migrateButton],
                                 accessibilityIdentifier: "migrate_group_banner")
    }

    private func migrateGroupPressed(migrationInfo: GroupsV2MigrationInfo) {
        guard let groupThread = thread as? TSGroupThread else {
            owsFailDebug("Invalid thread.")
            return
        }
        showManualMigrationAlert(groupThread: groupThread, migrationInfo: migrationInfo)
    }

    // MARK: - Dropped Group Members Banner

    func createDroppedGroupMembersBannerIfNecessary(viewState: CVViewState) -> UIView? {
        guard let droppedMembersInfo = GroupMigrationActionSheet.buildDroppedMembersInfo(thread: thread) else {
            return nil
        }
        return createDroppedGroupMembersBanner(viewState: viewState,
                                               droppedMembersInfo: droppedMembersInfo)
    }

    // MARK: - Name collision banners

    func createMessageRequestNameCollisionBannerIfNecessary(viewState: CVViewState) -> UIView? {
        guard !viewState.isMessageRequestNameCollisionBannerHidden else { return nil }
        guard let contactThread = thread as? TSContactThread else { return nil }

        let collisionFinder = ContactThreadNameCollisionFinder(thread: contactThread)
        let collisionCount = databaseStorage.read { readTx in
            collisionFinder.findCollisions(transaction: readTx).count
        }
        guard collisionCount > 0 else { return nil }

        let banner = NameCollisionBanner()
        banner.labelText = NSLocalizedString(
            "MESSAGE_REQUEST_NAME_COLLISON_BANNER_LABEL",
            comment: "Banner label notifying user that a new message is from a user with the same name as an existing contact")
        banner.reviewActionText = NSLocalizedString(
            "MESSAGE_REQUEST_REVIEW_NAME_COLLISION",
            comment: "Button to allow user to review known name collisions with an incoming message request")

        banner.closeAction = { [weak self] in
            viewState.isMessageRequestNameCollisionBannerHidden = true
            self?.ensureBannerState()
        }

        banner.reviewAction = { [weak self] in
            guard let self = self else { return }
            let vc = NameCollisionResolutionViewController(collisionFinder: collisionFinder, collisionDelegate: self)
            self.present(vc, animated: true)
        }

        return banner
    }

    func createGroupMembershipCollisionBannerIfNecessary() -> UIView? {
        guard let groupThread = thread as? TSGroupThread else { return nil }

        // Collision discovery can be expensive, so we only build our banner if we've already done the expensive bit
        guard let collisionFinder = viewState.groupNameCollisionFinder, collisionFinder.hasFetchedProfileUpdateMessages else {
            guard viewState.groupNameCollisionFinder == nil else {
                // We already have a collision finder. It just hasn't finished fetching.
                return nil
            }

            let collisionFinder = GroupMembershipNameCollisionFinder(thread: groupThread)
            viewState.groupNameCollisionFinder = collisionFinder

            firstly(on: .sharedUserInitiated) {
                self.databaseStorage.read { readTx in
                    // Prewarm our collision finder off the main thread
                    _ = collisionFinder.findCollisions(transaction: readTx)
                }
            }.done(on: .main) {
                self.ensureBannerState()
            }.catch { error in
                owsFailDebug("\(error)")
            }
            return nil
        }

        // Fetch the necessary info to build the banner
        guard let (title, avatar1, avatar2) = databaseStorage.read(block: { readTx -> (String, UIImage?, UIImage?)? in
            let collisionSets = collisionFinder.findCollisions(transaction: readTx).standardSort(readTx: readTx)
            guard !collisionSets.isEmpty, collisionSets[0].elements.count >= 2 else { return nil }

            let totalCollisionElementCount = collisionSets.reduce(0) { $0 + $1.elements.count }

            let title: String = {
                if collisionSets.count == 1 {
                    let titleFormat = NSLocalizedString(
                        "GROUP_MEMBERSHIP_SINGLE_COLLISION_BANNER_TITLE_FORMAT",
                        comment: "Banner title alerting user to a single name collision set ub the group membership. Embeds {{ total number of colliding members }}")
                    return String(format: titleFormat, OWSFormat.formatInt(totalCollisionElementCount))
                } else {
                    let titleFormat = NSLocalizedString(
                        "GROUP_MEMBERSHIP_MANY_COLLISIONS_BANNER_TITLE_FORMAT",
                        comment: "Banner title alerting user to many name collisions in the group membership. Embeds {{ total number of colliding members }}")
                    return String(format: titleFormat, OWSFormat.formatInt(totalCollisionElementCount))
                }
            }()

            let fetchAvatarForAddress = { (address: SignalServiceAddress) -> UIImage? in
                if address.isLocalAddress, let profileAvatar = self.profileManager.localProfileAvatarImage() {
                    return profileAvatar.resizedImage(to: CGSize(square: 24))
                } else {
                    return OWSContactAvatarBuilder.buildImage(
                        address: address,
                        diameter: 24,
                        transaction: readTx)
                }
            }

            let avatar1 = fetchAvatarForAddress(collisionSets[0].elements[0].address)
            let avatar2 = fetchAvatarForAddress(collisionSets[0].elements[1].address)
            return (title, avatar1, avatar2)

        }) else { return nil }

        let banner = NameCollisionBanner()
        banner.labelText = title
        banner.reviewActionText = NSLocalizedString(
            "GROUP_MEMBERSHIP_NAME_COLLISION_BANNER_REVIEW_BUTTON",
            comment: "Button to allow user to review known name collisions in group membership")
        if let avatar1 = avatar1, let avatar2 = avatar2 {
            banner.primaryImage = avatar1
            banner.secondaryImage = avatar2
        }

        banner.closeAction = { [weak self] in
            self?.databaseStorage.asyncWrite(block: { writeTx in
                collisionFinder.markCollisionsAsResolved(transaction: writeTx)
            }, completion: {
                self?.ensureBannerState()
            })
        }

        banner.reviewAction = { [weak self] in
            guard let self = self else { return }
            let vc = NameCollisionResolutionViewController(collisionFinder: collisionFinder, collisionDelegate: self)
            self.present(vc, animated: true)
        }

        return banner
    }
}

// MARK: -

fileprivate extension ConversationViewController {

    typealias DroppedMembersInfo = GroupMigrationActionSheet.DroppedMembersInfo

}

// MARK: -

fileprivate extension ConversationViewController {

    func createDroppedGroupMembersBanner(viewState: CVViewState,
                                         droppedMembersInfo: DroppedMembersInfo) -> UIView {

        let title: String
        if droppedMembersInfo.addableMembers.count > 1 {
            let titleFormat = NSLocalizedString("GROUPS_LEGACY_GROUP_DROPPED_MEMBERS_BANNER_N_FORMAT",
                                                comment: "Format for the title for the the 'dropped group members' banner. Embeds: {{ the number of dropped group members }}.")
            title = String(format: titleFormat, OWSFormat.formatInt(droppedMembersInfo.addableMembers.count))
        } else {
            title = NSLocalizedString("GROUPS_LEGACY_GROUP_DROPPED_MEMBERS_BANNER_1",
                                      comment: "Title for the the 'dropped group member' banner.")
        }

        let notNowButton = OWSButton(title: CommonStrings.notNowButton) { [weak self] in
            AssertIsOnMainThread()
            viewState.isDroppedGroupMembersBannerHidden = true
            self?.ensureBannerState()
        }
        notNowButton.titleLabel?.font = UIFont.ows_dynamicTypeSubheadlineClamped.ows_semibold

        let addMembersButtonText = NSLocalizedString("GROUPS_LEGACY_GROUP_RE_ADD_DROPPED_GROUP_MEMBERS_BUTTON",
                                                     comment: "Label for the 'add members' button in the 're-add dropped groups members' banner.")
        let addMembersButton = OWSButton(title: addMembersButtonText) { [weak self] in
            self?.reAddDroppedGroupMembers(droppedMembersInfo: droppedMembersInfo)
        }
        addMembersButton.titleLabel?.font = UIFont.ows_dynamicTypeSubheadlineClamped.ows_semibold

        return Self.createBanner(title: title,
                                 buttons: [notNowButton, addMembersButton],
                                 accessibilityIdentifier: "dropped_group_members_banner")
    }

    func reAddDroppedGroupMembers(droppedMembersInfo: DroppedMembersInfo) {
        let mode = GroupMigrationActionSheet.Mode.reAddDroppedMembers(members: droppedMembersInfo.addableMembers)
        let view = GroupMigrationActionSheet(groupThread: droppedMembersInfo.groupThread, mode: mode)
        view.present(fromViewController: self)
    }

    // MARK: -

    static func buildBannerLabel(title: String) -> UILabel {
        let label = UILabel()
        label.font = UIFont.ows_dynamicTypeSubheadlineClamped.ows_semibold
        label.text = title
        label.textColor = .white
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        return label
    }

    static func createBanner(title: String,
                             buttons: [UIView],
                             accessibilityIdentifier: String) -> UIView {

        let titleLabel = buildBannerLabel(title: title)
        titleLabel.font = .ows_dynamicTypeSubheadlineClamped

        let buttonRow = UIStackView(arrangedSubviews: [UIView.hStretchingSpacer()] + buttons)
        buttonRow.axis = .horizontal
        buttonRow.spacing = 24

        let bannerView = UIStackView(arrangedSubviews: [ titleLabel, buttonRow ])
        bannerView.axis = .vertical
        bannerView.alignment = .fill
        bannerView.spacing = 10
        bannerView.layoutMargins = UIEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
        bannerView.isLayoutMarginsRelativeArrangement = true
        bannerView.addBackgroundView(withBackgroundColor: .ows_accentBlue)
        bannerView.accessibilityIdentifier = accessibilityIdentifier
        return bannerView
    }
}

// MARK: -

// A convenience view that allows block-based gesture handling.
@objc
public class GestureView: UIView {
    @objc
    public required init() {
        super.init(frame: .zero)

        self.layoutMargins = .zero
    }

    @available(*, unavailable, message:"use other constructor instead.")
    @objc
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    public typealias BlockType = () -> Void

    private var tapBlock: BlockType?

    @objc
    public func addTap(block tapBlock: @escaping () -> Void) {
        owsAssertDebug(self.tapBlock == nil)

        self.tapBlock = tapBlock
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTap(_:))))
    }

    // MARK: - Events

    @objc
    func didTap(_ sender: UITapGestureRecognizer) {
        guard sender.state == .recognized else {
            return
        }
        guard let tapBlock = tapBlock else {
            owsFailDebug("Missing tapBlock.")
            return
        }
        tapBlock()
    }
}

private class NameCollisionBanner: UIView {

    var primaryImage: UIImage? {
        get { primaryImageView.image }
        set {
            primaryImageView.image = newValue
            setNeedsUpdateConstraints()
        }
    }

    var secondaryImage: UIImage? {
        get { secondaryImageView.image }
        set {
            secondaryImageView.image = newValue
            setNeedsUpdateConstraints()
        }
    }

    var labelText: String? {
        get { label.text }
        set { label.text = newValue }
    }

    var reviewActionText: String? {
        get { reviewButton.title(for: .normal) }
        set { reviewButton.setTitle(newValue, for: .normal) }
    }

    var reviewAction: () -> Void {
        get { reviewButton.block }
        set { reviewButton.block = newValue }
    }

    var closeAction: () -> Void {
        get { closeButton.block }
        set { closeButton.block = newValue }
    }

    private let label: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = UIFont.ows_dynamicTypeFootnote
        label.textColor = Theme.secondaryTextAndIconColor
        return label
    }()

    private let primaryImageView: UIImageView = {
        let avatarSize = CGSize(square: 24)
        let borderWidth: CGFloat = 2
        let totalSize = avatarSize.plus(CGSize(square: borderWidth))

        let imageView = UIImageView.withTemplateImageName(
            "info-outline-24",
            tintColor: Theme.secondaryTextAndIconColor)
        imageView.contentMode = .center

        imageView.layer.borderColor = Theme.secondaryBackgroundColor.cgColor
        imageView.layer.borderWidth = borderWidth
        imageView.layer.cornerRadius = totalSize.smallerAxis / 2
        imageView.layer.masksToBounds = true

        imageView.autoSetDimensions(to: totalSize)
        imageView.setCompressionResistanceHigh()
        imageView.setContentHuggingHigh()
        return imageView
    }()

    private let secondaryImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.layer.cornerRadius = 12
        imageView.layer.masksToBounds = true

        imageView.autoSetDimensions(to: CGSize(square: 24))
        imageView.setCompressionResistanceHigh()
        imageView.setContentHuggingHigh()
        return imageView
    }()

    private let closeButton: OWSButton = {
        let button = OWSButton(
            imageName: "x-circle-16",
            tintColor: Theme.secondaryTextAndIconColor)
        button.accessibilityLabel = NSLocalizedString("BANNER_CLOSE_ACCESSIBILITY_LABEL",
            comment: "Accessibility label for banner close button")
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setCompressionResistanceHigh()
        button.setContentHuggingHigh()
        return button
    }()

    private let reviewButton: OWSButton = {
        let button = OWSButton()
        button.setTitleColor(Theme.accentBlueColor, for: .normal)
        button.setTitleColor(Theme.accentBlueColor.withAlphaComponent(0.7), for: .highlighted)
        button.titleLabel?.font = UIFont.ows_dynamicTypeFootnote
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.secondaryBackgroundColor

        [secondaryImageView, primaryImageView, label, closeButton, reviewButton]
            .forEach { addSubview($0) }

        // Offsets adjusted in updateConstraints() based on content
        primaryImageViewConstraints = (
            top: primaryImageView.autoPinEdge(.top, to: .top, of: self, withOffset: 18),
            leading: primaryImageView.autoPinEdge(.leading, to: .leading, of: self, withOffset: 16),
            trailing: label.autoPinEdge(.leading, to: .trailing, of: primaryImageView, withOffset: 16)
        )
        // Secondary image is always offset to the top left of the primary image
        secondaryImageView.autoPinEdge(.top, to: .top, of: primaryImageView, withOffset: -12)
        secondaryImageView.autoPinEdge(.leading, to: .leading, of: primaryImageView, withOffset: -12)

        // Note that UIButtons are being aligned based on their content subviews
        // UIButtons this small will have an intrinsic size larger than their content
        // That extra padding between the content and its frame messes up alignment
        label.autoPinEdge(toSuperviewEdge: .top, withInset: 12)
        closeButton.imageView?.autoPinEdge(.top, to: .top, of: label)
        reviewButton.titleLabel?.autoPinEdge(.top, to: .bottom, of: label, withOffset: 3)
        reviewButton.titleLabel?.autoPinEdge(.bottom, to: .bottom, of: self, withOffset: -12)

        // Aligning things this way is useful, because we can also increase the tap target
        // for the tiny close button without messing up the appearance.
        closeButton.contentEdgeInsets = UIEdgeInsets(hMargin: 8, vMargin: 8)
        closeButton.imageView?.autoPinLeading(toTrailingEdgeOf: label, offset: 16)
        closeButton.imageView?.autoPinTrailing(toEdgeOf: self, offset: -16)
        reviewButton.titleLabel?.autoPinLeading(toEdgeOf: label)

        accessibilityElements = [label, reviewButton, closeButton]
    }

    var primaryImageViewConstraints: (top: NSLayoutConstraint, leading: NSLayoutConstraint, trailing: NSLayoutConstraint)?

    override func updateConstraints() {
        super.updateConstraints()
        guard let topConstraint = primaryImageViewConstraints?.top,
              let leadingConstraint = primaryImageViewConstraints?.leading,
              let trailingConstraint = primaryImageViewConstraints?.trailing else { return }

        // If we have a secondary image, we want to adjust our constraints a bit
        let hasSecondaryImage = (secondaryImage != nil)
        topConstraint.constant = hasSecondaryImage ? 24 : 18
        leadingConstraint.constant = hasSecondaryImage ? 28 : 16
        trailingConstraint.constant = hasSecondaryImage ? 12 : 16
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
