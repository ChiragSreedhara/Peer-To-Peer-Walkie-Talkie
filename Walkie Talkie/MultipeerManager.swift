
import MultipeerConnectivity
import Foundation
import Combine
import UIKit

class MultipeerManager: NSObject, ObservableObject {
    private let serviceType = "mesh-audio"
    
    private var myPeerId: MCPeerID!
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!
    
    private var ignoreList: [String] = []
    
   
    private var isRestartingScanner = false
    private var isStopped = false
    private var reconciliationTimer: Timer?

    @Published var connectedPeers: [MCPeerID] = []
    
    var onPacketReceived: ((Data, String) -> Void)?
    var onDebugLog: ((String) -> Void)?
    
    override init() {
        super.init()
    }
    
    func startNetworking(as name: String, ignoring: [String] = []) {
        self.isStopped = false
        self.myPeerId = MCPeerID(displayName: name)
        self.ignoreList = ignoring.map { $0.lowercased() }
        
        session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .none)
        session.delegate = self
        
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: nil, serviceType: serviceType)
        advertiser.delegate = self
        
        browser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: serviceType)
        browser.delegate = self
        
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
        
        onDebugLog?("Layer 4: walkie talkie started as '\(name)'")
        if !ignoreList.isEmpty {
            onDebugLog?("Layer 4: Simulating multihop by Ignoring: \(ignoreList.joined(separator: ", "))")
        }

        reconciliationTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                let mpcPeerNames = Set(self.session.connectedPeers.map(\.displayName))
                let stale = self.connectedPeers.filter { !mpcPeerNames.contains($0.displayName) }
                for ghost in stale {
                    self.onDebugLog?("Layer 4: Removing some peer who dropped \(ghost.displayName)")
                }
                self.connectedPeers.removeAll { !mpcPeerNames.contains($0.displayName) }
            }
        }
    }
    
    func stopNetworking() {
        isStopped = true
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        reconciliationTimer?.invalidate()

        advertiser = nil
        browser = nil
        session = nil
        DispatchQueue.main.async {
            self.connectedPeers.removeAll()
        }
        onDebugLog?("Layer 4: Disconnected")
    }

    func restartScanning() {
        browser?.stopBrowsingForPeers()
        advertiser?.stopAdvertisingPeer()
        browser?.startBrowsingForPeers()
        advertiser?.startAdvertisingPeer()
        onDebugLog?("Layer 4: Scanner restarted")
    }

    func broadcastToNeighbors(data: Data, excluding excludedPeerName: String? = nil) {
        let targetPeers = session.connectedPeers.filter {
            $0.displayName.lowercased() != excludedPeerName?.lowercased() &&
            !ignoreList.contains($0.displayName.lowercased())
        }
        guard !targetPeers.isEmpty else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.session.send(data, toPeers: targetPeers, with: .unreliable)
            } catch {
                self.onDebugLog?("Failed to blast the Voice pckts: \(error)")
            }
        }
    }
    private func rebuildSession() {
        guard !isStopped else { return }
        session.disconnect()
        reconciliationTimer?.invalidate()

        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.session = MCSession(peer: self.myPeerId, securityIdentity: nil, encryptionPreference: .none)
            self.session.delegate = self
            
            self.advertiser.startAdvertisingPeer()
            self.browser.startBrowsingForPeers()
            
            self.onDebugLog?("Layer 4: Session resetup, reconnecting w peers.")
        }
    }
}

extension MultipeerManager: MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        guard !isStopped else { return }
        if ignoreList.contains(peerID.displayName.lowercased()) {
            onDebugLog?("Layer 4: Ignoring \(peerID.displayName)")
            return
        }

        if myPeerId.displayName > peerID.displayName {
            onDebugLog?("Layer 4: Found \(peerID.displayName). Have high priority, inviting others")
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 30)
        } else {
            onDebugLog?("Layer 4: Found \(peerID.displayName). yielding priority.")
        }
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        guard !isStopped else {
            invitationHandler(false, nil)
            return
        }
        if ignoreList.contains(peerID.displayName.lowercased()) {
            onDebugLog?("Layer 4: Ignoring this invite from \(peerID.displayName) (in ignore list).")
            invitationHandler(false, nil)
            return
        }
        
        onDebugLog?("Layer 4: accepting invite from \(peerID.displayName)")
        invitationHandler(true, session)
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard !isStopped else { return }
        if ignoreList.contains(peerID.displayName.lowercased()) {
            onDebugLog?("Layer 4: Pckts dropped directly coming from \(peerID.displayName) — in distance list.")
            return
        }
        onDebugLog?("Layer 4: Caught \(data.count) bytes from immediate neighbor \(peerID.displayName)")
        onPacketReceived?(data, peerID.displayName)
    }
    
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        guard !isStopped else { return }
        DispatchQueue.main.async {
            switch state {
            case .connected:
                if self.ignoreList.contains(peerID.displayName.lowercased()) {
                    self.onDebugLog?("Layer 4: \(peerID.displayName) joined through another peer but is in distance list, so we block")
                    return
                }
                
                // Remove any stale entry with same name (old MCPeerID obj from a prev connection )
                let hadStale = self.connectedPeers.contains { $0.displayName == peerID.displayName && $0 != peerID }
                self.connectedPeers.removeAll { $0.displayName == peerID.displayName }
                self.connectedPeers.append(peerID)
                if hadStale {
                    self.onDebugLog?("Layer 4: \(peerID.displayName) reconnected (replaced stale entry).")
                } else {
                    self.onDebugLog?("Layer 4: \(peerID.displayName) connected!")
                }
            case .notConnected:
                self.connectedPeers.removeAll { $0 == peerID || $0.displayName == peerID.displayName }
                self.onDebugLog?("Layer 4: \(peerID.displayName) disconnected.")
                
                if self.connectedPeers.isEmpty {
                    self.onDebugLog?("Layer 4: Isolated! Restarting connection to fix issues")
                    self.rebuildSession()
                } else if !self.isRestartingScanner {
                    self.isRestartingScanner = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.browser.stopBrowsingForPeers()
                        self.browser.startBrowsingForPeers()
                        self.onDebugLog?("Layer 4: Scanner refreshed")
                        self.isRestartingScanner = false
                    }
                }
                
            case .connecting:
                self.onDebugLog?("Layer 4: Handshaking with \(peerID.displayName)...")
            @unknown default: break
            }
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}
