//
//  VideoCollectionViewController.swift
//  MacMagazine
//
//  Created by Cassio Rossi on 12/04/2019.
//  Copyright © 2019 MacMagazine. All rights reserved.
//

import CoreData
import UIKit

class VideoCollectionViewController: UICollectionViewController {

	// MARK: - Properties -

	@IBOutlet private weak var logoView: UIView!
	@IBOutlet private weak var favorite: UIBarButtonItem!
	@IBOutlet private weak var spin: UIActivityIndicatorView!

	var isSearching = false
	var videos: [JSONVideo]?

	var isLoading = true
	var pageToken: String = ""
	var lastContentOffset = CGPoint()
	var direction: Direction = .up

	var showFavorites = false
	let favoritePredicate = NSPredicate(format: "favorite == %@", NSNumber(value: true))

	fileprivate let managedObjectContext = CoreDataStack.shared.viewContext

	fileprivate lazy var fetchedResultsController: NSFetchedResultsController<Video> = {
		let fetchRequest: NSFetchRequest<Video> = Video.fetchRequest()

		let sortDescriptor = NSSortDescriptor(key: "pubDate", ascending: false)
		fetchRequest.sortDescriptors = [sortDescriptor]

		// Initialize Fetched Results Controller
		let controller = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: managedObjectContext, sectionNameKeyPath: nil, cacheName: nil)
		controller.delegate = self

		do {
			try controller.performFetch()
		} catch {
			let fetchError = error as NSError
			print("\(fetchError), \(fetchError.userInfo)")
		}

		return controller
	}()

	private var searchController: UISearchController?

	// MARK: - View lifecycle -

	override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
		navigationItem.titleView = logoView
		navigationItem.title = nil

		searchController = UISearchController(searchResultsController: nil)
		searchController?.searchBar.autocapitalizationType = .none
		searchController?.searchBar.delegate = self
		searchController?.searchBar.placeholder = "Buscar nos vídeos..."
		searchController?.hidesNavigationBarDuringPresentation = true
		self.definesPresentationContext = true

		pageToken = ""
		getVideos()
	}

	override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
		super.viewWillTransition(to: size, with: coordinator)

		guard let flowLayout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout else {
			return
		}
		flowLayout.invalidateLayout()
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		if fetchedResultsController.fetchedObjects?.isEmpty ?? true &&
			!isLoading {
			pageToken = ""
			isLoading = true
			getVideos()
		}
	}

	// MARK: - Local methods -

	fileprivate func getVideos() {
		navigationItem.titleView = self.spin
		direction = .up

		API().getVideos(using: pageToken) { videos in
			guard let videos = videos,
				let items = videos.items
				else {
					return
			}
			self.pageToken = videos.nextPageToken ?? ""

			let videoIds: [String] = items.compactMap {
				return $0.snippet?.resourceId?.videoId
			}
			API().getVideosStatistics(videoIds) { statistics in
				guard let stats = statistics?.items else {
					return
				}
				DispatchQueue.main.async {
					self.isLoading = false
					CoreDataStack.shared.save(playlist: videos, statistics: stats)
					self.collectionView.reloadData()
					self.navigationItem.titleView = self.logoView
				}
			}
		}
	}

	fileprivate func search(_ text: String) {
		videos = nil

		API().searchVideos(text) { videos in
			guard let videos = videos,
				let items = videos.items
				else {
					return
			}

			let videoIds: [String] = items.compactMap {
				return $0.id?.videoId
			}
			API().getVideosStatistics(videoIds) { statistics in
				guard let stats = statistics?.items else {
					return
				}

				self.videos = items.compactMap {
					guard let title = $0.snippet?.title,
						let videoId = $0.id?.videoId
						else {
							return nil
					}

					var likes = ""
					var views = ""
					let stat = stats.filter {
						$0.id == videoId
					}
					if !stat.isEmpty {
						views = stat[0].statistics?.viewCount ?? ""
						likes = stat[0].statistics?.likeCount ?? ""
					}

					let artworkURL = $0.snippet?.thumbnails?.maxres?.url ?? $0.snippet?.thumbnails?.high?.url ?? ""

					return JSONVideo(title: title, videoId: videoId, pubDate: $0.snippet?.publishedAt ?? "", artworkURL: artworkURL, views: views, likes: likes)
				}

				DispatchQueue.main.async {
					self.collectionView.reloadData()
					self.searchController?.searchBar.resignFirstResponder()
					self.navigationItem.searchController = nil
					self.searchController?.isActive = false
				}
			}
		}
	}

	// MARK: - Actions methods -

	@IBAction private func search(_ sender: Any) {
		navigationItem.searchController = searchController
		searchController?.searchBar.becomeFirstResponder()
	}

	@IBAction private func showFavorites(_ sender: Any) {
		showFavorites = !showFavorites
		if showFavorites {
			fetchedResultsController.fetchRequest.predicate = favoritePredicate

			self.navigationItem.titleView = nil
			self.navigationItem.title = "Favoritos"
			favorite.image = UIImage(named: "fav_on")
		} else {
			fetchedResultsController.fetchRequest.predicate = nil

			self.navigationItem.titleView = logoView
			self.navigationItem.title = nil
			favorite.image = UIImage(named: "fav_off")
		}

		do {
			try fetchedResultsController.performFetch()
			UIView.transition(with: collectionView, duration: 0.4, options: showFavorites ? .transitionFlipFromRight : .transitionFlipFromLeft, animations: {
				self.collectionView.reloadData()
			})
		} catch {
			logE(error.localizedDescription)
		}
	}

}

// MARK: - Scroll detection -

extension VideoCollectionViewController {
	override func scrollViewDidScroll(_ scrollView: UIScrollView) {
		let offset = scrollView.contentOffset
		direction = offset.y > lastContentOffset.y && offset.y > 100 ? .down : .up
		lastContentOffset = offset

		// Pull to Refresh
		if offset.y < -100 && navigationItem.titleView == logoView {
			pageToken = ""
			getVideos()
		}
	}
}

// MARK: - UICollectionViewDataSource -

extension VideoCollectionViewController {

	func showNotFound() {
		var message = isLoading ? "Carregando..." : "Você ainda não favoritou nenhum vídeo."
		if isSearching {
			message = "Nenhum resultado encontrado"
			guard let _ = videos else {
				let spin = UIActivityIndicatorView(style: .whiteLarge)
				spin.startAnimating()
				collectionView.backgroundView = spin

				return
			}
		}

		let notFound = UILabel(frame: CGRect(x: 0, y: 0, width: collectionView.bounds.size.width, height: collectionView.bounds.size.height))
		notFound.text = message
		notFound.textColor = Settings().isDarkMode() ? .white : .black
		notFound.textAlignment = .center
		collectionView.backgroundView = notFound
	}

	override func numberOfSections(in collectionView: UICollectionView) -> Int {
		if isSearching {
			return 1
		} else {
			guard let sections = fetchedResultsController.sections else {
				showNotFound()
				return 0
			}
			collectionView.backgroundView = nil
			return sections.count
		}
	}

	override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		if isSearching {
			if videos?.isEmpty ?? true {
				showNotFound()
			}
			return videos?.count ?? 0
		} else {
			guard let sections = fetchedResultsController.sections else {
				showNotFound()
				return 0
			}
			let sectionInfo = sections[section]
			let items = sectionInfo.numberOfObjects
			if items == 0 {
				showNotFound()
			}
			return items
		}
	}

	override func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
		if direction == .down &&
			indexPath.item % 14 == 0 &&
			navigationItem.titleView == logoView &&
			!isSearching {
			self.getVideos()
		}
	}

	override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "video", for: indexPath) as? VideosCollectionViewCell else {
			fatalError("Unexpected Index Path")
		}

		// Configure the cell
		if isSearching {
			guard let videos = videos else {
				return cell
			}
			let object = videos[indexPath.item]
			cell.configureVideo(with: object)
		} else {
			let object = fetchedResultsController.object(at: indexPath)
			cell.configureVideo(with: object)
		}

		return cell
	}

	// MARK: - UICollectionViewDelegate -

	override func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
		return false
	}

}

// MARK: - FetchedResultsController Delegate -

extension VideoCollectionViewController: NSFetchedResultsControllerDelegate {

	func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {}

	private func controller(controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeSection sectionInfo: NSFetchedResultsSectionInfo, atIndex sectionIndex: Int, forChangeType type: NSFetchedResultsChangeType) {

		switch type {
		case .insert:
			self.collectionView?.insertSections(NSIndexSet(index: sectionIndex) as IndexSet)
		case .update:
			self.collectionView?.reloadSections(NSIndexSet(index: sectionIndex) as IndexSet)
		case .delete:
			self.collectionView?.deleteSections(NSIndexSet(index: sectionIndex) as IndexSet)
		case .move:
			break
		@unknown default:
			break
		}
	}

	private func controller(controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeObject anObject: Any, atIndexPath indexPath: IndexPath?, forChangeType type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {

		guard let newIndexPath = newIndexPath,
			let indexPath = indexPath
			else {
				return
		}

		switch type {
		case .insert:
			self.collectionView?.insertItems(at: [newIndexPath])
		case .update:
			self.collectionView?.reloadItems(at: [indexPath])
		case .delete:
			self.collectionView?.deleteItems(at: [indexPath])
		case .move:
			self.collectionView?.moveItem(at: indexPath, to: newIndexPath)
		@unknown default:
			break
		}
	}

	func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
		DispatchQueue.main.async {
			self.collectionView?.reloadData()
		}
	}

}

extension VideoCollectionViewController: UICollectionViewDelegateFlowLayout {
	func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {

		let screen = UIScreen.main.bounds.size
		// YouTube thumbnail images size (16:9)
		let ratio: CGFloat = 1.778

		// Number of items per column based on device screen size
		let divider = screen.width < 600 ? 1 : screen.width > 768 ? 3 : 2

		// margin of 20px
		let width = (screen.width - CGFloat((divider + 1) * 20)) / CGFloat(divider)

		// image has a bottom margin of 120px to accomodate labels and buttons
		// 10px distance betwwen thumb and labels
		// 80px for labels
		// 25px for fav and share buttons
		// 5px bottom margin
		let height = (width / ratio) + 120

		return CGSize(width: width, height: height)
	}
}

// MARK: - UISearchBarDelegate -

extension VideoCollectionViewController: UISearchBarDelegate {
	func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
		guard let text = searchBar.text else {
			return
		}
		isSearching = true
		self.collectionView.reloadData()
		search(text)
	}

	func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
		isSearching = false
		searchBar.resignFirstResponder()
		navigationItem.searchController = nil
		self.collectionView.reloadData()
	}
}