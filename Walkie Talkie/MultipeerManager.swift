/*
 ============================================================================
 LAYER 4: NETWORK TRANSPORT LAYER
 ============================================================================
 */

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
    
    @Published var connectedPeers: [MCPeerID] = []
    
    var onPacketReceived: ((Data, String) -> Void)?
    var onDebugLog: ((String) -> Void)?
    
    override init() {
        super.init()
    }
    
    func startNetworking(as name: String, ignoring: [String] = []) {
        self.myPeerId = MCPeerID(displayName: name)
        self.ignoreList = ignoring
        
        session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .none)
        session.delegate = self
        
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: nil, serviceType: serviceType)
        advertiser.delegate = self
        
        browser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: serviceType)
        browser.delegate = self
        
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
        
        onDebugLog?("Layer 4: Radios started as '\(name)'")
        if !ignoreList.isEmpty {
            onDebugLog?("Layer 4: 🛑 Simulating distance. Ignoring: \(ignoreList.joined(separator: ", "))")
        }
    }
    
    func broadcastToNeighbors(data: Data) {
        guard !session.connectedPeers.isEmpty else { return }
        do {
            try session.send(data, toPeers: session.connectedPeers, with: .unreliable)
        } catch {
            onDebugLog?("Failed to blast data: \(error)")
        }
    }
    
    private func rebuildSession() {
        session.disconnect()
        
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.session = MCSession(peer: self.myPeerId, securityIdentity: nil, encryptionPreference: .none)
            self.session.delegate = self
            
            self.advertiser.startAdvertisingPeer()
            self.browser.startBrowsingForPeers()
            
            self.onDebugLog?("Layer 4: ⚡️ Session rebuilt. Ready to rejoin mesh.")
        }
    }
}

extension MultipeerManager: MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        if ignoreList.contains(peerID.displayName) { return }
        
        if myPeerId.hashValue > peerID.hashValue {
            onDebugLog?("Layer 4: Found \(peerID.displayName). Priority high, inviting...")
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 30)
        } else {
            onDebugLog?("Layer 4: Found \(peerID.displayName). Yielding invite priority.")
        }
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        if ignoreList.contains(peerID.displayName) {
            invitationHandler(false, nil)
            return
        }
        
        onDebugLog?("Layer 4: Auto-accepting invite from \(peerID.displayName)")
        invitationHandler(true, session)
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        onDebugLog?("Layer 4: Caught \(data.count) bytes from immediate neighbor \(peerID.displayName)")
        onPacketReceived?(data, peerID.displayName)
    }
    
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                if !self.connectedPeers.contains(peerID) {
                    self.connectedPeers.append(peerID)
                    self.onDebugLog?("Layer 4: 🟢 \(peerID.displayName) connected!")
                }
            case .notConnected:
                self.connectedPeers.removeAll { $0 == peerID }
                self.onDebugLog?("Layer 4: 🔴 \(peerID.displayName) disconnected.")
                
                if self.connectedPeers.isEmpty {
                    self.onDebugLog?("Layer 4: ⚠️ Isolated! Poisoned session detected. Rebuilding from scratch...")
                    self.rebuildSession()
                } else if !self.isRestartingScanner {
                    self.isRestartingScanner = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.browser.stopBrowsingForPeers()
                        self.browser.startBrowsingForPeers()
                        self.onDebugLog?("Layer 4: 🔄 Scanner refreshed to hunt for dropped peers.")
                        self.isRestartingScanner = false
                    }
                }
                
            case .connecting:
                self.onDebugLog?("Layer 4: 🟡 Handshaking with \(peerID.displayName)...")
            @unknown default: break
            }
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}
