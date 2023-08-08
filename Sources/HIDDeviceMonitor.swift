//
//  HIDDeviceMonitor.swift
//  USBDeviceSwift
//
//  Created by Artem Hruzd on 6/14/17.
//  Copyright © 2017 Artem Hruzd. All rights reserved.
//

import Cocoa
import Foundation
import IOKit.hid

public protocol HIDDeviceMonitorDelegate {
    func deviceDataReceived(data: Data, dataPointer:UnsafeMutablePointer<UInt8>, device: IOHIDDevice)
}

open class HIDDeviceMonitor {
    public let vp:[HIDMonitorData]
    public let fallbackInputReportSize:Int //fallback reportSize if HIDDevice kIOHIDMaxInputReportSizeKey is unavailable
    
    public var delegate: HIDDeviceMonitorDelegate? = nil
    
    public init(_ vp:[HIDMonitorData], reportSize:Int) {
        self.vp = vp
        self.fallbackInputReportSize = reportSize
    }
    
    @objc open func start() {
        let managerRef = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        var deviceMatches:[[String:Any]] = []
        for vp in self.vp {
            var match = [kIOHIDProductIDKey: vp.productId, kIOHIDVendorIDKey: vp.vendorId]
            if let usagePage = vp.usagePage {
                match[kIOHIDDeviceUsagePageKey] = usagePage
            }
            if let usage = vp.usage {
                match[kIOHIDDeviceUsageKey] = usage
            }
            deviceMatches.append(match)
        }
        IOHIDManagerSetDeviceMatchingMultiple(managerRef, deviceMatches as CFArray)
        IOHIDManagerScheduleWithRunLoop(managerRef, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue);
        IOHIDManagerOpen(managerRef, IOOptionBits(kIOHIDOptionsTypeNone));
        
        let matchingCallback:IOHIDDeviceCallback = { inContext, inResult, inSender, inIOHIDDeviceRef in
            let this:HIDDeviceMonitor = unsafeBitCast(inContext, to: HIDDeviceMonitor.self)
            this.rawDeviceAdded(inResult, inSender: inSender!, inIOHIDDeviceRef: inIOHIDDeviceRef)
        }
        
        let removalCallback:IOHIDDeviceCallback = { inContext, inResult, inSender, inIOHIDDeviceRef in
            let this:HIDDeviceMonitor = unsafeBitCast(inContext, to: HIDDeviceMonitor.self)
            this.rawDeviceRemoved(inResult, inSender: inSender!, inIOHIDDeviceRef: inIOHIDDeviceRef)
        }
        IOHIDManagerRegisterDeviceMatchingCallback(managerRef, matchingCallback, unsafeBitCast(self, to: UnsafeMutableRawPointer.self))
        IOHIDManagerRegisterDeviceRemovalCallback(managerRef, removalCallback, unsafeBitCast(self, to: UnsafeMutableRawPointer.self))
        
        
        RunLoop.current.run()
    }
    
    open func read(_ inResult: IOReturn, inSender: UnsafeMutableRawPointer, type: IOHIDReportType, reportId: UInt32, report: UnsafeMutablePointer<UInt8>, reportLength: CFIndex, device: IOHIDDevice) {
        let data = Data(bytes: UnsafePointer<UInt8>(report), count: reportLength)
        self.delegate?.deviceDataReceived(data: data, dataPointer: report, device: device)
        NotificationCenter.default.post(name: .HIDDeviceDataReceived, object: ["data": data, "dataPtr" : report, "ioHIDDevice": device] as [String : Any])
    }
    
    open func rawDeviceAdded(_ inResult: IOReturn, inSender: UnsafeMutableRawPointer, inIOHIDDeviceRef: IOHIDDevice!) {
        // It would be better to look up the report size and create a chunk of memory of that size
        let device = HIDDevice(device:inIOHIDDeviceRef)
        let inputReportSize = device.maxInputReportSize > 0 ? device.maxInputReportSize : fallbackInputReportSize
        let report = UnsafeMutablePointer<UInt8>.allocate(capacity: inputReportSize)
        let inputCallback : IOHIDReportWithTimeStampCallback = { inContext, inResult, inSender, type, reportId, report, reportLength, timeStamp in
            /** @typedef IOHIDReportCallback
                @discussion Type and arguments of callout C function that is used when a HID report completion routine is called.
                @param context void * pointer to your data, often a pointer to an object.
                @param result Completion result of desired operation.
                @param sender Interface instance sending the completion routine.
                @param type The type of the report that was completed.
                @param reportID The ID of the report that was completed.
                @param report Pointer to the buffer containing the contents of the report.
                @param reportLength Size of the buffer received upon completion.
                @param timeStamp The time at which the report arrived.
            */
            let this:HIDDeviceMonitor = unsafeBitCast(inContext, to: HIDDeviceMonitor.self)
            let deviceRef:IOHIDDevice = unsafeBitCast(inSender, to: IOHIDDevice.self)
            this.read(inResult, inSender: inSender!, type: type, reportId: reportId, report: report, reportLength: reportLength, device: deviceRef)
        }
        
        //Hook up inputcallback
        IOHIDDeviceRegisterInputReportWithTimeStampCallback(inIOHIDDeviceRef!, report, inputReportSize, inputCallback, unsafeBitCast(self, to: UnsafeMutableRawPointer.self))
        
        NotificationCenter.default.post(name: .HIDDeviceConnected, object: ["device": device])
    }
    
    open func rawDeviceRemoved(_ inResult: IOReturn, inSender: UnsafeMutableRawPointer, inIOHIDDeviceRef: IOHIDDevice!) {
        let device = HIDDevice(device:inIOHIDDeviceRef)
        NotificationCenter.default.post(name: .HIDDeviceDisconnected, object: [
            "id": device.id,
            "device": device
        ] as [String : Any])
    }
}
