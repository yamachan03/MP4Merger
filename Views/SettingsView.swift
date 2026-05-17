import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var languageManager: LanguageManager
    
    var body: some View {
        Form {
            Picker(languageManager.localized("Language"), selection: $languageManager.currentLanguage) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .pickerStyle(.menu)
            .padding()
        }
        .padding()
        .frame(width: 300, height: 100)
        .navigationTitle(languageManager.localized("Settings"))
    }
}
//
//  Untitled.swift
//  MP4Merger
//
//  Created by (redacted) on 2026/05/17.
//

