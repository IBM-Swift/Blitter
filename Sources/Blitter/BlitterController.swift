/**
 * Copyright IBM Corporation 2016
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 **/

import Kitura
import Kassandra
import Foundation
import SwiftyJSON
import CredentialsFacebook
import LoggerAPI

public class BlitterController {
    
    let kassandra = Kassandra()
    public let router = Router()
    
    public init() {
        router.all("/*", middleware: BodyParser())
        router.get("/", handler: getMyFeed)
        router.get("/:user", handler: getUserFeed)
        router.post("/", handler: bleet)
        router.put("/:user", handler: followAuthor)
    }
}


extension BlitterController: BlitterProtocol {
    
    public func bleet(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
        
        let userID = authenticate(request: request, defaultUser: "Robert")
        
        let jsonResult = request.json
        guard let json = jsonResult else {
            response.status(.badRequest)
            next()
            return
        }
        
        let message = json[Bleet.FieldNames.message.rawValue].stringValue
        
        try self.kassandra.connect(with: "blitter") { result in
            
            let sql = "SELECT subscriber FROM subscription WHERE author='\(userID)'"
            self.kassandra.execute(sql){ result in
                let rows = result.asRows!
                
                let subscribers: [String] = rows.flatMap {
                    return $0[Subscription.Field.subscriber.rawValue] as? String
                }
                
                let newbleets: [Bleet] = subscribers.map {
                    return Bleet( id:          UUID(),
                                  author:      userID,
                                  subscriber:  $0,
                                  message:     message,
                                  postDate:    Date())
                }
                
                newbleets.forEach { $0.save() { _ in } }
                
                response.status(.OK)
                next()
            }
            
        }
    }
    
    public func getMyFeed(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
        
        let userID = authenticate(request: request, defaultUser: "Jack")
        
        try kassandra.connect(with: "blitter") { result in
            Bleet.fetch(predicate: Bleet.Field.subscriber.rawValue == userID, limit: 50) { bleets, error in
                if let twts = bleets {
                    do {
                        try response.status(.OK).send(json: JSON(twts.stringValuePairs)).end()
                        
                    } catch {
                        print(error)
                    }
                }
            }
        }
    }
    
    public func getUserFeed(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
        
        guard let myUsername = request.parameters["user"] else {
            response.status(.badRequest)
            next()
            return
        }
        
        try kassandra.connect(with: "blitter") { result in
        Bleet.fetch(predicate: Bleet.Field.author.rawValue == myUsername, limit: 50) { bleets, error in
                
                if let twts = bleets {
                    do {
                        try response.status(.OK).send(json: JSON(twts.stringValuePairs)).end()
                        
                    } catch {
                        print(error)
                    }
                }
            }
        }
    }
    
    
    public func followAuthor(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
        
        let myUsername = authenticate(request: request, defaultUser: "Jack")
        
        guard let author = request.parameters["user"] else {
            response.status(.badRequest)
            next()
            return
        }
        try kassandra.connect(with: "blitter") { _ in
            Subscription.insert([.id: UUID(), .author: author, .subscriber: myUsername]).execute { result in
                do {
                    try response.status(.OK).end()
                    
                } catch {
                    print(error)
                }
            }
        }
    }
    
    
}



