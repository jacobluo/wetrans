import Foundation

public struct TransferQueueEvent: Equatable, Sendable {
    public let task: TransferTask

    public init(task: TransferTask) {
        self.task = task
    }
}
