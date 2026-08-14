package fest.swingbuzz.terminal.data

import fest.swingbuzz.terminal.domain.BraceletID
import fest.swingbuzz.terminal.domain.SampleData
import fest.swingbuzz.terminal.domain.SimulatedBracelet
import kotlinx.coroutines.delay

/**
 * Reads a bracelet's NFC chip.
 *
 * Split out behind an interface for a practical reason, and the reason differs
 * slightly from the iOS one. There, Core NFC does not exist on the Simulator at
 * all. Here, `android.nfc` exists but an emulator has no chip to present, and
 * the reading itself is an Activity-lifecycle affair (`enableReaderMode`) that
 * has no business inside a screen. Keeping the reader abstract means the whole
 * app is developable on a laptop, and the real `NfcBraceletReader` arrives
 * without touching a screen.
 */
interface BraceletReader {
    /**
     * Whether this device can actually read a chip. Drives whether the design's
     * prototype-only "simulate a bracelet" panel is offered.
     */
    val isHardwareBacked: Boolean

    /**
     * Bracelets the operator can pick from when there is no hardware.
     * Empty on a real reader.
     */
    val simulatedOptions: List<SimulatedBracelet>

    /**
     * Wait for a chip and return its id.
     *
     * @param selection which fixture bracelet the operator tapped in the
     *   prototype panel. A hardware reader ignores this and waits for a real
     *   chip instead.
     * @throws ScanCancelled if the operator cancels the scan sheet.
     */
    suspend fun read(selection: BraceletID?): BraceletID
}

/** The operator dismissed the scan sheet before a chip was read. */
class ScanCancelled : Exception("Scan cancelled.")

/**
 * The reader used until real NFC lands: the operator taps one of the five
 * fixture bracelets and a short delay stands in for the chip handshake.
 */
class SimulatedBraceletReader(
    /** The handshake delay, matching the prototype's 950 ms. */
    private val readDuration: Long = 950L,
) : BraceletReader {

    override val isHardwareBacked = false
    override val simulatedOptions: List<SimulatedBracelet> = SampleData.simulatedBracelets

    override suspend fun read(selection: BraceletID?): BraceletID {
        if (selection == null) throw ScanCancelled()
        delay(readDuration)
        return selection
    }
}
