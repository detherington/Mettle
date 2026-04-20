import AVFoundation
import SwiftUI

struct DevicePicker: View {
    let devices: [AVCaptureDevice]
    @Binding var selectedDeviceID: String?

    var body: some View {
        Picker("Source", selection: $selectedDeviceID) {
            ForEach(devices, id: \.uniqueID) { device in
                Text(device.localizedName).tag(Optional(device.uniqueID))
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(minWidth: 160)
        .disabled(devices.count <= 1)
    }
}
