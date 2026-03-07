import Foundation

struct BlogPost: Identifiable {
    var fileURL: URL
    var title: String
    var date: Date
    var draft: Bool
    var summary: String
    var tags: [String]
    var categories: [String]
    var pin: Bool
    var math: Bool
    var mathJax: Bool
    var isPrivate: Bool
    var searchable: Bool
    var cover: String
    var author: String
    var keywords: [String]
    var customTaxonomies: [String: [String]]
    var taxonomyWeights: [String: Int]
    var slug: String
    var urlPath: String
    var aliases: [String]
    var translationKey: String
    var menuEntry: MenuFrontMatter
    var buildOptions: PostBuildOptions
    var cascadeBuildOptions: PostBuildOptions?
    var frontMatterFormat: FrontMatterFormat
    var rawFrontMatter: String
    var creationMode: ContentCreationMode
    var bundleRootURL: URL?
    var pageResources: [PageResourceItem]
    var body: String

    var id: String {
        fileURL.path
    }

    var fileName: String {
        fileURL.lastPathComponent
    }

    var displayFileName: String {
        switch creationMode {
        case .singleFile:
            return fileURL.lastPathComponent
        case .leafBundle, .branchBundle:
            return bundleRootURL?.lastPathComponent ?? fileURL.deletingLastPathComponent().lastPathComponent
        }
    }

    var usesPageBundle: Bool {
        creationMode.createsBundle
    }

    var bundleDisplayName: String {
        creationMode.displayName
    }

    static func empty(in contentURL: URL) -> BlogPost {
        let file = contentURL.appendingPathComponent("new-post.md")
        return BlogPost(
            fileURL: file,
            title: "",
            date: Date(),
            draft: true,
            summary: "",
            tags: [],
            categories: [],
            pin: false,
            math: false,
            mathJax: false,
            isPrivate: false,
            searchable: true,
            cover: "",
            author: "",
            keywords: [],
            customTaxonomies: [:],
            taxonomyWeights: [:],
            slug: "",
            urlPath: "",
            aliases: [],
            translationKey: "",
            menuEntry: MenuFrontMatter(),
            buildOptions: PostBuildOptions(),
            cascadeBuildOptions: nil,
            frontMatterFormat: .toml,
            rawFrontMatter: "",
            creationMode: .singleFile,
            bundleRootURL: nil,
            pageResources: [],
            body: ""
        )
    }
}
