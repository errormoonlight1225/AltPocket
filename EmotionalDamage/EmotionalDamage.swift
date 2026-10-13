import Foundation

@discardableResult
public func start_em_proxy(bind_addr: String) -> Int32 {
    return bind_addr.withCString { start_emotional_damage($0) }
}

public func stop_em_proxy() { stop_emotional_damage() }
