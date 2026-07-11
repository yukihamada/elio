import Foundation
import CoreMotion
import UIKit

/// MCP Server for motion and sensor data: shake detection, orientation,
/// accelerometer/gyroscope, pedometer, altimeter, and activity recognition.
final class MotionServer: MCPServer {
    let id = "motion"
    let name = "モーション"
    let serverDescription = "振り検知、デバイスの向き、加速度・ジャイロ、歩数計、気圧高度、移動状態の取得"
    let icon = "gyroscope"

    private let motionManager = CMMotionManager()
    private let pedometer = CMPedometer()
    private let altimeter = CMAltimeter()
    private let activityManager = CMMotionActivityManager()

    /// Flag indicating whether shake detection is enabled.
    private var shakeDetectionEnabled = false

    func listTools() -> [MCPTool] {
        [
            MCPTool(
                name: "shake_detect",
                description: "振り検知（シェイク）を有効/無効にします",
                inputSchema: MCPInputSchema(
                    properties: [
                        "enabled": MCPPropertySchema(type: "boolean", description: "true=有効, false=無効"),
                    ],
                    required: ["enabled"]
                )
            ),
            MCPTool(
                name: "get_orientation",
                description: "現在のデバイスの向きを取得します（portrait, landscape, faceup, facedown等）",
                inputSchema: MCPInputSchema()
            ),
            MCPTool(
                name: "get_motion",
                description: "加速度・ジャイロ・磁力計の現在値をスナップショットで取得します",
                inputSchema: MCPInputSchema()
            ),
            MCPTool(
                name: "pedometer",
                description: "今日の歩数・距離・階段・ペースを取得します（歩数計）",
                inputSchema: MCPInputSchema()
            ),
            MCPTool(
                name: "altitude",
                description: "現在の気圧と相対高度を取得します",
                inputSchema: MCPInputSchema()
            ),
            MCPTool(
                name: "is_moving",
                description: "ユーザーの移動状態を判定します（歩行中/走行中/静止中/車両移動中）",
                inputSchema: MCPInputSchema()
            ),
        ]
    }

    @MainActor
    func callTool(name: String, arguments: [String: JSONValue]) async throws -> MCPResult {
        switch name {
        case "shake_detect":
            return shakeDetect(arguments)
        case "get_orientation":
            return getOrientation()
        case "get_motion":
            return await getMotion()
        case "pedometer":
            return await getPedometer()
        case "altitude":
            return await getAltitude()
        case "is_moving":
            return await isMoving()
        default:
            return MCPResult(content: [.text("[ERROR] Unknown tool: \(name)")], isError: true)
        }
    }

    // MARK: - Shake Detection

    private func shakeDetect(_ args: [String: JSONValue]) -> MCPResult {
        guard let enabled = args["enabled"]?.boolValue else {
            return MCPResult(content: [.text("[ERROR] 'enabled' (boolean) is required")], isError: true)
        }
        shakeDetectionEnabled = enabled
        let status = enabled ? "有効" : "無効"
        return MCPResult(content: [.text("振り検知を\(status)にしました")])
    }

    // MARK: - Orientation

    @MainActor
    private func getOrientation() -> MCPResult {
        let orientation = UIDevice.current.orientation
        let name: String
        switch orientation {
        case .portrait:
            name = "portrait（縦向き）"
        case .portraitUpsideDown:
            name = "portrait_upside_down（逆さ縦向き）"
        case .landscapeLeft:
            name = "landscape_left（左横向き）"
        case .landscapeRight:
            name = "landscape_right（右横向き）"
        case .faceUp:
            name = "faceup（画面が上）"
        case .faceDown:
            name = "facedown（画面が下）"
        case .unknown:
            name = "unknown（不明）"
        @unknown default:
            name = "unknown（不明）"
        }
        return MCPResult(content: [.text("デバイスの向き: \(name)")])
    }

    // MARK: - Motion (Accelerometer / Gyroscope / Magnetometer)

    private func getMotion() async -> MCPResult {
        guard motionManager.isDeviceMotionAvailable else {
            return MCPResult(content: [.text("[ERROR] デバイスモーションセンサーは利用できません")], isError: true)
        }

        return await withCheckedContinuation { continuation in
            motionManager.deviceMotionUpdateInterval = 0.1
            motionManager.startDeviceMotionUpdates(using: .xMagneticNorthZVertical, to: .main) { [weak self] motion, error in
                self?.motionManager.stopDeviceMotionUpdates()

                if let error = error {
                    continuation.resume(returning: MCPResult(
                        content: [.text("[ERROR] \(error.localizedDescription)")],
                        isError: true
                    ))
                    return
                }

                guard let motion = motion else {
                    continuation.resume(returning: MCPResult(
                        content: [.text("[ERROR] モーションデータを取得できませんでした")],
                        isError: true
                    ))
                    return
                }

                let accel = motion.userAcceleration
                let gyro = motion.rotationRate
                let gravity = motion.gravity
                let magneticField = motion.magneticField.field
                let attitude = motion.attitude

                let info = """
                加速度 (G):
                  x: \(String(format: "%.4f", accel.x)), y: \(String(format: "%.4f", accel.y)), z: \(String(format: "%.4f", accel.z))
                重力 (G):
                  x: \(String(format: "%.4f", gravity.x)), y: \(String(format: "%.4f", gravity.y)), z: \(String(format: "%.4f", gravity.z))
                ジャイロ (rad/s):
                  x: \(String(format: "%.4f", gyro.x)), y: \(String(format: "%.4f", gyro.y)), z: \(String(format: "%.4f", gyro.z))
                磁力計 (μT):
                  x: \(String(format: "%.2f", magneticField.x)), y: \(String(format: "%.2f", magneticField.y)), z: \(String(format: "%.2f", magneticField.z))
                姿勢:
                  roll: \(String(format: "%.4f", attitude.roll)) rad, pitch: \(String(format: "%.4f", attitude.pitch)) rad, yaw: \(String(format: "%.4f", attitude.yaw)) rad
                """

                continuation.resume(returning: MCPResult(content: [.text(info)]))
            }
        }
    }

    // MARK: - Pedometer

    private func getPedometer() async -> MCPResult {
        guard CMPedometer.isStepCountingAvailable() else {
            return MCPResult(content: [.text("[ERROR] 歩数計はこのデバイスでは利用できません")], isError: true)
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())

        return await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: startOfDay, to: Date()) { data, error in
                if let error = error {
                    continuation.resume(returning: MCPResult(
                        content: [.text("[ERROR] \(error.localizedDescription)")],
                        isError: true
                    ))
                    return
                }

                guard let data = data else {
                    continuation.resume(returning: MCPResult(
                        content: [.text("[ERROR] 歩数計データを取得できませんでした")],
                        isError: true
                    ))
                    return
                }

                var lines: [String] = []
                lines.append("今日の歩数: \(data.numberOfSteps) 歩")

                if let distance = data.distance {
                    lines.append("距離: \(String(format: "%.0f", distance.doubleValue)) m")
                }

                if CMPedometer.isFloorCountingAvailable() {
                    if let floorsAscended = data.floorsAscended {
                        lines.append("上った階数: \(floorsAscended) 階")
                    }
                    if let floorsDescended = data.floorsDescended {
                        lines.append("下りた階数: \(floorsDescended) 階")
                    }
                }

                if let pace = data.currentPace {
                    let secPerMeter = pace.doubleValue
                    let minPerKm = secPerMeter * 1000 / 60
                    lines.append("現在のペース: \(String(format: "%.1f", minPerKm)) 分/km")
                }

                if let cadence = data.currentCadence {
                    lines.append("ケイデンス: \(String(format: "%.1f", cadence.doubleValue)) 歩/秒")
                }

                continuation.resume(returning: MCPResult(content: [.text(lines.joined(separator: "\n"))]))
            }
        }
    }

    // MARK: - Altitude / Pressure

    private func getAltitude() async -> MCPResult {
        guard CMAltimeter.isRelativeAltitudeAvailable() else {
            return MCPResult(content: [.text("[ERROR] 気圧高度計はこのデバイスでは利用できません")], isError: true)
        }

        return await withCheckedContinuation { continuation in
            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] altitudeData, error in
                self?.altimeter.stopRelativeAltitudeUpdates()

                if let error = error {
                    continuation.resume(returning: MCPResult(
                        content: [.text("[ERROR] \(error.localizedDescription)")],
                        isError: true
                    ))
                    return
                }

                guard let altitudeData = altitudeData else {
                    continuation.resume(returning: MCPResult(
                        content: [.text("[ERROR] 高度データを取得できませんでした")],
                        isError: true
                    ))
                    return
                }

                let pressure = altitudeData.pressure.doubleValue // kPa
                let relativeAltitude = altitudeData.relativeAltitude.doubleValue // meters

                let info = """
                気圧: \(String(format: "%.2f", pressure)) kPa (\(String(format: "%.1f", pressure * 10)) hPa)
                相対高度: \(String(format: "%.2f", relativeAltitude)) m（計測開始時からの差分）
                """

                continuation.resume(returning: MCPResult(content: [.text(info)]))
            }
        }
    }

    // MARK: - Activity Detection (is_moving)

    private func isMoving() async -> MCPResult {
        guard CMMotionActivityManager.isActivityAvailable() else {
            return MCPResult(content: [.text("[ERROR] アクティビティ検出はこのデバイスでは利用できません")], isError: true)
        }

        return await withCheckedContinuation { continuation in
            activityManager.startActivityUpdates(to: .main) { [weak self] activity in
                self?.activityManager.stopActivityUpdates()

                guard let activity = activity else {
                    continuation.resume(returning: MCPResult(
                        content: [.text("[ERROR] アクティビティデータを取得できませんでした")],
                        isError: true
                    ))
                    return
                }

                var states: [String] = []
                if activity.stationary {
                    states.append("静止中")
                }
                if activity.walking {
                    states.append("歩行中")
                }
                if activity.running {
                    states.append("走行中")
                }
                if activity.automotive {
                    states.append("車両移動中")
                }
                if activity.cycling {
                    states.append("自転車")
                }
                if states.isEmpty {
                    states.append("不明")
                }

                let confidence: String
                switch activity.confidence {
                case .low:
                    confidence = "低"
                case .medium:
                    confidence = "中"
                case .high:
                    confidence = "高"
                @unknown default:
                    confidence = "不明"
                }

                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm:ss"
                let timeStr = formatter.string(from: activity.startDate)

                let info = """
                移動状態: \(states.joined(separator: ", "))
                確信度: \(confidence)
                検出時刻: \(timeStr)
                """

                continuation.resume(returning: MCPResult(content: [.text(info)]))
            }
        }
    }
}
