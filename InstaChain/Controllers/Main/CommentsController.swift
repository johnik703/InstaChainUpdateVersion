//
//  CommentsController.swift
//  InstaChain
//
//  Created by John Nik on 2/4/18.
//  Copyright © 2018 johnik703. All rights reserved.
//

import UIKit
import SVProgressHUD
import ObjectMapper
import IQKeyboardManager

enum WritingStatus {
    case comment
    case reply
}

class CommentsController: UICollectionViewController {
    
    let cellId = "cellId"
    let headerCellId = "headerCellId"
    
    var writingStatus: WritingStatus = .comment
    var permlink: String?
    var author: String?
    
    var commentAuthor: String?
    var commentPermlink: String?
    
    var comments = [Comment]()
    let data = CurrentSession.getI().localData.userBaseInfo
    
    var isExistReplies = false
    var sendRepliesCount = 0
    var recievedRepliesCount = 0
    
    var sendStatesCount = 0
    var recievedStatesCount = 0
    
    lazy var cancelReplyButton: UIBarButtonItem = {
        let cancelButton = UIBarButtonItem(title: "Cancel reply", style: .plain, target: self, action: #selector(handleCancelButton))
        
        return cancelButton
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupViews()
        
        fetchComments()
    }
    
    
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        IQKeyboardManager.shared().isEnabled = false
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        IQKeyboardManager.shared().isEnabled = true
    }
    
    lazy var containerView: CommentInputAccessoryView = {
        
        let frame = CGRect(x: 0, y: 0, width: view.frame.width, height: 50)
        let commentInputAccessoryView = CommentInputAccessoryView(frame: frame)
        commentInputAccessoryView.delegate = self
        
        return commentInputAccessoryView
    }()
    
    override var inputAccessoryView: UIView? {
        get {
            return containerView
        }
    }
    
    override var canBecomeFirstResponder: Bool {
        return true
    }
}

extension CommentsController {
    
    fileprivate func fetchComments() {
        
        guard let author = author, let permlink = permlink else { return }
        
        getDisscussionComment(author: author, permlink: permlink)
    }
    
    func getDisscussionComment(author: String, permlink: String) {
        
        SVProgressHUD.show()
        
        AppServerRequests.getCommentsOfPost(author: author, permlink: permlink) {
            [weak self] (r) in
            
            guard let strongSelf = self else {
                SVProgressHUD.dismiss()
                return }
            
            switch r {
                
            case .success (let d):
                if let data = d as? [PostData] {
                    
                    strongSelf.comments.removeAll()
                    
                    if data.count == 0 {
                        DispatchQueue.main.async {
                            SVProgressHUD.dismiss()
                            return
                        }
                    }
                    
                    strongSelf.sendStatesCount = data.count
                    
                    for i in 0 ..< data.count {
                        let datum = data[i]
                        let comment = Comment(comment: datum, replies: [])
                        strongSelf.comments.append(comment)
                        
                        if datum.children > 0 {
                            strongSelf.isExistReplies = true
                            strongSelf.sendRepliesCount += 1
                        }
                    }
                    
                    for i in 0 ..< data.count {
                        let datum = data[i]
                        strongSelf.getDiscussionState(parentPermlink: permlink, author: datum.author, permlink: datum.permlink, index: i)
                    }
                    
                }
                break
            default:
                break
                
            }
        }
    }
    
    func getDiscussionState(parentPermlink: String, author: String, permlink: String, index: Int) {
        
        let urlString = String(format: ServerUrls.getState, parentPermlink, author, permlink)
        
        guard let urlStr = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let url = URL(string: urlStr) else {
                return
        }
        
        URLSession.shared.dataTask(with: url) { (data, response, error) in
            
            self.recievedStatesCount += 1
            
            if let error = error {
                print(error)
                self.showErrorMessage(message: AlertMessages.somethingWrong.rawValue)
                return
            }
            
            guard let data = data else { return }
            
            do {
                
                guard let json = try JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String: Any] else { return }
                
                guard let content = json["content"] as? [String: Any] else { return }
                guard let commentData = content["\(author)/\(permlink)"] as? [String: Any] else { return }
                guard let activeVotes = commentData["active_votes"] as? [[String: Any]] else { return }
                
                var votes = [ActiveVoterData]()
                
                for acitveVote in activeVotes {
                    if let vote = ActiveVoterData(JSON: acitveVote) {
                        votes.append(vote)
                    }
                    
                }
                
                self.comments[index].comment.activeVotes = votes
                
                if self.sendStatesCount == self.recievedStatesCount {
                    
                    if !self.isExistReplies {
                        DispatchQueue.main.async {
                            SVProgressHUD.dismiss()
                            self.reloadCollectionView()
                            
                        }
                    } else {
                        for i in 0 ..< self.comments.count {
                            let datum = self.comments[i].comment
                            if datum.children > 0 {
                                let author = datum.author
                                let permlink = datum.permlink
                                self.getDisscussionCommentReplies(author: author, permlink: permlink, index: i)
                            }
                        }
                    }
                }
                
            } catch let jsonErr {
                print("Error serializing error: ", jsonErr)
            }
            
        }.resume()
        
    }
    
    private func reloadCollectionView() {
        self.isExistReplies = false
        self.sendRepliesCount = 0
        self.recievedRepliesCount = 0
        self.sendStatesCount = 0
        self.recievedStatesCount = 0
        self.containerView.clearCommentTextField()
        self.comments = self.comments.reversed()
        self.collectionView?.reloadData()
    }
    
    func getDisscussionCommentReplies(author: String, permlink: String, index: Int) {
        
        AppServerRequests.getCommentsOfPost(author: author, permlink: permlink) {
            [weak self] (r) in
            
            guard let strongSelf = self else {
                SVProgressHUD.dismiss()
                return }
            strongSelf.recievedRepliesCount += 1
            switch r {
                
            case .success (let d):
                if let data = d as? [PostData] {
                    
                    strongSelf.comments[index].replies = data.reversed()
                    
                    if strongSelf.recievedRepliesCount == strongSelf.sendRepliesCount {
                        DispatchQueue.main.async {
                            SVProgressHUD.dismiss()
                            strongSelf.reloadCollectionView()
                            
                        }
                    }
                }
                break
            default:
                break
                
            }
        }
    }
}

extension CommentsController: CommentInputAccessoryViewDelegate {
    func didSubmit(for comment: String) {
        
        let title = String.random().lowercased()
        
        if self.writingStatus == .comment {
            if let permlink = self.permlink, let name = CurrentSession.getI().localData.userBaseInfo?.name, let wif = CurrentSession.getI().localData.privWif?.active, let parentPermlink = self.permlink, let parentAuthor = self.author {
                self.commnentOnPost(title: title, permlink: "re-" + permlink + "-" + title, body: comment, url: [""], author: name, tag: [""], wif: wif, parentPermlink: parentPermlink, parentAuthor: parentAuthor)
                
                
            }
        } else {
            if let permlink = self.commentPermlink, let name = CurrentSession.getI().localData.userBaseInfo?.name, let wif = CurrentSession.getI().localData.privWif?.active, let parentPermlink = self.commentPermlink, let parentAuthor = self.commentAuthor {
                self.commnentOnPost(title: title, permlink: "re-" + permlink + "-" + title, body: comment, url: [""], author: name, tag: [""], wif: wif, parentPermlink: parentPermlink, parentAuthor: parentAuthor)
                
                
            }
        }
        
        
    }
    
    fileprivate func checkPrivateKeyType() -> Bool {
        
        guard let privateKeyType = UserDefaults.standard.getPrivateKeyType() else { return false }
        
        if privateKeyType == PrivateKeyType.memo.rawValue {
            return false
        } else {
            return true
        }
    }
    
    fileprivate func getPrivateKey() -> String? {
        guard let privateKeyType = UserDefaults.standard.getPrivateKeyType() else { return nil }
        if privateKeyType == PrivateKeyType.owner.rawValue {
            guard let key = CurrentSession.getI().localData.privWif?.owner else { return nil }
            return key
        } else if privateKeyType == PrivateKeyType.posting.rawValue {
            guard let key = CurrentSession.getI().localData.privWif?.posting else { return nil }
            return key
        } else if privateKeyType == PrivateKeyType.active.rawValue {
            guard let key = CurrentSession.getI().localData.privWif?.active else { return nil }
            return key
        }
        return nil
    }
    
    func commnentOnPost(title: String, permlink: String,body: String, url: [String], author: String, tag: [String], wif: String, parentPermlink: String, parentAuthor: String) {
        
        guard checkPrivateKeyType() else {
            self.showJHTAlerttOkayWithIcon(message: AlertMessages.invalidPermission.rawValue)
            return
        }
        guard let key = self.getPrivateKey() else {
            self.showJHTAlerttOkayWithIcon(message: AlertMessages.invalidPermission.rawValue)
            return }
        
        SVProgressHUD.show()
        
        let headers = [
            "content-type": "application/json",
            ]
        let parameters = [
            "parent_author": parentAuthor,
            "parent_permlink": parentPermlink,
            "author": author,
            "permlink": permlink,
            "title": title,
            "body": body,
            "json_metadata": [
                "tags": [],
                "users": [],
                "links": [],
                "image": [],
                "format": "html",
                "app": "instachain_mobile/0.1"
            ],
            "wif": key
            ] as [String : Any]
        
        do {
            
            let postData = try JSONSerialization.data(withJSONObject: parameters, options: [])
            
            let request = NSMutableURLRequest(url: NSURL(string: ServerUrls.postComment)! as URL,
                                              cachePolicy: .useProtocolCachePolicy,
                                              timeoutInterval: 10.0)
            request.httpMethod = "POST"
            request.allHTTPHeaderFields = headers
            request.httpBody = postData as Data
            
            let session = URLSession.shared
            let dataTask = session.dataTask(with: request as URLRequest, completionHandler: { (data, response, error) -> Void in
                if (error != nil) {
                    SVProgressHUD.dismiss()
                    print(error)
                } else {
                    
                    _ = response as? HTTPURLResponse
                    let responseString = String(data: data!, encoding: .utf8)
                    let commentsData = Mapper<CommentResponseData>().map(JSONString: responseString!)
                    //print(responseString)
                    print(commentsData?.blockNum)
                    print("responseString = \(String(describing: responseString))")
                    
                    print(commentsData?.blockNum)
                    if let operations = commentsData?.operationData as? Array<Any> {
                        DispatchQueue.main.async {
                            for items in operations {
                                if let operation = items as? Array<Any> {
                                    for items in operation {
                                        if let item = items as? String{
                                            print(item)
                                        }else {
                                            if let item = items as? CommentResponseData {
                                                print(item.id)
                                                
                                            }
                                        }
                                        
                                    }
                                }
                            }
                            if let author = self.author, let permlink = self.permlink {
                                self.getDisscussionComment(author: author, permlink: permlink)
                                
                            }
                            
                        }
                    } else {
                        if responseString?.range(of: "You may only comment once every 20 seconds.") != nil {
                            self.showErrorMessage(message: "You may only comment once every 20 seconds.")
                        } else {
                            self.showErrorMessage(message: AlertMessages.somethingWrong.rawValue)
                            self.showJHTAlerttOkayWithIcon(message: AlertMessages.somethingWrong.rawValue)
                        }
                    }
                }
                
            })
            
            dataTask.resume()
        }
        catch {
            
        }
        
    }
    
    fileprivate func showErrorMessage(message: String) {
        DispatchQueue.main.async {
            SVProgressHUD.dismiss()
            self.showJHTAlerttOkayWithIcon(message: message)
        }
    }
}

extension CommentsController {
    
    func handleGoingProfileController(username: String) {
        
        let profileController = ProfileController()
        profileController.profileName = username
        if CurrentSession.getI().localData.userBaseInfo?.name != username {
            profileController.isLookOtherProfile = true
        } else {
            return
        }
        
        let image = UIImage(named: AssetName.leftArrow.rawValue)
        let backButton = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(profileController.dismissController))
        profileController.navigationItem.leftBarButtonItem = backButton
        profileController.navigationItem.title = "Profile"
        navigationController?.pushViewController(profileController, animated: true)
    }
}

extension CommentsController: UICollectionViewDelegateFlowLayout {
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return comments[section].replies.count
    }
    
    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        return comments.count
    }
    
    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: cellId, for: indexPath) as! CommentReplyCell
        cell.commentController = self
        let comment = comments[indexPath.section].replies[indexPath.item]
        cell.comment = comment
        
        cell.setNeedsDisplay()
        
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        
        let frame = CGRect(x: 0, y: 0, width: view.frame.width, height: 50)
        let dummyCell = CommentReplyCell(frame: frame)
        dummyCell.comment = comments[indexPath.section].replies[indexPath.item]
        dummyCell.layoutIfNeeded()
        
        let targetSize = CGSize(width: view.frame.width - 56, height: 1000)
        let estimatedSize = dummyCell.systemLayoutSizeFitting(targetSize)
        
        let height = max(40 + 8 + 8, estimatedSize.height)
        return CGSize(width: view.frame.width, height: height)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return 0
    }
    
    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        
        let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: headerCellId, for: indexPath) as! CommentCell
        header.comment = comments[indexPath.section].comment
        header.commentController = self
        
        header.setNeedsDisplay()
        
        return header
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        
        let frame = CGRect(x: 0, y: 0, width: view.frame.width, height: 50)
        let dummyCell = CommentCell(frame: frame)
        dummyCell.comment = comments[section].comment
        dummyCell.layoutIfNeeded()
        
        let targetSize = CGSize(width: view.frame.width, height: 1000)
        let estimatedSize = dummyCell.systemLayoutSizeFitting(targetSize)
        
        let height = max(40 + 8 + 8, estimatedSize.height)
        return CGSize(width: view.frame.width, height: height)
    }
}

extension CommentsController {
    
    @objc fileprivate func handleCancelButton() {
        
        cancelReplyButton.isEnabled = false
        self.writingStatus = .comment
        self.containerView.commentTextView.placeholderLabel.text = "Write a comment"
    }
}

extension CommentsController {
    
    fileprivate func setupViews() {
        setupNavBar()
        setupCollectionView()
    }
    
    private func setupNavBar() {
        
        navigationItem.title = "Comments"
        
        
        navigationItem.rightBarButtonItem = cancelReplyButton
        
        cancelReplyButton.isEnabled = false
    }
    
    private func setupCollectionView() {
        
        
        collectionView?.alwaysBounceVertical = true
        collectionView?.isScrollEnabled = true
        
        collectionView?.keyboardDismissMode = .interactive
        
        collectionView?.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: -50, right: 0)
        collectionView?.scrollIndicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: -50, right: 0)
        collectionView?.backgroundColor = DarkModeManager.getViewBackgroundColor()
        collectionView?.register(CommentReplyCell.self, forCellWithReuseIdentifier: cellId)
        collectionView?.register(CommentCell.self, forSupplementaryViewOfKind: UICollectionElementKindSectionHeader, withReuseIdentifier: headerCellId)
    }
    
}

