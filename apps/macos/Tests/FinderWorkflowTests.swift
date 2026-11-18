import AppKit
import Carbon
import CloakToolsCore
import Testing
@testable import CloakTools

@Test func fitAcceptsFinderSizePhrasesAndPreservesTheExactRecipeLimit() throws {
    for (text, expected) in [("under 2 MB", 1_999_999), ("2 MB", 2_000_000), ("500", 500_000),
                             ("1.25 mb", 1_250_000), ("2001 B", 2_001), ("  Under 1.01 KB  ", 1_009)] {
        var draft = ImageFitDraft()
        draft.sizeLimit = text
        let options = try draft.options()
        #expect(options.maximumBytes == expected)
        #expect(try ImageFitDraft(options: options).options() == options)
    }
    for invalid in ["under 1 KB", "5000 MB", "1.2345 KB", "2 apples", "-2 MB"] {
        var draft = ImageFitDraft()
        draft.sizeLimit = invalid
        #expect(throws: ImageFitError.self) { try draft.options() }
    }
}

@MainActor @Test func finderAddsToOneSharingReviewAndStartsFreshAfterSaving() async throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fm.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? fm.removeItem(at: root) }
    let first = root.appendingPathComponent("Contract"), second = root.appendingPathComponent("Receipt")
    try Data("a".utf8).write(to: first)
    try Data("b".utf8).write(to: second)

    let model = AppModel()
    model.workbench.showWindow = {}
    model.present(.collect(files: [first]))
    let review = try #require(model.sharingReview)
    model.workbench.browse(.media)
    model.present(.collect(files: [second]))
    #expect(model.workbench.page == .collect && model.sharingReview === review)
    func waitForReview() async throws {
        let clock = ContinuousClock()
        let limit = clock.now.advanced(by: .seconds(5))
        while review.task.busy, clock.now < limit { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!review.task.busy)
    }
    try await waitForReview()
    #expect(review.files.map(\.name) == ["Contract", "Receipt"])
    review.save(in: root)
    model.present(.collect(files: [second]))
    try await waitForReview()
    #expect(review.files.map(\.name) == ["Receipt"] && review.output == nil)
    #expect(try fm.contentsOfDirectory(atPath: root.appendingPathComponent("Shared Copies").path).sorted() == ["Contract", "Receipt"])
    model.workbench.close(.collect)
    #expect(model.sharingReview == nil)
}

@MainActor @Test func registeredFinderServicesHaveCallableHostMethodsAndBetaChannel() throws {
    let info = try #require(Bundle.main.infoDictionary)
    #expect(info["CloakToolsReleaseChannel"] as? String == "Beta")
    let services = try #require(info["NSServices"] as? [[String: Any]])
    let types = ["fitImage": ImageConversion.inputTypes.map(\.identifier), "reuseStructure": ["public.folder"],
                 "collectCopies": ["public.data"], "compareFolders": ["public.folder"]]
    for (message, identifiers) in types {
        let entry = try #require(services.first { $0["NSMessage"] as? String == message })
        #expect(entry["NSSendFileTypes"] as? [String] == identifiers)
        #expect(AppDelegate.instancesRespond(to: NSSelectorFromString(message + ":userData:error:")))
    }
}

@MainActor @Test func repeatedFinderURLAppleEventsKeepTheOpenCollection() async throws {
    let model = AppModel.shared
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer {
        model.workbench.close(.collect)
        try? FileManager.default.removeItem(at: root)
    }
    let inputs = ["First", "Second"].map { root.appendingPathComponent($0) }
    for input in inputs {
        try Data(input.lastPathComponent.utf8).write(to: input)
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kInternetEventClass), eventID: AEEventID(kAEGetURL),
                                           targetDescriptor: .init(processIdentifier: getpid()), returnID: AEReturnID(kAutoGenerateReturnID),
                                           transactionID: AETransactionID(kAnyTransactionID))
        let url = FinderIntent.collect(files: [input]).url
        event.setParam(.init(string: url.absoluteString), forKeyword: AEKeyword(keyDirectObject))
        _ = try event.sendEvent(options: [.noReply], timeout: 2)
        let clock = ContinuousClock(), deadline = clock.now.advanced(by: .seconds(5))
        while model.sharingReview?.files.contains(where: { $0.source == input.standardizedFileURL }) != true, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
    }
    #expect(model.sharingReview?.files.map(\.name) == ["First", "Second"])
}

@MainActor @Test func reuseReviewSavesAndUpdatesTheChosenBranchesInOneFileSet() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("Last Month")
    for path in ["Assets/Photos", "Deliverables"] {
        try FileManager.default.createDirectory(at: source.appendingPathComponent(path), withIntermediateDirectories: true)
    }
    let review = StructureReview(source)
    let clock = ContinuousClock(), deadline = clock.now.advanced(by: .seconds(5))
    while review.task.busy, clock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
    let store = FileSetStore(url: root.appendingPathComponent("sets.json"))
    review.toggle("Assets", included: false)
    review.name = "June"
    review.saveSet { try store.save([$0]) }
    let first = try #require(store.load().first)
    #expect(first.entries.map(\.path) == ["Deliverables"] && review.matchesSavedSet)
    review.toggle("Assets/Photos", included: true)
    #expect(!review.matchesSavedSet && review.selection.contains("Assets"))
    review.saveSet { try store.save([$0]) }
    let second = try #require(store.load().first)
    #expect(second.id == first.id && second.entries.map(\.path) == ["Assets/Photos", "Deliverables"])
}
