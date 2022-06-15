import Foundation
import WalletConnectKMS
import WalletConnectUtils
import WalletConnectRelay
import Combine

class Engine {
    var onInvite: ((Invite) -> Void)?
    var onNewThread: ((Thread) -> Void)?
    let networkingInteractor: NetworkingInteractor
    let inviteStore: CodableStore<(Invite)>
    let topicToInvitationPubKeyStore: CodableStore<String>
    let registry: Registry
    let logger: ConsoleLogging
    let kms: KeyManagementService
    let threadsStore: CodableStore<Thread>
    private var publishers = [AnyCancellable]()

    init(registry: Registry,
         networkingInteractor: NetworkingInteractor,
         kms: KeyManagementService,
         logger: ConsoleLogging,
         topicToInvitationPubKeyStore: CodableStore<String>,
         inviteStore: CodableStore<Invite>,
         threadsStore: CodableStore<Thread>) {
        self.registry = registry
        self.kms = kms
        self.networkingInteractor = networkingInteractor
        self.logger = logger
        self.topicToInvitationPubKeyStore = topicToInvitationPubKeyStore
        self.inviteStore = inviteStore
        self.threadsStore = threadsStore
        setUpRequestHandling()
        setUpResponseHandling()
    }

    func invite(peerPubKey: String, openingMessage: String) async throws {
        let pubKey = try kms.createX25519KeyPair()
        let invite = Invite(pubKey: pubKey.hexRepresentation, openingMessage: openingMessage)
        let topic = try AgreementPublicKey(hex: peerPubKey).rawRepresentation.sha256().toHexString()
        let request = ChatRequest(params: .invite(invite))
        networkingInteractor.requestUnencrypted(request, topic: topic)
        let agreementKeys = try kms.performKeyAgreement(selfPublicKey: pubKey, peerPublicKey: peerPubKey)
        let threadTopic = agreementKeys.derivedTopic()
        try await networkingInteractor.subscribe(topic: threadTopic)
        logger.debug("invite sent on topic: \(topic)")
    }

    func accept(inviteId: String) async throws {
        guard let hexPubKey = try topicToInvitationPubKeyStore.get(key: "todo-topic") else {
            throw ChatError.noPublicKeyForInviteId
        }
        let pubKey = try! AgreementPublicKey(hex: hexPubKey)
        guard let invite = try inviteStore.get(key: inviteId) else {
            throw ChatError.noInviteForId
        }
        logger.debug("accepting an invitation")
        let agreementKeys = try! kms.performKeyAgreement(selfPublicKey: pubKey, peerPublicKey: invite.pubKey)
        let topic = agreementKeys.derivedTopic()
        try await networkingInteractor.subscribe(topic: topic)
        fatalError("not implemented")
    }

    private func handleInvite(_ invite: Invite) {
        onInvite?(invite)
        logger.debug("did receive an invite")
        try? inviteStore.set(invite, forKey: invite.id)
//        networkingInteractor.respondSuccess(for: RequestSubscriptionPayload)
    }

    private func setUpRequestHandling() {
        networkingInteractor.requestPublisher.sink { [unowned self] subscriptionPayload in
            switch subscriptionPayload.request.params {
            case .invite(let invite):
                handleInvite(invite)
            case .message(let message):
                print("received message: \(message)")
            }
        }.store(in: &publishers)
    }

    private func setUpResponseHandling() {
        networkingInteractor.responsePublisher.sink { [unowned self] response in
            switch response.requestParams {
            case .invite(let invite):
                fatalError("not implemented")
            case .message(let message):
                print("received message response: \(message)")
            }
        }.store(in: &publishers)
    }
}