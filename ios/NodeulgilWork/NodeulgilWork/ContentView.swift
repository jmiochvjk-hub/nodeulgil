import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Group {
            if store.session == nil {
                LoginView()
            } else {
                MainView()
            }
        }
        .task { await store.pull() }
    }
}

struct LoginView: View {
    @EnvironmentObject private var store: AppStore
    @State private var pin = ""
    @State private var message = ""

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.white.ignoresSafeArea()

                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("노들길")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.blue)
                                Text("근무기록")
                                    .font(.system(size: 32, weight: .heavy))
                            }
                            Spacer()
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(.blue)
                                .frame(width: 56, height: 56)
                                .background(Color.blue.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }

                        HStack(spacing: 8) {
                            RolePill(text: "직원")
                            RolePill(text: "점장")
                            RolePill(text: "관리자")
                        }
                    }
                    .padding(.top, max(24, proxy.safeAreaInsets.top + 12))
                    .padding(.horizontal, 24)

                    Spacer(minLength: 28)

                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("PIN 로그인")
                                .font(.system(size: 22, weight: .bold))
                            Text("등록된 PIN을 입력해 주세요.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        SecureField("PIN 4~8자리", text: $pin)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .font(.system(size: 22, weight: .semibold))
                            .padding(.horizontal, 16)
                            .frame(height: 56)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        Button {
                            message = store.login(pin: pin) ? "" : "PIN을 확인해 주세요."
                        } label: {
                            Text("입장")
                                .font(.system(size: 17, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        HStack(spacing: 8) {
                            Image(systemName: store.syncText.contains("됨") || store.syncText.contains("저장") ? "checkmark.circle.fill" : "icloud")
                            Text(store.syncText)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        if !message.isEmpty {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 430)
                    .background(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color(.separator).opacity(0.35), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 20, y: 10)
                    .padding(.horizontal, 20)

                    Spacer(minLength: 24)

                    Text("Cloudflare 동기화는 앱 내부 설정으로 처리됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, max(18, proxy.safeAreaInsets.bottom + 12))
                }
            }
        }
    }
}

struct RolePill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemBackground))
            .clipShape(Capsule())
    }
}

struct MainView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationStack {
            Group {
                switch store.session {
                case .staff(let person):
                    StaffView(person: person)
                case .manager:
                    ManagerView()
                case .admin:
                    AdminView()
                case nil:
                    EmptyView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.session?.title ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(store.session?.name ?? "")
                            .font(.headline)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("로그아웃") { store.logout() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Text(store.syncText)
                    Spacer()
                    Button("동기화") { Task { await store.pull() } }
                }
                .font(.caption)
                .padding(10)
                .background(.bar)
            }
        }
    }
}

struct StaffView: View {
    @EnvironmentObject private var store: AppStore
    let person: Person
    @State private var showWork = false

    var body: some View {
        List {
            MonthSection()
            SummarySection(people: [person])

            Section("내 근무 입력") {
                Button("오늘 근무 기록") { showWork = true }
                WorkRows(records: store.recordsForActiveMonth())
            }

            ReservationSection(canDelete: false)
        }
        .navigationTitle(store.activeStore?.name ?? "직원")
        .sheet(isPresented: $showWork) {
            WorkEditor(person: person, editableMemo: false)
        }
    }
}

struct ManagerView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editingPerson: Person?

    var body: some View {
        List {
            MonthSection()
            AddPersonSection(allowManager: false)
            PeopleManagementSection(people: store.people(in: store.activeStoreId).filter { $0.role != .manager })
            SummarySection(people: store.people(in: store.activeStoreId))

            Section("근무 시간 수정/확인") {
                ForEach(store.people(in: store.activeStoreId)) { person in
                    Button {
                        editingPerson = person
                    } label: {
                        PersonLine(person: person, detail: "\(formatMinutes(store.totalMinutes(for: person)))")
                    }
                }
                WorkRows(records: store.recordsForActiveMonth())
            }

            ReservationSection(canDelete: true)
        }
        .navigationTitle(store.activeStore?.name ?? "점장")
        .sheet(item: $editingPerson) { person in
            WorkEditor(person: person, editableMemo: true)
        }
    }
}

struct AdminView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editingPerson: Person?
    @State private var shopName = ""
    @State private var confirmDelete = false

    var body: some View {
        List {
            Section("점포 선택") {
                Picker("점포", selection: Binding(
                    get: { store.selectedStoreId ?? "" },
                    set: { store.selectedStoreId = $0 }
                )) {
                    ForEach(store.db.shops) { shop in
                        Text(shop.name).tag(shop.id)
                    }
                }
                TextField("점포명", text: $shopName)
                HStack {
                    Button("점포명 저장") { _ = store.updateShopName(shopName) }
                    Spacer()
                    Button("점포 삭제", role: .destructive) { confirmDelete = true }
                }
            }

            AddShopSection()
            AddPersonSection(allowManager: true)
            PeopleManagementSection(people: store.people(in: store.activeStoreId))
            MonthSection()
            SummarySection(people: store.people(in: store.activeStoreId))

            Section("근무 시간 수정/확인") {
                ForEach(store.people(in: store.activeStoreId)) { person in
                    Button {
                        editingPerson = person
                    } label: {
                        PersonLine(person: person, detail: "\(formatMinutes(store.totalMinutes(for: person)))")
                    }
                }
                WorkRows(records: store.recordsForActiveMonth())
            }

            ReservationSection(canDelete: true)
        }
        .navigationTitle("관리자")
        .onAppear { shopName = store.activeStore?.name ?? "" }
        .onChange(of: store.selectedStoreId) { _, _ in shopName = store.activeStore?.name ?? "" }
        .confirmationDialog("점포를 삭제할까요?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("삭제", role: .destructive) { store.deleteActiveShop() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("직원, 근무기록, 예약도 함께 삭제됩니다.")
        }
        .sheet(item: $editingPerson) { person in
            WorkEditor(person: person, editableMemo: true)
        }
    }
}

struct MonthSection: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Section {
            DatePicker("월 선택", selection: $store.selectedMonth, displayedComponents: [.date])
            DatePicker("날짜 선택", selection: $store.selectedDate, displayedComponents: [.date])
        }
    }
}

struct SummarySection: View {
    @EnvironmentObject private var store: AppStore
    let people: [Person]

    var body: some View {
        Section("월간 통계") {
            ForEach(people) { person in
                let records = store.recordsForActiveMonth().filter { $0.staffId == person.id }
                let reviews = records.reduce(0) { $0 + $1.review }
                PersonLine(
                    person: person,
                    detail: "\(formatMinutes(store.totalMinutes(for: person))) · \(records.count)일 · 리뷰 \(reviews)건"
                )
            }
        }
    }
}

struct WorkRows: View {
    @EnvironmentObject private var store: AppStore
    let records: [WorkRecord]

    var body: some View {
        ForEach(records) { record in
            let person = store.db.people.first { $0.id == record.staffId }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(record.date)
                    Spacer()
                    Text("\(record.start)~\(record.end)")
                }
                .font(.subheadline.weight(.semibold))
                Text("\(person?.name ?? "미확인") · \(formatMinutes(minutes(from: record.start, to: record.end))) · 리뷰 \(record.review)건")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !record.note.isEmpty {
                    Text(record.note).font(.caption)
                }
            }
        }
    }
}

struct WorkEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let person: Person
    let editableMemo: Bool
    @State private var date: Date
    @State private var start: Date
    @State private var end: Date
    @State private var review = 0
    @State private var note = ""

    init(person: Person, editableMemo: Bool) {
        self.person = person
        self.editableMemo = editableMemo
        let now = Date()
        _date = State(initialValue: now)
        _start = State(initialValue: Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: now) ?? now)
        _end = State(initialValue: Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: now) ?? now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(person.name) {
                    DatePicker("날짜", selection: $date, displayedComponents: [.date])
                    DatePicker("출근", selection: $start, displayedComponents: [.hourAndMinute])
                    DatePicker("퇴근", selection: $end, displayedComponents: [.hourAndMinute])
                    Stepper("리뷰 \(review)건", value: $review, in: 0...999)
                    TextField(editableMemo ? "특이사항 메모" : "메모는 점장/관리자만 수정 가능", text: $note, axis: .vertical)
                        .disabled(!editableMemo)
                }
            }
            .navigationTitle("근무 기록")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        store.saveWork(person: person, date: date, start: start, end: end, review: review, note: note)
                        dismiss()
                    }
                }
            }
            .onAppear {
                date = store.selectedDate
                if let record = store.db.records.first(where: { $0.date == date.ymd && $0.staffId == person.id }) {
                    start = dateFromTime(record.start)
                    end = dateFromTime(record.end)
                    review = record.review
                    note = record.note
                }
            }
        }
    }
}

struct AddPersonSection: View {
    @EnvironmentObject private var store: AppStore
    let allowManager: Bool
    @State private var name = ""
    @State private var pin = ""
    @State private var role: PersonRole = .employee
    @State private var message = ""

    var body: some View {
        Section("직원 추가") {
            TextField("이름", text: $name)
            SecureField("PIN", text: $pin).keyboardType(.numberPad)
            Picker("구분", selection: $role) {
                if allowManager { Text("점장").tag(PersonRole.manager) }
                Text("직원").tag(PersonRole.employee)
                Text("알바").tag(PersonRole.parttime)
            }
            Button("추가") {
                if store.addPerson(name: name, pin: pin, role: role) {
                    name = ""
                    pin = ""
                    message = ""
                } else {
                    message = "이름/PIN을 확인해 주세요."
                }
            }
            if !message.isEmpty { Text(message).foregroundStyle(.red) }
        }
    }
}

struct PeopleManagementSection: View {
    let people: [Person]

    var body: some View {
        Section("직원/PIN 관리") {
            ForEach(people) { person in
                NavigationLink {
                    PersonEditor(person: person)
                } label: {
                    PersonLine(person: person, detail: "PIN \(person.pin)")
                }
            }
        }
    }
}

struct PersonEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let person: Person
    @State private var name: String
    @State private var pin: String
    @State private var role: PersonRole
    @State private var confirmDelete = false
    @State private var message = ""

    init(person: Person) {
        self.person = person
        _name = State(initialValue: person.name)
        _pin = State(initialValue: person.pin)
        _role = State(initialValue: person.role)
    }

    var body: some View {
        Form {
            Section("정보") {
                Picker("구분", selection: $role) {
                    ForEach(PersonRole.allCases) { role in
                        Text(role.title).tag(role)
                    }
                }
                TextField("이름", text: $name)
                SecureField("PIN", text: $pin).keyboardType(.numberPad)
                Button("저장") {
                    if store.updatePerson(person, name: name, pin: pin, role: role) {
                        dismiss()
                    } else {
                        message = "수정 권한 또는 PIN을 확인해 주세요."
                    }
                }
                if !message.isEmpty { Text(message).foregroundStyle(.red) }
            }

            Section {
                Button("직원 삭제", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle("직원 관리")
        .confirmationDialog("삭제할까요?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("삭제", role: .destructive) {
                store.deletePerson(person)
                dismiss()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("이 사람의 근무기록도 함께 삭제됩니다.")
        }
    }
}

struct AddShopSection: View {
    @EnvironmentObject private var store: AppStore
    @State private var name = ""
    @State private var managerName = ""
    @State private var pin = ""
    @State private var message = ""

    var body: some View {
        Section("점포 추가") {
            TextField("점포명", text: $name)
            TextField("점장 이름", text: $managerName)
            SecureField("점장 PIN", text: $pin).keyboardType(.numberPad)
            Button("점포 추가") {
                if store.addShop(name: name, managerName: managerName, pin: pin) {
                    name = ""
                    managerName = ""
                    pin = ""
                    message = ""
                } else {
                    message = "점포명/점장/PIN을 확인해 주세요."
                }
            }
            if !message.isEmpty { Text(message).foregroundStyle(.red) }
        }
    }
}

struct ReservationSection: View {
    @EnvironmentObject private var store: AppStore
    let canDelete: Bool
    @State private var date = Date()
    @State private var time = Date()
    @State private var customer = ""
    @State private var phone = ""
    @State private var memo = ""
    @State private var remindMin = 10

    var body: some View {
        Section("예약자 등록") {
            DatePicker("날짜", selection: $date, displayedComponents: [.date])
            DatePicker("시간", selection: $time, displayedComponents: [.hourAndMinute])
            TextField("고객명", text: $customer)
            TextField("연락처", text: $phone)
            Picker("알림", selection: $remindMin) {
                Text("미설정").tag(0)
                Text("5분 전").tag(5)
                Text("10분 전").tag(10)
                Text("30분 전").tag(30)
                Text("60분 전").tag(60)
            }
            TextField("특이사항 메모", text: $memo, axis: .vertical)
            Button("예약자 등록") {
                if store.addReservation(date: date, time: time, customer: customer, phone: phone, memo: memo, remindMin: remindMin) {
                    customer = ""
                    phone = ""
                    memo = ""
                }
            }
        }

        Section("예약 내역") {
            ForEach(store.reservationsForActiveMonth()) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.customer).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(item.datetime.replacingOccurrences(of: "T", with: " "))
                    }
                    Text("\(item.phone.isEmpty ? "연락처 없음" : item.phone) · 알림 \(item.remindMin)분 전")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !item.memo.isEmpty {
                        Text(item.memo).font(.caption)
                    }
                    if canDelete {
                        Button("삭제", role: .destructive) { store.deleteReservation(item) }
                            .font(.caption)
                    }
                }
            }
        }
    }
}

struct PersonLine: View {
    let person: Person
    let detail: String

    var body: some View {
        HStack {
            Circle()
                .fill(color(for: person.role))
                .frame(width: 9, height: 9)
            VStack(alignment: .leading) {
                Text(person.name)
                Text("\(person.role.title) · \(detail)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

func color(for role: PersonRole) -> Color {
    switch role {
    case .manager: .teal
    case .employee: .blue
    case .parttime: .orange
    }
}

func minutes(from start: String, to end: String) -> Int {
    let s = start.split(separator: ":").compactMap { Int($0) }
    let e = end.split(separator: ":").compactMap { Int($0) }
    guard s.count == 2, e.count == 2 else { return 0 }
    var total = (e[0] * 60 + e[1]) - (s[0] * 60 + s[1])
    if total < 0 { total += 1440 }
    return total
}

func formatMinutes(_ value: Int) -> String {
    let h = value / 60
    let m = value % 60
    return m == 0 ? "\(h)시간" : "\(h)시간 \(m)분"
}

func dateFromTime(_ value: String) -> Date {
    let parts = value.split(separator: ":").compactMap { Int($0) }
    let now = Date()
    guard parts.count == 2 else { return now }
    return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: now) ?? now
}
