import Foundation

protocol ArtSource {
    func loadArtPaths(completion: @escaping ([String]) -> Void)
}

class FolderSource: ArtSource {

    private let folderPath: String

    init(folderPath: String) {
        self.folderPath = folderPath
    }

    func loadArtPaths(completion: @escaping ([String]) -> Void) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: folderPath) else {
            completion([])
            return
        }

        let ansiExtensions: Set<String> = ["ans", "ansi", "asc", "diz", "ice", "bin", "xb", "pcb", "adf"]

        let paths = contents
            .filter { name in
                let ext = (name as NSString).pathExtension.lowercased()
                return ansiExtensions.contains(ext)
            }
            .compactMap { name -> String? in
                let path = (folderPath as NSString).appendingPathComponent(name)
                guard let data = Cache.read(path) else { return nil }
                guard AnsiContentValidator.isLikelyAnsiArt(data: data, fileName: name) else { return nil }
                return path
            }

        completion(paths)
    }
}

class PackSource: ArtSource {

    private let packURL: String

    init(packURL: String) {
        self.packURL = packURL
    }

    func loadArtPaths(completion: @escaping ([String]) -> Void) {
        let packName = extractPackName(from: packURL)

        PackFetcher.fetchFileList(packURL: packURL) { filenames in
            guard !filenames.isEmpty else {
                completion([])
                return
            }

            let queue = DispatchQueue(label: "com.lardissone.AnsiSaver.packSource")
            var localPaths: [String] = []
            let group = DispatchGroup()

            for filename in filenames {
                let localPath = Cache.ansPath(forPack: packName, file: filename)

                if Cache.exists(localPath) {
                    if let data = Cache.read(localPath),
                       AnsiContentValidator.isLikelyAnsiArt(data: data, fileName: filename) {
                        queue.sync { localPaths.append(localPath) }
                    } else {
                        try? FileManager.default.removeItem(atPath: localPath)
                    }
                    if Cache.exists(localPath) {
                        continue
                    }
                }

                group.enter()
                PackFetcher.downloadFile(packURL: self.packURL, filename: filename, to: localPath) { success in
                    if success {
                        queue.sync { localPaths.append(localPath) }
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                completion(localPaths)
            }
        }
    }

    private func extractPackName(from url: String) -> String {
        let trimmed = url.hasSuffix("/") ? String(url.dropLast()) : url
        return (trimmed as NSString).lastPathComponent
    }
}

class URLSource: ArtSource {

    private let fileURLs: [String]

    init(fileURLs: [String]) {
        self.fileURLs = fileURLs
    }

    func loadArtPaths(completion: @escaping ([String]) -> Void) {
        let queue = DispatchQueue(label: "com.lardissone.AnsiSaver.urlSource")
        var localPaths: [String] = []
        let group = DispatchGroup()

        for urlString in fileURLs {
            let localPath = Cache.urlCachePath(for: urlString)
            let remoteName = URL(string: urlString)?.lastPathComponent ?? "download.ans"

            if Cache.exists(localPath) {
                if let data = Cache.read(localPath),
                   AnsiContentValidator.isLikelyAnsiArt(data: data, fileName: remoteName) {
                    queue.sync { localPaths.append(localPath) }
                } else {
                    try? FileManager.default.removeItem(atPath: localPath)
                }
                if Cache.exists(localPath) {
                    continue
                }
            }

            guard let url = URL(string: urlString) else { continue }

            group.enter()
            let task = URLSession.shared.dataTask(with: url) { data, _, error in
                if let data = data, error == nil,
                   AnsiContentValidator.isLikelyAnsiArt(data: data, fileName: remoteName) {
                    Cache.write(data, to: localPath)
                    queue.sync { localPaths.append(localPath) }
                }
                group.leave()
            }
            task.resume()
        }

        group.notify(queue: .main) {
            completion(localPaths)
        }
    }
}
