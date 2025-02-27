//
//  EntryController.swift
//  JournalCoreData
//
//  Created by Spencer Curtis on 8/12/18.
//  Copyright © 2018 Lambda School. All rights reserved.
//

import Foundation
import CoreData

//#error("Change this value to your own firebase database! (and then delete this line)")
let baseURL = URL(string: "https://journal-4de34.firebaseio.com/")!

class EntryController {
    
    // MARK: - CRUD
    
    func createEntry(with title: String, bodyText: String, mood: String) {
        
        let entry = Entry(title: title, bodyText: bodyText, mood: mood)
        
        put(entry: entry)
        
        saveToPersistentStore()
    }
    
    func update(entry: Entry, title: String, bodyText: String, mood: String) {
        
        entry.title = title
        entry.bodyText = bodyText
        entry.timestamp = Date()
        entry.mood = mood
        
        put(entry: entry)
        
        saveToPersistentStore()
    }
    
    func delete(entry: Entry) {
        
        CoreDataStack.shared.mainContext.delete(entry)
        deleteEntryFromServer(entry: entry)
        saveToPersistentStore()
    }
    
    // MARK: - Networking Methods
    
    private func put(entry: Entry, completion: @escaping ((Error?) -> Void) = { _ in }) {
        
        let identifier = entry.identifier ?? UUID().uuidString
        let requestURL = baseURL.appendingPathComponent(identifier).appendingPathExtension("json")
        var request = URLRequest(url: requestURL)
        request.httpMethod = "PUT"
        
        do {
            request.httpBody = try JSONEncoder().encode(entry)
        } catch {
            NSLog("Error encoding Entry: \(error)")
            completion(error)
            return
        }
        
        URLSession.shared.dataTask(with: request) { (data, _, error) in
            if let error = error {
                NSLog("Error PUTting Entry to server: \(error)")
                completion(error)
                return
            }
            
            
            
            completion(nil)
        }.resume()
    }
    
    func deleteEntryFromServer(entry: Entry, completion: @escaping ((Error?) -> Void) = { _ in }) {
        
        guard let identifier = entry.identifier else {
            NSLog("Entry identifier is nil")
            completion(NSError())
            return
        }
        
        let requestURL = baseURL.appendingPathComponent(identifier).appendingPathExtension("json")
        var request = URLRequest(url: requestURL)
        request.httpMethod = "DELETE"
        
        URLSession.shared.dataTask(with: request) { (data, _, error) in
            if let error = error {
                NSLog("Error deleting entry from server: \(error)")
                completion(error)
                return
            }
            
            completion(nil)
        }.resume()
    }
    
    func fetchEntriesFromServer(completion: @escaping ((Error?) -> Void) = { _ in }) {
        
        let requestURL = baseURL.appendingPathExtension("json")
        
        URLSession.shared.dataTask(with: requestURL) { (data, _, error) in
            
            if let error = error {
                NSLog("Error fetching entries from server: \(error)")
                completion(error)
                return
            }
            
            guard let data = data else {
                NSLog("No data returned from data task")
                completion(NSError())
                return
            }

            let moc = CoreDataStack.shared.mainContext
            
            do {
                let entryReps = try JSONDecoder().decode([String: EntryRepresentation].self, from: data).map({$0.value})
                self.updateEntries(with: entryReps/*, in: moc*/)
            } catch {
                NSLog("Error decoding JSON data: \(error)")
                completion(error)
                return
            }
            
            moc.perform {
                do {
                    try moc.save()
                    completion(nil)
                } catch {
                    NSLog("Error saving context: \(error)")
                    completion(error)
                }
            }
        }.resume()
    }
    
    // MARK: - Local Storage Methods
    
    func updateEntries(with representations: [EntryRepresentation]) {
        
        // Which representations do we already have in Core Data?
        
        let identifiersToFetch = representations.map { $0.identifier }
        
        let representationsByID = Dictionary(uniqueKeysWithValues: zip(identifiersToFetch, representations))
        
        // Make a mutable copy of the dictionary above
        
        var entriesToCreate = representationsByID
        
        let fetchRequest: NSFetchRequest<Entry> = Entry.fetchRequest()
        // Only fetch tasks with these identifiers
        fetchRequest.predicate = NSPredicate(format: "identifier IN %@", identifiersToFetch) // or potentially "identifier NOT IN %@"
        
        let context = CoreDataStack.shared.container.newBackgroundContext()
        
        context.performAndWait {
            
            
            
            do {
                let existingEntries = try context.fetch(fetchRequest)
                
                // Update the ones we do have
                
                for entry in existingEntries {
                    
                    // Grab the TaskRepresentation that corresponds to this task
                    guard let identifier = entry.identifier,
                        let representation = representationsByID[identifier] else { continue }
                    // This can be abstracted out to another function
                    entry.title = representation.title
                    entry.bodyText = representation.bodyText
                    entry.mood = representation.mood
                    
                    
                    entriesToCreate.removeValue(forKey: identifier)
                }
                
                // Figure out which ones we don't have
                
                for representation in entriesToCreate.values {
                    Entry(entryRepresentation: representation, context: context)
                }
                try context.save()
            } catch {
                print("Error fetching tasks from persistent store: \(error)")
            }
        }
    }
    
    private func fetchSingleEntryFromPersistentStore(with identifier: String?, in context: NSManagedObjectContext) -> Entry? {
        
        guard let identifierToFetch = identifier else { return nil }
        
        let fetchRequest: NSFetchRequest<Entry> = Entry.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "identfier IN %@"/*"identfier == %@"*/, identifierToFetch)
        
        var result: Entry? = nil
        do {
            result = try context.fetch(fetchRequest).first
            print(result?.identifier ?? "It's nil")
        } catch {
            NSLog("Error fetching single entry: \(error)")
            return nil
        }
        return result
    }
    
    private func updateEntries(with representations: [EntryRepresentation], in context: NSManagedObjectContext) {
        context.performAndWait {
            for entryRep in representations {
                guard let identifier = entryRep.identifier else { continue }
                
                let entry = self.fetchSingleEntryFromPersistentStore(with: identifier, in: context)
                if let entry = entry, entry != entryRep {
                    self.update(entry: entry, with: entryRep)
                } else if entry == nil {
                    _ = Entry(entryRepresentation: entryRep, context: context)
                }
            }
        }
    }
    
    private func update(entry: Entry, with entryRep: EntryRepresentation) {
        entry.title = entryRep.title
        entry.bodyText = entryRep.bodyText
        entry.mood = entryRep.mood
        entry.timestamp = entryRep.timestamp
        entry.identifier = entryRep.identifier
    }
    
    func saveToPersistentStore() {        
        do {
            try CoreDataStack.shared.mainContext.save()
        } catch {
            NSLog("Error saving managed object context: \(error)")
        }
    }
}
