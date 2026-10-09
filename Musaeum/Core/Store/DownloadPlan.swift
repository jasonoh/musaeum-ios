/// Which file the phone asks the Mac for. **One rule, trusting the Mac's own** (`reflow.available`, which the
/// server derives as "a PDF and no EPUB"): the phone does not re-derive it from `formats`, as it does not
/// re-derive `formats`' preference order.
enum DownloadPlan: Equatable, Sendable {
    case reflow
    case format(String)

    static func of(_ book: ContractBook) -> DownloadPlan? {
        if book.reflow.available { return .reflow }
        return book.preferredFormat.map(DownloadPlan.format)
    }
}
