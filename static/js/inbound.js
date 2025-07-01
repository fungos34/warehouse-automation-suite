
let inboundCart = {};
let lastConfirmedPOs = []; // Store confirmed PO IDs and vendor info

async function loadInboundItems() {
    const resp = await fetch('/items', { headers: { Authorization: 'Bearer ' + jwtToken } });
    const items = await resp.json();
    // Fetch vendors for each item
    const vendorResp = await fetch('/partners?vendor=1', { headers: { Authorization: 'Bearer ' + jwtToken } });
    const vendors = await vendorResp.json();
    const vendorMap = {};
    vendors.forEach(v => vendorMap[v.id] = v);

    // Group items by vendor
    const grouped = {};
    items.forEach(item => {
    const vendorId = item.vendor_id;
    if (!grouped[vendorId]) grouped[vendorId] = [];
    grouped[vendorId].push(item);
    });

    let html = '';
    Object.entries(grouped).forEach(([vendorId, items]) => {
    const vendor = vendorMap[vendorId] || { name: 'Unknown Vendor' };
    html += `<h5>${vendor.name}</h5><ul>`;
    items.forEach(item => {
        html += `<li>
        <b>${item.name}</b> (${item.sku})<br>
        ${item.cost} ${item.cost_currency_code || item.currency_code || '€'}
        <button onclick="addToInboundCart(${vendorId}, ${item.id}, '${item.name}', ${item.cost}, '${item.cost_currency_code || item.currency_code || '€'}')">Add to Cart</button>
        </li>`;
    });
    html += '</ul>';
    });
    document.getElementById('inbound-item-list').innerHTML = html;
};

document.getElementById('inbound-buy-btn').onclick = async function() {
    if (Object.keys(inboundCart).length === 0) {
    document.getElementById('inbound-buy-result').textContent = 'Cart is empty!';
    return;
    }
    let resultHtml = '';
    lastConfirmedPOs = [];
    try {
    for (const [vendorId, items] of Object.entries(inboundCart)) {
        // 1. Create purchase order
        const poResp = await fetch('/purchase-orders/', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + jwtToken },
        body: JSON.stringify({ partner_id: Number(vendorId) })
        });
        const po = await poResp.json();
        if (!poResp.ok) throw new Error(po.detail || 'Failed to create PO');
        const poId = po.purchase_order_id || po.id || po.po_id || po.order_id;

        // 2. Add lines
        const lines = Object.values(items).map(item => ({
            item_id: item.id,
            quantity: item.qty,
            route_id: 1, // or whatever is appropriate
            price: item.price || 0, // or item.price if you want to store vendor price
            currency_id: item.currency_id || 1, // fallback to 1 if missing
            cost: item.cost || item.price || 0, // use cost if available, otherwise price
            cost_currency_id: item.cost_currency_id || 1
        }));
        const lineResp = await fetch(`/purchase-orders/${poId}/lines`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                Authorization: 'Bearer ' + jwtToken
            },
            body: JSON.stringify(lines)
        });
        if (!lineResp.ok) throw new Error('Failed to add PO lines');

        // 3. Confirm PO
        const confirmResp = await fetch(`/purchase-orders/${poId}/confirm`, {
        method: 'POST',
        headers: { Authorization: 'Bearer ' + jwtToken }
        });
        if (!confirmResp.ok) throw new Error('Failed to confirm PO');
        resultHtml += `PO for vendor #${vendorId} created and confirmed!<br>`;
        lastConfirmedPOs.push({ poId, vendorId });
    }
    inboundCart = {};
    renderInboundCart();
    loadInboundItems();

    // Add download buttons for each confirmed PO
    resultHtml += lastConfirmedPOs.map(po =>
        `<button onclick="downloadPO(${po.poId})">Download Purchase Order #${po.poId}</button>`
    ).join('<br>');
    document.getElementById('inbound-buy-result').innerHTML = resultHtml;
    } catch (e) {
    document.getElementById('inbound-buy-result').textContent = e.message || 'Error placing purchase orders';
    }
};

function renderInboundCart() {
    const cartList = document.getElementById('inbound-cart-list');
    if (Object.keys(inboundCart).length === 0) {
    cartList.innerHTML = '<i>Cart is empty</i>';
    return;
    }
    let html = '';
    Object.entries(inboundCart).forEach(([vendorId, items]) => {
    html += `<b>Vendor #${vendorId}</b><ul>`;
    Object.values(items).forEach(item => {
        html += `<li>
        ${item.name} (${item.price} ${item.currency}) x 
        <input type="number" min="1" value="${item.qty}" style="width:40px" onchange="updateInboundCartQty(${vendorId},${item.id},this.value)">
        <button onclick="removeFromInboundCart(${vendorId},${item.id})">Remove</button>
        </li>`;
    });
    html += '</ul>';
    });
    cartList.innerHTML = html;
};


async function updatePurchaseOrdersDropdown() {
    const resp = await fetch('/purchase-orders/draft', { headers: { Authorization: 'Bearer ' + jwtToken } });
    const data = await resp.json();
    const select = document.getElementById('confirm-po-id');
    select.innerHTML = '';
    data.forEach(po => {
    const ref = `${po.code}-${po.id.toString(36).toUpperCase().slice(-5)}`;
    const label = `#${po.id}: ${po.code} (Vendor: ${po.vendor_name || po.partner_id}) - Ref: ${ref}`;
    const opt = document.createElement('option');
    opt.value = po.id;
    opt.textContent = label;
    select.appendChild(opt);
    });
};

async function updatePurchaseDownloadDropdown() {
    const resp = await fetch('/purchase-orders/', { headers: { Authorization: 'Bearer ' + jwtToken } });
    const data = await resp.json();
    const select = document.getElementById('download-po-id');
    select.innerHTML = '';
    data.forEach(po => {
    const ref = `${po.code}-${po.id.toString(36).toUpperCase().slice(-5)}`;
    const label = `#${po.id}: ${po.code} (Vendor: ${po.partner_id}) - Ref: ${ref}`;
    const opt = document.createElement('option');
    opt.value = po.id;
    opt.textContent = label;
    select.appendChild(opt);
    });
};


document.getElementById('download-po-label-btn').onclick = async function() {
    const poId = document.getElementById('download-po-id').value;
    if (!poId) return;
    let code = poId;
    try {
        const resp = await fetch(`/purchase-orders/${poId}`, { headers: { Authorization: 'Bearer ' + jwtToken } });
        if (resp.ok) {
        const order = await resp.json();
        code = order.code || poId;
        }
    } catch (e) {}
    const resp = await fetch(`/purchase-orders/${poId}/print-label`, { headers: { Authorization: 'Bearer ' + jwtToken } });
    const blob = await resp.blob();
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `PurchaseOrder_Label_${code}.pdf`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    window.URL.revokeObjectURL(url);
};


document.getElementById('download-po-bill-btn').onclick = async function() {
    const poId = document.getElementById('download-po-id').value;
    if (!poId) return;
    const resp = await fetch(`/purchase-orders/${poId}/print-order`, {
    headers: { Authorization: 'Bearer ' + jwtToken }
    });
    if (!resp.ok) {
    alert('Failed to download purchase order bill');
    return;
    }
    const blob = await resp.blob();
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `PurchaseOrder_${poId}.pdf`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    window.URL.revokeObjectURL(url);
};

document.getElementById('download-po-shipping-btn').onclick = async function() {
    const poId = document.getElementById('download-po-id').value;
    if (!poId) return;
    const resp = await fetch(`/purchase-orders/${poId}/print-shipment`, {
    headers: { Authorization: 'Bearer ' + jwtToken }
    });
    if (!resp.ok) {
    alert('Failed to download purchase order shipping label');
    return;
    }
    const blob = await resp.blob();
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `PurchaseOrder_Shipping_${poId}.pdf`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    window.URL.revokeObjectURL(url);
};

document.getElementById('confirm-po-form').onsubmit = async function(e) {
    e.preventDefault();
    const poId = document.getElementById('confirm-po-id').value;
    try {
    const resp = await fetch(`/purchase-orders/${poId}/confirm`, {
        method: 'POST',
        headers: { Authorization: 'Bearer ' + jwtToken }
    });
    const data = await resp.json();
    document.getElementById('po-confirm-result').textContent = resp.ok ? 'Purchase order confirmed!' : data.detail || 'Error';
    updatePurchaseOrdersDropdown(); // Refresh the dropdown
    loadInboundItems(); // Optionally refresh items
    } catch (e) {
    document.getElementById('po-confirm-result').textContent = 'Error confirming purchase order';
    }
};


document.getElementById('cancel-po-btn').onclick = async function() {
    const poId = document.getElementById('confirm-po-id').value;
    if (!poId) return;
    try {
    const resp = await fetch(`/purchase-orders/${poId}/cancel`, {
        method: 'POST',
        headers: { Authorization: 'Bearer ' + jwtToken }
    });
    const data = await resp.json();
    document.getElementById('po-confirm-result').textContent = resp.ok ? 'Purchase order cancelled!' : data.detail || 'Error';
    updatePurchaseOrdersDropdown();
    loadInboundItems();
    } catch (e) {
    document.getElementById('po-confirm-result').textContent = 'Error cancelling purchase order';
    }
};


// Download function
window.downloadPO = async function(poId) {
    const resp = await fetch(`/purchase-orders/${poId}/print-order`, {
    headers: { Authorization: 'Bearer ' + jwtToken }
    });
    if (!resp.ok) {
    alert('Failed to download purchase order');
    return;
    }
    const blob = await resp.blob();
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `PurchaseOrder_${poId}.pdf`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    window.URL.revokeObjectURL(url);
};

window.addToInboundCart = function(vendorId, id, name, price, currency) {
    if (!inboundCart[vendorId]) inboundCart[vendorId] = {};
    if (!inboundCart[vendorId][id]) inboundCart[vendorId][id] = { id, name, price, currency, qty: 0 };
    inboundCart[vendorId][id].qty += 1;
    renderInboundCart();
};

window.updateInboundCartQty = function(vendorId, id, qty) {
    if (qty < 1) { removeFromInboundCart(vendorId, id); return; }
    inboundCart[vendorId][id].qty = parseInt(qty);
    renderInboundCart();
};

window.removeFromInboundCart = function(vendorId, id) {
    delete inboundCart[vendorId][id];
    if (Object.keys(inboundCart[vendorId]).length === 0) delete inboundCart[vendorId];
    renderInboundCart();
};

// Initial load
loadInboundItems();
renderInboundCart();
// Call this after login and after confirming/cancelling a purchase order
updatePurchaseDownloadDropdown();
updatePurchaseOrdersDropdown();
