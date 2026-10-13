"""Narrow compatibility patches to pinned native sources; keep vendored history intact."""
from pathlib import Path
p=Path('Dependencies/minimuxer/src/lib.rs')
s=p.read_text()
start=s.index('pub fn fetch_first_device(')
end=s.index('\n/// Tests if the device',start)
s=s[:start]+'''pub fn fetch_first_device(timeout: Option<u16>) -> Result<Device, IdeviceError> {
    let deadline = timeout.map(|milliseconds| {
        std::time::Instant::now() + Duration::from_millis(u64::from(milliseconds))
    });
    loop {
        if let Ok(device) = idevice::get_first_device() {
            return Ok(device);
        }
        if let Some(deadline) = deadline {
            if std::time::Instant::now() >= deadline {
                return Err(IdeviceError::NoDevice);
            }
        }
        std::thread::sleep(Duration::from_millis(10));
    }
}
''' + s[end:]
p.write_text(s)
