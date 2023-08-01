//
//  HIDDevice.swift
//  USBDeviceSwift
//
//  Created by Artem Hruzd on 6/14/17.
//  Copyright © 2017 Artem Hruzd. All rights reserved.
//

import Cocoa
import Foundation
import IOKit.hid

public extension Notification.Name {
    static let HIDDeviceDataReceived = Notification.Name("HIDDeviceDataReceived")
    static let HIDDeviceConnected = Notification.Name("HIDDeviceConnected")
    static let HIDDeviceDisconnected = Notification.Name("HIDDeviceDisconnected")
}

public struct HIDMonitorData {
    public let vendorId:Int
    public let productId:Int
    public var usagePage:Int?
    public var usage:Int?

    public init (vendorId:Int, productId:Int) {
        self.vendorId = vendorId
        self.productId = productId
    }

    public init (vendorId:Int, productId:Int, usagePage:Int?, usage:Int?) {
        self.vendorId = vendorId
        self.productId = productId
        self.usagePage = usagePage
        self.usage = usage
    }
}
public struct HIDBCDVersion {
    public let majorVersion: Int
    public let minorVersion: Int
    public let subMinorVersion: Int
    
    public let rawValue: String
    public init?(bcdVersionString: String) {
        let length = bcdVersionString.count
        if length < 3 {
            return nil
        }
        let indexMajor = bcdVersionString.index(bcdVersionString.startIndex, offsetBy: 0)
        let indexMinor = bcdVersionString.index(bcdVersionString.endIndex, offsetBy: -2)
        let indexSubMinor = bcdVersionString.index(bcdVersionString.endIndex, offsetBy: -1)
        
        guard let major = Int(String(bcdVersionString[..<indexMinor]))
                ,let minor = Int(String(bcdVersionString[indexMinor]))
                ,let subMinor = Int(String(bcdVersionString[indexSubMinor]))
        else {
            return nil
        }
        self.majorVersion = major
        self.minorVersion = minor
        self.subMinorVersion = subMinor
        self.rawValue = bcdVersionString
    }
}

public struct HIDDevice {
    public let id:Int
    public let vendorId:Int
    public let productId:Int
    public let reportSize:Int
    public let device:IOHIDDevice
    public let name:String
    public let interfaceId:Int
    public let versionValue: Int?
    public let version: HIDBCDVersion?
    public let serialNumber: String?
    public let reportInterval: Int?
    
    public init(device:IOHIDDevice) {
        self.device = device
        
        self.id = IOHIDDeviceGetProperty(self.device, kIOHIDLocationIDKey as CFString) as? Int ?? -1
        self.name = IOHIDDeviceGetProperty(self.device, kIOHIDProductKey as CFString) as? String ?? ""
        self.vendorId = IOHIDDeviceGetProperty(self.device, kIOHIDVendorIDKey as CFString) as? Int ?? -1
        self.productId = IOHIDDeviceGetProperty(self.device, kIOHIDProductIDKey as CFString) as? Int ?? -1
        self.reportSize = IOHIDDeviceGetProperty(self.device, kIOHIDMaxInputReportSizeKey as CFString) as? Int ?? -1
        self.versionValue = IOHIDDeviceGetProperty(self.device, kIOHIDVersionNumberKey as CFString) as? Int //bcdDevice, actually
        self.version = HIDBCDVersion(bcdVersionString: String(format: "%x", self.versionValue ?? 0))
        self.serialNumber = IOHIDDeviceGetProperty(self.device, kIOHIDSerialNumberKey as CFString) as? String
        self.reportInterval = IOHIDDeviceGetProperty(self.device, kIOHIDReportIntervalKey as CFString) as? Int
        
        /**
         Discussion: after macOS 13.3, kUUSBInterfaceNumber might not available if treated as HIDDevice
         https://developer.apple.com/forums/thread/728001
         https://github.com/libusb/hidapi/pull/530
         https://github.com/libusb/hidapi/pull/534
         using solution from HIDAPI
         https://github.com/libusb/hidapi/pull/534/commits/652b9a5d539b9e88e8bc1670b6efae0f323b570d
         and mix it with USBDeviceSwift due to some C language convert
        **/
        self.interfaceId = IOHIDDeviceGetProperty(self.device, kUSBInterfaceNumber as CFString) as? Int ?? Int(HIDDevice.readUSBInterfaceFromHIDServiceParent(hidService: device))
    }
    
    //MARK: copied from HIDAPI
    static func readUSBInterfaceFromHIDServiceParent(hidService: IOHIDDevice) -> Int32 {
        var result: Int32 = -1
        var success = false
        var current: io_registry_entry_t = IO_OBJECT_NULL
        var res: kern_return_t
        var parentNumber = 0

        res = IORegistryEntryGetParentEntry(IOHIDDeviceGetService(hidService), kIOServicePlane, &current)
        while res == KERN_SUCCESS && parentNumber < 3 {
            var parent: io_registry_entry_t = IO_OBJECT_NULL
            var interfaceNumber: Int32 = -1
            parentNumber += 1

            success = HIDDevice.tryGetIORegistryIntProperty(current, kUSBInterfaceNumber as CFString, &interfaceNumber)
            if success {
                result = interfaceNumber
                break
            }

            res = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            if parent != IO_OBJECT_NULL {
                IOObjectRelease(current)
                current = parent
            }
        }

        if current != IO_OBJECT_NULL {
            IOObjectRelease(current)
            current = IO_OBJECT_NULL
        }
        
        return result
    }
    
    //MARK: copied from USBDeviceSwift/SerialDeviceMonitor
    private static func tryGetIORegistryIntProperty(_ entry: io_registry_entry_t, _ key: CFString, _ value: inout Int32) -> Bool {
        if let intValue = getDeviceProperty(device: entry, key: key as String) as? NSNumber {
            value = Int32(intValue.intValue)
            return true
        }
        return false
    }
    
    private static func getParentProperty(device:io_object_t, key:String) -> AnyObject? {
        return IORegistryEntrySearchCFProperty(device, kIOServicePlane, key as CFString, kCFAllocatorDefault, IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents))
    }
    
    private static func getDeviceProperty(device:io_object_t, key:String) -> AnyObject? {
        let cfKey = key as CFString
        let propValue = IORegistryEntryCreateCFProperty(device, cfKey, kCFAllocatorDefault, 0)
        
        return propValue?.takeRetainedValue()
    }
}
