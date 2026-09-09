import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published var db: WorkDatabase = .seed
    @Published var session: AppSession?
    @Published var selectedDate = Date()
    @Published var selectedMonth = Date()
    @Published var selectedStoreId: String?
    @Published var syncText = "동기화 대기"
    @Published var passcode = UserDefaults.standard.string(forKey: "nodeulgil-pass") ?? ""

    private let apiURL = URL(string: "https://nodeulgil-api.jmiochvjk.workers.dev/data")!
    private let storageKey = "nodeulgil-ios-db"
    private var remoteVersion: Int64 = 0

    init() {
        loadLocal()
        selectedStoreId = db.shops.first?.id
    }

    var activeStoreId: String? {
        switch session {
        case .admin: selectedStoreId
        case .manager(let person), .staff(let person): person.storeId
        case nil: nil
        }
    }

    var activeStore: Shop? {
        guard let activeStoreId else { return nil }
        return db.shops.first { $0.id == activeStoreId }
    }

    func login(pin: String) -> Bool {
        guard pin.range(of: #"^\d{4,8}$"#, options: .regularExpression) != nil else { return false }
        if let admin = db.admins.first(where: { $0.pin == pin }) {
            session = .admin(admin)
            selectedStoreId = db.shops.first?.id
            return true
        }
        guard let person = db.people.first(where: { $0.pin == pin }) else { return false }
        session = person.role == .manager ? .manager(person) : .staff(person)
        selectedStoreId = person.storeId
        return true
    }

    func logout() {
        session = nil
    }

    func savePasscode(_ value: String) {
        passcode = value.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(passcode, forKey: "nodeulgil-pass")
    }

    func people(in storeId: String?) -> [Person] {
        guard let storeId else { return [] }
        return db.people.filter { $0.storeId == storeId }.sorted { $0.name < $1.name }
    }

    func recordsForActiveMonth() -> [WorkRecord] {
        guard let sid = activeStoreId else { return [] }
        let key = selectedMonth.monthKey
        return db.records
            .filter { $0.storeId == sid && $0.date.hasPrefix(key) }
            .sorted {
                $0.date == $1.date ? $0.start < $1.start : $0.date < $1.date
            }
    }

    func reservationsForActiveMonth() -> [Reservation] {
        guard let sid = activeStoreId else { return [] }
        let key = selectedMonth.monthKey
        return db.reservations
            .filter { $0.storeId == sid && $0.datetime.hasPrefix(key) }
            .sorted { $0.datetime < $1.datetime }
    }

    func totalMinutes(for person: Person) -> Int {
        recordsForActiveMonth()
            .filter { $0.staffId == person.id }
            .reduce(0) { $0 + minutes(from: $1.start, to: $1.end) }
    }

    func saveWork(person: Person, date: Date, start: Date, end: Date, review: Int, note: String) {
        let dateKey = date.ymd
        let startText = timeString(start)
        let endText = timeString(end)
        mutate {
            if let index = db.records.firstIndex(where: { $0.date == dateKey && $0.staffId == person.id }) {
                db.records[index].start = startText
                db.records[index].end = endText
                db.records[index].review = review
                if case .staff = session {} else { db.records[index].note = note }
            } else {
                db.records.append(WorkRecord(
                    id: makeId("rec"),
                    storeId: person.storeId,
                    staffId: person.id,
                    date: dateKey,
                    start: startText,
                    end: endText,
                    review: review,
                    note: note,
                    ok: false
                ))
            }
        }
    }

    func addPerson(name: String, pin: String, role: PersonRole) -> Bool {
        guard let sid = activeStoreId, isValidPin(pin), !name.isEmpty, !pinTaken(pin) else { return false }
        mutate {
            db.people.append(Person(id: makeId("person"), storeId: sid, name: name, pin: pin, role: role))
        }
        return true
    }

    func updatePerson(_ person: Person, name: String, pin: String, role: PersonRole) -> Bool {
        guard canManage(person), isValidPin(pin), !name.isEmpty, !pinTaken(pin, excluding: person.id) else { return false }
        mutate {
            guard let index = db.people.firstIndex(where: { $0.id == person.id }) else { return }
            db.people[index].name = name
            db.people[index].pin = pin
            db.people[index].role = role
        }
        refreshSessionIfNeeded(personId: person.id)
        return true
    }

    func deletePerson(_ person: Person) {
        guard canManage(person) else { return }
        mutate {
            db.people.removeAll { $0.id == person.id }
            db.records.removeAll { $0.staffId == person.id }
        }
    }

    func addShop(name: String, managerName: String, pin: String) -> Bool {
        guard !name.isEmpty, !managerName.isEmpty, isValidPin(pin), !pinTaken(pin) else { return false }
        let shopId = makeId("shop")
        mutate {
            db.shops.append(Shop(id: shopId, name: name, createdAt: Int64(Date().timeIntervalSince1970 * 1000)))
            db.people.append(Person(id: makeId("person"), storeId: shopId, name: managerName, pin: pin, role: .manager))
        }
        selectedStoreId = shopId
        return true
    }

    func updateShopName(_ name: String) -> Bool {
        guard case .admin = session, let sid = selectedStoreId, !name.isEmpty else { return false }
        mutate {
            guard let index = db.shops.firstIndex(where: { $0.id == sid }) else { return }
            db.shops[index].name = name
        }
        return true
    }

    func deleteActiveShop() {
        guard case .admin = session, let sid = selectedStoreId, db.shops.count > 1 else { return }
        mutate {
            db.shops.removeAll { $0.id == sid }
            db.people.removeAll { $0.storeId == sid }
            db.records.removeAll { $0.storeId == sid }
            db.reservations.removeAll { $0.storeId == sid }
        }
        selectedStoreId = db.shops.first?.id
    }

    func addReservation(date: Date, time: Date, customer: String, phone: String, memo: String, remindMin: Int) -> Bool {
        guard let sid = activeStoreId, !customer.isEmpty else { return false }
        let dt = "\(date.ymd)T\(timeString(time))"
        let creator: String?
        if case .staff(let person) = session { creator = person.id } else { creator = nil }
        mutate {
            db.reservations.append(Reservation(
                id: makeId("res"),
                storeId: sid,
                staffId: creator,
                datetime: dt,
                customer: customer,
                phone: phone,
                memo: memo,
                remindMin: remindMin,
                notified: false,
                createdBy: creator
            ))
        }
        return true
    }

    func deleteReservation(_ reservation: Reservation) {
        guard let sid = activeStoreId, reservation.storeId == sid else { return }
        mutate {
            db.reservations.removeAll { $0.id == reservation.id }
        }
    }

    func pull() async {
        guard !passcode.isEmpty else {
            syncText = "동기화 비밀번호 필요"
            return
        }
        var request = URLRequest(url: apiURL)
        request.setValue(passcode, forHTTPHeaderField: "X-Pass")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                syncText = "동기화 실패"
                return
            }
            let envelope = try JSONDecoder().decode(SyncEnvelope.self, from: data)
            if let remote = envelope.data {
                db = remote
                remoteVersion = envelope.v
                saveLocal()
                syncText = "동기화됨"
            }
        } catch {
            syncText = "오프라인"
        }
    }

    func push() async {
        guard !passcode.isEmpty else {
            syncText = "동기화 비밀번호 필요"
            return
        }
        var request = URLRequest(url: apiURL)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(passcode, forHTTPHeaderField: "X-Pass")
        request.httpBody = try? JSONEncoder().encode(PushEnvelope(data: db, base: remoteVersion))
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode
            if status == 409 {
                let envelope = try JSONDecoder().decode(SyncEnvelope.self, from: data)
                if let remote = envelope.data {
                    db = remote
                    remoteVersion = envelope.v
                    saveLocal()
                }
                syncText = "다른 기기 변경 반영됨"
                return
            }
            guard status == 200 else {
                syncText = "저장 대기"
                return
            }
            remoteVersion = (try? JSONDecoder().decode(SyncEnvelope.self, from: data).v) ?? Int64(Date().timeIntervalSince1970 * 1000)
            syncText = "저장됨"
        } catch {
            syncText = "오프라인 저장"
        }
    }

    private func mutate(_ change: () -> Void) {
        change()
        saveLocal()
        Task { await push() }
    }

    private func loadLocal() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let local = try? JSONDecoder().decode(WorkDatabase.self, from: data) else { return }
        db = local
    }

    private func saveLocal() {
        if let data = try? JSONEncoder().encode(db) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func canManage(_ person: Person) -> Bool {
        switch session {
        case .admin:
            person.storeId == selectedStoreId
        case .manager(let manager):
            person.storeId == manager.storeId && person.role != .manager
        default:
            false
        }
    }

    private func refreshSessionIfNeeded(personId: String) {
        guard let person = db.people.first(where: { $0.id == personId }) else { return }
        switch session {
        case .staff(let old) where old.id == personId:
            session = person.role == .manager ? .manager(person) : .staff(person)
        case .manager(let old) where old.id == personId:
            session = person.role == .manager ? .manager(person) : .staff(person)
        default:
            break
        }
    }

    private func pinTaken(_ pin: String, excluding id: String = "") -> Bool {
        db.admins.contains { $0.pin == pin && $0.id != id } ||
        db.people.contains { $0.pin == pin && $0.id != id }
    }

    private func isValidPin(_ pin: String) -> Bool {
        pin.range(of: #"^\d{4,8}$"#, options: .regularExpression) != nil
    }

    private func makeId(_ prefix: String) -> String {
        "\(prefix)-\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(6).lowercased())"
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func minutes(from start: String, to end: String) -> Int {
        let s = start.split(separator: ":").compactMap { Int($0) }
        let e = end.split(separator: ":").compactMap { Int($0) }
        guard s.count == 2, e.count == 2 else { return 0 }
        var total = (e[0] * 60 + e[1]) - (s[0] * 60 + s[1])
        if total < 0 { total += 1440 }
        return total
    }
}
