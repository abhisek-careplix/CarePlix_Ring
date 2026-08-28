package com.careplix.ringprovisioner

import android.app.Application
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.careplix.ringprovisioner.ble.DeviceId
import com.careplix.ringprovisioner.ble.GattSnapshot
import com.careplix.ringprovisioner.ble.RingNaming
import com.careplix.ringprovisioner.ble.RingProvisioner
import com.careplix.ringprovisioner.ble.rename.GapNameStrategy
import com.careplix.ringprovisioner.ble.rename.RenameOutcome
import com.careplix.ringprovisioner.ble.rename.RenameStrategy
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class ProvisionUiState(
    val rawInput: String = "",
    val deviceId: DeviceId? = null,
    val useSuffixedName: Boolean = true,
    val busy: Boolean = false,
    val log: List<String> = emptyList(),
    val snapshot: GattSnapshot? = null,
    val outcome: RenameOutcome? = null,
    val error: String? = null,
) {

    /** The name that will actually be written, given the current input and naming toggle. */
    val targetName: String
        get() = deviceId
            ?.takeIf { useSuffixedName }
            ?.let { RingNaming.suffixed(it) }
            ?: RingNaming.plain()

    val canAct: Boolean get() = deviceId is DeviceId.Mac && !busy

    /**
     * A scanned serial is accepted and displayed, but cannot drive a scan filter -- Android
     * needs a MAC to address a specific peripheral.
     */
    val serialNotAddressable: Boolean get() = deviceId is DeviceId.Serial
}

class ProvisionViewModel(app: Application) : AndroidViewModel(app) {

    private val adapter: BluetoothAdapter? =
        (app.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    private val provisioner: RingProvisioner? =
        adapter?.let { RingProvisioner(app.applicationContext, it) }

    private val _state = MutableStateFlow(ProvisionUiState())
    val state: StateFlow<ProvisionUiState> = _state.asStateFlow()

    /** Strategies attempted, in order. Extend this once the vendor command set is known. */
    private val strategies: List<RenameStrategy> = listOf(GapNameStrategy())

    fun onInputChanged(input: String) {
        _state.update {
            it.copy(rawInput = input, deviceId = DeviceId.parse(input), error = null)
        }
    }

    /** Called by the barcode screen; the scanned payload replaces whatever was typed. */
    fun onCodeScanned(payload: String) = onInputChanged(payload)

    fun onSuffixToggled(enabled: Boolean) {
        _state.update { it.copy(useSuffixedName = enabled) }
    }

    fun clear() {
        _state.value = ProvisionUiState()
    }

    fun runDiagnostics() {
        val address = (state.value.deviceId as? DeviceId.Mac)?.value ?: return
        val provisioner = provisioner ?: return failBluetoothUnavailable()

        viewModelScope.launch {
            _state.update {
                it.copy(busy = true, error = null, snapshot = null, outcome = null, log = emptyList())
            }
            appendLog("Connecting to $address")
            runCatching { provisioner.diagnose(address) }
                .onSuccess { snapshot ->
                    appendLog("Discovered ${snapshot.services.size} services")
                    appendLog("GAP name writable: ${snapshot.isGapNameWritable}")
                    _state.update { it.copy(busy = false, snapshot = snapshot) }
                }
                .onFailure { error ->
                    _state.update {
                        it.copy(busy = false, error = error.message ?: "Diagnostics failed")
                    }
                }
        }
    }

    fun renameToLoop() {
        val address = (state.value.deviceId as? DeviceId.Mac)?.value ?: return
        val provisioner = provisioner ?: return failBluetoothUnavailable()
        val newName = state.value.targetName

        viewModelScope.launch {
            _state.update { it.copy(busy = true, error = null, outcome = null, log = emptyList()) }
            runCatching {
                provisioner.rename(address, newName, strategies, onProgress = ::appendLog)
            }
                .onSuccess { outcome ->
                    appendLog(outcome.message)
                    _state.update { it.copy(busy = false, outcome = outcome) }
                }
                .onFailure { error ->
                    _state.update {
                        it.copy(busy = false, error = error.message ?: "Rename failed")
                    }
                }
        }
    }

    private fun failBluetoothUnavailable() {
        _state.update { it.copy(busy = false, error = "This device has no usable Bluetooth adapter") }
    }

    private fun appendLog(line: String) {
        _state.update { it.copy(log = it.log + line) }
    }
}
