
async function updateSaleOrdersDropdown() {
    let url = '/sale-orders/draft';
    try {
    const resp = await fetch(url, {
        headers: { Authorization: 'Bearer ' + jwtToken }
    });
    const data = await resp.json();
    if (resp.ok) {
        const count = data.length;
        document.getElementById('sales-orders-list').innerHTML = count
        ? `<b>${count} sale order(s) waiting for confirmation</b>`
        : '<i>No sale orders waiting for confirmation.</i>';


        // Populate confirm dropdown with payment reference
        const select = document.getElementById('confirm-sale-id');
        select.innerHTML = '';
        data.forEach(o => {
        const ref = `${o.code}-${o.id.toString(36).toUpperCase().slice(-5)}`;
        const opt = document.createElement('option');
        opt.value = o.id;
        opt.textContent = `#${o.id}: ${o.code} (Customer: ${o.partner_id}) - Ref: ${ref}`;
        select.appendChild(opt);
        });
    } else {
        document.getElementById('sales-orders-list').textContent = data.detail || 'Error fetching sale orders';
    }
    } catch (e) {
    document.getElementById('sales-orders-list').textContent = 'Error fetching sale orders';
    }
}


async function updateSaleDownloadDropdown() {
  const resp = await fetch('/sale-orders/', { headers: { Authorization: 'Bearer ' + jwtToken } });
  const data = await resp.json();
  const select = document.getElementById('download-sale-order-id');
  select.innerHTML = '';
  data.forEach(o => {
    const ref = `${o.code}-${o.id.toString(36).toUpperCase().slice(-5)}`;
    const opt = document.createElement('option');
    opt.value = o.id;
    opt.textContent = `#${o.id}: ${o.code} (Customer: ${o.partner_id}) - Ref: ${ref}`;
    select.appendChild(opt);
  });
}

// Show sale orders
document.getElementById('sales-query-form').onsubmit = async function(e) {
    e.preventDefault();
    updateSaleOrdersDropdown();
    let url = '/sale-orders/draft';
    try {
    const resp = await fetch(url, {
        headers: { Authorization: 'Bearer ' + jwtToken }
    });
    const data = await resp.json();
    if (resp.ok) {
        const count = data.length;
        document.getElementById('sales-orders-list').innerHTML = count
        ? `<b>${count} sale order(s) waiting for confirmation</b>`
        : '<i>No sale orders waiting for confirmation.</i>';


        // Populate confirm dropdown with payment reference
        const select = document.getElementById('confirm-sale-id');
        select.innerHTML = '';
        data.forEach(o => {
        const ref = `${o.code}-${o.id.toString(36).toUpperCase().slice(-5)}`;
        const opt = document.createElement('option');
        opt.value = o.id;
        opt.textContent = `#${o.id}: ${o.code} (Customer: ${o.partner_id}) - Ref: ${ref}`;
        select.appendChild(opt);
        });
    } else {
        document.getElementById('sales-orders-list').textContent = data.detail || 'Error fetching sale orders';
    }
    } catch (e) {
    document.getElementById('sales-orders-list').textContent = 'Error fetching sale orders';
    }
};

// Confirm sale order
document.getElementById('confirm-sale-form').onsubmit = async function(e) {
    e.preventDefault();
    const soId = document.getElementById('confirm-sale-id').value;
    try {
    const resp = await fetch(`/sale-orders/${soId}/confirm`, {
        method: 'POST',
        headers: { Authorization: 'Bearer ' + jwtToken }
    });
    const data = await resp.json();
    document.getElementById('sales-result').textContent = resp.ok ? 'Sale order confirmed!' : data.detail || 'Error';
    updateSaleOrdersDropdown(); // Refresh the dropdown and count
    } catch (e) {
    document.getElementById('sales-result').textContent = 'Error confirming sale order';
    }
};

document.getElementById('cancel-sale-btn').onclick = async function() {
    const soId = document.getElementById('confirm-sale-id').value;
    if (!soId) return;
    try {
    const resp = await fetch(`/sale-orders/${soId}/cancel`, {
        method: 'POST',
        headers: { Authorization: 'Bearer ' + jwtToken }
    });
    const data = await resp.json();
    document.getElementById('sales-result').textContent = resp.ok ? 'Sale order cancelled!' : data.detail || 'Error';
    updateSaleOrdersDropdown();
    } catch (e) {
    document.getElementById('sales-result').textContent = 'Error cancelling sale order';
    }
};


document.getElementById('download-sale-bill-btn').onclick = async function() {
    const soId = document.getElementById('download-sale-order-id').value;
    if (!soId) return;
    const resp = await fetch(`/sale-orders/${soId}/print-order`, {
        headers: { Authorization: 'Bearer ' + jwtToken }
    });
    if (!resp.ok) {
        alert('Failed to download sale order bill');
        return;
    }
    const blob = await resp.blob();
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `SaleOrder_${soId}.pdf`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    window.URL.revokeObjectURL(url);
};

document.getElementById('download-sale-shipping-btn').onclick = async function() {
    const soId = document.getElementById('download-sale-order-id').value;
    if (!soId) return;
    const resp = await fetch(`/sale-orders/${soId}/print-shipment`, {
        headers: { Authorization: 'Bearer ' + jwtToken }
    });
    if (!resp.ok) {
        alert('Failed to download sale order shipping label');
        return;
    }
    const blob = await resp.blob();
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `SaleOrder_Shipping_${soId}.pdf`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    window.URL.revokeObjectURL(url);
};


document.getElementById('download-sale-label-btn').onclick = async function() {
    const soId = document.getElementById('download-sale-order-id').value;
    if (!soId) return;
    // Optionally fetch the code for a nicer filename
    let code = soId;
    try {
    const resp = await fetch(`/sale-orders/${soId}`, { headers: { Authorization: 'Bearer ' + jwtToken } });
    if (resp.ok) {
        const order = await resp.json();
        code = order.code || soId;
    }
    } catch (e) {}
    await window.downloadSaleOrderLabel(soId, code);
};


window.downloadSaleOrder = async function(orderId) {
    const resp = await fetch(`/sale-orders/${orderId}/print-order`, {
    headers: { Authorization: 'Bearer ' + jwtToken }
    });
    if (!resp.ok) {
    alert('Failed to download sale order');
    return;
    }
    const blob = await resp.blob();
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `SaleOrder_${orderId}.pdf`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    window.URL.revokeObjectURL(url);
};

window.downloadSaleOrderLabel = async function(id, code) {
    const resp = await fetch(`/sale-orders/${id}/print-label`, { headers: { Authorization: 'Bearer ' + jwtToken } });
    const blob = await resp.blob();
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `SaleOrder_Label_${code || id}.pdf`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    window.URL.revokeObjectURL(url);
};


// Call this after login and after confirming/cancelling a sale order
updateSaleDownloadDropdown();
