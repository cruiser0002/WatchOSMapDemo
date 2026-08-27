import Foundation
import Network
import Combine

public enum ConnectionGrade: String, Equatable, CaseIterable {
    case excellent = "EXCELLENT" // RTT < 150ms, low jitter, fast network
    case good      = "GOOD"      // RTT 150-300ms, stable
    case poor      = "POOR"      // RTT 300-700ms or constrained/high jitter
    case critical  = "CRITICAL"  // RTT > 700ms or frequent packet drops
    case offline   = "OFFLINE"   // Unsatisfied path
}

public final class NetworkQualityMonitor: ObservableObject {
    @Published public var isConnected: Bool = true
    @Published public var isConstrained: Bool = false
    @Published public var isExpensive: Bool = false
    @Published public var isCellular: Bool = false
    
    @Published public var smoothedLatencyMs: Double = AppConstants.Network.Quality.initialLatencyMs
    @Published public var jitterMs: Double = AppConstants.Network.Quality.initialJitterMs
    @Published public var connectionGrade: ConnectionGrade = .excellent
    
    private var lastLatencyMs: Double = AppConstants.Network.Quality.initialLatencyMs
    private let monitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "RadarMap.NetworkQualityMonitor")
    
    public init(monitor: NWPathMonitor? = nil, startMonitoring: Bool = true) {
        if startMonitoring {
            let activeMonitor = monitor ?? NWPathMonitor()
            self.monitor = activeMonitor
            setupMonitor(activeMonitor)
        } else {
            self.monitor = nil
        }
    }
    
    deinit {
        monitor?.cancel()
    }
    
    private func setupMonitor(_ monitor: NWPathMonitor) {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isConnected = (path.status == .satisfied)
                self.isConstrained = path.isConstrained
                self.isExpensive = path.isExpensive
                self.isCellular = path.usesInterfaceType(.cellular)
                self.evaluateGrade()
            }
        }
        monitor.start(queue: monitorQueue)
    }
    
    /// Records a new RTT latency sample from a completed network operation.
    public func recordLatencySample(_ rttMs: Double) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.recordLatencySample(rttMs)
            }
            return
        }
        
        let alpha = AppConstants.Network.Quality.emaAlpha // Weight for Exponential Moving Average
        let currentJitter = abs(rttMs - lastLatencyMs)
        
        lastLatencyMs = rttMs
        smoothedLatencyMs = (1.0 - alpha) * smoothedLatencyMs + alpha * rttMs
        jitterMs = (1.0 - alpha) * jitterMs + alpha * currentJitter
        
        evaluateGrade()
    }
    
    public func evaluateGrade() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.evaluateGrade()
            }
            return
        }
        
        if !isConnected {
            connectionGrade = .offline
            return
        }
        
        if smoothedLatencyMs < AppConstants.Network.Quality.excellentLatencyMs && jitterMs < AppConstants.Network.Quality.excellentJitterMs && !isConstrained {
            connectionGrade = .excellent
        } else if smoothedLatencyMs < AppConstants.Network.Quality.goodLatencyMs && jitterMs < AppConstants.Network.Quality.goodJitterMs {
            connectionGrade = .good
        } else if smoothedLatencyMs < AppConstants.Network.Quality.poorLatencyMs || isConstrained {
            connectionGrade = .poor
        } else {
            connectionGrade = .critical
        }
    }
}
