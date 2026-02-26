import SwiftUI

/// 🎨 前端视图：负责展示界面和接收用户点击
struct ContentView: View {
    // 引入我们的“指挥官” ViewModel
    // @StateObject 会保证 ViewModel 的生命周期与视图绑定，并监听它的变化
    @StateObject private var viewModel = ContentViewModel()
    
    // 控制扫描状态的本地变量
    @State private var isScanning = false
    
    var body: some View {
        VStack(spacing: 40) {
            
            // 1. 状态指示图标
            Image(systemName: viewModel.isDangerClose ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .foregroundColor(viewModel.isDangerClose ? .red : .green)
                .animation(.easeInOut, value: viewModel.isDangerClose)
            
            // 2. 核心警告信息展示
            Text(viewModel.warningMessage)
                .font(.title2)
                .bold()
                .multilineTextAlignment(.center)
                .padding()
                .background(viewModel.isDangerClose ? Color.red.opacity(0.2) : Color.gray.opacity(0.1))
                .cornerRadius(15)
                .padding(.horizontal)
            
            Spacer()
            
            // 3. 控制按钮
            Button(action: {
                if isScanning {
                    viewModel.stopScanning()
                } else {
                    viewModel.startScanning()
                }
                isScanning.toggle()
            }) {
                Text(isScanning ? "停止扫描" : "开始环境感知")
                    .font(.title3)
                    .bold()
                    .foregroundColor(.white)
                    .frame(width: 200, height: 60)
                    .background(isScanning ? Color.red : Color.blue)
                    .cornerRadius(30)
                    .shadow(radius: 5)
            }
            .padding(.bottom, 50)
        }
        .padding(.top, 50)
    }
}