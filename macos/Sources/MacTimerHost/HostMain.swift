import Foundation
import MacTimerCore

@main
enum MacTimerHost {
    static func main() {
        let store = UsageSnapshotStore()

        while true {
            guard let header = readExactly(4) else { break }
            let rawLength = header.withUnsafeBytes {
                $0.load(as: UInt32.self)
            }
            let length = Int(UInt32(littleEndian: rawLength))

            guard length > 0, length <= 4_000_000 else {
                write(NativeSyncResponse(ok: false, error: "invalid message length"))
                break
            }

            guard let body = readExactly(length) else { break }
            let response = process(body: body, store: store)
            guard write(response) else { break }
        }
    }

    private static func process(
        body: Data,
        store: UsageSnapshotStore
    ) -> NativeSyncResponse {
        do {
            let payload = try JSONDecoder().decode(
                NativeSyncPayload.self,
                from: body
            )
            guard payload.type == "sync" else {
                return NativeSyncResponse(
                    ok: false,
                    error: "unsupported message type"
                )
            }

            let existing: UsageSnapshot?
            do {
                existing = try store.load()
            } catch {
                existing = nil
            }

            let needFull = payload.reset != true && existing == nil
            let snapshot = UsageMerger.merge(
                existing: existing,
                payload: payload
            )
            try store.save(snapshot)

            return NativeSyncResponse(
                ok: true,
                updatedAt: snapshot.updatedAt,
                days: snapshot.days.count,
                needFull: needFull
            )
        } catch {
            return NativeSyncResponse(
                ok: false,
                error: String(describing: error)
            )
        }
    }

    private static func readExactly(_ count: Int) -> Data? {
        var data = Data()
        while data.count < count {
            let chunk: Data
            do {
                chunk = try FileHandle.standardInput.read(
                    upToCount: count - data.count
                ) ?? Data()
            } catch {
                return nil
            }
            if chunk.isEmpty { return nil }
            data.append(chunk)
        }
        return data
    }

    @discardableResult
    private static func write(_ response: NativeSyncResponse) -> Bool {
        do {
            let data = try JSONEncoder().encode(response)
            var length = UInt32(data.count).littleEndian
            let header = Data(bytes: &length, count: 4)
            try FileHandle.standardOutput.write(contentsOf: header)
            try FileHandle.standardOutput.write(contentsOf: data)
            return true
        } catch {
            return false
        }
    }
}
