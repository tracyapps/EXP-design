import Foundation

struct DocumentSearch {
    enum Kind: String, CaseIterable {
        case page = "Page"
        case artboard = "Artboard"
        case source = "Component Source"
        case instance = "Component Instance"

        var filterName: String {
            switch self {
            case .page: "Pages"
            case .artboard: "Artboards"
            case .source: "Component Sources"
            case .instance: "Component Instances"
            }
        }
    }

    enum Target: Hashable {
        case page(UUID)
        case artboard(pageID: UUID, id: UUID)
        case source(UUID)
        case instance(pageID: UUID, id: UUID)
    }

    struct Result: Identifiable {
        let id: Target
        let kind: Kind
        let name: String
        let location: String
        let pageID: UUID?
        var componentName: String? = nil
    }

    let results: [Result]

    init(document: Document) {
        var results: [Result] = []
        var sources: [UUID: String] = [:]
        for source in document.sources {
            sources[source.id] = source.name
            results.append(Result(id: .source(source.id), kind: .source, name: source.name,
                                  location: "Components", pageID: nil, componentName: source.name))
        }

        for page in document.pages {
            results.append(Result(id: .page(page.id), kind: .page, name: page.name,
                                  location: "Canvas Pages", pageID: page.id))
            var boards: [UUID: String] = [:]
            for board in page.artboards {
                boards[board.id] = board.name
                results.append(Result(id: .artboard(pageID: page.id, id: board.id), kind: .artboard,
                                      name: board.name, location: page.name, pageID: page.id))
            }
            func indexInstances(in nodes: [Node], parents: [String]? = nil) {
                for node in nodes where node.isVisible {
                    let location = parents ?? [page.name, node.artboardID.flatMap { boards[$0] } ?? "Wall"]
                    switch node.content {
                    case .instance(let instance):
                        let sourceName = sources[instance.sourceID]
                        results.append(Result(id: .instance(pageID: page.id, id: node.id), kind: .instance,
                                              name: node.name,
                                              location: (location + (sourceName.map { [$0] } ?? [])).joined(separator: " › "),
                                              pageID: page.id, componentName: sourceName))
                    case .group(let children):
                        indexInstances(in: children, parents: location + [node.name])
                    default:
                        break
                    }
                }
            }
            indexInstances(in: page.nodes)
        }

        self.results = results.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            if order != .orderedSame { return order == .orderedAscending }
            return $0.location.localizedStandardCompare($1.location) == .orderedAscending
        }
    }

    func matches(_ query: String, kind: Kind?, pageID: UUID?, componentNameOnly: Bool) -> [Result] {
        let words = query.split(whereSeparator: \.isWhitespace)
        return results.filter { result in
            if let kind, result.kind != kind { return false }
            if let pageID, result.pageID != pageID { return false }
            if componentNameOnly {
                guard let name = result.componentName else { return false }
                return words.allSatisfy { name.localizedStandardContains(String($0)) }
            }
            let text = "\(result.name) \(result.kind.rawValue) \(result.location)"
            return words.allSatisfy { text.localizedStandardContains(String($0)) }
        }
    }
}
