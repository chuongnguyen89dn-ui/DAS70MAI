import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

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
            return CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: payload.count, blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0, dataLength: payload.count, flags: 0, blockBufferOut: &blockBuffer).flatMapStatus {
                CMBlockBufferReplaceDataBytes(with: base, blockBuffer: blockBuffer!, offsetIntoDestination: 0, dataLength: payload.count)
            }
        }
        guard status == noErr, let blockBuffer else { return }
        var sampleBuffer: CMSampleBuffer?
        var sampleSize = payload.count
        guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: blockBuffer, formatDescription: formatDescription, sampleCount: 1, sampleTimingEntryCount: 0, sampleTimingArray: nil, sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize, sampleBufferOut: &sampleBuffer) == noErr, let sampleBuffer, let session else { return }
        VTDecompressionSessionDecodeFrame(session, sampleBuffer: sampleBuffer, flags: [._EnableAsynchronousDecompression], infoFlagsOut: nil) { [weak self] status, _, imageBuffer, _, _ in
            guard status == noErr, let imageBuffer else { return }
            self?.onPixelBuffer?(imageBuffer)
        }
    }

    func reset() {
        if let session { VTDecompressionSessionInvalidate(session) }
        session = nil; formatDescription = nil; sps = nil; pps = nil
    }

    private func inspectParameterSet(_ avcc: Data) {
        guard avcc.count > 4 else { return }
        let type = avcc[4] & 0x1F
        let raw = Data(avcc.dropFirst(4))
        if type == 7 { sps = raw }
        if type == 8 { pps = raw }
    }

    private func ensureSession() -> Bool {
        if session != nil { return true }
        guard let sps, let pps else { return false }
        let status: OSStatus = sps.withUnsafeBytes { sb in pps.withUnsafeBytes { pb in
            guard let sp = sb.bindMemory(to: UInt8.self).baseAddress, let pp = pb.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            let pointers: [UnsafePointer<UInt8>] = [sp, pp]
            let sizes = [sps.count, pps.count]
            return pointers.withUnsafeBufferPointer { ps in sizes.withUnsafeBufferPointer { ss in
                CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: kCFAllocatorDefault, parameterSetCount: 2, parameterSetPointers: ps.baseAddress!, parameterSetSizes: ss.baseAddress!, nalUnitHeaderLength: 4, formatDescriptionOut: &formatDescription)
            }}
        }}
        guard status == noErr, let formatDescription else { return false }
        let attrs: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA, kCVPixelBufferIOSurfacePropertiesKey: [:]]
        return VTDecompressionSessionCreate(allocator: kCFAllocatorDefault, formatDescription: formatDescription, decoderSpecification: nil, imageBufferAttributes: attrs as CFDictionary, outputCallback: nil, decompressionSessionOut: &session) == noErr
    }
}

private extension OSStatus {
    func flatMapStatus(_ next: () -> OSStatus) -> OSStatus { self == noErr ? next() : self }
}
