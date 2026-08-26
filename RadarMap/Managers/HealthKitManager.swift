import Foundation
import Combine
#if canImport(HealthKit)
import HealthKit
#endif

public final class HealthKitManager: NSObject, ObservableObject {
    @Published public var currentHeartRate: Double = 0.0
    @Published public var isSessionActive: Bool = false
    
    #if os(watchOS)
    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    #endif
    
    public override init() {
        super.init()
    }
    
    public func requestAuthorization(completion: @escaping (Bool) -> Void = { _ in }) {
        #if os(watchOS)
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false)
            return
        }
        
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let typesToRead: Set<HKObjectType> = [heartRateType]
        let typesToShare: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            heartRateType
        ]
        
        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { success, _ in
            DispatchQueue.main.async {
                completion(success)
            }
        }
        #else
        // Mock fallback for simulator/host tests
        DispatchQueue.main.async {
            self.currentHeartRate = 78.0
            completion(true)
        }
        #endif
    }
    
    public func startLiveHeartRateSession() {
        #if os(watchOS)
        guard HKHealthStore.isHealthDataAvailable(), workoutSession == nil else { return }
        
        let workoutConfig = HKWorkoutConfiguration()
        workoutConfig.activityType = .other
        workoutConfig.locationType = .outdoor
        
        do {
            workoutSession = try HKWorkoutSession(healthStore: healthStore, configuration: workoutConfig)
            workoutBuilder = workoutSession?.associatedWorkoutBuilder()
            
            workoutSession?.delegate = self
            workoutBuilder?.delegate = self
            workoutBuilder?.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: workoutConfig)
            
            let startDate = Date()
            workoutSession?.startActivity(with: startDate)
            workoutBuilder?.beginCollection(withStart: startDate) { [weak self] success, error in
                DispatchQueue.main.async {
                    self?.isSessionActive = success
                }
            }
        } catch {
            print("[HealthKitManager] Error starting workout session: \(error.localizedDescription)")
        }
        #else
        isSessionActive = true
        currentHeartRate = 82.0
        #endif
    }
    
    public func stopLiveHeartRateSession() {
        #if os(watchOS)
        guard let session = workoutSession else { return }
        session.end()
        workoutBuilder?.endCollection(withEnd: Date()) { [weak self] _, _ in
            self?.workoutBuilder?.finishWorkout { _, _ in
                DispatchQueue.main.async {
                    self?.workoutSession = nil
                    self?.workoutBuilder = nil
                    self?.isSessionActive = false
                }
            }
        }
        #else
        isSessionActive = false
        #endif
    }
}

#if os(watchOS)
extension HealthKitManager: HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    public func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        DispatchQueue.main.async {
            self.isSessionActive = (toState == .running)
        }
    }
    
    public func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("[HealthKitManager] Workout session failed: \(error.localizedDescription)")
    }
    
    public func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) { }
    
    public func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        guard collectedTypes.contains(heartRateType) else { return }
        
        if let statistics = workoutBuilder.statistics(for: heartRateType) {
            let heartRateUnit = HKUnit.count().unitDivided(by: .minute())
            if let value = statistics.mostRecentQuantity()?.doubleValue(for: heartRateUnit) {
                DispatchQueue.main.async {
                    self.currentHeartRate = value
                }
            }
        }
    }
}
#endif
