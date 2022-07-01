//
//  ContentView.swift
//  GDReaderSUI
//
//  Created by Jim Toth on 5/25/22.
//

import SwiftUI

struct ContentView: View {

  @State private var text: String = """
  0 HEAD
  1 GEDC
  2 VERS 7.0
  0 @I1@ INDI
  1 NAME John /Smith/
  1 FAMS @F1@
  0 @I2@ INDI
  1 NAME Jane /Doe/
  1 FAMS @F1@
  0 @F1@ FAM
  1 HUSB @I1@
  1 WIFE @I2@
  0 @S1@ SOUR
  1 TITL Source One
  0 @N1@ SNOTE Shared note 1
  0 TRLR
  """  // Placeholder GEDCOM File
  
  struct Family: Identifiable, Comparable {
    let id: String
    var husb: String = "?"
    var wife: String = "?"
    let textContent: String
    static func < (lhs: Family, rhs: Family) -> Bool { lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending }
  }
  @State private var families = [
    Family(id: "F1", textContent: "FAM\n1 HUSB @I1@\n1 WIFE @I2@")
  ]  // Placeholders, from the placeholder GEDCOM file.
   
  struct Individual: Identifiable {
    let id: String
    let name: String
    let textContent: String
  }
  @State private var individuals = [
    Individual(id: "I1", name: "Smith John", textContent: "INDI\n1 NAME John /Smith/\n1 FAMS @F1@"),
    Individual(id: "I2", name: "Doe Jane", textContent: "INDI\n1 NAME Jane /Doe/\n1 FAMS @F1@")
  ]  // Placeholders, from the placeholder GEDCOM file.
  @State private var indKeyPath: KeyPath = \Individual.id

  struct GeneralRecord: Identifiable, Comparable {
    let id: String
    let textContent: String
    static func < (lhs: GeneralRecord, rhs: GeneralRecord) -> Bool { lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending }
  }
  @State private var sources = [GeneralRecord(id: "S1", textContent: "SOUR\n1 TITL Source One")]
  @State private var others = [GeneralRecord(id: "HEAD", textContent: "1 GEDC\n2 VERS 7.0"),
                               GeneralRecord(id: "N1", textContent: "SNOTE Shared note 1\n0 TRLR")]
  @State private var currentFileName: String = "click Open New"  // All Placeholders
  
  var body: some View {
    HStack {
      VStack (alignment: .leading) {
        Text(currentFileName)
        TextEditor(text: $text)
          .font(.body)
        HStack() {
          Button(action: {
            let openURL = showOpenPanel()
            readText(from: openURL)
          }, label: {
            HStack {
              Image(systemName: "square.and.arrow.up")
              Text("Open New")
            }
            .frame(width: 120)
          })
          Button(action: {
              processText()
          }, label: {
            Text("Process")
            .frame(width: 80)
          })
          Spacer()
        }
        .padding()
        HStack {
          Spacer()
          Picker("Sort INDI by", selection: $indKeyPath) {
            Text("Xref Number").tag(\Individual.id)
            Text("Surname").tag(\Individual.name)
          }
          .frame(width: 200)
        }
        .padding(.bottom)
      } // end of VStack One Closure
      .frame(width: 300.0)
      VStack (alignment: .leading) {
        HStack(){
          Text(" FAM")
            .frame(minWidth: 50.0)
          Text("HUSB/WIFE")
        }
        NavigationView {
          List() {
             ForEach(families.sorted()) { Family in
                NavigationLink( destination: RecordDetail(recordText: Family.textContent)) {
                  Text(Family.id)
                  Text(Family.husb)
                  Text(Family.wife)
                }
             }
          }
          Text("No selection")
        }
        HStack() {
          Text("  INDI")
            .frame(width: 50.0)
          Text("Name")
        }
        NavigationView {
          List() {
            ForEach(individuals.sorted(by: {$0[keyPath: indKeyPath].localizedStandardCompare($1[keyPath: indKeyPath]) == .orderedAscending})) { Individual in
              NavigationLink( destination: RecordDetail(recordText: Individual.textContent)) {
                Text(Individual.id)
                Text(Individual.name)
              }
            }
          }
          Text("No selection")
       }
      } // end of VStack Two Closure
      VStack(alignment: .leading) {
        Text("SOUR")
        NavigationView {
          List {
            ForEach(sources.sorted()) { GeneralRecord in
              NavigationLink(GeneralRecord.id, destination: TextEditor(text: .constant( GeneralRecord.textContent)))
            }
           }
          Text("No selection")
        }
        Text("Other")
        NavigationView {
          List {
            ForEach(others.sorted()) { GeneralRecord in
              NavigationLink(GeneralRecord.id, destination: TextEditor(text: .constant( GeneralRecord.textContent)))
            }
          }
          Text("No selection")
        }
      } // end of VStack Three Closure
    } // end of HStack
  } // end of body/view
  
  func showOpenPanel() -> URL? {
      let openPanel = NSOpenPanel()
      openPanel.allowedContentTypes = []
      openPanel.allowsMultipleSelection = false
      openPanel.canChooseDirectories = false
      openPanel.canChooseFiles = true
      let response = openPanel.runModal()
      return response == .OK ? openPanel.url : nil
  }
  
  func readText(from url: URL?) {
    guard let url = url else { return }
    do {
      let loadedText = try String(contentsOf: url)
      text = loadedText
    }
    catch {
      guard let loadedText = try? String(contentsOf: url, encoding: String.Encoding.macOSRoman) else { return }
      text = loadedText  // Handles decades old file received "helpfully" encoded for my Mac.
    }
    currentFileName = url.lastPathComponent
  }
  
  func processText() {
//
// Splits "text" into GEDCOM records, placing each record into
// one of four bins. Additional processing is done. The HEAD
// record has content, and is destined for the default others bin.
// The TRLR record has no content. Its level and its tag end up
// being appended to the textContent of the final data record.
// The while loop begins each pass by reading the entire content
// of the current record, after having already parsed the current
// xRef on the previous pass through the loop.
//
    var localFamilies: [Family] = []
    var localIndividuals: [Individual] = []
    var surnameDict: [String: String] = [:]
    var localSources: [GeneralRecord] = []
    var localOthers: [GeneralRecord] = []
    let mysca = Scanner(string: text)
    guard let _ = mysca.scanString("0 HEAD") else {
      print("failed on header record")
      return
    }
    var xRef = "HEAD"  // Initialized with not an actual xRef.
    while !mysca.isAtEnd {
      guard let textContent = mysca.scanUpToString("0 @") else {
        print("failed reading up to next record")
        return
      }
      switch xRef[xRef.startIndex] {
      case "F":
        localFamilies.append(Family(id: xRef, textContent: textContent))
      case "I":
// Extra work for individual record. Parse the individual name, rearrange
// with surname first, save surname in its own dict for later use.
// The function restOfLineFrom is defined in swift file StringExtension.
       var theName = "?"
        if let nameValue = textContent.restOfLineFrom("1 NAME ") {
          let parts = nameValue.split(separator: "/" )
          switch parts.count {
          case 1:
            let processed = String(parts[0])
            if processed.count == nameValue.count {  // had no slashes, so no surname
              theName = "? " + processed
              surnameDict[xRef] = "?"
            }
            else {
              theName = processed + " ?"  // surname only
              surnameDict[xRef] = processed
            }
          case 2:
            let given = String(parts[0])
            let surname = String(parts[1])
            theName = surname + " " + given
            surnameDict[xRef] = surname
          case 3:
            let given = String(parts[0])
            let surname = String(parts[1])
            let suffix = String(parts[2])
            theName = surname + " " + given + suffix
            surnameDict[xRef] = surname
          default:
            break
          }
        }
        localIndividuals.append(Individual(id: xRef, name: theName, textContent: textContent))
      case "S":
        localSources.append(GeneralRecord(id: xRef, textContent: textContent))
      default:
        localOthers.append(GeneralRecord(id: xRef, textContent: textContent))
      }
      if !mysca.isAtEnd {
        guard let _ = mysca.scanString("0 @"),
              let tempXRef = mysca.scanUpToString("@"),
              let _ = mysca.scanString("@ ") else {
          print("failed reading next xRef")
          return
        }
        xRef = tempXRef
      }
    }  // End of while loop.
    individuals = localIndividuals  // No additional processing for display.
    sources = localSources  // Ditto
    others = localOthers  // Ditto
// Process the family spouse surnames, obtained from the previously saved surnameDict.
    for (index, currentFamily) in localFamilies.enumerated() {
      var husband: String? = "noTAG"
      if let husbValue = currentFamily.textContent.restOfLineFrom("1 HUSB ") {
        let parts = husbValue.split(separator: "@" )
        if parts.count > 0 {
          let localXRef = String(parts[0])
          husband = surnameDict[localXRef] ?? "noINDI"
       }
      }
      var wife: String? = "noTAG"
      if let wifeValue = currentFamily.textContent.restOfLineFrom("1 WIFE ") {
        let parts = wifeValue.split(separator: "@" )
        if parts.count > 0 {
          let localXRef = String(parts[0])
          wife = surnameDict[localXRef] ?? "noINDI"
         }
      }
      localFamilies[index].husb = husband ?? "?"
      localFamilies[index].wife = wife ?? "?"
    }
    families = localFamilies
  }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
