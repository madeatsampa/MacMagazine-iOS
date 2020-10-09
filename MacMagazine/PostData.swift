//
//  PostData.swift
//  MacMagazine
//
//  Created by Cassio Rossi on 08/04/2019.
//  Copyright © 2019 MacMagazine. All rights reserved.
//

import Foundation

struct PostData: Codable {
	var title: String?
	var link: String?
	var thumbnail: String?
	var favorito: Bool = false
	var pubDate: String?
	var excerpt: String?
    var postId: String?
    var shortURL: String?

    init(title: String?,
         link: String?,
         thumbnail: String?,
         favorito: Bool,
         pubDate: String? = "",
         excerpt: String? = "",
         postId: String? = "",
         shortURL: String? = "") {

		self.title = title
		self.link = link
		self.thumbnail = thumbnail
		self.favorito = favorito
		self.pubDate = pubDate
		self.excerpt = excerpt
        self.postId = postId
        self.shortURL = shortURL
	}
}
