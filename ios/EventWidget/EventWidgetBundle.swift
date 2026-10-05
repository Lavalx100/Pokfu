//
//  EventWidgetBundle.swift
//  EventWidget
//
//  Created by Ruijie Li on 23/7/2024.
//

import WidgetKit
import SwiftUI

@main
struct EventWidgetBundle: WidgetBundle {
  var body: some Widget {
    if #available(iOS 14.0, *) {
      PokfuUpcomingEventWidget()
    }
    if #available(iOS 16.1, *) {
      PokfuEventLiveActivity()
    }
  }
}
