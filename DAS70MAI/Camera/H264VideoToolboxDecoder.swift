import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

/// Minimal low-latency H.264 decoder for AVCC NAL units from IPCamKit.
/// Frames are delivered as CVPixelBuffer so A500S and the iPhone camera share the same ADAS pipeline.
final class H264VideoToolboxDecoder: @unchecked Sendable {
    var onPixelBuffer: (@Sendable (CVPixelBuffer) -> Void)?

    private var session: VTDecompressionSession?
    private var formatDescription: CMVideoFormatDescription?
    private var sps: Data?
    private var pps: Data?

    func decode(nalus: [Data]) {
        for avcc in nalus { inspectParameterSet(avcc) }
        guard ensureSession(), let formatDescription else { return }

        let payload = nalus.reduce(into: Data()) { $0.append($1) }
        var blockBuffer: CMBlockBuffer?
        let status = payload.withUnsafeBytes { bytes -> OSStatus in
            guard let base = bytes.baseAddress else { return kCMBlockBufferBadCustomBlockSourceErr }
            return CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: payload.count,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: payload.count,
                flags: 0,
                blockBufferOut: &blockBuffer
            ).flatMapStatus {
                CMBlockBufferReplaceDataBytes(with: base, blockBuffer: blockBuffer!, offsetIntoDestination: 0, dataLength: payload.count)
            }
        }
        guard status == noErr, let blockBuffer else { return }

        var sampleBuffer: CMSampleBuffer?
        var sampleSize = payload.count
        guard CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 0,
            sampleTimingArray: nil,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        ) == noErr, let sampleBuffer, let session else { return }

        VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sampleBuffer,
            flags: [.enableAsynchronousDecompression, ._EnableTemporalProcessing],
            infoFlagsOut: nil,
            outputHandler: { [weak self] status, _, imageBuffer, _, _ in
                guard status == noErr, let imageBuffer else { return }
                self?.onPixelBuffer?(imageBuffer)
            }
        )
    }

    func reset() {
        if let session { VTDecompressionSessionInvalidate(session) }
        session = nil
        formatDescription = nil
        sps = nil
        pps = nil
    }

    private func inspectParameterSet(_ avcc: Data) {
        guard avcc.count > 4 else { return }
        let type = avcc[4] & 0x1F
        let raw = avcc.dropFirst(4)
        if type == 7 { sps = Data(raw) }
        if type == 8 { pps = Data(raw) }
    }

    private func ensureSession() -> Bool {
        if session != nil { return true }
        guard let sps, let pps else { return false }
        let status: OSStatus = sps.withUnsafeBytes { spsBytes in
            pps.withUnsafeBytes { ppsBytes in
                guard let spsBase = spsBytes.bindMemory(to: UInt8.self).baseAddress,
                      let ppsBase = ppsBytes.bindMemory(to: UInt8.self).baseAddress else { return -1 }
                let pointers: [UnsafePointer<UInt8>] = [spsBase, ppsBase]
                let sizes = [sps.count, pps.count]
                return pointers.withUnsafeBufferPointer { pointerBuffer in
                    sizes.withUnsafeBufferPointer { sizeBuffer in
                        CMVideoFormatDescriptionCreateFromH264ParameterSets(
                            allocator: kCFAllocatorDefault,
                            parameterSetCount: 2,
                            parameterSetPointers: pointerBuffer.baseAddress!,
                            parameterSetSizes: sizeBuffer.baseAddress!,
                            nalUnitHeaderLength: 4,
                            formatDescriptionOut: &formatDescription
                        )
                    }
                }
            }
        }
        guard status == noErr, let formatDescription else { return false }
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        return VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDescription,
            decoderSpecification: [kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder: true] as CFDictionary,
            imageBufferAttributes: attributes as CFDictionary,
            outputCallback: nil,
            decompressionSessionOut: &session
        ) == noErr
    }
}

private extension OSStatus {
    func flatMapStatus(_ next: () -> OSStatus) -> OSStatus {
        self == noErr ? next() : self
    }
}
