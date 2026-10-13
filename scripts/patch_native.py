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

# Bind synchronously so the UI only reports success after the UDP socket opens.
p=Path('Dependencies/em_proxy/src/lib.rs')
s=p.read_text()
if '-> Option<Sender<()>>' not in s:
    s=s.replace('pub fn start_loopback(bind_addr: SocketAddrV4) -> Sender<()> {', 'pub fn start_loopback(bind_addr: SocketAddrV4) -> Option<Sender<()>> {')
    a=s.index('    std::thread::spawn(move || {')
    b=s.index('        let mut ready = false;',a)
    s=s[:a]+"    let mut socket = std::net::UdpSocket::bind(bind_addr).ok()?;\n    std::thread::spawn(move || {\n"+s[b:]
    s=s.replace('    tx\n}', '    Some(tx)\n}')
    s=s.replace('    let handle = start_loopback(address);', '    let handle = match start_loopback(address) { Some(h) => h, None => return -4 };')
    s=s.replace('socket.send_to(b, endpoint).unwrap();', 'let _ = socket.send_to(b, endpoint);')
    s=s.replace('                            // Swap bytes 12-15 with 16-19', '                            if b.len() < 20 || b[0] >> 4 != 4 { continue; }\n                            // Swap bytes 12-15 with 16-19')
    s=s.replace('panic!("IPv6 not supported");', '// IPv6 is not routed by the exported client configuration.')
    p.write_text(s)
