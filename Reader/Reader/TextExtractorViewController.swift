//
//  TextExtractorViewController.swift
//  Reader
//
//  Created by Anirudh Natarajan on 6/24/20.
//  Copyright © 2020 Anirudh Natarajan. All rights reserved.
//

import UIKit
import EpubExtractor
import Firebase

class TextExtractorViewController: UIViewController {
    
    @IBOutlet var leftPage: UILabel!
    @IBOutlet var rightPage: UILabel!
    @IBOutlet var pagesTotalLabel: UILabel!
    @IBOutlet var pagesSectionLabel: UILabel!
    
    var epub: Epub!
    var epubName = ""
    var section = 0
    var page = 0
    var book: [[String]] = [[String]]()
    let spacing: CGFloat = 13
    let fontSize: CGFloat = 25
    
    var totalPages = 0
    var currentPage = 0
    var pagesSection = 0
    
    var startTime = Date.init()
    var pastTime = 0
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        UIApplication.shared.isIdleTimerDisabled = true
        self.view.backgroundColor = UIColor.systemBackground
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let style = NSMutableParagraphStyle()
        style.lineSpacing = spacing
        style.alignment = .justified
        
        let font = UIFont(name: "Georgia", size: fontSize)
        
        let attributes = [NSAttributedString.Key.paragraphStyle: style, NSAttributedString.Key.font: font]
        
        leftPage.attributedText = NSAttributedString(string: leftPage.text ?? "ok", attributes: attributes)
        rightPage.attributedText = NSAttributedString(string: rightPage.text ?? "ok", attributes: attributes)
        
        leftPage.adjustsFontSizeToFitWidth = true
        leftPage.minimumScaleFactor = 0.5
        leftPage.lineBreakMode = .byClipping
        leftPage.numberOfLines = 0
        
        rightPage.adjustsFontSizeToFitWidth = true
        rightPage.minimumScaleFactor = 0.5
        rightPage.lineBreakMode = .byClipping
        rightPage.numberOfLines = 0
        
        var sections = extractText()
        if sections.count > 2 {
            sections.remove(at: 0)
        }
        (book, totalPages) = getPagedBook(sections: sections)
        
        let ref = Database.database().reference(fromURL: "https://epubreader-6d14e.firebaseio.com").child(epubName)
        ref.observeSingleEvent(of: .value, with: { (snapshot) in
            for child in snapshot.children {
                let snap = child as! DataSnapshot
                let key = snap.key
                if key == "page" {
                    self.page = Int("\(snap.value ?? 0)")!
                } else if key == "section" {
                    self.section = Int("\(snap.value ?? 0)")!
                } else if key == "current" {
                    self.currentPage = Int("\(snap.value ?? 0)")!
                } else if key == "time" {
                    self.pastTime = Int("\(snap.value ?? 0)")!
                }
            }
            self.pagesSection = self.book[self.section].count
            self.updateText()
        })
        
        ref.observe(.childChanged) { (snapshot) in
            if snapshot.key == "flip"{
                let val = "\(snapshot.value ?? "none")"
                let flip = val.split(separator: "_")[0]
                if flip == "right" {
                    self.nextPage()
                } else if flip == "left" {
                    self.previousPage()
                }
            }
        }
    }

    func nextPage() {
        page += 2
        currentPage += 2
        if page >= book[section].count {
            section += 1
            page = 0
            if section >= book.count {
                section = book.count - 1
                page = book[section].count - 1
                currentPage = totalPages
            }
            pagesSection = book[section].count
        }
        
        updateText()
    }
    
    func previousPage() {
        page -= 2
        currentPage -= 2
        if page < 0 {
            section -= 1
            if section < 0 {
                section = 0
                page = 0
                currentPage = 0
            } else {
                page = book[section].count-2
            }
            pagesSection = book[section].count
        }
        
        updateText()
    }
    
    func updateText() {
        leftPage.text = book[section][page]
        if book[section].count - 1 > page+1 {
            rightPage.text = book[section][page+1]
        } else {
            rightPage.text = ""
        }
        
        pagesTotalLabel.text = "Page \(currentPage)/\(totalPages)"
        pagesSectionLabel.text = "\(pagesSection-page) pages left in this section"
        
        let ref = Database.database().reference(fromURL: "https://epubreader-6d14e.firebaseio.com").child(epubName)
        let time = Date.init().seconds(from: startTime) + pastTime
        let v = ["page":"\(page)", "section":"\(section)", "current":"\(currentPage)", "time":"\(time)"]
        ref.updateChildValues(v, withCompletionBlock: { (err, ref) in
            if err != nil {
                print(err)
                return
            }
        })
    }
    
    func getPagedBook(sections: [String]) -> ([[String]], Int) {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
            for i in fileURLs {
                let a = epubName.replacingOccurrences(of: " ", with: "%20")
                if i.absoluteString.contains("\(a)DESC.txt") {
                    do {
                        print("Found existing file.")
                        let description = try String(contentsOf: i, encoding: .utf8)
                        return arrayFromDesc(desc: description)
                    }
                    catch {
                        print(error)
                    }
                }
            }
        } catch {
           print("Error while enumerating files \(documentsURL.path): \(error.localizedDescription)")
       }
        
        var book:[[String]] = []
        var pages = 0
        
        if sections.count > 0 {
            for i in 0...sections.count-1 {
                let screenSize = self.view.frame.size
                let sectionText = sections[i]
                
                book.append([String]())
                var sectionWords = sectionText.words
                let maxHeight = screenSize.height - (27+55) - spacing*spacing*2
                var excerpt = ""
                
                while sectionWords != [] {
                    (excerpt, sectionWords) = extractHeight(withConstrainedWidth: screenSize.width/2 - (15+20+30), font: leftPage.font!, maxHeight: maxHeight, wordsArray: sectionWords)
                    book[i].append(excerpt)
                    pages += 1
                }
            }
            
            let data:NSData = book.description.data(using: .utf8)! as NSData
            let destinationPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first
            data.write(toFile: "\(destinationPath ?? "")/\(epubName)DESC.txt", atomically: true)
             
        }
        return (book, pages)
    }
    
    func extractText() -> [String] {
        var sections = [String]()
        
        for spine in epub.spines {
            do {
                sections.append(try epub.content(forSpine: spine))
            } catch {
                print("there was an error: \(error)")
            }
        }
        return sections
    }
    
    func extractHeight(withConstrainedWidth width: CGFloat, font: UIFont, maxHeight: CGFloat, wordsArray: [String]) -> (String, [String]) {
        var words = wordsArray
        var excerpt = ""
        
        while (excerpt.height(withConstrainedWidth: width, font: font) < maxHeight) {
            excerpt.append(contentsOf: words[0])
            words.remove(at: 0)
            if words.count-1 >= 1 {
                if excerpt.height(withConstrainedWidth: width, font: font) + words[1].height(withConstrainedWidth: width, font: font) > maxHeight {
                    break
                }
            }
            if words.count-1<=0 {
                break
            }
        }
        
        return (excerpt, words)
    }
    
    func arrayFromDesc(desc: String) -> ([[String]], Int) {
        var book:[[String]] = []
        var z = desc.components(separatedBy: "], [")
        z[0] = String(z[0].dropFirst())
        z[z.count-1] = String(z[z.count-1].dropLast())
        var count = 0
        for i in z {
            let (a,b) = stringToArray(str: i)
            book.append(a)
            count += b
        }
        
        return (book, count)
    }
    
    func stringToArray(str: String) -> ([String], Int) {
        var pages = str.components(separatedBy: "\", \"")
        pages[0] = String(pages[0].dropFirst())
        pages[pages.count-1] = String(pages[pages.count-1].dropLast())
        for i in 0...pages.count-1 {
            pages[i] = pages[i].replacingOccurrences(of: "\\n", with: "\n")
            pages[i] = pages[i].replacingOccurrences(of: "\\\"", with: "\"")
            pages[i] = pages[i].replacingOccurrences(of: "\\'", with: "\'")
        }
        
        return (pages, pages.count)
    }
}

extension String {
    func height(withConstrainedWidth width: CGFloat, font: UIFont) -> CGFloat {
        let constraintRect = CGSize(width: width, height: .greatestFiniteMagnitude)
        let boundingBox = self.boundingRect(with: constraintRect, options: .usesLineFragmentOrigin, attributes: [NSAttributedString.Key.font: font], context: nil)

        return ceil(boundingBox.height)
    }
    
    var lines: [String] {
        return self.components(separatedBy: "\n")
    }
    
    var words: [String] {
        var array = [String]()
        for i in lines {
            let a = i.split(separator: " ")
            for j in a {
                array.append(String(j) + " ")
            }
            array.append("\n")
        }
        return array
    }
}

extension Date {
    func seconds(from date: Date) -> Int {
        return Calendar.current.dateComponents([.second], from: date, to: self).second ?? 0
    }
}
