//
//  GetBandWidht.swift
//  SAMUH
//
//  Created by Jigar Khatri on 14/09/22.
//

import Foundation
import ObjectMapper


struct RawPlaylistModel: Codable{
    internal var Url: URL?
    internal var content: String?
}

struct StreamResolution: Codable{
    internal var bandwidth: Double?
    internal var name: String?
}


func getPlaylist(from url: URL, completion: @escaping (String) -> Void) {
    let task = URLSession.shared.dataTask(with: url) { data, response, error in
        if let error = error {
            print(error)
            completion("")
        } else if let data = data, let string = String(data: data, encoding: .utf8) {
            print(url)
            print(string)
            completion(string)
        } else {
            print("")
        }
    }
    task.resume()
}


/// Iterates over the provided playlist contetn and fetches all the stream info data under the `#EXT-X-STREAM-INF"` key.
/// - Parameter playlist: Playlist object obtained from the stream url.
/// - Returns: All available stream resolutions for respective bandwidth.

//func getStreamResolutions(from playlist: RawPlaylistModel, completion: @escaping ([StreamResolution], [StreamUrl]) -> Void) {
//    var resolutions = [StreamResolution]()
//    var resolutionsURL = [StreamUrl]()
//
//    return completion(resolutions, resolutionsURL)
//
//}
func getStreamResolutions(from playlist: RawPlaylistModel, completion: @escaping ([StreamResolution], [String]) -> Void) {
    var resolutions = [StreamResolution]()
    var resolutionsURL = [String]()

    playlist.content?.enumerateLines { line, shouldStop in
        print(line)
        
        let infoline = line.replacingOccurrences(of: "#EXT-X-STREAM-INF", with: "")
        let infoItems = infoline.components(separatedBy: ",")
        let bandwidthItem = infoItems.first(where: { $0.contains(":BANDWIDTH") })
        let nameItem = infoItems.first(where: { $0.contains("RESOLUTION")})
        let nameURL = infoItems.first(where: { $0.contains("chunklist_")})
        let isHtpps = infoItems.first(where: { $0.contains("https:")})

        //SET NAME
        if nameURL != "" && nameURL != nil{
            resolutionsURL.append(nameURL ?? "")
        }
        else if isHtpps != ""{
            resolutionsURL.append(isHtpps ?? "")
        }
        
        //SET BANNER
        if let bandwidth = bandwidthItem?.components(separatedBy: "=").last,
            let name = nameItem?.components(separatedBy: "=").last{
            print(nameURL ?? "")
            var strName = name.replacingOccurrences(of: "p", with: "")
            strName = strName.replacingOccurrences(of: "\"", with: "")
            
            let arrItem = strName.components(separatedBy: "x")
            if arrItem.count != 0{
                strName = arrItem[0]
            }
            
            let band : Float = Float(bandwidth) ?? 0.0
            resolutions.append(StreamResolution(bandwidth: Double(band), name: strName))
        }
    }
    return completion(resolutions ,resolutionsURL)
}

