//
//  MachinePageViewController.swift
//  RentnKing
//
//  Created by Jigar Khatri on 19/03/25.
//

import UIKit

class MachinePageViewController: UIPageViewController {
    weak var tutorialDelegate: MachinePageViewControllerDelegate?
    var strID : String = ""
    var arrRentalReady : [RentalReadyModel] = []
    var objRentalReadyData : MachineModel!

    fileprivate(set) lazy var orderedViewControllers: [UIViewController] = {
      // The view controllers will be shown in this order
        return [self.newColoredViewController("NotesVC"), self.newColoredViewController("RantalReadyVC"), self.newColoredViewController("ChecklistVC"), self.newColoredViewController("PartsListVC"), self.newColoredViewController("ServiceVC")]
    }()
    
    fileprivate func newColoredViewController(_ nameVC: String) -> UIViewController {
        let vc = UIStoryboard(name: GlobalMainConstants.EQUIPMENT_MODEL, bundle: nil) .
        instantiateViewController(withIdentifier: nameVC)
        vc.title = "96"
    
        return vc
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        dataSource = self
        delegate = self
        
//        if let initialViewController = orderedViewControllers.first {
//
//        }
        scrollToViewController(orderedViewControllers[1])
        
        tutorialDelegate?.MachinePageViewController(self,
                                                 didUpdatePageCount: orderedViewControllers.count)
        
    }
    
    
    /**
     Scrolls to the next view controller.
     */
    func scrollToNextViewController() {
      if let visibleViewController = viewControllers?.first,
        let nextViewController = pageViewController(self,
                                                    viewControllerAfter: visibleViewController) {
        scrollToViewController(nextViewController)
      }
    }
    func scrollToPreviewsViewController(indexCall : Int) {
      self.scrollToViewController(index : indexCall)
    }
    func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
      //        pageControl.setSelectedSegmentIndex((pages as NSArray).index(of: pendingViewControllers.last), animated: true)
    }
    
    
    /**
     Scrolls to the view controller at the given index. Automatically calculates
     the direction.
     
     - parameter newIndex: the new index to scroll to
     */
    
    func scrollToViewController(index newIndex: Int) {
      if let firstViewController = viewControllers?.first,
          let currentIndex = orderedViewControllers.firstIndex(of: firstViewController) {
          let direction: UIPageViewController.NavigationDirection = newIndex >= currentIndex ? .forward : .reverse
        let nextViewController = orderedViewControllers[newIndex]
        scrollToViewController(nextViewController, direction: direction)
      }
      
      if let firstViewController = viewControllers?.last,
          let currentIndex = orderedViewControllers.firstIndex(of: firstViewController) {
          let direction: UIPageViewController.NavigationDirection = newIndex >= currentIndex ? .reverse : .reverse
        let nextViewController = orderedViewControllers[newIndex]
        scrollToViewController(nextViewController, direction: direction)
      }
    }
    

    
    
    /**
     Scrolls to the given 'viewController' page.
     
     - parameter viewController: the view controller to show.
     */
    fileprivate func scrollToViewController(_ viewController: UIViewController,
                                            direction: UIPageViewController.NavigationDirection = .forward) {
        
        if let vc = viewController as? RantalReadyVC{
            vc.strID = self.strID
            vc.arrRentalReady = arrRentalReady
            vc.objRentalReadyData = self.objRentalReadyData
        }
        
      setViewControllers([viewController],
                         direction: direction,
                         animated: true,
                         completion: { (finished) -> Void in
                          // Setting the view controller programmatically does not fire
                          // any delegate methods, so we have to manually notify the
                          // 'tutorialDelegate' of the new index.
                          self.notifyTutorialDelegateOfNewIndex()
      })
    }
    
    /**
     Notifies '_tutorialDelegate' that the current page index was updated.
     */
    fileprivate func notifyTutorialDelegateOfNewIndex() {
      if let firstViewController = viewControllers?.first,
          let index = orderedViewControllers.firstIndex(of: firstViewController) {
        tutorialDelegate?.MachinePageViewController(self,
                                                 didUpdatePageIndex: index)
      }
    }
}

// MARK: UIPageViewControllerDataSource

extension MachinePageViewController: UIPageViewControllerDataSource {
  
  func pageViewController(_ pageViewController: UIPageViewController,
                          viewControllerBefore viewController: UIViewController) -> UIViewController? {
    guard let viewControllerIndex = orderedViewControllers.firstIndex(of: viewController) else {
      return nil
    }
    
    let previousIndex = viewControllerIndex - 1
    
    guard previousIndex >= 0 else {
      return nil
    }
    
    guard orderedViewControllers.count > previousIndex else {
      return nil
    }
    
    return orderedViewControllers[previousIndex]
    
    
  }
  
  func pageViewController(_ pageViewController: UIPageViewController,
                          viewControllerAfter viewController: UIViewController) -> UIViewController? {
    guard let viewControllerIndex = orderedViewControllers.firstIndex(of: viewController) else {
      return nil
    }
    
    let nextIndex = viewControllerIndex + 1
    let orderedViewControllersCount = orderedViewControllers.count
    
    guard orderedViewControllersCount != nextIndex else {
      return nil
    }
    
    guard orderedViewControllersCount > nextIndex else {
      return nil
    }
    
    return orderedViewControllers[nextIndex]
    
  }
  
}

extension MachinePageViewController: UIPageViewControllerDelegate {
  
  func pageViewController(_ pageViewController: UIPageViewController,
                          didFinishAnimating finished: Bool,
                          previousViewControllers: [UIViewController],
                          transitionCompleted completed: Bool) {
    notifyTutorialDelegateOfNewIndex()
  }
  
}
protocol MachinePageViewControllerDelegate: AnyObject {
  
  /**
   Called when the number of pages is updated.
   
   - parameter MachinePageViewController: the MachinePageViewController instance
   - parameter count: the total number of pages.
   */
  func MachinePageViewController(_ MachinePageViewController: MachinePageViewController,
                              didUpdatePageCount count: Int)
  
  /**
   Called when the current index is updated.
   
   - parameter MachinePageViewController: the MachinePageViewController instance
   - parameter index: the index of the currently visible page.
   */
  func MachinePageViewController(_ MachinePageViewController: MachinePageViewController,
                              didUpdatePageIndex index: Int)
  
}
