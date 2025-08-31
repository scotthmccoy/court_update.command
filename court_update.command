#!/usr/bin/swift

import Foundation
import RegexBuilder

// Check for chrome-cli
let result = shell("which chrome-cli")
guard !result.contains("not found") else {
	print("Requires chrome-cli. Please execute the following to continue:")
	print("brew install chrome-cli")
	exit(1)
}


// Get the tab ID
let tabId:Int 
do {
	tabId = try getTabIdOrOpen(
		url: "https://www.lacourt.ca.gov/casesummary/v2web3/?casetype=familylaw"
	)
} catch {
	printError("\(error)")
	exit(1)
}



// Run some javascript to submit the form
// You may need to go to Chrome and activate "View -> Developer -> Allow JavaScript from Apple Events"

execute(
	js: "document.querySelector('input[id=\\\"txtCaseNumber\\\"]').value = '24STFL12676'", 
	tabId: tabId
)

execute(
	js: "document.querySelector('input[id=\\\"submit1\\\"').click();", 
	tabId: tabId
)


// Wait for page to load
_ = getSourceUntilContaining(string: "24STFL12676", tabId: tabId)

// Extract dates
guard let mostRecentDate = getMostRecentDateFromSource() else {
	printError("No dates!")
	shell("say No Dates")
	exit(1)
}

// Convert to days ago
guard let daysAgo = Calendar.current.dateComponents([.day], from: mostRecentDate, to: Date()).day else {
	printError("No dates!")
	shell("say No Dates")
	exit(1)
}
shell("say \"\(daysAgo) days ago\"")


//let dateFormatter = DateFormatter()
//dateFormatter.dateFormat = "MMMM d, yyyy"
//let strDate = dateFormatter.string(from: mostRecentDate)
//print("Most Recent Update: \(strDate)")






// MARK: Other
func getMostRecentDateFromSource(format: String = "MM/dd/yyyy") -> Date? {
	let source = getSource(tabId: tabId)

	let dateFormatter = DateFormatter()
	dateFormatter.dateFormat = format


	var collectionDates:[Date] = source
	// Get all dates
	.match("[0-9]{1,2}\\/[0-9]{1,2}\\/[0-9]{4}")

	// Squash the array from [[String]] to [String]
	.flatMap({$0})

	// Convert to Swift.Date
	.compactMap {
		dateFormatter.date(from: $0)
	}


	collectionDates = collectionDates
	.sorted()
	.reversed()

	let dates = Array(collectionDates)

	return dates.first
}







// MARK: chrome-cli Funcs
enum CLISwiftError: Error {
	case generic(String)
}

func getTabId(url: String) -> Int? {
	let tabs = shell("chrome-cli list tablinks")

	guard let tab = tabs.split(separator: "\n")
	.first(where: {
		$0.contains(url)
	}) else {
		return nil
	}

	guard let strTabId = String(tab).substring(
		from: "[", 
		to: "]"
	) else {
		return nil
	}

	return Int(strTabId)
}

func getTabIdOrOpen(
	url: String
) throws(CLISwiftError) -> Int {

	// If the tab is already open return early
	if let tabId = getTabId(url: url) {
		return tabId
	}

	// Open the tab, and check every half second for 5 seconds
	shell("open -a /Applications/Google\\ Chrome.app \"\(url)\"")
	for _ in 1...10 {
		Thread.sleep(forTimeInterval: 0.5)

		if let tabId = getTabId(url: url) {
			return tabId
		}
	}

	throw .generic("Could not get tab")
}

func execute(
	js: String,
	tabId: Int
) {
	shell("chrome-cli execute \"\(js)\" -t \(tabId)")
}

func getSource(tabId: Int) -> String {
	shell("chrome-cli source -t \(tabId)")
}


// Essentially, waits for page load by getting the source until it contains a given string.
func getSourceUntilContaining(string: String, tabId: Int) -> String? {
	for _ in 1...10 {
		let source = getSource(tabId: tabId)
		if source.contains(string) {
			return source
		}
		Thread.sleep(forTimeInterval: 0.5)
	}

	return getSource(tabId: tabId)
}


// MARK: CLI Funcs
func printError(_ message: String) {
    fputs(message + "\n", stderr)
}

@discardableResult
func shell(_ command: String) -> String {
    let task = Process()
    let pipe = Pipe()
    
    task.standardOutput = pipe
    task.standardError = pipe
    task.arguments = ["-c", command]
    task.executableURL = URL(fileURLWithPath: "/bin/zsh")
    task.standardInput = nil

	do {
	    try task.run()
	} catch {
		return "Error: \(error)"
	}
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)!
    
    return output
}


// MARK: Sting Extensions
extension StringProtocol {
    func index<S: StringProtocol>(of string: S, options: String.CompareOptions = []) -> Index? {
        range(of: string, options: options)?.lowerBound
    }
    func endIndex<S: StringProtocol>(of string: S, options: String.CompareOptions = []) -> Index? {
        range(of: string, options: options)?.upperBound
    }
    func indices<S: StringProtocol>(of string: S, options: String.CompareOptions = []) -> [Index] {
        ranges(of: string, options: options).map(\.lowerBound)
    }
    func ranges<S: StringProtocol>(of string: S, options: String.CompareOptions = []) -> [Range<Index>] {
        var result: [Range<Index>] = []
        var startIndex = self.startIndex
        while startIndex < endIndex,
            let range = self[startIndex...]
                .range(of: string, options: options) {
                result.append(range)
                startIndex = range.lowerBound < range.upperBound ? range.upperBound :
                    index(range.lowerBound, offsetBy: 1, limitedBy: endIndex) ?? endIndex
        }
        return result
    }
}



// MARK: String
extension String {
    
    public func numberOfOccurances(_ str:String) -> Int {
        let ret = self.components(separatedBy:str).count - 1
        return ret
    }

    func match(_ regex: String) -> [[String]] {
        let nsString = self as NSString
        
        return (
            try? NSRegularExpression(
                pattern: regex,
                options: []
            )
        )?.matches(
            in: self,
            options: [],
            range: NSMakeRange(0, nsString.length)
        )
        .map { match in
            (0..<match.numberOfRanges)
            .map {
                match
                .range(at: $0)
                .location == NSNotFound ? "" : nsString.substring(
                    with: match.range(at: $0)
                )
            }
        } ?? []
    }

    public func groupMatch(regex:String, groupNumber:Int) -> String? {
        let regex = try! NSRegularExpression(pattern:regex)
        
        let range = NSRange(location:0, length:self.count)
        guard let match = regex.firstMatch(in:self, range:range) else {
            return nil
        }
        
        guard let groupRange = Range(match.range(at:groupNumber), in:self) else {
            return nil
        }
            
        let ret = self[groupRange]
        return String(ret)
    }
    
    public func substring(to:Int) -> String {
        let startIndex = self.startIndex
        let endIndex = index(self.startIndex, offsetBy:min(to, self.count))
        let substring = self[startIndex ..< endIndex]
        let ret = String(substring)
        return ret
    }
    
    public func substring(from:String, to:String? = nil) -> String? {
        guard let startIndex = self.endIndex(of:from) else {
            return nil
        }

        let substr = self[startIndex..<self.endIndex]
        
        if let unwrappedTo = to {
            guard let endIndex = substr.index(of:unwrappedTo) else {
                return nil
            }

            let ret = String(substr[substr.startIndex..<endIndex])
            return ret
        } else {
            return String(substr)
        }
    }


    @available(iOS 16, *)
    func transformBetween(
        startToken: String,
        endToken: String,
        transform: (String) -> (String)
    ) -> String {
        
        let matcher = Regex {
            startToken
            Capture {
                OneOrMore(.any, .reluctant)
            }
            endToken
        }

        return self.replacing(matcher, with: { match in
            return startToken + transform(String(match.output.1)) + endToken
        })
    }

}
