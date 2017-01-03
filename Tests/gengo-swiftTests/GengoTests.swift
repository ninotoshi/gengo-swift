import UIKit
import XCTest

let TIMEOUT: TimeInterval = 5
let gengo = Gengo(
    publicKey: "Your API Key",
    privateKey: "Your Private Key",
    sandbox: true
)

class GengoFixtures {
    var job1 = GengoJob()
    var job2 = GengoJob()
    
    init() {
        job1.languagePair = GengoLanguagePair(
            source: GengoLanguage(code: "en"),
            target: GengoLanguage(code: "ja"),
            tier: GengoTier.Standard
        )
        job1.sourceText = "Testing Gengo API library calls."
        
        job2.languagePair = GengoLanguagePair(
            source: GengoLanguage(code: "ja"),
            target: GengoLanguage(code: "en"),
            tier: GengoTier.Standard
        )
        job2.sourceText = "API呼出しのテスト"
        job2.slug = "テストslug"
    }
    
    var testJobs: [GengoJob] {
        return [job1, job2]
    }
}

class GengoAccountTests: XCTestCase {
    var expectation: XCTestExpectation?
    
    override func setUp() {
        super.setUp()
        expectation = self.expectation(description: "GengoAccountTests")
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testGetStats() {
        gengo.getStats() {account, error in
            XCTAssertNil(error)
            XCTAssertLessThan(account.since!.timeIntervalSince1970, Date().timeIntervalSince1970)
            
            self.expectation!.fulfill()
        }
        
        waitForExpectations(timeout: TIMEOUT, handler: nil)
    }
    
    func testGetBalance() {
        gengo.getBalance() {account, error in
            XCTAssertNil(error)
            XCTAssertGreaterThanOrEqual(account.creditPresent!, 0.0 as Float)
            
            self.expectation!.fulfill()
        }
        
        waitForExpectations(timeout: TIMEOUT, handler: nil)
    }
    
    func testGetPreferredTranslators() {
        gengo.getPreferredTranslators() {translators, error in
            XCTAssertNil(error)
            for translator in translators {
                XCTAssertGreaterThan(translator.id!, 0)
            }
            
            self.expectation!.fulfill()
        }

        waitForExpectations(timeout: TIMEOUT, handler: nil)
    }
}

class GengoServiceTests: XCTestCase {
    var expectation: XCTestExpectation?
    
    override func setUp() {
        super.setUp()
        expectation = self.expectation(description: "GengoServiceTests")
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testGetLanguages() {
        gengo.getLanguages() {languages, error in
            XCTAssertNil(error)
            XCTAssertGreaterThan(languages.count, 0)
            var english: GengoLanguage?
            for language in languages {
                if language.code == "en" {
                    english = language
                }
            }
            if let e = english {
                XCTAssertEqual(e.name!, "English")
                XCTAssertEqual(e.unitType!, GengoLanguageUnitType.Word)
            } else {
                XCTFail("English not found")
            }

            self.expectation!.fulfill()
        }
        
        waitForExpectations(timeout: TIMEOUT, handler: nil)
    }
    
    func testGetLanguagePairs() {
        gengo.getLanguagePairs(GengoLanguage(code: "ja")) {pairs, error in
            XCTAssertNil(error)
            XCTAssertGreaterThan(pairs.count, 0)
            var nonJaCount = 0
            for pair in pairs {
                if pair.source.code != "ja" {
                    nonJaCount += 1
                }
            }
            XCTAssertEqual(nonJaCount, 0)
            
            self.expectation!.fulfill()
        }
        
        waitForExpectations(timeout: TIMEOUT, handler: nil)
    }
    
    func testGetQuoteText() {
        gengo.getQuoteText(GengoFixtures().testJobs) {jobs, error in
            XCTAssertNil(error)
            XCTAssertGreaterThan(jobs.count, 0)
            
            // the job order in `jobs` may be different from that in `tests`
            for job in jobs {
                if job.languagePair!.source.code == "ja" {
                    XCTAssertEqual(job.unitCount!, 8)
                } else if job.languagePair!.source.code == "en" {
                    XCTAssertEqual(job.unitCount!, 5)
                } else {
                    XCTFail("invalid source language")
                }
                XCTAssertGreaterThan(job.credit!.amount, 0.0 as Float)
            }

            self.expectation!.fulfill()
        }
        
        waitForExpectations(timeout: TIMEOUT, handler: nil)
    }
    
    func testGetQuoteFile() {
        var fileJobs: [GengoJob] = []
        for (i, job) in GengoFixtures().testJobs.enumerated() {
            var fileJob = GengoJob()
            fileJob.languagePair = job.languagePair
            fileJob.sourceFile = GengoFile(
                data: job.sourceText!.data(using: String.Encoding.utf8)!,
                name: "\(i).txt"
            )
            fileJobs.append(fileJob)
        }
        
        for job in fileJobs {
            XCTAssertEqual(job.type!, GengoJobType.File)
        }
        
        gengo.getQuoteFile(fileJobs) {jobs, error in
            XCTAssertNil(error)
            XCTAssertGreaterThan(jobs.count, 0)
            
            // the job order in `jobs` may be different from that in `tests`
            for job in jobs {
                if job.languagePair!.source.code == "ja" {
                    XCTAssertEqual(job.unitCount!, 8)
                } else if job.languagePair!.source.code == "en" {
                    XCTAssertEqual(job.unitCount!, 5)
                } else {
                    XCTFail("invalid source language")
                }
                XCTAssertGreaterThan(job.credit!.amount, 0.0 as Float)
                XCTAssertFalse(job.identifier!.isEmpty)
            }
            
            self.expectation!.fulfill()
        }

        waitForExpectations(timeout: TIMEOUT, handler: nil)
    }
}

class GengoJobsTests: XCTestCase {
    var expectation: XCTestExpectation?
    
    override func setUp() {
        super.setUp()
        expectation = self.expectation(description: "GengoJobsTests")
    }
    
    override func tearDown() {
        super.tearDown()
    }

    func testCreateJobs() {
        gengo.createJobs(GengoFixtures().testJobs) {order, error in
            if let e = error {
                if e.code == GengoErrorCode.notEnoughCredits.rawValue {
                    self.expectation!.fulfill()
                    return
                }
                XCTFail("error is not nil: \(e)")
            }
            
            if let o = order {
                XCTAssertGreaterThanOrEqual(o.id!, 0)
                XCTAssertGreaterThanOrEqual(o.credit!.amount, 0.0 as Float)
                XCTAssertGreaterThanOrEqual(o.jobCount!, 0)
            } else {
                if error == nil { // all the jobs are duplicates
                    self.expectation!.fulfill()
                    return
                }
                XCTFail("order is nil")
            }
            
            self.expectation!.fulfill()
        }
        
        waitForExpectations(timeout: TIMEOUT, handler: nil)
    }
    
    func testGetJobsWithParameters() {
        let parameters: [String: Any] = ["count": 1]
        gengo.getJobs(parameters) {jobs, error in
            XCTAssertNil(error)
            XCTAssertEqual(jobs.count, 1)
            
            self.expectation!.fulfill()
        }
        
        waitForExpectations(timeout: TIMEOUT, handler: nil)
    }
    
    func testGetJobsWithIDs() {
        gengo.getJobs([1217482, 1217483]) {jobs, error in
            XCTAssertNil(error)
            XCTAssertEqual(jobs.count, 2)
            
            self.expectation!.fulfill()
        }
        
        waitForExpectations(timeout: TIMEOUT, handler: nil)
    }
}

class GengoJobTests: XCTestCase {
    var expectation: XCTestExpectation?
    
    override func setUp() {
        super.setUp()
        expectation = self.expectation(description: "GengoJobTests")
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testGetJob() {
        let jobID = 1222395
        gengo.getJob(jobID, mt: GengoBool.false) {job, error in
            XCTAssertNil(error)
            if let j = job {
                XCTAssertEqual(j.id!, jobID)

                if let order = j.order {
                    XCTAssertGreaterThan(order.id!, 0)
                } else {
                    XCTFail("order is nil")
                }
            } else {
                XCTFail("job is nil")
            }
            
            self.expectation!.fulfill()
        }

        waitForExpectations(timeout: TIMEOUT, handler: nil)
    }
    
    func testPutJob() {
        var feedback = GengoFeedback()
        feedback.rating = 5
        feedback.commentForTranslator = "thank you"
        feedback.commentForGengo = "awesome"
        gengo.putJob(1222396, action: GengoJobAction.approve(feedback)) {error in
            XCTAssertNil(error)
            
            self.expectation!.fulfill()
        }
        
        waitForExpectations(timeout: TIMEOUT, handler: nil)
    }
    
    func testDeleteJob() {
        gengo.deleteJob(1222391) {error in
            XCTAssertNil(error)

            self.expectation!.fulfill()
        }
        
        waitForExpectations(timeout: TIMEOUT, handler: nil)
    }
    
    func testGetRevisions() {
        gengo.getRevisions(1222391) {revisions, error in
            XCTAssertNil(error)
            for revision in revisions {
                XCTAssertGreaterThan(revision.id!, 0)
            }
            
            self.expectation!.fulfill()
        }
        
        waitForExpectations(timeout: TIMEOUT, handler: nil)
    }
    
    func testGetRevision() {
        gengo.getRevision(1222106, revisionID: 2569054) {revision, error in
            XCTAssertNil(error)
            
            self.expectation!.fulfill()
        }
        
        waitForExpectations(timeout: TIMEOUT, handler: nil)
    }
    
    func testGetFeedback() {
        gengo.getFeedback(1222396) {feedback, error in
            XCTAssertNil(error)
            
            self.expectation!.fulfill()
        }
        
        waitForExpectations(timeout: TIMEOUT, handler: nil)
    }
    
    func testGetComments() {
        gengo.getComments(1222395) {comments, error in
            XCTAssertNil(error)
            
            self.expectation!.fulfill()
        }
        
        waitForExpectations(timeout: TIMEOUT, handler: nil)
    }
    
    func testPostComment() {
        gengo.postComment(1222395, comment: "どうも") {error in
            XCTAssertNil(error)
            
            self.expectation!.fulfill()
        }
        
        waitForExpectations(timeout: TIMEOUT, handler: nil)
    }
}

class GengoOrderTests: XCTestCase {
    var expectation: XCTestExpectation?
    
    override func setUp() {
        super.setUp()
        expectation = self.expectation(description: "GengoOrderTests")
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testGetOrder() {
        gengo.getOrder(321447) {order, error in
            XCTAssertNil(error)
            if let o = order {
                XCTAssertGreaterThan(o.id!, 0)
                XCTAssertGreaterThan(o.jobCount!, 0)
                XCTAssertGreaterThan(o.units!, 0)
                XCTAssertGreaterThan(o.credit!.amount, 0.0 as Float)
            }
            
            self.expectation!.fulfill()
        }
        
        waitForExpectations(timeout: TIMEOUT, handler: nil)
    }
    
    func testDeleteOrder() {
        gengo.deleteOrder(321747) {error in
            XCTAssertNil(error)
            
            self.expectation!.fulfill()
        }
        
        waitForExpectations(timeout: TIMEOUT, handler: nil)
    }
}

class GengoGlossaryTests: XCTestCase {
    var expectation: XCTestExpectation?
    
    override func setUp() {
        super.setUp()
        expectation = self.expectation(description: "GengoGlossaryTests")
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testGetGlossaries() {
        gengo.getGlossaries() {glossaries, error in
            XCTAssertNil(error)
            for glossary in glossaries {
                XCTAssertGreaterThan(glossary.id!, 0)
            }

            self.expectation!.fulfill()
        }
        
        waitForExpectations(timeout: TIMEOUT, handler: nil)
    }
    
    func testGetGlossary() {
        gengo.getGlossary(0) {glossary, error in
            XCTAssertNil(error)
            
            self.expectation!.fulfill()
        }
        
        waitForExpectations(timeout: TIMEOUT, handler: nil)
    }
}

class GengoConvertPrimitiveTests: XCTestCase {
    func testToInt() {
        XCTAssertEqual(Gengo.toInt(1)!, 1)
        XCTAssertEqual(Gengo.toInt("1")!, 1)
        XCTAssertEqual(Gengo.toInt("0")!, 0)
        XCTAssertEqual(Gengo.toInt(1.8)!, 1)

        XCTAssertNil(Gengo.toInt(""))
        XCTAssertNil(Gengo.toInt("a"))
        XCTAssertNil(Gengo.toInt(nil))
    }
    
    func testToFloat() {
        XCTAssertEqual(Gengo.toFloat(1.8)!, 1.8 as Float)
        XCTAssertEqual(Gengo.toFloat(1)!, 1 as Float)
        XCTAssertEqual(Gengo.toFloat("1.8")!, 1.8 as Float)
        XCTAssertEqual(Gengo.toFloat("1")!, 1 as Float)
        XCTAssertEqual(Gengo.toFloat("")!, 0.0 as Float)
        XCTAssertEqual(Gengo.toFloat("a")!, 0.0 as Float)

        XCTAssertNil(Gengo.toFloat(nil))
    }
    
    func testToDate() {
        XCTAssertEqual(Gengo.toDate("1")!, Date(timeIntervalSince1970: 1))
        XCTAssertEqual(Gengo.toDate(1)!, Date(timeIntervalSince1970: 1))

        XCTAssertNil(Gengo.toDate(""))
        XCTAssertNil(Gengo.toDate("a"))
        XCTAssertNil(Gengo.toDate(nil))
    }
}

class GengoBoolTests: XCTestCase {
    func test() {
        XCTAssertEqual(GengoBool(value: true), GengoBool.true)
        XCTAssertEqual(GengoBool(value: false), GengoBool.false)
        XCTAssertEqual(GengoBool(value: nil), GengoBool.false)
        XCTAssertEqual(GengoBool(value: ""), GengoBool.false)
        XCTAssertEqual(GengoBool(value: "1"), GengoBool.true)
        XCTAssertEqual(GengoBool(value: "0"), GengoBool.false)
        XCTAssertEqual(GengoBool(value: 2), GengoBool.true)
        XCTAssertEqual(GengoBool(value: 1), GengoBool.true)
        XCTAssertEqual(GengoBool(value: 0), GengoBool.false)
        XCTAssertEqual(GengoBool(value: -1), GengoBool.false)
        
        XCTAssertEqual(GengoBool.true.toInt(), 1)
        XCTAssertEqual(GengoBool.false.toInt(), 0)
        
        XCTAssertTrue(GengoBool.true.boolValue)
        XCTAssertFalse(GengoBool.false.boolValue)
        
        XCTAssert(true == GengoBool.true)
        XCTAssert(true != GengoBool.false)
        XCTAssert(false == GengoBool.false)
        XCTAssert(false != GengoBool.true)
        XCTAssert(GengoBool.true == true)
        XCTAssert(GengoBool.true != false)
        XCTAssert(GengoBool.false == false)
        XCTAssert(GengoBool.false != true)

        XCTAssertFalse(true == GengoBool.false)
        XCTAssertFalse(true != GengoBool.true)
        XCTAssertFalse(false == GengoBool.true)
        XCTAssertFalse(false != GengoBool.false)
        XCTAssertFalse(GengoBool.true == false)
        XCTAssertFalse(GengoBool.true != true)
        XCTAssertFalse(GengoBool.false == true)
        XCTAssertFalse(GengoBool.false != false)
        
        XCTAssertTrue(Bool(GengoBool.true))
        XCTAssertFalse(Bool(GengoBool.false))
    }
}