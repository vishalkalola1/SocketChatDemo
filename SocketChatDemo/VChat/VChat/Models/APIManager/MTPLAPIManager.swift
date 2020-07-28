//
//  MTPLAPIManager.swift
//  mindpillow
//
//  Created by Moweb on 23/05/19.
//  Copyright © 2019 vishal. All rights reserved.
//

import Reachability
import CommonCrypto
import SocketIO

typealias completionHandlerAPI = (Data?,String?) -> Void
typealias reloadCustomData = (_ percentage:Int) -> Void

class MTPLAPIManager: NSObject {
    
    //MARK: ---- All ClassObject ----
    static let shared = MTPLAPIManager()
    
    
    
    private var reachability: Reachability?
    private var isInternetReachable : Bool = false
    private var Header = [String:String]()
    private var appData = Data()
    private var FileURL : URL?
    private var session : URLSession!
    var progressData : reloadCustomData!
    var finalResponse : completionHandlerAPI!
    
    
    
    private func buildRequest(_ url:String) -> URLRequest {
        let url = URL(string: url)!
        print("\n\n URL ------- 🚀 -------->> \n \(url) \n <<-------- 🚀 -------\n\n ")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        return request
    }
    
    private func makeSession() -> URLSession {
        let configuaration = URLSessionConfiguration.background(withIdentifier: "Test")
        let session = URLSession(configuration: configuaration, delegate: self, delegateQueue: .main)
        return session
    }
    
    func callPostAPI(_ url:String,requestBody:[String:Any]? = nil, isJsonData:Bool? = false, isLoaderShow:Bool? = true, completionHandler:@escaping completionHandlerAPI) -> Void {
        guard let parameters = requestBody else {
            return
        }
        
        var request = buildRequest(url)
        var formData = String()
        
        formData = convertIntoFormData(parameters)
        
        request.httpBody = formData.data(using: .utf8)
        request.timeoutInterval = 120.0
        
        if reachability?.connection != .none {
            if isLoaderShow! {
                //showProgressHUD("Loading...")
            }
            session = makeSession()
            let task = session.downloadTask(with: request)
            finalResponse = nil
            finalResponse = completionHandler
            task.resume()
        }else{
            print("No Internet Connection")
        }
    }
    
    func upload(_ baseURl:String, parameter:[String:Any]?, videoPath: [String], filekey: String,callback: @escaping completionHandlerAPI) {
        if reachability?.connection != .none {
//            guard let parameters = parameter else {
//                return
//            }
            DispatchQueue.main.async {
                let boundary = self.generateBoundary()
                //self.showProgressHUD("Processing...")
                var request = self.buildRequest(baseURl)
                request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                request.setValue("Keep-Alive", forHTTPHeaderField: "Connection")
                
                guard let payloadFileURL = self.buildPayloadFile(videoFileURL: videoPath, parameter:parameter , boundary: boundary, filekey: filekey) else{
                    callback(nil,"file not found")
                    //MBProgressHUD.hide(for: (UIApplication.topViewController()?.view!)!, animated: true)
                    return
                }
                //self.obj?.label.text = "Uploading..."
                self.performUpload(request, payload: payloadFileURL, callback: callback)
            }
        }else{
            print("No Internet Connection")
        }
    }
    
//    func showProgressHUD(_ text:String) -> Void {
//        obj = MBProgressHUD.showAdded(to: UIApplication.topViewController()!.view, animated: true)
//        obj?.mode = .indeterminate
//        obj?.label.text = text
//    }
    
    private func buildPayloadFile(videoFileURL: [String], parameter:[String:Any]?, boundary: String, filekey: String) -> URL? {
        let fileManager = FileManager.default
        
        let fileURL = fileManager.temporaryDirectory
        let filePath = fileURL.appendingPathComponent(UUID().uuidString).path
        let payloadFileURL = URL(fileURLWithPath: filePath)
        
        guard let stream = OutputStream(url: payloadFileURL, append: false) else {
            return nil
        }
        
        stream.open()
        
        let lineBreak = "\r\n"
        for (key,value) in parameter ?? [:] {
            //define the data post parameter
            stream.write("--\(boundary + lineBreak)")
            stream.write("Content-Disposition:form-data; name=\(key)\(lineBreak + lineBreak)")
            stream.write("\("\(value)" + lineBreak)")
        }
        
        for fileURL in videoFileURL {
            let videoFileURL = URL.init(fileURLWithPath: fileURL)
            let mimetype = videoFileURL.absoluteString.mimeTypeForPath()
            stream.write("--\(boundary + lineBreak)")
            stream.write("Content-Disposition:form-data; name=\(filekey); filename=\"\(videoFileURL.lastPathComponent)\"\(lineBreak)")
            stream.write("Content-Type: \(mimetype + lineBreak + lineBreak)")
            if stream.append(contentsOf: videoFileURL) < 0 {
                 return nil
            }
        }
        
        stream.write(lineBreak)
        stream.write("--\(boundary)--\(lineBreak)")
        stream.close()
        print("\n\n ----- 🛣 ---->> \n \(payloadFileURL) \n <<---- 🛣 ---- \n\n")
        return payloadFileURL
    }
    
    private func performUpload(_ request: URLRequest, payload: URL, callback: @escaping completionHandlerAPI) {
        session = makeSession()
        let task = session.uploadTask(with: request, fromFile: payload)
        finalResponse = callback
        task.resume()
    }
    
    fileprivate func generateBoundary() -> String {
        return "Boundary-\(UUID().uuidString)"
    }
    
    func setupReachability() {
        reachability = Reachability.init()
        if reachability?.connection != .none {
            isInternetReachable = true
        } else {
            isInternetReachable = false
        }
        NotificationCenter.default.addObserver(self, selector: #selector(reachabilityChanged(_:)), name: Notification.Name("reachabilityChanged"), object:reachability)
        do {
            try reachability?.startNotifier()
        } catch {
            print("could not start reachability notifier")
        }
    }
    
    @objc func reachabilityChanged(_ note: Notification) {
        let reachability = note.object as! Reachability
        if reachability.connection != .none {
            isInternetReachable = true
           
            print("internet available")
        } else {
            isInternetReachable = false
            print("internet not available")
        }
    }
    
    
    
    func convertIntoFormData(_ params:[String:Any]) -> String {
        var data = [String]()
        for(key, value) in params {
            data.append(key + "=\(value)")
        }
        return data.map { String($0) }.joined(separator: "&")
    }
    
    func getJsonString(_ body:[String:Any]) -> String {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: body, options: .prettyPrinted)
            let jsonString = String.init(data: jsonData, encoding: .utf8)!
            let cleanJson = jsonString.filter { !"\n\t\r".contains($0) }
            print("\n\n Request Body -------- 🆚 -------->> \n \(cleanJson) \n <<---------- 🆚 -------- \n\n")
            return cleanJson
        } catch {
            fatalError("Wrong Json")
        }
    }
}

extension MTPLAPIManager:URLSessionDelegate {
    
    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        if let err = error {
            print("Error: \(err.localizedDescription)")
        } else {
            print("Sucess")
        }
    }
    
//    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
//        DispatchQueue.main.async {
//            guard let appDelegate = NSApplication.shared.delegate as? AppDelegate, let completionHandler = appDelegate.bgSessionCompletionHandler else {
//                session.finishTasksAndInvalidate()
//                return
//            }
//            appDelegate.bgSessionCompletionHandler = nil
//            completionHandler()
//        }
//    }
}

extension MTPLAPIManager:URLSessionDataDelegate {
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
       // MBProgressHUD.hide(for: (UIApplication.topViewController()?.view!)!, animated: true)
        if let err = error {
            print("\n\n Error Server --------- ❌  --------->>")
            print(err.localizedDescription)
            print(" <<--------- ❌ --------- \n\n")
            finalResponse(nil, err.localizedDescription)
        } else {
            if (task.response as! HTTPURLResponse).statusCode == 200 {
                print("\n\n Receive data With ------- ✅ ------->>  Status code: \((task.response as! HTTPURLResponse).statusCode)")
                if let json = String.init(data: appData, encoding: .utf8){
                    print(json)
                }
                print(" <<------- ✅ ------- \n\n ")
                finalResponse(appData, nil)
            }else{
                print("\n\n Error Server --------- ❌  --------->> Status code: \((task.response as! HTTPURLResponse).statusCode)")
                if let json = String.init(data: appData, encoding: .utf8){
                    print(json)
                }
                print(" <<--------- ❌ --------- \n\n")
                finalResponse(nil, error?.localizedDescription ?? "Server not respoding")
            }
        }
        appData = Data()
        session.finishTasksAndInvalidate()
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        let uploadProgress:Float = Float(totalBytesSent) / Float(totalBytesExpectedToSend)
        let progressPercent = Int(uploadProgress*100)
        print("\n\n Request uploading status ------- 💯 ------->> \(progressPercent) <<------- 💯 ------- \n\n")
        //selfg.progressData!(progressPercent)
    }
    
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: (URLSession.ResponseDisposition) -> Void) {
        completionHandler(URLSession.ResponseDisposition.allow)
    }
    
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        self.appData.append(data)
    }
}

extension MTPLAPIManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            print("\n\n Downloading File ----- 🛣 ---->> \n \(location) \n <<---- 🛣 ---- \n\n")
            let data = try Data(contentsOf: location)
            self.appData.append(data)
        } catch {
            print("\(error.localizedDescription)")
        }
    }
}
 
