import Foundation

enum PackFetcher {

    static func fetchFileList(packURL: String, completion: @escaping ([String]) -> Void) {
        let normalizedURL = packURL.hasSuffix("/") ? packURL : packURL + "/"
        guard let url = URL(string: normalizedURL) else {
            completion([])
            return
        }

        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil,
                  let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                completion([])
                return
            }
            guard let html = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1) else {
                completion([])
                return
            }

            let filenames = parseANSFilenames(from: html)
            completion(filenames)
        }
        task.resume()
    }

    static func downloadFile(packURL: String, filename: String, to localPath: String,
                             completion: @escaping (Bool) -> Void) {
        let normalizedURL = packURL.hasSuffix("/") ? packURL : packURL + "/"
        guard let encodedFilename = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            completion(false)
            return
        }
        let rawURL = normalizedURL + "raw/" + encodedFilename
        guard let url = URL(string: rawURL) else {
            completion(false)
            return
        }

        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil,
                  let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                completion(false)
                return
            }

            Cache.write(data, to: localPath)
            completion(true)
        }
        task.resume()
    }

    static func parseANSFilenames(from html: String) -> [String] {
        let pattern = #"href="[^"]*?/([^/"]+\.(?:ans|ANS|ice|ICE|asc|ASC|bin|BIN|xb|XB|pcb|PCB|adf|ADF))""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range)

        var filenames: [String] = []
        for match in matches {
            if let filenameRange = Range(match.range(at: 1), in: html) {
                let filename = String(html[filenameRange])
                if !filenames.contains(filename) {
                    filenames.append(filename)
                }
            }
        }
        return filenames
    }
}
