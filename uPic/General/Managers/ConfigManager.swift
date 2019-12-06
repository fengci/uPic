//
//  CoreManager.swift
//  uPic
//
//  Created by Svend Jin on 2019/6/11.
//  Copyright © 2019 Svend Jin. All rights reserved.
//

import Foundation
import Cocoa
import LoginServiceKit

public class ConfigManager {
    
    // static
    public static var shared = ConfigManager()
    
    // instance
    
    public var firstUsage: BoolType {
        if Defaults[.firstUsage] == nil {
            Defaults[.firstUsage] = BoolType._false.rawValue
            return ._true
        } else {
            return ._false
        }
    }
    
    public func firstSetup() {
        //FIXME: 临时处理 folder、filename 的数据到新版的 saveKey 中。后续版本需要移除
        self._upgradeHostData()
        
        guard firstUsage == ._true else {
            return
        }
        Defaults[.compressFactor] = 100
        Defaults.synchronize()
        
        self.setHostItems(items: [Host.getDefaultHost()])
        
        LoginServiceKit.removeLoginItems()
    }
    
    //MARK: 临时处理 folder、filename 的数据到新版的 saveKey 中。后续版本需要移除
    private func _upgradeHostData() {
        if Defaults.bool(forKey: "_upgradedHostData") {
            return
        }
        let hostItems = self.getHostItems()
        for host in hostItems {
            if (host.data == nil || !host.data!.containsKey(key: "saveKeyPath")) {
                continue
            }
            let data = host.data!
            if let saveKeyPath = data.value(forKey: "saveKeyPath") as? String, !saveKeyPath.isEmpty {
                continue
            }
            
            var saveKeyPath = ""
            
            if data.containsKey(key: "folder") {
                if let folder = data.value(forKey: "folder") as? String, !folder.isEmpty {
                    saveKeyPath += "\(folder)/"
                }
            }
            
            if data.containsKey(key: "saveKey") {
                if let saveKey = data.value(forKey: "saveKey") as? String, let saveKeyObj = HostSaveKey(rawValue: saveKey) {
                    saveKeyPath += saveKeyObj._getSaveKeyPathPattern()
                } else {
                    saveKeyPath += HostSaveKey.filename._getSaveKeyPathPattern()
                }
            }
            
            host.data?.setValue(saveKeyPath, forKey: "saveKeyPath")
        }
        
        self.setHostItems(items: hostItems)
        Defaults.set(true, forKey: "_upgradedHostData")
    }
    
    public func removeAllUserDefaults() {
        // 提前取出图床配置
        let hostItems = self.getHostItems()
        let defaultHostId = Defaults[.defaultHostId]
        let historyList = self.getHistoryList_New()
        
        let domain = Bundle.main.bundleIdentifier!
        Defaults.removePersistentDomain(forName: domain)
        Defaults.synchronize()
        
        DispatchQueue.main.async {
            // 清除所有用户设置后，再重新写入图床配置
            self.setHostItems(items: hostItems)
            Defaults[.defaultHostId] = defaultHostId
            
            let list = historyList.map { (model) -> [String: Any] in
                return model.toKeyValue()
            }
            
            self.setHistoryList_New(items: list)
        }
    }
    
}


extension ConfigManager {
    // MARK: 图床配置和默认图床
    
    func getHostItems() -> [Host] {
        return Defaults[.hostItems] ?? [Host]()
    }
    
    func setHostItems(items: [Host]) -> Void {
        Defaults[.hostItems] = items
        Defaults.synchronize()
        ConfigNotifier.postNotification(.changeHostItems)
    }
    
    func getDefaultHost() -> Host? {
        guard let defaultHostId = Defaults[.defaultHostId], let hostItems = Defaults[.hostItems] else {
            return nil
        }
        for host in hostItems {
            if host.id == defaultHostId {
                return host
            }
        }
        return nil
    }
}


extension ConfigManager {
    // MARK: 上传历史
    
    public var historyLimit_New: Int {
        get {
            let defaultLimit = 100
            let limit = Defaults[.historyLimit]
            if (limit == nil || limit == 0) {
                return defaultLimit
            }
            return limit!
        }
        
        set {
            Defaults[.historyLimit] = newValue
            Defaults.synchronize()
        }
    }
    
    func getHistoryList_New() -> [HistoryThumbnailModel] {
        let historyList = Defaults[.historyList] ?? [[String: Any]]()
        let historyListModel: [HistoryThumbnailModel] = historyList.map({ (item) -> HistoryThumbnailModel in
            return HistoryThumbnailModel.keyValue(keyValue: item)
        })
        return historyListModel
    }
    
    func setHistoryList_New(items: [[String: Any]]) -> Void {
        Defaults[.historyList] = items
        Defaults.synchronize()
        ConfigNotifier.postNotification(.updateHistoryList)
    }
    
    func addHistory_New(url: String, previewModel: HistoryThumbnailModel) -> Void {
        var list = self.getHistoryList_New().map { (model) -> [String: Any] in
            return model.toKeyValue()
        }
        list.insert(previewModel.toKeyValue(), at: 0)
        
        if list.count > self.historyLimit_New {
            list.removeFirst(list.count - self.historyLimit_New)
        }
        
        self.setHistoryList_New(items: list)
    }
    
    func clearHistoryList_New() -> Void {
        self.setHistoryList_New(items: [])
    }
}

extension ConfigManager {
    // MARK: 上传前压缩图片，压缩率
    var compressFactor: Int {
        get {
            return Defaults[.compressFactor] ?? 100
        }
        
        set {
            Defaults[.compressFactor] = newValue
            Defaults.synchronize()
        }
    }
}

extension ConfigManager {
    // import & export config
    
    func importHosts() {
        NSApp.activate(ignoringOtherApps: true)
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canCreateDirectories = false
        openPanel.allowedFileTypes = ["json"]
        
        openPanel.begin { (result) -> Void in
            if result.rawValue == NSApplication.ModalResponse.OK.rawValue {
                guard let url = openPanel.url,
                    let data = NSData(contentsOfFile: url.path),
                    let array = try? JSONSerialization.jsonObject(with: data as Data) as? [String]
                    else {
                        NotificationExt.shared.postImportErrorNotice()
                        return
                }
                let hostItems = array.map(){ str in
                    return Host.deserialize(str: str)
                }.filter { $0 != nil }
                if hostItems.count == 0 {
                    NotificationExt.shared.postImportErrorNotice()
                    return
                }
                
                // choose import method
                
                let alert = NSAlert()
                
                alert.messageText = "Import host configuration".localized
                alert.informativeText = "⚠️ Please choose import method, merge or overwrite?".localized
                
                alert.addButton(withTitle: "merge".localized).refusesFirstResponder = true
                
                alert.addButton(withTitle: "⚠️ overwrite".localized).refusesFirstResponder = true
                
                let modalResult = alert.runModal()
                
                switch modalResult {
                case .alertFirstButtonReturn:
                    // current Items
                    var currentHostItems = ConfigManager.shared.getHostItems()
                    for host in hostItems {
                        let isContains = currentHostItems.contains(where: {item in
                            return item == host
                        })
                        if (!isContains) {
                            currentHostItems.append(host!)
                        }
                    }
                    ConfigManager.shared.setHostItems(items: currentHostItems)
                    NotificationExt.shared.postImportSuccessfulNotice()
                case .alertSecondButtonReturn:
                    ConfigManager.shared.setHostItems(items: hostItems as! [Host])
                    NotificationExt.shared.postImportSuccessfulNotice()
                default:
                    print("Cancel Import")
                }
            }
        }
    }
    
    func exportHosts() {
        let hostItems = ConfigManager.shared.getHostItems()
        if hostItems.count == 0 {
            NotificationExt.shared.postExportErrorNotice("No exportable hosts!".localized)
            return
        }
        
        NSApp.activate(ignoringOtherApps: true)
        let savePanel = NSSavePanel()
        savePanel.directoryURL = URL(fileURLWithPath: NSHomeDirectory().appendingPathComponent(path: "Documents"))
        savePanel.nameFieldStringValue = "uPic_hosts.json"
        savePanel.allowsOtherFileTypes = false
        savePanel.isExtensionHidden = true
        savePanel.canCreateDirectories = true
        savePanel.allowedFileTypes = ["json"]
        
        savePanel.begin { (result) -> Void in
            if result.rawValue == NSApplication.ModalResponse.OK.rawValue {
                
                guard let url = savePanel.url else {
                    NotificationExt.shared.postImportErrorNotice()
                    return
                }
                
                let hostStrArr = hostItems.map(){ hostItem in
                    return hostItem.serialize()
                }
                if (!JSONSerialization.isValidJSONObject(hostStrArr)) {
                    NotificationExt.shared.postImportErrorNotice()
                    return
                }
                let os = OutputStream(toFileAtPath: url.path, append: false)
                os?.open()
                JSONSerialization.writeJSONObject(hostStrArr, to: os!, options: .prettyPrinted, error: .none)
                os?.close()
                NotificationExt.shared.postExportSuccessfulNotice()
            }
        }
    }
}
