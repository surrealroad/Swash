//
//  SparkleUpdater.swift
//  Swash
//

import Foundation
import Sparkle
import Combine

final class SparkleUpdater: ObservableObject {
    static let shared = SparkleUpdater()
    
    private let updaterController: SPUStandardUpdaterController
    
    @Published var canCheckForUpdates: Bool = false
    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            updaterController.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }
    
    private init() {
        self.updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.automaticallyChecksForUpdates = updaterController.updater.automaticallyChecksForUpdates
        
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
    }
    
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
