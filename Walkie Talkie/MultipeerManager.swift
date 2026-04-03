import MultipeerConnectivity
import Foundation
import Combine
import UIKit

class MultipeerManager: NSObject, ObservableObject {
    private let serviceType = "mesh-audio"
    private let myPeerId = MCPeerID(displayName: UIDevice.current.name)
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!
    
    
    @Published var connectedPeers: [MCPeerID] = []
    
    var onPacketReceived: ((Data) -> Void)?
    
    override init() {
        super.init()
        session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: nil, serviceType: serviceType)
        advertiser.delegate = self
        
        browser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: serviceType)
        browser.delegate = self
    }
    
    func startNetworking() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }
    
    func broadcastToNeighbors(data: Data) {
        guard !session.connectedPeers.isEmpty else { return }
        do {
            try session.send(data, toPeers: session.connectedPeers, with: .unreliable)
        } catch {
            print("Failed to blast data: \(error)")
        }
    }
}

extension MultipeerManager: MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        print("Layer 4: Caught \(data.count) raw bytes from \(peerID.displayName)")
            
        onPacketReceived?(data)
    }
    
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                if !self.connectedPeers.contains(peerID) {
                    self.connectedPeers.append(peerID)
                    print("Layer 4: \(peerID.displayName) joined the mesh!")
                }
                
            case .notConnected:
                self.connectedPeers.removeAll { $0 == peerID }
                print("Layer 4: \(peerID.displayName) disconnected.")
                
            case .connecting:
                print("Layer 4: Handshaking with \(peerID.displayName)...")
                
            @unknown default:
                break
            }
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("Layer 4 Warning: The scanner lost sight of \(peerID.displayName).")
    }
    
    
}
