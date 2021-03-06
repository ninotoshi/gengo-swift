import Foundation
import MobileCoreServices

open class Gengo {
    let publicKey: String
    let privateKey: String
    let apiHost: String
    var urlSession: URLSessionProtocol
    
    init(publicKey: String, privateKey: String, sandbox: Bool = false, urlSession: URLSessionProtocol = URLSession.shared) {
        self.publicKey = publicKey
        self.privateKey = privateKey
        self.apiHost = sandbox ? "http://api.sandbox.gengo.com/v2/" : "https://api.gengo.com/v2/"
        self.urlSession = urlSession
    }
}

// utilities
extension Gengo {
    class func toInt(_ value: Any?) -> Int? {
        if let n = value as? NSNumber {
            return n.intValue
        } else if let s = value as? String {
            return Int(s)
        }
        return nil
    }
    
    class func toFloat(_ value: Any?) -> Float? {
        if let n = value as? NSNumber {
            return n.floatValue
        } else if let s = value as? String {
            return Float(s)
        }
        return nil
    }
    
    class func toDate(_ value: Any?) -> Date? {
        if let i = toInt(value) {
            return Date(timeIntervalSince1970: Double(i))
        }
        return nil
    }
}

public enum GengoError: Error {
    case systemError(error: Error)
    case httpError(statusCode: Int)
    case invalidResponseError(URLResponse?)
    case applicationError(code: Int?, message: String?)
    case invalidDataError(data: Data)
    case nilDataError()
}

extension Gengo {
    class func toError(
            data optionalData: Data?,
            response optionalResponse: URLResponse?,
            error optionalError: Error?
        ) -> GengoError? {
        
        if let e = optionalError {
            return toError(error: e)
        }

        if let httpResponse = optionalResponse as? HTTPURLResponse {
            if let gengoError = toError(response: httpResponse) {
                return gengoError
            }
        }
        
        if let data = optionalData {
            return toError(data: data)
        }
        
        return GengoError.nilDataError()
    }

    class func toError(error: Error) -> GengoError {
        return GengoError.systemError(error: error)
    }

    class func toError(response: HTTPURLResponse) -> GengoError? {
        let code = response.statusCode
        if 200..<300 ~= code {
            return nil
        }

        return GengoError.httpError(statusCode: code)
    }

    class func toError(data: Data) -> GengoError? {
        if let json = (
            try? JSONSerialization.jsonObject(
                with: data,
                options: JSONSerialization.ReadingOptions.mutableContainers
            )
            ) as? [String: AnyObject] {
            if let opstat = json["opstat"] as? String {
                if opstat == "ok" {
                    return nil
                }
                
                var code: Int? = nil
                var message: String? = nil
                if let err = json["err"] as? [String: AnyObject] {
                    if let ec = err["code"] as? Int {
                        code = ec
                    } else if let ec = err["code"] as? String {
                        code = Int(ec)
                    } else {
                        code = nil
                    }
                    message = err["msg"] as? String
                }
                return GengoError.applicationError(
                    code: code,
                    message: message
                )
            }
        }
        
        return GengoError.invalidDataError(data: data)
    }
}

// Account methods
extension Gengo {
    func getStats(_ callback: @escaping (GengoAccount, GengoError?) -> ()) {
        let request = GengoGet(gengo: self, endpoint: "account/stats")
        request.access() {result, error in
            var account = GengoAccount()
            if let accountDictionary = result as? [String: AnyObject] {
                account = Gengo.toAccount(accountDictionary)
            }
            callback(account, error)
        }
    }
    
    func getBalance(_ callback: @escaping (GengoAccount, GengoError?) -> ()) {
        let request = GengoGet(gengo: self, endpoint: "account/balance")
        request.access() {result, error in
            var account = GengoAccount()
            if let accountDictionary = result as? [String: AnyObject] {
                account = Gengo.toAccount(accountDictionary)
            }
            
            callback(account, error)
        }
    }
    
    func getPreferredTranslators(_ callback: @escaping ([GengoTranslator], GengoError?) -> ()) {
        let request = GengoGet(gengo: self, endpoint: "account/preferred_translators")
        request.access() {result, error in
            var translators: [GengoTranslator] = []
            if let unwrappedResult = result as? [[String: AnyObject]] {
                for json in unwrappedResult {
                    let languagePair = Gengo.toLanguagePair(json)
                    
                    if let translatorArray = json["translators"] as? [[String: AnyObject]] {
                        for translatorDictionary in translatorArray {
                            var translator = GengoTranslator()
                            translator.id = Gengo.toInt(translatorDictionary["id"])
                            translator.jobCount = Gengo.toInt(translatorDictionary["number_of_jobs"])
                            translator.languagePair = languagePair
                            translators.append(translator)
                        }
                    }
                }
            }
            
            callback(translators, error)
        }
    }
}

// Service methods
extension Gengo {
    func getLanguages(_ callback: @escaping ([GengoLanguage], GengoError?) -> ()) {
        let request = GengoGet(gengo: self, endpoint: "translate/service/languages")
        request.access() {result, error in
            var languages: [GengoLanguage] = []
            if let unwrappedResult = result as? [[String: AnyObject]] {
                for language in unwrappedResult {
                    if let code = language["lc"] as? String, let unitType = language["unit_type"] as? String {
                        languages.append(GengoLanguage(
                            code: code,
                            name: language["language"] as? String,
                            localizedName: language["localized_name"] as? String,
                            unitType: GengoLanguageUnitType(rawValue: unitType)
                        ))
                    }
                }
            }
            callback(languages, error)
        }
    }
    
    func getLanguagePairs(_ source: GengoLanguage? = nil, callback: @escaping ([GengoLanguagePair], GengoError?) -> ()) {
        var query: [String: AnyObject] = [:]
        if let src = source {
            query["lc_src"] = src.code as AnyObject?
        }
        
        let request = GengoGet(gengo: self, endpoint: "translate/service/language_pairs", query: query)
        request.access() {result, error in
            var pairs: [GengoLanguagePair] = []
            if let unwrappedResult = result as? [[String: AnyObject]] {
                for pair in unwrappedResult {
                    if let p = Gengo.toLanguagePair(pair) {
                        pairs.append(p)
                    }
                }
            }
            callback(pairs, error)
        }
    }
    
    func getQuoteText(_ jobs: [GengoJob], callback: @escaping ([GengoJob], GengoError?) -> ()) {
        getQuote("translate/service/quote", jobs: jobs, callback: callback)
    }
    
    func getQuoteFile(_ jobs: [GengoJob], callback: @escaping ([GengoJob], GengoError?) -> ()) {
        getQuote("translate/service/quote/file", jobs: jobs, callback: callback)
    }
    
    fileprivate func getQuote(_ endpoint: String, jobs: [GengoJob], callback: @escaping ([GengoJob], GengoError?) -> ()) {
        var jobsDictionary: [String: [String: AnyObject]] = [:]
        var files: [String: GengoFile] = [:]
        for (index, job) in jobs.enumerated() {
            if job.languagePair == nil {
                continue
            }
            if job.type == nil {
                continue
            }
            let job_key = "job_\(index + 1)"
            jobsDictionary[job_key] = [
                "lc_src": job.languagePair!.source.code as AnyObject,
                "lc_tgt": job.languagePair!.target.code as AnyObject,
                "tier": job.languagePair!.tier.rawValue as AnyObject,
                "type": job.type!.rawValue as AnyObject,
            ]
            if (job.type == GengoJobType.File) {
                let file_key = "file_\(index + 1)"
                _ = jobsDictionary[job_key]?.updateValue(file_key as AnyObject, forKey: "file_key")
                files[file_key] = job.sourceFile
            } else {
                if let sourceText = job.sourceText {
                    _ = jobsDictionary[job_key]?.updateValue(sourceText as AnyObject, forKey: "body_src")
                }
            }
        }
        let body = ["jobs": jobsDictionary]
        
        let request = GengoUpload(gengo: self, endpoint: endpoint, body: body as [String : AnyObject], files: files)
        request.access() {result, error in
            callback(self.fillJobs(jobs, result: result), error)
        }
    }
    
    // jobs are passed by value
    fileprivate func fillJobs(_ jobs: [GengoJob], result: AnyObject?) -> [GengoJob] {
        var jobArray: [GengoJob] = []
        if let unwrappedResult = result as? [String: AnyObject] {
            if let unwrappedJobs = unwrappedResult["jobs"] as? [String: [String : AnyObject]] {
                for (key, jobDictionary) in unwrappedJobs {
                    // "job_3" -> ["job", "3"] -> "3" -> 3 -> 2
                    let i = Int(key.split(whereSeparator: {$0 == "_"}).map { String($0) }[1])! - 1
                    var job = jobs[i]
                    job.credit = Gengo.toMoney(jobDictionary)
                    job.eta = Gengo.toInt(jobDictionary["eta"])
                    job.unitCount = Gengo.toInt(jobDictionary["unit_count"])
                    job.identifier = jobDictionary["identifier"] as? String
                    if job.slug == nil {
                        job.slug = jobDictionary["title"] as? String
                    }
                    
                    jobArray.append(job)
                }
            }
        }
        
        return jobArray
    }
}

// Jobs methods
extension Gengo {
    /// Posts GengoJobs.
    /// If both of the GengoOrder and the GengoError are nil, it is probably that all the jobs are duplicates.
    func createJobs(_ jobs: [GengoJob], callback: @escaping (GengoOrder?, GengoError?) -> ()) {
        var jobsDictionary: [String: [String: Any]] = [:]
        for (index, job) in jobs.enumerated() {
            if job.type == nil {
                continue
            }
            if job.languagePair == nil {
                continue
            }
            let jobDictionary: [String: Any?] = [
                "type": job.type!.rawValue,
                "slug": job.slug,
                "body_src": job.sourceText,
                "lc_src": job.languagePair!.source.code,
                "lc_tgt": job.languagePair!.target.code,
                "tier": job.languagePair!.tier.rawValue,
                "identifier": job.identifier,
                "auto_approve": job.autoApprove?.toInt(),
                "comment": job.comment,
                "custom_data": job.customData,
                "force": job.force?.toInt(),
                "use_preferred": job.usePreferred?.toInt(),
                "position": job.position,
                "purpose": job.purpose,
                "tone": job.tone,
                "callback_url": job.callbackURL,
                "max_chars": job.maxChars,
                "as_group": job.asGroup?.toInt()
            ]
            
            // pick up and unwrap Optional.Some values
            let sequence = "job_\(index + 1)"
            jobsDictionary[sequence] = [:]
            for (k, v) in jobDictionary {
                if let value: Any = v {
                    jobsDictionary[sequence]![k] = value
                }
            }
        }
        let body = ["jobs": jobsDictionary]
        
        let request = GengoPost(gengo: self, endpoint: "translate/jobs", body: body as [String : AnyObject])
        request.access() {result, error in
            var order: GengoOrder? = nil
            if let orderDictionary = result as? [String: AnyObject] {
                if orderDictionary["order_id"] != nil {
                    order = Gengo.toOrder(orderDictionary)
                }
            }
            callback(order, error)
        }
    }
    
    /// - parameter parameters["status"]:: GengoJobStatus
    /// - parameter parameters["after"]:: Date or Int
    /// - parameter parameters["count"]:: Int
    func getJobs(_ parameters: [String: Any] = [:], callback: @escaping ([GengoJob], GengoError?) -> ()) {
        var q: [String: AnyObject] = [:]
        if let status = parameters["status"] as? GengoJobStatus {
            q["status"] = status.rawValue as AnyObject?
        }
        if let date = parameters["after"] as? Date {
            q["timestamp_after"] = Int(date.timeIntervalSince1970) as AnyObject?
        } else if let int = parameters["after"] as? Int {
            q["timestamp_after"] = int as AnyObject?
        }
        if let count = parameters["count"] as? Int {
            q["count"] = count as AnyObject?
        }
        
        let request = GengoGet(gengo: self, endpoint: "translate/jobs", query: q)
        request.access() {result, error in
            var jobs: [GengoJob] = []
            if let unwrappedJobs = result as? [[String: AnyObject]] {
                for job in unwrappedJobs {
                    jobs.append(Gengo.toJob(job))
                }
            }
            
            callback(jobs, error)
        }
    }
    
    func getJobs(_ ids: [Int], callback: @escaping ([GengoJob], GengoError?) -> ()) {
        var stringIDs: [String] = []
        for id in ids {
            stringIDs.append(String(id))
        }
        let joinedIDs = stringIDs.joined(separator: ",")
        
        let request = GengoGet(gengo: self, endpoint: "translate/jobs/\(joinedIDs)")
        request.access() {result, error in
            var jobs: [GengoJob] = []
            if let unwrappedResult = result as? [String: AnyObject] {
                if let unwrappedJobs = unwrappedResult["jobs"] as? [[String: AnyObject]] {
                    for job in unwrappedJobs {
                        jobs.append(Gengo.toJob(job))
                    }
                }
            }
            
            callback(jobs, error)
        }
    }
}

// Job methods
extension Gengo {
    func getJob(_ id: Int, mt: GengoBool, callback: @escaping (GengoJob?, GengoError?) -> ()) {
        let query = ["pre_mt": mt.toInt()]
        let request = GengoGet(gengo: self, endpoint: "translate/job/\(id)", query: query as [String : AnyObject])
        request.access() {result, error in
            var job: GengoJob?
            if let unwrappedResult = result as? [String: AnyObject] {
                if let jobDictionary = unwrappedResult["job"] as? [String: AnyObject] {
                    job = Gengo.toJob(jobDictionary)
                }
            }
            
            callback(job, error)
        }
    }
    
    func putJob(_ id: Int, action: GengoJobAction, callback: @escaping (GengoError?) -> ()) {
        var body: [String: AnyObject] = [:]
        
        switch action {
        case .revise(let comment):
            body = ["action": "revise" as AnyObject, "comment": comment as AnyObject]
        case .approve(let feedback):
            body = ["action": "approve" as AnyObject]
            if let rating = feedback.rating {
                body["rating"] = rating as AnyObject?
            }
            if let commentForTranslator = feedback.commentForTranslator {
                body["for_translator"] = commentForTranslator as AnyObject?
            }
            if let commentForGengo = feedback.commentForGengo {
                body["for_mygengo"] = commentForGengo as AnyObject?
            }
            if let isPublic = feedback.isPublic {
                body["public"] = isPublic.toInt() as AnyObject?
            }
        case .reject(let reason, let comment, let captcha, let followUp):
            body["action"] = "reject" as AnyObject?
            body["reason"] = reason.rawValue as AnyObject?
            body["comment"] = comment as AnyObject?
            body["captcha"] = captcha as AnyObject?
            body["follow_up"] = followUp.rawValue as AnyObject?
        }
        
        let request = GengoPut(gengo: self, endpoint: "translate/job/\(id)", body: body)
        request.access() {result, error in
            callback(error)
        }
    }
    
    func deleteJob(_ id: Int, callback: @escaping (GengoError?) -> ()) {
        let request = GengoDelete(gengo: self, endpoint: "translate/job/\(id)")
        request.access() {result, error in
            callback(error)
        }
    }
    
    func getRevisions(_ jobID: Int, callback: @escaping ([GengoRevision], GengoError?) -> ()) {
        let request = GengoGet(gengo: self, endpoint: "translate/job/\(jobID)/revisions")
        request.access() {result, error in
            var revisions: [GengoRevision] = []
            if let unwrappedResult = result as? [String: AnyObject] {
                if let revisionsArray = unwrappedResult["revisions"] as? [[String: AnyObject]] {
                    for revision in revisionsArray {
                        revisions.append(Gengo.toRevision(revision))
                    }
                }
            }
            
            callback(revisions, error)
        }
    }
    
    func getRevision(_ jobID: Int, revisionID: Int, callback: @escaping (GengoRevision?, GengoError?) -> ()) {
        let request = GengoGet(gengo: self, endpoint: "translate/job/\(jobID)/revision/\(revisionID)")
        request.access() {result, error in
            var revision: GengoRevision?
            if let unwrappedResult = result as? [String: AnyObject] {
                if let revisionDictionary = unwrappedResult["revision"] as? [String: AnyObject] {
                    revision = Gengo.toRevision(revisionDictionary)
                }
            }
            
            callback(revision, error)
        }
    }
    
    func getFeedback(_ jobID: Int, callback: @escaping (GengoFeedback?, GengoError?) -> ()) {
        let request = GengoGet(gengo: self, endpoint: "translate/job/\(jobID)/feedback")
        request.access() {result, error in
            var feedback: GengoFeedback?
            if let unwrappedResult = result as? [String: AnyObject] {
                if let feedbackDictionary = unwrappedResult["feedback"] as? [String: AnyObject] {
                    feedback = GengoFeedback()
                    feedback?.rating = Gengo.toInt(feedbackDictionary["rating"])
                    feedback?.commentForTranslator = feedbackDictionary["for_translator"] as? String
                }
            }
            
            callback(feedback, error)
        }
    }
    
    func getComments(_ jobID: Int, callback: @escaping ([GengoComment], GengoError?) -> ()) {
        let request = GengoGet(gengo: self, endpoint: "translate/job/\(jobID)/comments")
        request.access() {result, error in
            var comments: [GengoComment] = []
            if let unwrappedResult = result as? [String: AnyObject] {
                if let commentsArray = unwrappedResult["thread"] as? [[String: AnyObject]] {
                    for commentDictionary in commentsArray {
                        var comment = GengoComment()
                        comment.body = commentDictionary["body"] as? String
                        if let author = commentDictionary["author"] as? String {
                            comment.author = GengoComment.Author(rawValue: author)
                        }
                        comment.createdTime = Gengo.toDate(commentDictionary["ctime"])
                        
                        comments.append(comment)
                    }
                }
            }

            callback(comments, error)
        }
    }
    
    func postComment(_ jobID: Int, comment: String, callback: @escaping (GengoError?) -> ()) {
        let body = ["body": comment]
        let request = GengoPost(gengo: self, endpoint: "translate/job/\(jobID)/comment", body: body as [String : AnyObject])
        request.access() {result, error in
            callback(error)
        }
    }
}

// Order methods
extension Gengo {
    func getOrder(_ id: Int, callback: @escaping (GengoOrder?, GengoError?) -> ()) {
        let request = GengoGet(gengo: self, endpoint: "translate/order/\(id)")
        request.access() {result, error in
            var order: GengoOrder? = nil
            if let unwrappedResult = result as? [String: AnyObject] {
                if let orderDictionary = unwrappedResult["order"] as? [String: AnyObject] {
                    order = Gengo.toOrder(orderDictionary)
                }
            }
            
            callback(order, error)
        }
    }

    func deleteOrder(_ id: Int, callback: @escaping (GengoError?) -> ()) {
        let request = GengoDelete(gengo: self, endpoint: "translate/order/\(id)")
        request.access() {result, error in
            callback(error)
        }
    }
}

// Glossary methods
extension Gengo {
    func getGlossaries(_ callback: @escaping ([GengoGlossary], GengoError?) -> ()) {
        let request = GengoGet(gengo: self, endpoint: "translate/glossary")
        request.access() {result, error in
            var glossaries: [GengoGlossary] = []
            if let glossaryArray = result as? [[String: AnyObject]] {
                for glossaryDictionary in glossaryArray {
                    glossaries.append(Gengo.toGlossary(glossaryDictionary))
                }
            }
            
            callback(glossaries, error)
        }
    }
    
    func getGlossary(_ id: Int, callback: @escaping (GengoGlossary?, GengoError?) -> ()) {
        let request = GengoGet(gengo: self, endpoint: "translate/glossary/\(id)")
        request.access() {result, error in
            var glossary: GengoGlossary?
            if let glossaryDictionary = result as? [String: AnyObject] {
                if let _ = glossaryDictionary["id"] as? Int {
                    glossary = Gengo.toGlossary(glossaryDictionary)
                }
            }

            callback(glossary, error)
        }
    }
}

// JSON to object
extension Gengo {
    fileprivate class func toLanguagePair(_ json: [String: AnyObject]) -> GengoLanguagePair? {
        let price: GengoMoney? = toMoney(json)
        
        var languagePair: GengoLanguagePair?
        if let src = json["lc_src"] as? String, let tgt = json["lc_tgt"] as? String {
            if let tierString = json["tier"] as? String {
                if let tier = GengoTier(rawValue: tierString) {
                    languagePair = GengoLanguagePair(
                        source: GengoLanguage(code: src),
                        target: GengoLanguage(code: tgt),
                        tier: tier,
                        price: price
                    )
                }
            }
        }
        
        return languagePair
    }
    
    fileprivate class func toMoney(_ json: [String: AnyObject]) -> GengoMoney? {
        var money: GengoMoney?
        
        var amount = toFloat(json["credits"])
        if amount == nil {
            amount = toFloat(json["credits_used"])
        }
        if amount == nil {
            amount = toFloat(json["total_credits"])
        }
        if amount == nil {
            return money
        }

        if let currencyString = json["currency"] as? String {
            if let currency = GengoCurrency(rawValue: currencyString) {
                money = GengoMoney(
                    amount: amount!,
                    currency: currency
                )
            }
        }
        
        return money
    }
    
    fileprivate class func toJob(_ json: [String: AnyObject]) -> GengoJob {
        var job = GengoJob()
        
        job.languagePair = toLanguagePair(json)
        job.sourceText = json["body_src"] as? String
        job.autoApprove = GengoBool(value: json["auto_approve"])
        job.credit = toMoney(json)
        job.eta = toInt(json["eta"])
        job.id = toInt(json["job_id"])
        job.order = GengoOrder()
        job.order!.id = toInt(json["order_id"])
        job.slug = json["slug"] as? String
        if let status = json["status"] as? String {
            job.status = GengoJobStatus(rawValue: status)
        }
        job.unitCount = toInt(json["unit_count"])
        job.createdTime = toDate(json["ctime"])
        
        return job
    }

    fileprivate class func toRevision(_ json: [String: AnyObject]) -> GengoRevision {
        var revision = GengoRevision()

        revision.id = Gengo.toInt(json["rev_id"])
        if let body = json["body_tgt"] as? String {
            revision.body = body
        }
        revision.createdTime = Gengo.toDate(json["ctime"])
        
        return revision
    }
    
    fileprivate class func toOrder(_ json: [String: AnyObject]) -> GengoOrder {
        var order = GengoOrder()
        order.id = toInt(json["order_id"])
        order.credit = toMoney(json)
        if let count = toInt(json["job_count"]) {
            order.jobCount = count
        } else if let count = toInt(json["total_jobs"]) {
            order.jobCount = count
        }
        order.asGroup = GengoBool(value: json["as_group"])
        order.units = toInt(json["total_units"])

        return order
    }
    
    fileprivate class func toAccount(_ json: [String: AnyObject]) -> GengoAccount {
        var account = GengoAccount()
        
        account.creditSpent = Gengo.toFloat(json["credits_spent"])
        account.creditPresent = Gengo.toFloat(json["credits"])
        if let currency = json["currency"] as? String {
            account.currency = GengoCurrency(rawValue: currency)
        }
        account.since = Gengo.toDate(json["user_since"])
        
        return account
    }
    
    fileprivate class func toGlossary(_ json: [String: AnyObject]) -> GengoGlossary {
        var glossary = GengoGlossary()
        
        glossary.id = Gengo.toInt(json["id"])
        if let source = json["source_language_code"] as? String {
            glossary.sourceLanguage = GengoLanguage(code: source)
        }
        var targets: [GengoLanguage] = []
        if let targetArray = json["target_languages"] as? [[AnyObject]] {
            for target in targetArray {
                if target.count >= 2 {
                    if let code = target[1] as? String {
                        targets.append(GengoLanguage(code: code))
                    }
                }
            }
        }
        glossary.targetLanguages = targets
        glossary.isPublic = GengoBool(value: json["is_public"])
        glossary.unitCount = Gengo.toInt(json["unit_count"])
        glossary.description = json["description"] as? String
        glossary.title = json["title"] as? String
        glossary.status = Gengo.toInt(json["status"])
        glossary.createdTime = Gengo.toDate(json["ctime"])
        
        return glossary
    }
}

// enums and structs

public enum GengoLanguageUnitType: String {
    case Word = "word"
    case Character = "character"
}

public struct GengoLanguage: CustomStringConvertible {
    let code: String
    let name: String?
    let localizedName: String?
    let unitType: GengoLanguageUnitType?
    
    init(code: String, name: String? = nil, localizedName: String? = nil, unitType: GengoLanguageUnitType? = nil) {
        self.code = code
        self.name = name
        self.localizedName = localizedName
        self.unitType = unitType
    }
    
    public var description: String {
        return (name == nil) ? code : name!
    }
}

public enum GengoTier: String, CustomStringConvertible {
    case Standard = "standard"
    case Pro = "pro"
    case Ultra = "ultra"
    
    public var description: String {
        return rawValue
    }
}

public enum GengoCurrency: String, CustomStringConvertible {
    case USD = "USD"
    case EUR = "EUR"
    case JPY = "JPY"
    case GBP = "GBP"
    
    public var description: String {
        return rawValue
    }
}

public struct GengoMoney: CustomStringConvertible {
    let amount: Float
    let currency: GengoCurrency
    
    init(amount: Float, currency: GengoCurrency) {
        self.amount = amount
        self.currency = currency
    }
    
    public var description: String {
        return "\(currency)\(amount)"
    }
}

public struct GengoLanguagePair: CustomStringConvertible {
    let source: GengoLanguage
    let target: GengoLanguage
    let tier: GengoTier
    let price: GengoMoney?
    
    init(source: GengoLanguage, target: GengoLanguage, tier: GengoTier, price: GengoMoney? = nil) {
        self.source = source
        self.target = target
        self.tier = tier
        self.price = price
    }
    
    public var description: String {
        return "\(tier): \(source) -> \(target)"
    }
}

public enum GengoJobType: String {
    case Text = "text"
    case File = "file"
}

public enum GengoBool {
    case `true`, `false`
    
    init(value: Any?) {
        if let i = Gengo.toInt(value) {
            self = (i >= 1) ? .true : .false
        } else {
            self = .false
        }
    }
    
    public var boolValue: Bool {
        return self == .true
    }

    func toInt() -> Int {
        return (self == .true) ? 1 : 0
    }
}

func ==(left: Bool, right: GengoBool) -> Bool {
    return left == right.boolValue
}

func ==(left: GengoBool, right: Bool) -> Bool {
    return left.boolValue == right
}

func !=(left: Bool, right: GengoBool) -> Bool {
    return !(left == right)
}

func !=(left: GengoBool, right: Bool) -> Bool {
    return !(left == right)
}

extension Bool {
    init(_ gengoBool: GengoBool) {
        self = gengoBool.boolValue
    }
}

public struct GengoFile {
    let data: Data
    let name: String
    let mimeType: String
    
    init(path: String) {
        self.init(data: try! Data(contentsOf: URL(fileURLWithPath: path)), name: (path as NSString).lastPathComponent)
    }
    
    /// - parameter name:: file name as if returned by String#lastPathComponent
    init(data: Data, name: String) {
        self.data = data
        self.name = name
        
        var mime =  "application/octet-stream";
        if let identifier = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (name as NSString).pathExtension as CFString, nil)?.takeRetainedValue() {
            if let m = UTTypeCopyPreferredTagWithClass(identifier, kUTTagClassMIMEType)?.takeRetainedValue() as String? {
                mime = m
            }
        }
        self.mimeType = mime
    }
}

public enum GengoJobStatus: String {
    case Queued = "queued"
    case Available = "available"
    case Pending = "pending"
    case Reviewable = "reviewable"
    case Approved = "approved"
    case Revising = "revising"
    case Rejected = "rejected"
    case Canceled = "canceled"
}

public struct GengoJob: CustomStringConvertible {
    var languagePair: GengoLanguagePair?
    var type: GengoJobType? = GengoJobType.Text
    var sourceText: String? {
        didSet {
            if let text = sourceText, slug == nil {
                if text.count <= 15 {
                    slug = text
                } else {
                    slug = text.prefix(15) + "..."
                }
            }
        }
    }
    var sourceFile: GengoFile? {
        didSet {
            type = (sourceFile == nil) ? nil : GengoJobType.File
        }
    }
    var slug: String?
    
    var autoApprove: GengoBool?
    /// a string to link with a file uploaded by getQuoteFile()
    var identifier: String?
    var comment: String?
    var customData: String?
    var force: GengoBool?
    var usePreferred: GengoBool?
    //    var glossaryID: String? // TODO
    var position: String?
    var purpose: String?
    var tone: String?
    var callbackURL: String?
    var maxChars: Int?
    var asGroup: GengoBool?
    
    var id: Int?
    var order: GengoOrder?
    var targetText: String?
    var credit: GengoMoney?
    var eta: Int?
    var unitCount: Int?
    var status: GengoJobStatus?
    var createdTime: Date?
    
    init() {}
    
    public var description: String {
        return "GengoJob" + (languagePair == nil ? "" : "(\(languagePair!))")
    }
}

public enum GengoJobAction {
    case revise(String)
    case approve(GengoFeedback)
    case reject(RejectData.Reason, String, String, RejectData.FollowUp)
    
    public struct RejectData {
        public enum Reason: String {
            case Quality = "quality"
            case Incomplete = "incomplete"
            case Other = "other"
        }
        
        public enum FollowUp: String {
            case Requeue = "requeue"
            case Cancel = "cancel"
        }
    }
}

public struct GengoRevision {
    var id: Int?
    var body: String?
    var createdTime: Date?
    
    init() {}
}

public struct GengoFeedback {
    var rating: Int?
    var commentForTranslator: String?
    var commentForGengo: String?
    var isPublic: GengoBool?

    init() {}
}

public struct GengoComment {
    var body: String?
    var author: Author?
    var createdTime: Date?
    
    public enum Author: String {
        case Customer = "customer"
        case Worker = "worker"
    }
    
    init() {}
}

public struct GengoOrder: CustomStringConvertible {
    var id: Int?
    var credit: GengoMoney?
    var jobCount: Int?
    var jobs: [GengoJob]?
    var asGroup: GengoBool?
    var units: Int?
    
    init() {}
    
    public var description: String {
        return "GengoOrder" + (id == nil ? "" : "#\(id!)")
    }
}

public struct GengoAccount {
    var creditSpent: Float?
    var creditPresent: Float?
    var currency: GengoCurrency?
    var since: Date?
    
    init() {}
}

public struct GengoTranslator {
    var id: Int?
    var jobCount: Int?
    var languagePair: GengoLanguagePair?
    
    init() {}
}

public struct GengoGlossary {
    var id: Int?
    var sourceLanguage: GengoLanguage?
    var targetLanguages: [GengoLanguage]?
    var isPublic: GengoBool?
    var unitCount: Int?
    var description: String?
    var title: String?
    var status: Int?
    var createdTime: Date?
    
    init() {}
}
