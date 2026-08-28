package com.careplix.ringprovisioner.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Divider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.careplix.ringprovisioner.ProvisionUiState
import com.careplix.ringprovisioner.ble.DeviceId

@Composable
fun ProvisionScreen(
    state: ProvisionUiState,
    onInputChanged: (String) -> Unit,
    onScanRequested: () -> Unit,
    onSuffixToggled: (Boolean) -> Unit,
    onDiagnose: () -> Unit,
    onRename: () -> Unit,
    onClear: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("Ring Provisioner", style = MaterialTheme.typography.headlineSmall)

        OutlinedTextField(
            value = state.rawInput,
            onValueChange = onInputChanged,
            label = { Text("Ring MAC or hardware ID") },
            placeholder = { Text("AA:BB:CC:DD:EE:FF") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
            modifier = Modifier.fillMaxWidth(),
        )

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = onScanRequested, enabled = !state.busy) {
                Text("Scan code")
            }
            OutlinedButton(onClick = onClear, enabled = !state.busy) {
                Text("Clear")
            }
        }

        when (val id = state.deviceId) {
            is DeviceId.Mac -> Text(
                "Parsed MAC: ${id.value}",
                style = MaterialTheme.typography.bodyMedium,
            )

            is DeviceId.Serial -> Text(
                "Parsed as serial \"${id.value}\". Android can only address a ring by MAC, so " +
                    "this cannot be provisioned directly -- scan the MAC label instead.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.error,
            )

            null -> Unit
        }

        Divider()

        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text("Append MAC suffix", style = MaterialTheme.typography.bodyLarge)
                Text(
                    "Keeps rings distinguishable in a Bluetooth picker",
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            Switch(
                checked = state.useSuffixedName,
                onCheckedChange = onSuffixToggled,
                enabled = !state.busy,
            )
        }

        Text(
            "Will write name: ${state.targetName}",
            style = MaterialTheme.typography.titleMedium,
        )

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = onDiagnose, enabled = state.canAct) {
                Text("Run diagnostics")
            }
            Button(onClick = onRename, enabled = state.canAct) {
                Text("Rename")
            }
        }

        if (state.busy) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                CircularProgressIndicator()
                Text("Working...")
            }
        }

        state.error?.let { error ->
            Card(modifier = Modifier.fillMaxWidth()) {
                Text(
                    text = error,
                    modifier = Modifier.padding(12.dp),
                    color = MaterialTheme.colorScheme.error,
                )
            }
        }

        state.outcome?.let { outcome ->
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Text(
                        if (outcome.succeeded) "Rename verified" else "Rename not verified",
                        style = MaterialTheme.typography.titleMedium,
                        color = if (outcome.succeeded) {
                            MaterialTheme.colorScheme.primary
                        } else {
                            MaterialTheme.colorScheme.error
                        },
                    )
                    Text("Strategy: ${outcome.strategyId}")
                    Text("Requested: ${outcome.requestedName}")
                    Text("Now advertising: ${outcome.observedAdvertisedName ?: "(not seen)"}")
                    Text(outcome.message, style = MaterialTheme.typography.bodySmall)
                }
            }
        }

        if (state.log.isNotEmpty()) {
            Text("Log", style = MaterialTheme.typography.titleMedium)
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(12.dp)) {
                    state.log.forEach { line ->
                        Text(
                            line,
                            style = MaterialTheme.typography.bodySmall,
                            fontFamily = FontFamily.Monospace,
                        )
                    }
                }
            }
        }

        state.snapshot?.let { snapshot ->
            Text("GATT report", style = MaterialTheme.typography.titleMedium)
            Card(modifier = Modifier.fillMaxWidth()) {
                Text(
                    text = snapshot.toReport(),
                    modifier = Modifier.padding(12.dp),
                    style = MaterialTheme.typography.bodySmall,
                    fontFamily = FontFamily.Monospace,
                )
            }
        }
    }
}
