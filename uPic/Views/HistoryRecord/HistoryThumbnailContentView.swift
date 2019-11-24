//
//  PreviewItemView.swift
//  uPic
//
//  Created by 侯猛 on 2019/10/30.
//  Copyright © 2019 Svend Jin. All rights reserved.
//

import Cocoa

enum MouseStatus {
    case entered
    case exited
    case moved
}

class HistoryThumbnailContentView: NSView {
    
    private var trackingArea: NSTrackingArea?
    
    var mouseStatusHandler: ((MouseStatus, NSPoint?, NSView) -> Void)?
    
    var mousePointView: NSView!
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        mousePointView = NSView(frame: NSRect(x: 0, y: 0, width: 30, height: 30))
        mousePointView.wantsLayer = true
        mousePointView.layer?.backgroundColor = NSColor.clear.cgColor
//        mousePointView.layer?.backgroundColor = NSColor.red.cgColor
        addSubview(mousePointView)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        createTrackingArea()
    }
    
    override func updateTrackingAreas() {
        createTrackingArea()
        super.updateTrackingAreas()
    }
    
    private func createTrackingArea() {
        removeTrackingArea()
        let options : NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
        let newBounds = NSRect(x: 5, y: 5, width: bounds.width - 10, height: bounds.height - 10)
        trackingArea = NSTrackingArea(rect: newBounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    private func removeTrackingArea() {
        if trackingArea != nil {
            removeTrackingArea(trackingArea!)
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }
    
    override func mouseEntered(with event: NSEvent) {
        self.window?.acceptsMouseMovedEvents = true
        self.window?.makeFirstResponder(self)
        let eyeCenter = convert(event.locationInWindow, from: nil)
        mouseMoved(with: event)
        mouseStatusHandler?(.entered, convert(eyeCenter, to: nil), mousePointView)
    }
    
    override func mouseExited(with event: NSEvent) {
        self.window?.acceptsMouseMovedEvents = false
        mouseStatusHandler?(.exited, nil, mousePointView)
    }
    
    override func mouseMoved(with event: NSEvent) {
        let eyeCenter = convert(event.locationInWindow, from: nil)
        mousePointView.frame.origin = CGPoint(x: eyeCenter.x - 15, y: eyeCenter.y - 20)
        mouseStatusHandler?(.moved, eyeCenter, mousePointView)
    }
    
}