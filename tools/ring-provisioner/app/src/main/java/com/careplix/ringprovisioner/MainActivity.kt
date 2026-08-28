package com.careplix.ringprovisioner

import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.careplix.ringprovisioner.ui.BarcodeScannerScreen
import com.careplix.ringprovisioner.ui.ProvisionScreen
import com.google.accompanist.permissions.ExperimentalPermissionsApi
import com.google.accompanist.permissions.isGranted
import com.google.accompanist.permissions.rememberMultiplePermissionsState
import com.google.accompanist.permissions.rememberPermissionState
import com.google.accompanist.permissions.shouldShowRationale

class MainActivity : ComponentActivity() {

    private val viewModel: ProvisionViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    AppRoot(viewModel)
                }
            }
        }
    }
}

@OptIn(ExperimentalPermissionsApi::class)
@Composable
private fun AppRoot(viewModel: ProvisionViewModel) {
    val state by viewModel.state.collectAsState()
    var scanning by remember { mutableStateOf(false) }

    // The BLE permission set changed at API 31. Requesting the wrong one for the running
    // release gets silently denied, so the split is by build version rather than by feature.
    val blePermissions = remember {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            listOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            listOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }
    }
    val bleState = rememberMultiplePermissionsState(blePermissions)
    val cameraState = rememberPermissionState(Manifest.permission.CAMERA)

    when {
        !bleState.allPermissionsGranted -> PermissionGate(
            message = if (bleState.shouldShowRationale) {
                "Bluetooth permission is required to find and configure a ring."
            } else {
                "This tool needs Bluetooth permission to talk to rings."
            },
            onGrant = { bleState.launchMultiplePermissionRequest() },
        )

        scanning && !cameraState.status.isGranted -> PermissionGate(
            message = "Camera permission is required to read the QR code on the ring's label.",
            onGrant = { cameraState.launchPermissionRequest() },
        )

        scanning -> BarcodeScannerScreen(
            onCodeScanned = { payload ->
                viewModel.onCodeScanned(payload)
                scanning = false
            },
            onCancel = { scanning = false },
        )

        else -> ProvisionScreen(
            state = state,
            onInputChanged = viewModel::onInputChanged,
            onScanRequested = { scanning = true },
            onSuffixToggled = viewModel::onSuffixToggled,
            onDiagnose = viewModel::runDiagnostics,
            onRename = viewModel::renameToLoop,
            onClear = viewModel::clear,
        )
    }
}

@Composable
private fun PermissionGate(message: String, onGrant: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(message, style = MaterialTheme.typography.bodyLarge)
        Button(onClick = onGrant) { Text("Grant permission") }
    }
}
