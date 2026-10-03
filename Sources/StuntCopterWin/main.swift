import CStuntCopterWin
import WinSDK

_ = sc_set_dpi_aware()
sc_begin_fine_timer()
do {
    let app = try App()
    app.run()
} catch {
    "\(error)".withCString(encodedAs: UTF16.self) { text in
        "StuntCopter".withCString(encodedAs: UTF16.self) { title in
            _ = MessageBoxW(nil, text, title, UINT(MB_ICONERROR))
        }
    }
}
sc_end_fine_timer()
