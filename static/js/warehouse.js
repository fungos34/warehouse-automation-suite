
let currentTransferOrderId = null;
let transferOrderLines = [];

async function loadWarehouseItems() {
    const items = await fetch('/warehouse-items', {
    headers: { Authorization: 'Bearer ' + jwtToken }
    }).then(r => r.json());
    const select = document.getElementById('transfer-item-select');
    select.innerHTML = '';
    items.forEach(item => {
    const opt = document.createElement('option');
    opt.value = item.id;
    opt.textContent = `${item.sku} ${item.name} (Stock: ${item.total_quantity})`;
    select.appendChild(opt);
    });
};



async function loadTargetZones() {
    const resp = await fetch('/location-zones', { headers: { Authorization: 'Bearer ' + jwtToken } });
    const zones = await resp.json();
    const select = document.getElementById('transfer-target-zone');
    select.innerHTML = '';
    // Filter out vendor/customer zones
    zones
    .filter(z => !['ZON08', 'ZON09'].includes(z.zone_code))
    .forEach(z => {
        const opt = document.createElement('option');
        opt.value = z.zone_id;
        opt.textContent = `${z.zone_code} - ${z.zone_description}`;
        select.appendChild(opt);
    });
};


async function addTransferOrderLine() {
    const transferOrderId = await getOrCreateTransferOrderId();
    const item_id = document.getElementById('transfer-item-select').value;
    const quantity = document.getElementById('transfer-quantity').value;
    const target_zone_id = document.getElementById('transfer-target-zone').value;
    const route_id = 1; // or select as needed
    await fetch(`/transfer-orders/${transferOrderId}/lines`, {
    method: 'POST',
    headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer ' + jwtToken
    },
    body: JSON.stringify([
        { item_id, quantity, target_zone_id }
        // add more lines if needed
    ])
    });
    // Update UI
    transferOrderLines.push({ item_id, quantity, target_zone_id });
    // renderTransferOrderLines();
    fetchAndRenderTransferOrderLines();
};


async function fetchAndRenderTransferOrderLines() {
    if (!currentTransferOrderId) {
    document.getElementById('transfer-order-lines').innerHTML = '<i>No transfer order started.</i>';
    return;
    }
    const resp = await fetch(`/transfer-orders/${currentTransferOrderId}/lines`, {
    headers: { Authorization: 'Bearer ' + jwtToken }
    });
    if (!resp.ok) {
    document.getElementById('transfer-order-lines').innerHTML = '<i>Error loading lines.</i>';
    return;
    }
    const lines = await resp.json();
    if (!lines.length) {
    document.getElementById('transfer-order-lines').innerHTML = '<i>No lines yet.</i>';
    return;
    }
    // Optionally fetch items and zones for better display
    const [items, zones] = await Promise.all([
    fetch('/items', { headers: { Authorization: 'Bearer ' + jwtToken } }).then(r => r.json()),
    fetch('/location-zones', { headers: { Authorization: 'Bearer ' + jwtToken } }).then(r => r.json())
    ]);
    const itemMap = Object.fromEntries(items.map(i => [i.id, i]));
    const zoneMap = Object.fromEntries(zones.map(z => [z.zone_id, z]));
    document.getElementById('transfer-order-lines').innerHTML =
    '<ul>' + lines.map(line => {
        const item = itemMap[line.item_id] || {};
        const zone = zoneMap[line.target_zone_id] || {};
        return `<li>
        ${item.sku || ''} ${item.name || ''} (${line.quantity}) → ${zone.zone_code || line.target_zone_id}
        </li>`;
    }).join('') + '</ul>';
};


async function confirmTransferOrder() {
    if (currentTransferOrderId) {
    await fetch(`/transfer-orders/${currentTransferOrderId}/confirm`, { method: 'POST', headers: { Authorization: 'Bearer ' + jwtToken } });
    // Optionally show a message in the panel instead of alert
    document.getElementById('transfer-order-lines').innerHTML = '<i>Transfer order confirmed!</i>';
    currentTransferOrderId = null;
    transferOrderLines = [];
    // Optionally refresh warehouse items or transfer order list here
    }
};



async function populateMoveLineSelect() {
    // Add this fetch in parallel with items and locations
    const [moveLines, items, locations, lots] = await Promise.all([
        fetch('/move-lines', { headers: { Authorization: 'Bearer ' + jwtToken } }).then(r => r.json()),
        fetch('/items', { headers: { Authorization: 'Bearer ' + jwtToken } }).then(r => r.json()),
        fetch('/locations', { headers: { Authorization: 'Bearer ' + jwtToken } }).then(r => r.json()),
        fetch('/lots', { headers: { Authorization: 'Bearer ' + jwtToken } }).then(r => r.json())
    ]);
    const lotMap = Object.fromEntries(lots.map(l => [l.id, l.lot_number]));
    const itemMap = Object.fromEntries(items.map(i => [i.id, i]));
    const locMap = Object.fromEntries(locations.map(l => [l.id, l]));
    const select = document.getElementById('move-line-select');
    select.innerHTML = '';
    moveLines
        .filter(line => line.status !== 'done')
        .forEach(line => {
        const item = itemMap[line.item_id] || {};
        const src = locMap[line.source_id] || {};
        const tgt = locMap[line.target_id] || {};
        const lotLabel = line.lot_id && lotMap[line.lot_id] ? ` [Lot: ${lotMap[line.lot_id]}]` : '';
        const label = `${item.sku || ''} ${item.name || ''} (${line.quantity})${lotLabel} — ${src.code || line.source_id} → ${tgt.code || line.target_id}`;
        const opt = document.createElement('option');
        opt.value = line.id;
        opt.textContent = label;
        select.appendChild(opt);
    });
};
async function populatePickingSelect() {
    // Fetch pickings and zones in parallel
    const [pickings, zones] = await Promise.all([
        fetch('/pickings', { headers: { Authorization: 'Bearer ' + jwtToken } }).then(r => r.json()),
        fetch('/zones', { headers: { Authorization: 'Bearer ' + jwtToken } }).then(r => r.json())
    ]);
    const zoneMap = Object.fromEntries(zones.map(z => [z.id, z.code]));
    const select = document.getElementById('picking-select');
    select.innerHTML = '';

    // Fetch move lines for all pickings in parallel
    const moveLinesList = await Promise.all(
        pickings.map(p =>
            fetch(`/pickings/${p.id}/move-lines`, { headers: { Authorization: 'Bearer ' + jwtToken } })
                .then(r => r.ok ? r.json() : [])
                .then(lines => ({
                    picking: p,
                    hasOpenLines: lines.some(line => line.status !== 'done')
                }))
        )
    );

    // Filter pickings to only those with open move lines
    const pickingsWithLines = moveLinesList
        .filter(entry => entry.hasOpenLines)
        .map(entry => entry.picking);

    pickingsWithLines.forEach(p => {
        const srcCode = zoneMap[p.source_id] || p.source_id;
        const tgtCode = zoneMap[p.target_id] || p.target_id;
        const opt = document.createElement('option');
        opt.value = p.id;
        opt.textContent = `#${p.id}: ${p.type} (${p.status}) [${srcCode}→${tgtCode}]`;
        select.appendChild(opt);
    });

    // Auto-load move lines for the first picking
    if (pickingsWithLines.length) {
        await populateMoveLineSelectByPicking(pickingsWithLines[0].id);
    } else {
        document.getElementById('move-line-select').innerHTML = '';
    }
};

async function populateMoveLineSelectByPicking(pickingId) {
    const [moveLines, items, locations] = await Promise.all([
        fetch(`/pickings/${pickingId}/move-lines`, { headers: { Authorization: 'Bearer ' + jwtToken } }).then(r => r.json()),
        fetch('/items', { headers: { Authorization: 'Bearer ' + jwtToken } }).then(r => r.json()),
        fetch('/locations', { headers: { Authorization: 'Bearer ' + jwtToken } }).then(r => r.json())
    ]);
    const itemMap = Object.fromEntries(items.map(i => [i.id, i]));
    const locMap = Object.fromEntries(locations.map(l => [l.id, l]));
    const select = document.getElementById('move-line-select');
    select.innerHTML = '';
    moveLines
        .filter(line => line.status !== 'done')
        .forEach(line => {
        const item = itemMap[line.item_id] || {};
        const src = locMap[line.source_id] || {};
        const tgt = locMap[line.target_id] || {};
        const lotLabel = line.lot_number ? ` [Lot: ${line.lot_number}]` : '';
        const label = `${item.sku || ''} ${item.name || ''} (${line.quantity})${lotLabel} — ${src.code || line.source_id} → ${tgt.code || line.target_id}`;
        const opt = document.createElement('option');
        opt.value = line.id;
        opt.textContent = label;
        select.appendChild(opt);
        });
};

async function loadInterventions() {
    const resp = await fetch('/interventions', { headers: { Authorization: 'Bearer ' + jwtToken } });
    const interventions = await resp.json();
    const unresolved = interventions.filter(i => !i.resolved);
    const div = document.getElementById('interventions');
    if (!unresolved.length) {
    div.innerHTML = '<i>No unresolved interventions.</i>';
    return;
    }
    div.innerHTML = '<ul>' + unresolved.map(i =>
    `<li>
        Move #${i.move_id}: ${i.reason}
    </li>`
    ).join('') + '</ul>';
};


async function getOrCreateTransferOrderId() {
    if (currentTransferOrderId) return currentTransferOrderId;
    // Try to find an existing draft transfer order
    const resp = await fetch('/transfer-orders?status=draft', {
    headers: { Authorization: 'Bearer ' + jwtToken }
    });
    const orders = await resp.json();
    if (orders.length > 0) {
    currentTransferOrderId = orders[0].id;
    return currentTransferOrderId;
    }
    // Otherwise, create a new one
    const createResp = await fetch('/transfer-orders/', { 
    method: 'POST', 
    body: JSON.stringify({ partner_id: 1 }), 
    headers: { 
        'Content-Type': 'application/json',
        Authorization: 'Bearer ' + jwtToken
    } 
    });
    currentTransferOrderId = (await createResp.json()).transfer_order_id;
    await fetchAndRenderTransferOrderLines();
    return currentTransferOrderId;
};

function renderTransferOrderLines() {
    const div = document.getElementById('transfer-order-lines');
    div.innerHTML = transferOrderLines.map(line =>
    `<div>Item: ${line.item_id}, Qty: ${line.quantity}, Target Zone: ${line.target_zone_id}</div>`
    ).join('');
};

// Handle setting move line to done
document.getElementById('move-done-form').onsubmit = async function(e) {
    e.preventDefault();
    const moveId = document.getElementById('move-line-select').value;
    const pickingSelect = document.getElementById('picking-select');
    const selectedPickingId = pickingSelect.value;
    try {
        const resp = await fetch(`/move-lines/${moveId}/done`, {
            method: 'POST',
            headers: { Authorization: 'Bearer ' + jwtToken }
        });
        const data = await resp.json();
        document.getElementById('move-result').textContent = resp.ok ? 'Move set to done!' : data.detail || 'Error';
        // Refresh pickings and move lines, keeping the same picking selected if possible
        await populatePickingSelect();
        // Try to re-select the same picking if it still exists
        const newPickingSelect = document.getElementById('picking-select');
        if ([...newPickingSelect.options].some(opt => opt.value === selectedPickingId)) {
            newPickingSelect.value = selectedPickingId;
            await populateMoveLineSelectByPicking(selectedPickingId);
        }
        // Refresh the 3D warehouse view
        if (typeof fetchAndRender === 'function') {
            fetchAndRender();
        }
    } catch (e) {
        document.getElementById('move-result').textContent = 'Error setting move to done';
    }
};


// Populate items and locations for stock adjustment
async function loadStockAdjustmentSelectors() {
    // Items
    const items = await fetch('/items', { headers: { Authorization: 'Bearer ' + jwtToken } }).then(r => r.json());
    const itemSelect = document.getElementById('adjustment-item-select');
    itemSelect.innerHTML = '';
    items.forEach(item => {
        const opt = document.createElement('option');
        opt.value = item.id;
        opt.textContent = `${item.sku} ${item.name}`;
        itemSelect.appendChild(opt);
    });

    // Locations
    const locations = await fetch('/locations', { headers: { Authorization: 'Bearer ' + jwtToken } }).then(r => r.json());
    const locationSelect = document.getElementById('adjustment-location-select');
    locationSelect.innerHTML = '';
    locations.forEach(loc => {
        const opt = document.createElement('option');
        opt.value = loc.id;
        opt.textContent = `${loc.code} (${loc.description || ''})`;
        locationSelect.appendChild(opt);
    });
};

// Handle stock adjustment form submission
document.getElementById('stock-adjustment-form').onsubmit = async function(e) {
    e.preventDefault();
    const item_id = document.getElementById('adjustment-item-select').value;
    const location_id = document.getElementById('adjustment-location-select').value;
    const delta = document.getElementById('adjustment-delta').value;
    const reason = document.getElementById('adjustment-reason').value;
    try {
        const resp = await fetch('/stock-adjustments/', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                Authorization: 'Bearer ' + jwtToken
            },
            body: JSON.stringify({ item_id, location_id, delta, reason })
        });
        if (resp.ok) {
            document.getElementById('stock-adjustment-result').textContent = 'Stock adjusted!';
            fetchAndRender(); // Optionally refresh the warehouse view
        } else {
            const data = await resp.json();
            document.getElementById('stock-adjustment-result').textContent = data.detail || 'Error adjusting stock';
        }
    } catch (e) {
        document.getElementById('stock-adjustment-result').textContent = 'Error adjusting stock';
    }
};

async function fetchManufacturingOrders() {
    const [mos, items] = await Promise.all([
        fetch('/manufacturing-orders/?status=draft', {
            headers: { Authorization: 'Bearer ' + jwtToken }
        }).then(r => r.json()),
        fetch('/items', { headers: { Authorization: 'Bearer ' + jwtToken } }).then(r => r.json())
    ]);
    const itemMap = Object.fromEntries(items.map(i => [i.id, i]));
    const select = document.getElementById('mo-select');
    if (!select) return; // Prevent error if element is missing
    select.innerHTML = '';
    mos.forEach(mo => {
        const item = itemMap[mo.item_id] || {};
        const opt = document.createElement('option');
        opt.value = mo.id;
        opt.textContent = `#${mo.code} - ${item.sku || ''} ${item.name || ''} x${mo.quantity} (Partner: ${mo.partner_id})`;
        select.appendChild(opt);
    });
}

async function fetchConfirmedManufacturingOrders() {
    const [mos, items] = await Promise.all([
        fetch('/manufacturing-orders/?status=confirmed', {
            headers: { Authorization: 'Bearer ' + jwtToken }
        }).then(r => r.json()),
        fetch('/items', { headers: { Authorization: 'Bearer ' + jwtToken } }).then(r => r.json())
    ]);
    const itemMap = Object.fromEntries(items.map(i => [i.id, i]));
    const select = document.getElementById('mo-select-confirmed');
    if (!select) return; // Prevent error if element is missing
    select.innerHTML = '';
    mos.forEach(mo => {
        const item = itemMap[mo.item_id] || {};
        const opt = document.createElement('option');
        opt.value = mo.id;
        opt.textContent = `#${mo.code} - ${item.sku || ''} ${item.name || ''} x${mo.quantity} (Partner: ${mo.partner_id})`;
        select.appendChild(opt);
    });
}

// Populate BOM items
async function loadManufacturingItems() {
    const items = await fetch('/manufacturing-items', { headers: { Authorization: 'Bearer ' + jwtToken } }).then(r => r.json());
    const select = document.getElementById('mo-item-select');
    select.innerHTML = '';
    items.forEach(item => {
        const opt = document.createElement('option');
        opt.value = item.id;
        opt.textContent = `${item.sku} ${item.name}`;
        select.appendChild(opt);
    });
}
document.getElementById('mo-create-form').onsubmit = async function(e) {
    e.preventDefault();
    const item_id = document.getElementById('mo-item-select').value;
    const quantity = document.getElementById('mo-quantity').value;
    const planned_start = document.getElementById('mo-start').value;
    const planned_end = document.getElementById('mo-end').value;
    const fileInput = document.getElementById('mo-bom-file');
    let bomFile = fileInput.files[0];

    // 1. Create the MO
    const resp = await fetch('/manufacturing-orders/', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + jwtToken },
        body: JSON.stringify({ item_id, quantity, planned_start, planned_end })
    });
    const data = await resp.json();
    if (!resp.ok) {
        document.getElementById('mo-create-result').textContent = data.detail || 'Error';
        return;
    }
    document.getElementById('mo-create-result').textContent = `Created: ${data.code}`;

    // 2. If file selected, upload to BOM
    if (bomFile) {
        // Get BOM id for the selected item
        const itemResp = await fetch(`/items/${item_id}`, { headers: { Authorization: 'Bearer ' + jwtToken } });
        const itemData = await itemResp.json();
        if (itemData.bom_id) {
            const formData = new FormData();
            formData.append('file', bomFile);
            const uploadResp = await fetch(`/bom/${itemData.bom_id}/file`, {
                method: 'POST',
                headers: { Authorization: 'Bearer ' + jwtToken },
                body: formData
            });
            const uploadData = await uploadResp.json();
            document.getElementById('mo-create-result').textContent += uploadResp.ok
                ? ' (BOM file uploaded)'
                : ' (BOM file upload failed)';
        }
    }
};

document.getElementById('mo-done-btn').onclick = async function() {
    const moId = document.getElementById('mo-select-confirmed').value;
    if (!moId) return;
    const resp = await fetch(`/manufacturing-orders/${moId}/done`, {
        method: 'POST',
        headers: { Authorization: 'Bearer ' + jwtToken }
    });
    document.getElementById('mo-result').textContent = (await resp.json()).message;
    fetchManufacturingOrders();
};

// Add a button in your MO details panel:
document.getElementById('mo-download-label-btn').onclick = async function() {
    const moId = document.getElementById('mo-select-confirmed').value;
    if (!moId) return;
    const resp = await fetch(`/manufacturing-orders/${moId}/carrier-label`, {
        headers: { Authorization: 'Bearer ' + jwtToken }
    });
    if (!resp.ok) {
        alert('Carrier label not available');
        return;
    }
    const blob = await resp.blob();
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `carrier_label_MO_${moId}.pdf`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
};

document.getElementById('mo-confirm-btn').onclick = async function() {
    const moId = document.getElementById('mo-select').value;
    if (!moId) return;
    const resp = await fetch(`/manufacturing-orders/${moId}/confirm`, {
        method: 'POST',
        headers: { Authorization: 'Bearer ' + jwtToken }
    });
    document.getElementById('mo-result').textContent = (await resp.json()).message;
    fetchManufacturingOrders();
};

document.getElementById('mo-cancel-btn').onclick = async function() {
    const moId = document.getElementById('mo-select').value;
    if (!moId) return;
    const resp = await fetch(`/manufacturing-orders/${moId}/cancel`, {
        method: 'POST',
        headers: { Authorization: 'Bearer ' + jwtToken }
    });
    document.getElementById('mo-result').textContent = (await resp.json()).message;
    fetchManufacturingOrders();
};

document.getElementById('mo-download-btn').onclick = async function() {
    const moId = document.getElementById('mo-select-all').value;
    if (!moId) return;
    const resp = await fetch(`/manufacturing-orders/${moId}/download`, {
        headers: { Authorization: 'Bearer ' + jwtToken }
    });
    if (!resp.ok) {
        alert('Failed to download MO document');
        return;
    }
    const blob = await resp.blob();
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `MO_${moId}.pdf`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
};

document.getElementById('mo-download-receipt-btn').onclick = async function() {
    const moId = document.getElementById('mo-select-done').value;
    if (!moId) return;
    const resp = await fetch(`/manufacturing-orders/${moId}/receipt`, {
        headers: { Authorization: 'Bearer ' + jwtToken }
    });
    if (!resp.ok) {
        alert('Failed to download manufacturing receipt');
        return;
    }
    const blob = await resp.blob();
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `MO_${moId}_receipt.pdf`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
};

async function fetchAllManufacturingOrders() {
    const [mos, items] = await Promise.all([
        fetch('/manufacturing-orders/', { headers: { Authorization: 'Bearer ' + jwtToken } }).then(r => r.json()),
        fetch('/items', { headers: { Authorization: 'Bearer ' + jwtToken } }).then(r => r.json())
    ]);
    const itemMap = Object.fromEntries(items.map(i => [i.id, i]));
    const select = document.getElementById('mo-select-all');
    if (!select) return;
    select.innerHTML = '';
    mos.forEach(mo => {
        const item = itemMap[mo.item_id] || {};
        const opt = document.createElement('option');
        opt.value = mo.id;
        opt.textContent = `#${mo.code} - ${item.sku || ''} ${item.name || ''} x${mo.quantity} (${mo.status})`;
        select.appendChild(opt);
    });
}

async function fetchDoneManufacturingOrders() {
    const [mos, items] = await Promise.all([
        fetch('/manufacturing-orders/?status=done', {
            headers: { Authorization: 'Bearer ' + jwtToken }
        }).then(r => r.json()),
        fetch('/items', { headers: { Authorization: 'Bearer ' + jwtToken } }).then(r => r.json())
    ]);
    const itemMap = Object.fromEntries(items.map(i => [i.id, i]));
    const select = document.getElementById('mo-select-done');
    if (!select) return;
    select.innerHTML = '';
    mos.forEach(mo => {
        const item = itemMap[mo.item_id] || {};
        const opt = document.createElement('option');
        opt.value = mo.id;
        opt.textContent = `#${mo.code} - ${item.sku || ''} ${item.name || ''} x${mo.quantity} (Done)`;
        select.appendChild(opt);
    });
}



fetchDoneManufacturingOrders();
fetchAllManufacturingOrders();

// Call this when the warehouse panel is shown:
fetchConfirmedManufacturingOrders();
fetchManufacturingOrders();

loadManufacturingItems();
loadInterventions();
// Call loadWarehouseItems() and populate target zones on panel load
loadWarehouseItems();
loadTargetZones();
populatePickingSelect();
populateMoveLineSelect();
// Call this when the warehouse panel loads
loadStockAdjustmentSelectors();