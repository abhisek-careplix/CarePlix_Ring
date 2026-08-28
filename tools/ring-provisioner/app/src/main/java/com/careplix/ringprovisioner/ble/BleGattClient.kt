package com.careplix.ringprovisioner.ble

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.os.Build
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeout
import java.util.UUID
import java.util.concurrent.atomic.AtomicReference
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class BleException(message: String, val status: Int? = null) : Exception(
    if (status == null) message else "$message (status=$status)"
)

/**
 * Coroutine wrapper over [BluetoothGatt].
 *
 * The Android GATT stack allows exactly one outstanding operation per connection. Issuing a
 * second read/write/descriptor-write before the previous callback fires does not error -- it
 * returns false or is dropped, and the caller hangs. Every public operation here therefore
 * runs under [operationLock], and each one is individually timed out so a device that never
 * answers surfaces as a failure instead of a stuck screen.
 *
 * Not reusable: after [close] the instance is dead. Build a new one per connection.
 */
@SuppressLint("MissingPermission")
class BleGattClient(
    private val context: Context,
    private val device: BluetoothDevice,
) {

    private val operationLock = Mutex()
    private val gattRef = AtomicReference<BluetoothGatt?>(null)

    private val connectionCont = AtomicReference<CancellableContinuation<Unit>?>(null)
    private val servicesCont = AtomicReference<CancellableContinuation<List<BluetoothGattService>>?>(null)
    private val readCont = AtomicReference<CancellableContinuation<ByteArray>?>(null)
    private val writeCont = AtomicReference<CancellableContinuation<Unit>?>(null)
    private val descriptorCont = AtomicReference<CancellableContinuation<Unit>?>(null)
    private val mtuCont = AtomicReference<CancellableContinuation<Int>?>(null)

    private val _notifications = MutableSharedFlow<Notification>(
        replay = 0,
        extraBufferCapacity = 32,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )

    /** Every notification/indication the peripheral pushes, from any characteristic. */
    val notifications: SharedFlow<Notification> = _notifications

    data class Notification(val characteristic: UUID, val value: ByteArray) {
        override fun equals(other: Any?): Boolean =
            other is Notification &&
                characteristic == other.characteristic &&
                value.contentEquals(other.value)

        override fun hashCode(): Int = 31 * characteristic.hashCode() + value.contentHashCode()
    }

    val address: String get() = device.address

    /**
     * Opens a GATT connection. Always uses `autoConnect = false`: a provisioning tool wants a
     * fast, deterministic failure when the ring is not in range, not an indefinite background
     * retry.
     */
    suspend fun connect(timeoutMs: Long = CONNECT_TIMEOUT_MS) = operationLock.withLock {
        awaitOperation(connectionCont, timeoutMs, "connect") {
            val gatt = device.connectGatt(context, false, callback, BluetoothDevice.TRANSPORT_LE)
                ?: throw BleException("connectGatt returned null")
            gattRef.set(gatt)
        }
    }

    suspend fun discoverServices(
        timeoutMs: Long = OPERATION_TIMEOUT_MS,
    ): List<BluetoothGattService> = operationLock.withLock {
        val gatt = requireGatt()
        awaitOperation(servicesCont, timeoutMs, "discoverServices") {
            if (!gatt.discoverServices()) throw BleException("discoverServices rejected")
        }
    }

    /**
     * Negotiates a larger MTU. Failure is not fatal -- the caller falls back to the 20-byte
     * default payload -- so this returns the MTU actually in force rather than throwing.
     */
    suspend fun requestMtu(mtu: Int, timeoutMs: Long = OPERATION_TIMEOUT_MS): Int =
        operationLock.withLock {
            val gatt = requireGatt()
            runCatching {
                awaitOperation(mtuCont, timeoutMs, "requestMtu") {
                    if (!gatt.requestMtu(mtu)) throw BleException("requestMtu rejected")
                }
            }.getOrDefault(DEFAULT_MTU)
        }

    suspend fun read(
        characteristic: BluetoothGattCharacteristic,
        timeoutMs: Long = OPERATION_TIMEOUT_MS,
    ): ByteArray = operationLock.withLock {
        val gatt = requireGatt()
        awaitOperation(readCont, timeoutMs, "read ${characteristic.uuid}") {
            if (!gatt.readCharacteristic(characteristic)) throw BleException("read rejected")
        }
    }

    suspend fun write(
        characteristic: BluetoothGattCharacteristic,
        value: ByteArray,
        writeType: Int = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT,
        timeoutMs: Long = OPERATION_TIMEOUT_MS,
    ) = operationLock.withLock {
        val gatt = requireGatt()
        awaitOperation(writeCont, timeoutMs, "write ${characteristic.uuid}") {
            val accepted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                gatt.writeCharacteristic(characteristic, value, writeType) ==
                    BluetoothStatusCodes_SUCCESS
            } else {
                @Suppress("DEPRECATION")
                characteristic.value = value
                @Suppress("DEPRECATION")
                characteristic.writeType = writeType
                @Suppress("DEPRECATION")
                gatt.writeCharacteristic(characteristic)
            }
            if (!accepted) throw BleException("write rejected")
        }
    }

    /**
     * Subscribes to a characteristic. Both halves are required: the local registration tells
     * the Android stack to deliver callbacks, the CCCD write tells the peripheral to send.
     * Skipping the descriptor write is the classic reason notifications never arrive.
     */
    suspend fun enableNotifications(
        characteristic: BluetoothGattCharacteristic,
        timeoutMs: Long = OPERATION_TIMEOUT_MS,
    ) = operationLock.withLock {
        val gatt = requireGatt()
        if (!gatt.setCharacteristicNotification(characteristic, true)) {
            throw BleException("setCharacteristicNotification rejected")
        }
        val cccd = characteristic.getDescriptor(BleUuids.CCCD)
            ?: throw BleException("characteristic has no CCCD; cannot subscribe")

        val isIndication =
            characteristic.properties and BluetoothGattCharacteristic.PROPERTY_INDICATE != 0
        val enableValue = if (isIndication) {
            BluetoothGattDescriptor.ENABLE_INDICATION_VALUE
        } else {
            BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
        }

        awaitOperation(descriptorCont, timeoutMs, "cccd write") {
            val accepted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                gatt.writeDescriptor(cccd, enableValue) == BluetoothStatusCodes_SUCCESS
            } else {
                @Suppress("DEPRECATION")
                cccd.value = enableValue
                @Suppress("DEPRECATION")
                gatt.writeDescriptor(cccd)
            }
            if (!accepted) throw BleException("descriptor write rejected")
        }
    }

    fun findCharacteristic(service: UUID, characteristic: UUID): BluetoothGattCharacteristic? =
        gattRef.get()?.getService(service)?.getCharacteristic(characteristic)

    fun close() {
        gattRef.getAndSet(null)?.let { gatt ->
            runCatching { gatt.disconnect() }
            runCatching { gatt.close() }
        }
        failPending(BleException("client closed"))
    }

    private fun requireGatt(): BluetoothGatt =
        gattRef.get() ?: throw BleException("not connected")

    /**
     * Parks the caller on [slot] until the matching GATT callback resumes it, having first run
     * [start] to issue the request. If [start] throws, the slot is cleared so the next
     * operation is not poisoned; on timeout the same cleanup runs and a [BleException] is
     * raised rather than a bare cancellation.
     */
    private suspend fun <T> awaitOperation(
        slot: AtomicReference<CancellableContinuation<T>?>,
        timeoutMs: Long,
        label: String,
        start: () -> Unit,
    ): T = try {
        withTimeout(timeoutMs) {
            suspendCancellableCoroutine { cont ->
                if (!slot.compareAndSet(null, cont)) {
                    cont.resumeWithException(BleException("$label: operation already in flight"))
                    return@suspendCancellableCoroutine
                }
                cont.invokeOnCancellation { slot.compareAndSet(cont, null) }
                try {
                    start()
                } catch (t: Throwable) {
                    if (slot.compareAndSet(cont, null)) cont.resumeWithException(t)
                }
            }
        }
    } catch (e: TimeoutCancellationException) {
        slot.set(null)
        throw BleException("$label timed out after ${timeoutMs}ms")
    }

    private fun <T> AtomicReference<CancellableContinuation<T>?>.complete(value: T, status: Int) {
        val cont = getAndSet(null) ?: return
        if (status == BluetoothGatt.GATT_SUCCESS) {
            cont.resume(value)
        } else {
            cont.resumeWithException(BleException("GATT operation failed", status))
        }
    }

    private fun failPending(error: Throwable) {
        listOf(connectionCont, servicesCont, readCont, writeCont, descriptorCont, mtuCont)
            .forEach { slot ->
                @Suppress("UNCHECKED_CAST")
                val cont = (slot as AtomicReference<CancellableContinuation<Any?>?>).getAndSet(null)
                cont?.takeIf { it.isActive }?.resumeWithException(error)
            }
    }

    private val callback = object : BluetoothGattCallback() {

        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            when (newState) {
                BluetoothProfile.STATE_CONNECTED -> connectionCont.complete(Unit, status)
                BluetoothProfile.STATE_DISCONNECTED -> {
                    // Covers both a failed connect attempt and a mid-session drop. Either way
                    // every parked caller must be released or the UI hangs.
                    failPending(BleException("disconnected", status))
                    runCatching { gatt.close() }
                    gattRef.compareAndSet(gatt, null)
                }
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            servicesCont.complete(gatt.services.orEmpty(), status)
        }

        override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
            mtuCont.complete(mtu, status)
        }

        // API 33+ delivers the value as a parameter; older releases require reading
        // characteristic.value inside the callback, before the stack recycles it.
        override fun onCharacteristicRead(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
            status: Int,
        ) {
            readCont.complete(value, status)
        }

        @Deprecated("Required for API < 33")
        @Suppress("DEPRECATION")
        override fun onCharacteristicRead(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                readCont.complete(characteristic.value ?: ByteArray(0), status)
            }
        }

        override fun onCharacteristicWrite(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
            writeCont.complete(Unit, status)
        }

        override fun onDescriptorWrite(
            gatt: BluetoothGatt,
            descriptor: BluetoothGattDescriptor,
            status: Int,
        ) {
            descriptorCont.complete(Unit, status)
        }

        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
        ) {
            _notifications.tryEmit(Notification(characteristic.uuid, value))
        }

        @Deprecated("Required for API < 33")
        @Suppress("DEPRECATION")
        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
        ) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                val value = characteristic.value ?: ByteArray(0)
                _notifications.tryEmit(Notification(characteristic.uuid, value))
            }
        }
    }

    private companion object {
        const val CONNECT_TIMEOUT_MS = 15_000L
        const val OPERATION_TIMEOUT_MS = 10_000L
        const val DEFAULT_MTU = 23

        /** `BluetoothStatusCodes.SUCCESS`, inlined to avoid an API 33 reference on older builds. */
        const val BluetoothStatusCodes_SUCCESS = 0
    }
}
