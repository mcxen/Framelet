import Foundation
import Observation

@Observable
final class AppServices {
    let mediaProbe: MediaProbeService
    let ffmpegRunner: FFmpegRunner
    let keyframes: KeyframeService
    let thumbnails: ThumbnailService
    let waveforms: WaveformService
    let proxies: ProxyBuilder
    let commandLog: CommandLog
    let projectStore: ProjectStore
    let fileAccess: FileAccessService

    init(commandLog: CommandLog = CommandLog()) {
        self.commandLog = commandLog
        let ffmpegRunner = FFmpegRunner(commandLog: commandLog)
        let mediaProbe = FFprobeService(commandLog: commandLog)
        let keyframes = FFprobeKeyframeService(commandLog: commandLog)
        let thumbnails = AVAssetThumbnailService()
        let waveforms = FFmpegWaveformService(commandLog: commandLog)
        let proxies = FFmpegProxyBuilder(commandLog: commandLog)
        self.mediaProbe = mediaProbe
        self.ffmpegRunner = ffmpegRunner
        self.keyframes = keyframes
        self.thumbnails = thumbnails
        self.waveforms = waveforms
        self.proxies = proxies
        self.projectStore = ProjectStore()
        self.fileAccess = FileAccessService()
    }
}
