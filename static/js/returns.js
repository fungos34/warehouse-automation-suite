
async function startReturnOrderByCode(originModel) {
    const code = prompt(`Enter ${originModel.replace('_', ' ')} code:`);
    if (!code) return;

    // 1. Fetch order by code
    const orders = await fetch(`/${originModel.replace('_', '-') + 's'}?code=${code}`, {
    headers: { Authorization: 'Bearer ' + jwtToken }
    }).then(r => r.json());

    // Your /sale-orders and /purchase-orders endpoints return arrays
    const order = Array.isArray(orders) ? orders.find(o => o.code === code) : null;
    if (!order || order.status !== 'confirmed') {
    alert('Order not found or not confirmed');
    return;
    }

    // 2. Fetch order lines
    let linesUrl = '';
    if (originModel === 'sale_order') {
    linesUrl = `/sale-orders/${order.id}/lines`;
    } else if (originModel === 'purchase_order') {
    linesUrl = `/purchase-orders/${order.id}/lines`;
    } else {
    alert('Unsupported origin model');
    return;
    }
    const lines = await fetch(linesUrl, { headers: { Authorization: 'Bearer ' + jwtToken } }).then(r => r.json());

    // 3. Build a simple form for return quantities
    let formHtml = `<form id="return-lines-form"><h4>Return Items for ${code}</h4>`;
    lines.forEach((line, idx) => {
    const lotInfo = line.lot_id ? ` (Lot: ${line.lot_id})` : '';
    formHtml += `
        <div>
        <label>
            ${line.item_id}${lotInfo} - Max: ${line.quantity}
            <input type="number" min="0" max="${line.quantity}" value="0" name="qty${idx}">
        </label>
        </div>
    `;
    });
    formHtml += `<button type="submit">Submit Return</button></form>`;

    // Show modal
    const modal = document.createElement('div');
    modal.style.position = 'fixed';
    modal.style.top = '50%';
    modal.style.left = '50%';
    modal.style.transform = 'translate(-50%, -50%)';
    modal.style.background = '#fff';
    modal.style.padding = '24px';
    modal.style.zIndex = 3000;
    modal.style.borderRadius = '10px';
    modal.style.boxShadow = '0 4px 32px rgba(0,0,0,0.25)';
    modal.innerHTML = formHtml;
    document.body.appendChild(modal);

    modal.querySelector('form').onsubmit = async function(e) {
    e.preventDefault();
    const returnLines = [];
    lines.forEach((line, idx) => {
        const qty = parseInt(this[`qty${idx}`].value, 10);
        if (qty > 0) {
            returnLines.push({
                item_id: line.item_id,
                lot_id: line.lot_id || null,
                quantity: qty,
                reason: '',
                price: line.price // <-- add this if your backend supports it
            });
        }
    });
    if (!returnLines.length) {
        alert('No items selected for return.');
        return;
    }
    // 4. Submit return order
    const resp = await fetch('/return-orders/', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + jwtToken },
        body: JSON.stringify({
        origin_model: originModel,
        origin_code: code,
        lines: returnLines
        })
    });
    const data = await resp.json();
    if (resp.ok) {
        alert('Return order created!');
        document.body.removeChild(modal);
    } else {
        alert(JSON.stringify(data.detail) || 'Error creating return order');
    }
    };
};

async function loadReturnOrders() {
    const resp = await fetch('/return-orders/', { headers: { Authorization: 'Bearer ' + jwtToken } });
    const orders = await resp.json();
    const div = document.getElementById('return-orders-list');
    if (!orders.length) {
    div.innerHTML = '<i>No return orders.</i>';
    return;
    }
    div.innerHTML = '<ul>' + orders.map(o => `
    <li>
        <b>${o.code}</b>: ${o.origin_model} ${o.origin_id} (${o.status}) - ${o.partner_name}
        <button onclick="confirmReturnOrder(${o.id})">Confirm</button>
        <button onclick="cancelReturnOrder(${o.id})">Cancel</button>
        <button onclick="downloadReturnOrder(${o.id})">Print PDF</button>
        <button onclick="downloadReturnLabel(${o.id}, '${o.code}')">Print Label</button>
        <button onclick="downloadReturnBill(${o.id}, '${o.code}')">Download Refund Bill</button>
    </li>
    `).join('') + '</ul>';
};

async function loadCustomerReturnOrders() {
    const resp = await fetch('/return-orders/', { headers: { Authorization: 'Bearer ' + jwtToken } });
    const orders = await resp.json();
    // Optionally filter for this customer if needed
    // const myOrders = orders.filter(o => o.partner_id === currentCustomerId);
    const div = document.getElementById('customer-return-orders-list');
    if (!orders.length) {
    div.innerHTML = '<i>No return orders.</i>';
    return;
    }
    div.innerHTML = '<ul>' + orders.map(o => `
    <li>
        <b>${o.code}</b> (${o.status})
        <button onclick="downloadReturnLabel(${o.id}, '${o.code}')">Print Return Label</button>
    </li>
    `).join('') + '</ul>';
};


window.confirmReturnOrder = async function(id) {
    await fetch(`/return-orders/${id}/confirm`, { method: 'POST', headers: { Authorization: 'Bearer ' + jwtToken } });
    loadReturnOrders();
};
window.cancelReturnOrder = async function(id) {
    await fetch(`/return-orders/${id}/cancel`, { method: 'POST', headers: { Authorization: 'Bearer ' + jwtToken } });
    loadReturnOrders();
};
window.downloadReturnOrder = async function(id) {
    const resp = await fetch(`/return-orders/${id}/print-order`, { headers: { Authorization: 'Bearer ' + jwtToken } });
    const blob = await resp.blob();
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `ReturnOrder_${id}.pdf`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    window.URL.revokeObjectURL(url);
};

window.downloadReturnLabel = async function(id, code) {
    const resp = await fetch(`/return-orders/${id}/print-label`, { headers: { Authorization: 'Bearer ' + jwtToken } });
    const blob = await resp.blob();
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `ReturnOrder_Label_${code || id}.pdf`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    window.URL.revokeObjectURL(url);
};

window.downloadReturnBill = async function(id, code) {
    const resp = await fetch(`/return-orders/${id}/print-bill`, { headers: { Authorization: 'Bearer ' + jwtToken } });
    const blob = await resp.blob();
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `ReturnOrder_Bill_${code || id}.pdf`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    window.URL.revokeObjectURL(url);
};

// window.startReturnOrder = function(orderId) {
//   // Show a modal/form to select items/quantities to return
//   // For demo, just return all items:
//   fetch(`/sale-orders/${orderId}/lines`, { headers: { Authorization: 'Bearer ' + jwtToken } })
//     .then(r => r.json())
//     .then(lines => {
//       // Show a form to select which lines/quantities to return
//       // For now, just return the first line as an example:
//       const returnLines = lines.map(line => ({
//         item_id: line.item_id,
//         quantity: 1, // or let user choose
//         lot_id: line.lot_id // if needed
//       }));
//       fetch('/return-orders/', {
//         method: 'POST',
//         headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + jwtToken },
//         body: JSON.stringify({
//           origin_model: 'sale_order',
//           origin_id: orderId,
//           lines: returnLines
//         })
//       }).then(resp => resp.json())
//         .then(data => alert('Return order created!'))
//         .catch(e => alert('Error creating return order'));
//     });
// };

// Load initial data
loadReturnOrders();
loadCustomerReturnOrders();