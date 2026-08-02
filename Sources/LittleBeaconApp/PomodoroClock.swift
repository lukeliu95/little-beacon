import Darwin
import Foundation
import LittleBeaconCore

func systemPomodoroClockReading(at wallDate: Date = Date()) -> PomodoroClockReading {
    var timebase = mach_timebase_info_data_t()
    mach_timebase_info(&timebase)
    let continuousNanoseconds = Double(mach_continuous_time())
        * Double(timebase.numer)
        / Double(timebase.denom)

    var bootTime = timeval()
    var bootTimeSize = MemoryLayout<timeval>.size
    let bootStatus = sysctlbyname("kern.boottime", &bootTime, &bootTimeSize, nil, 0)
    let bootIdentifier = bootStatus == 0
        ? "\(bootTime.tv_sec):\(bootTime.tv_usec)"
        : nil

    return PomodoroClockReading(
        wallDate: wallDate,
        bootIdentifier: bootIdentifier,
        continuousSeconds: continuousNanoseconds / 1_000_000_000
    )
}
