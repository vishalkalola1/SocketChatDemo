//
//  SocketManager.swift
//  ChatDemo
//
//  Created by vishal on 14/07/19.
//  Copyright © 2019 vishal. All rights reserved.
//

import UIKit
import SocketIO
import CoreData
import MBProgressHUD


typealias completionHandler = ([String:Any]?, String?) -> Void
typealias completionHandlerArray = ([[String:Any]]?, String?) -> Void
typealias completionHandlerBool = (Bool?, String?) -> Void

protocol ReceiveMessage {
    func receiveMsg(msg : ChatMessages)
    func typingMsg(data : [String:Any])
    func updateStatus(data : [String:Any])
}
protocol ReceiveChannel {
    func receiveChnl()
}


class SocketManagerAPI: NSObject {
    
    let manager = SocketManager(socketURL: URL(string: ChatURLManager.SocketUrl)!, config: [.log(true), .compress, .connectParams(["user_id":UserDefaults.standard.userID ?? ""])])
    let socket : SocketIOClient!
    
    var delegate : ReceiveMessage?
    var chnlDelegate : ReceiveChannel?
    
    static var shared : SocketManagerAPI {
        return SocketManagerAPI()
    }
    
    override init() {
        self.socket = manager.defaultSocket
    }
    
    func connectSocket(completion:completionHandlerBool? = nil) -> Void {
        socket.on(clientEvent: .connect) { data, ack in
            print("---------->> socket connected <<---------------")
            self.getData()
            if let completion = completion {
                completion(true,nil)
            }
        }
        socket.connect()
    }
    
    func socketDisconnect(completion:@escaping completionHandlerBool) -> Void {
        socket.on(clientEvent: .disconnect) { (data, ack) in
            print("---------->> socket disconnected <<---------------")
            completion(true,nil)
        }
        socket.disconnect()
    }
    
    func getData() -> Void {
        if UserDefaults.standard.userID != nil {
            self.socket.removeAllHandlers()
            self.getHistroy()
            self.getChannel()
            self.getTypingMessage()
            self.getChangeStatus()
            self.getMessages()
        }
    }
    
    func getUserList(ackCallBack:@escaping completionHandlerArray) -> Void {
        socket.emitWithAck("UserList").timingOut(after: 0) { (data) in
            print("got data \(data)")
            guard let data = data[0] as? [[String:Any]] else { ackCallBack(nil,"data Not availabel"); return }
            ackCallBack(data,nil)
        }
    }
    
    func getChatList(_ data:[String:Any], ackCallBack:@escaping completionHandlerArray) -> Void {
        socket.emitWithAck("channelList" , data).timingOut(after: 0) { (data) in
            print("got data \(data)")
            guard let data = data[0] as? [[String:Any]] else { ackCallBack(nil,"data Not availabel"); return }
            
            ackCallBack(data,nil)
        }
    }
    
    func insertChannelList(arrayData : [[String:Any]],isUpdatedUnread:Bool = true) -> [ChatList]?{
        do {
            let managedObjectContext = appdelegate.persistentContainer.viewContext
            let decoder = JSONDecoder()
            if let context = CodingUserInfoKey.managedObjectContext {
                decoder.userInfo[context] = managedObjectContext
            }
            let objUser = try decoder.decode([ChatList].self, from: arrayData.toData())
            if isUpdatedUnread {
                for obj in objUser {
                    obj.unreadcount = 1
                }
            }
            appdelegate.saveContext()
            return objUser
        } catch {
            print("nodata found")
            return nil
        }
    }
    
    func getChangeStatus(){
        socket.on("ChangeStatus/\(UserDefaults.standard.userID!)") {data, ack in
            if let getData = data[0] as? [String:Any]{
                let status = self.updateMessageStatus(getData)
                if status {
                    self.delegate?.updateStatus(data: getData)
                }
            }
        }
    }
    
    func getMessages() -> Void {
        socket.on("receiveMessage/\(UserDefaults.standard.userID!)") {data, ack in
            if let getData = data[0] as? [String:Any]{
                if let msg =  self.insertMessage(dict: getData){
                    if msg.sender != UserDefaults.standard.userID {
                        let dict = ["is_read":"2","id":msg.id,"sender":msg.sender] as [String:Any]
                        self.emitStatus(dict)
                        self.delegate?.receiveMsg(msg: msg)
                    }
                }
            }
            ack.with("got it")
        }
    }
    
    func getChatMessageHistory(_ completion : @escaping completionHandlerBool) -> Void {
        let userID = UserDefaults.standard.userID!
        let params = ["id":userID,
                      "updated_at":getLastMessageUpdatedTime() ?? 0] as [String : Any]
        socket.emitWithAck("getMessageHistory", params).timingOut(after: 0) { data in
            let arrayData = data[0] as? [[String:Any]]
            if arrayData?.count ?? 0 > 0 {
                if self.insertUpdateMsgArray(array: arrayData!){
                    completion(true , nil)
                }else{
                    completion(false , nil)
                }
            }else{
                completion(false , nil)
            }
        }
    }
    
    func getLastMessageUpdatedTime() -> Double? {
        let context = appdelegate.persistentContainer.viewContext
        let request = NSFetchRequest<ChatMessages>(entityName: "ChatMessages")
        request.sortDescriptors = [NSSortDescriptor(key: "updated_at", ascending: false)]
        request.fetchLimit = 1
        request.returnsObjectsAsFaults = false
        do{
            let obj = try context.fetch(request)
            if obj.count > 0 {
                print(obj[0].id)
                return obj[0].updated_at
            }else{
                return nil
            }
        }catch{
            return nil
        }
    }
    
    func getLastChatListUpdatedTime() -> Double? {
        let context = appdelegate.persistentContainer.viewContext
        let request = NSFetchRequest<ChatList>(entityName: "ChatList")
        request.sortDescriptors = [NSSortDescriptor(key: "updated_at", ascending: false)]
        request.fetchLimit = 1
        request.returnsObjectsAsFaults = false
        do{
            let obj = try context.fetch(request)
            if obj.count > 0 {
                return obj[0].updated_at
            }else{
                return nil
            }
        }catch{
            return nil
        }
    }
    
    func emitStatus(_ params : [String:Any]) -> Void {
        socket.emit("ChangeStatus", params)
    }
    
    func updateMessageStatus(_ arrayData : [String:Any]) -> Bool {
        
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "ChatMessages")
        fetchRequest.predicate = NSPredicate(format: "id = '\(arrayData["id"] ?? "")'")
        
        do {
            guard let result = try? appdelegate.persistentContainer.viewContext.fetch(fetchRequest)  as? [ChatMessages] else { return false }
            if result.count > 0 {
                let objResult = result[0]
                
                objResult.is_read = arrayData["is_read"] as? String
                appdelegate.saveContext()
            }
            return true
        } catch {
            print("error executing fetch request: \(error.localizedDescription)")
            return false
        }
    }
    
    func getChannel() -> Void {
        socket.on("channelList/\(UserDefaults.standard.userID!)") {data, ack in
            print(data)
            
            guard let customData = data as? [[String:Any]] else { return }
            if (customData[0]["isBroadcast"] as? String) != nil && (customData[0]["isBroadcast"] as? String) == "1" && (customData[0]["createdBy"] as? Int64) == UserDefaults.standard.userID!{
                let updated = self.checkChannelAvailable(customData,isUpdatedUnread: false)
                if updated {
                    self.chnlDelegate?.receiveChnl()
                }
            }else{
                let updated = self.checkChannelAvailable(customData)
                if updated {
                    self.chnlDelegate?.receiveChnl()
                }
            }
            
            ack.with("Got your currentAmount", "dude")
        }
    }
    
    func getTypingMessage() -> Void{
        socket.on("getTyping/\(UserDefaults.standard.userID!)") {data, ack in
            print(data)
            
            guard let customData = data as? [[String:Any]] else { return }
            self.delegate?.typingMsg(data: customData[0])
            ack.with("Got your currentAmount", "dude")
        }
    }
    
    func updateUnReadMsgCount(_ chatID : Int64, count : Int = 0) -> Bool{
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "ChatList")
        fetchRequest.predicate = NSPredicate(format: "chatid = \(chatID)")
        
        
        do {
            guard let result = try? appdelegate.persistentContainer.viewContext.fetch(fetchRequest)  as? [ChatList] else { return false }
            if result.count > 0 {
                let objResult = result[0]
                if count > 0 {
                    objResult.unreadcount += Int16(count)
                }else{
                    objResult.unreadcount = Int16(count)
                }
                
                appdelegate.saveContext()
            }
            return true
        } catch {
            print("error executing fetch request: \(error.localizedDescription)")
            return false
        }
        
    }
    
    func checkChannelAvailable(_ arrayData : [[String:Any]], isUpdatedUnread: Bool = true) -> Bool {
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "ChatList")
        fetchRequest.predicate = NSPredicate(format: "chatid = '\(arrayData[0]["chatid"] ?? "")'")
        
        do {
            guard let result = try? appdelegate.persistentContainer.viewContext.fetch(fetchRequest)  as? [ChatList] else { return false }
            if result.count > 0 {
                let objResult = result[0]
                let updatedData = arrayData[0]
                objResult.userIds = updatedData["userIds"] as? String
                objResult.last_message = updatedData["last_message"] as? String
                objResult.chatid = updatedData["chatid"] as! Int64
                objResult.channelType = updatedData["channelType"] as? String
                objResult.channelName = updatedData["channelName"] as? String
                objResult.updated_at = updatedData["updated_at"] as? Double ?? 0.0
                if isUpdatedUnread {
                    objResult.unreadcount += 1
                }
                if let createdAt = updatedData["created_at"] as? Double {
                    objResult.created_at = createdAt
                }
                appdelegate.saveContext()
            }else{
                _ = self.insertChannelList(arrayData: arrayData,isUpdatedUnread: isUpdatedUnread)
            }
            return true
        } catch {
            print("error executing fetch request: \(error.localizedDescription)")
            return false
        }
    }
    
    func checkChannelAvailable(_ objChatList : ChatList, isUpdatedUnread: Bool = true) -> Bool {
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "ChatList")
        fetchRequest.predicate = NSPredicate(format: "chatid = \(objChatList.chatid)")
        
        do {
            guard let result = try? appdelegate.persistentContainer.viewContext.fetch(fetchRequest)  as? [ChatList] else { return false }
            if result.count > 0 {
                let objResult = result[0]
                objResult.userIds = objChatList.userIds
                objResult.last_message = objChatList.last_message
                objResult.chatid = objChatList.chatid
                objResult.channelType = objChatList.channelType
                objResult.channelName = objChatList.channelName
                objResult.updated_at = objChatList.updated_at
                if isUpdatedUnread {
                    objResult.unreadcount += 1
                }
                appdelegate.saveContext()
                return true
            }else{
                return false
            }
        } catch {
            print("error executing fetch request: \(error.localizedDescription)")
            return false
        }
    }
    
    func checkGetExist(_ objChatID : Int64) -> ChatList? {
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "ChatList")
        fetchRequest.predicate = NSPredicate(format: "chatid = \(objChatID)")
        
        do {
            guard let result = try? appdelegate.persistentContainer.viewContext.fetch(fetchRequest)  as? [ChatList] else { return nil }
            if result.count > 0 {
                return result[0]
            }else{
                return nil
            }
        } catch {
            print("error executing fetch request: \(error.localizedDescription)")
            return nil
        }
    }
    
    func checkMsgAvailable(_ arrayData : [String:Any]) -> Void {
        let fetchRequest = NSFetchRequest<ChatMessages>(entityName: "ChatMessages")
        fetchRequest.predicate = NSPredicate(format: "id = '\(arrayData["id"] ?? "")'")
        
        do {
            let result = try appdelegate.persistentContainer.viewContext.fetch(fetchRequest)
            if result.count > 0 {
                let objResult = result[0]
                let updatedData = arrayData
                objResult.chat_id = updatedData["chat_id"] as! Int64
                objResult.id = updatedData["id"] as! Int64
                objResult.is_read = updatedData["is_read"] as? String
                objResult.message = updatedData["message"] as? String
                objResult.receiver = updatedData["receiver"] as? String
                objResult.sender = updatedData["sender"] as! Int64
                objResult.senderName = updatedData["senderName"] as? String
                objResult.updated_at = updatedData["updated_at"] as? Double ?? 0.0
                objResult.msgtype = Int16(updatedData["msgtype"] as? Int ?? 0)
                objResult.mediaurl = updatedData["mediaurl"] as? String
                objResult.created_at = updatedData["created_at"] as? Double ?? 0.0
                appdelegate.saveContext()
            }else{
                if let msg =  self.insertMessage(dict: arrayData) {
                    if msg.sender != UserDefaults.standard.userID! && Int(msg.is_read!)! <= 2 {
                        
                        if updateUnReadMsgCount(msg.chat_id, count: 1) {
                            let dict = ["is_read":"2","id":msg.id,"sender":msg.sender] as [String:Any]
                            self.emitStatus(dict)
                        }
                    }
                }
            }
        } catch {
            print("error executing fetch request: \(error.localizedDescription)")
        }
    }
    
    func insertUpdateMsgArray(array : [[String:Any]]) -> Bool {
        for (index , msgData) in array.enumerated() {
            checkMsgAvailable(msgData)
            
            if index == array.count - 1{
                return true
            }
        }
        return false
    }
    
    
    func insertMessage(dict : [String:Any]) -> ChatMessages?{
        do{
            let managedObjectContext = appdelegate.persistentContainer.viewContext
            let decoder = JSONDecoder()
            if let context = CodingUserInfoKey.managedObjectContext {
                decoder.userInfo[context] = managedObjectContext
            }
            
            let objUser = try decoder.decode(ChatMessages.self, from: dict.toData())
            appdelegate.saveContext()
            
            return objUser
            
        } catch {
            print(error.localizedDescription)
            return nil
        }
    }
    
    func authenticateUser(_ data:[String:Any], completion:@escaping completionHandler) -> Void {
        socket.emitWithAck("Authenticate",data).timingOut(after: 0) { (data) in
            if let Maindata = data as? [Any], Maindata.count > 0 {
                if let arrayData = Maindata as? [[String:Any]],arrayData.count > 0 {
                    let dataDict = arrayData[0]
                    completion(dataDict,nil)
                } else {
                    completion(nil,"data Not available")
                }
            } else {
                completion(nil,"data Not available")
            }
        }
    }
    
    func userSignUp(_ data:[String:Any], completion:@escaping completionHandler) -> Void {
        socket.emitWithAck("SignUp",data).timingOut(after: 0) { (data) in
            print("got data \(data)")
            guard let data = data[0] as? [String:Any] else { completion(nil,"data Not available"); return }
            completion(data,nil)
        }
    }
    
    func sendMessage(_ params : [String:Any], ackCallBack:@escaping completionHandler) -> Void {
        socket.emitWithAck("sendMessage", params).timingOut(after: 0) { data in
            print("got message")
            guard let data = data[0] as? [String:Any] else { ackCallBack(nil,"data Not available"); return }
            ackCallBack(data,nil)
        }
        print(socket.sid)
    }
    
    func sendBroadcastMessage(_ params : [[String:Any]], ackCallBack:@escaping completionHandlerArray) -> Void {
        socket.emitWithAck("sendbroadcastMessage", params).timingOut(after: 0) { data in
            print("got message")
            guard let data = data[0] as? [[String:Any]] else { ackCallBack(nil,"data Not available"); return }
            ackCallBack(data,nil)
        }
        print(socket.sid)
    }
    
    
    func updateTyping(_ params : [String:Any]) -> Void {
        socket.emit("UserTyping", params)
    }
    
    
    func getChatID(_ params : [String:Any], ackCallBack:@escaping completionHandler) -> Void {
        socket.emitWithAck("GetChatId", params).timingOut(after: 0) { data in
            print("got message")
            guard let data1 = data[0] as? [String:Any] else { ackCallBack(nil,"data Not available"); return }
            ackCallBack(data1,nil)
        }
    }
    
    func createGroup(_ params : [String:Any], ackCallBack:@escaping completionHandler) -> Void {
        socket.emitWithAck("CreateGroup", params).timingOut(after: 0) { data in
            print("got message")
            guard let data1 = data[0] as? [[String:Any]] else { ackCallBack(nil,"data Not available"); return }
            guard let data2 = data1[0]  as? [String:Any] else { ackCallBack(nil,"data Not available"); return }
            ackCallBack(data2,nil)
        }
    }
    
    func getHistroy() -> Void {
        var mbProgress : MBProgressHUD?
        DispatchQueue.main.async {
            mbProgress = MBProgressHUD.showAdded(to: (UIApplication.topViewController()?.view!)!, animated: true)
            mbProgress?.label.text = "Sync Data..."
        }
        
        let params = ["senderId": "\(UserDefaults.standard.userID!)",
            "updated_at":getLastChatListUpdatedTime() ?? 0] as [String : Any]
        
        self.getChatList(params) { (chatList, error) in
            if let error = error {
                print(error)
                mbProgress?.hide(animated: true)
            }else{
                do {
                    //try clearDeepObjectEntity("ChatList")
                    if let chatlist = chatList, chatlist.count > 0 {
                        if self.checkChannelAvailable(chatlist,isUpdatedUnread: false) {
                            self.getChatMessageHistory { (success, error) in
                                if success ?? false{
                                    self.chnlDelegate?.receiveChnl()
                                }
                                mbProgress?.hide(animated: true)
                            }
                        }else{
                            mbProgress?.hide(animated: true)
                        }
                    }else{
                        print("nodata found")
                        mbProgress?.hide(animated: true)
                    }
                }catch{
                    print("nodata found")
                    mbProgress?.hide(animated: true)
                }
            }
        }
    }
}
